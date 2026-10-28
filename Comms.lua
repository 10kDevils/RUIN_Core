-- RUIN Core: comms layer
-- One addon prefix, four scopes (GUILD, ORG, OFFICERS, PEER), chunking,
-- a throttled send queue and hidden password-protected org channels.
local ADDON, ns = ...

local Comms = {}
ns.Comms = Comms

local SEP = "\030"            -- record separator between frame fields
local FRAME_VERSION = "1"
local MAX_MSG = 250           -- stay under the 255-byte addon message cap
local TICK = 0.1
local TOKEN_CAP, TOKEN_RATE = 10, 1.0   -- Blizzard allows ~10 burst, ~1/s per prefix
local QUEUE_MAX_AGE = 60
local PARTIAL_MAX_AGE = 90     -- long messages (shared routes) arrive at about one part a second
local PARTIALS_PER_SENDER, PARTIALS_MAX = 8, 400

Comms.PRIORITY = { ALERT = 1, NORMAL = 2, BULK = 3 }

local handlers = {}                       -- kind -> { fn, ... }
local queues = { {}, {}, {} }             -- by priority
local tokens = TOKEN_CAP
local sessionTag = ns.RandomToken(2)
local counter = 0
local partials = {}                       -- sender..id -> partial message
local channels = { ORG = {}, OFFICERS = {} }   -- scope -> { name, password, joined }
local warnedPassword = {}
local knownNames = {}   -- every channel name used this session (lowercase), for hiding notices

---------------------------------------------------------------------------
-- Handlers
---------------------------------------------------------------------------
-- fn(data, sender, scope); data is always a table
function Comms:Register(kind, fn)
    handlers[kind] = handlers[kind] or {}
    table.insert(handlers[kind], fn)
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function nextId()
    counter = (counter + 1) % 100000
    return sessionTag .. counter
end

-- scope: "GUILD" | "ORG" | "OFFICERS" | "PEER" (target = character name)
function Comms:Send(kind, data, scope, target, priority)
    local ok, payload = pcall(ns.Serialize, data)
    if not ok then
        ns:Debug("could not serialize " .. tostring(kind))
        return false
    end
    local id = nextId()
    local header = #FRAME_VERSION + #kind + #id + 2 + 2 + 5   -- 5 separators, up to 2-digit part counts
    local room = MAX_MSG - header
    if room < 40 then
        ns:Debug("message kind too long: " .. kind)
        return false
    end
    local total = math.max(1, math.ceil(#payload / room))
    if total > 99 then
        ns:Debug("message too large: " .. kind)
        return false
    end
    local queue = queues[priority or Comms.PRIORITY.NORMAL] or queues[2]
    local now = GetTime()
    for i = 1, total do
        local chunk = payload:sub((i - 1) * room + 1, i * room)
        queue[#queue + 1] = {
            text = table.concat({ FRAME_VERSION, kind, id, i, total, chunk }, SEP),
            scope = scope, target = target, t = now,
        }
    end
    return true
end

local function idForName(name)
    if not name then return nil end
    local id = GetChannelName(name)
    if id and id > 0 then return id end
    return nil
end

local function channelId(scope)
    local ch = channels[scope]
    return ch and idForName(ch.name)
end

-- Returns chatType, target, reason ("drop" | "wait" | nil)
-- For ORG/OFFICERS an explicit target is a channel name (used to announce a
-- key change on the old channel before everyone moves to the new one).
local function resolve(item)
    local scope = item.scope
    if scope == "GUILD" then
        if not IsInGuild() then return nil, nil, "drop" end
        return "GUILD", nil
    elseif scope == "ORG" or scope == "OFFICERS" then
        local name = item.target or channels[scope].name
        if not name then return nil, nil, "drop" end
        local id = idForName(name)
        if not id then return nil, nil, "wait" end
        return "CHANNEL", id
    elseif scope == "PEER" then
        if not item.target then return nil, nil, "drop" end
        return "WHISPER", item.target
    end
    return nil, nil, "drop"
end

local function isThrottled(result)
    local E = Enum and Enum.SendAddonMessageResult
    if type(result) ~= "number" or not E then return false end
    return result == E.AddonMessageThrottle or result == E.ChannelThrottle
end

local function isFailure(result)
    return result == false or (type(result) == "number" and result ~= 0)
end

local function flush()
    if tokens < TOKEN_CAP then
        tokens = math.min(TOKEN_CAP, tokens + TOKEN_RATE * TICK)
    end
    local now = GetTime()
    for p = 1, #queues do
        local queue = queues[p]
        local i = 1
        while i <= #queue do
            if tokens < 1 then return end
            local item = queue[i]
            if now - item.t > QUEUE_MAX_AGE then
                table.remove(queue, i)
            else
                local chatType, target, reason = resolve(item)
                if reason == "drop" then
                    table.remove(queue, i)
                elseif reason == "wait" then
                    i = i + 1
                else
                    local result = C_ChatInfo.SendAddonMessage(ns.PREFIX, item.text, chatType, target)
                    if isThrottled(result) then
                        tokens = 0
                        return
                    end
                    if isFailure(result) then
                        ns:Debug(("send failed (%s) on %s"):format(tostring(result), chatType))
                    end
                    table.remove(queue, i)
                    tokens = tokens - 1
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function parseFrame(text)
    local fields, pos = {}, 1
    for n = 1, 5 do
        local s = text:find(SEP, pos, true)
        if not s then return nil end
        fields[n] = text:sub(pos, s - 1)
        pos = s + 1
    end
    fields[6] = text:sub(pos)
    return fields
end

function Comms:ScopeForChannel(...)
    for scope, ch in pairs(channels) do
        if ch.name then
            local lname = ch.name:lower()
            local id = channelId(scope)
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                if type(v) == "string" and v:lower():find(lname, 1, true) then return scope end
                if type(v) == "number" and id and v == id then return scope end
            end
        end
    end
    return nil
end

function Comms:OnAddonMessage(prefix, text, chatType, sender, target, zoneChannelID, localID, channelName)
    if prefix ~= ns.PREFIX or type(text) ~= "string" then return end
    if ns.playerNorm and ns.NormalizeName(sender) == ns.playerNorm then return end

    local scope
    if chatType == "GUILD" then
        scope = "GUILD"
    elseif chatType == "WHISPER" then
        scope = "PEER"
    elseif chatType == "CHANNEL" then
        scope = Comms:ScopeForChannel(channelName, target, localID)
    end
    if not scope then return end

    local f = parseFrame(text)
    if not f or f[1] ~= FRAME_VERSION then return end
    local kind, id = f[2], f[3]
    -- The Watch hid this player from the RUIN network.
    if ns.Watch and ns.Watch:AnyHidden() and kind:sub(1, 1) ~= "W" and ns.Watch:IsHidden(sender) then return end
    local idx, total, chunk = tonumber(f[4]), tonumber(f[5]), f[6]
    if not idx or not total or total < 1 or total > 99 or idx < 1 or idx > total then return end

    local payload
    if total == 1 then
        payload = chunk
    else
        local key = sender .. SEP .. id
        local p = partials[key]
        if not p then
            -- a few long messages in flight per sender, a few hundred in all
            local mine, all = 0, 0
            for _, q in pairs(partials) do
                all = all + 1
                if q.sender == sender then mine = mine + 1 end
            end
            if mine >= PARTIALS_PER_SENDER or all >= PARTIALS_MAX then return end
            p = { total = total, got = 0, parts = {}, t = GetTime(), sender = sender }
            partials[key] = p
        end
        if p.total ~= total then return end
        if not p.parts[idx] then
            p.parts[idx] = chunk
            p.got = p.got + 1
        end
        if p.got < p.total then return end
        partials[key] = nil
        payload = table.concat(p.parts, "", 1, p.total)
    end

    local data, err = ns.Deserialize(payload)
    if err or type(data) ~= "table" then
        ns:Debug("bad payload from " .. tostring(sender) .. ": " .. tostring(err))
        return
    end
    -- other players' text: game links stay, every other escape code goes
    data = ns.SanitizeTree(data)
    if type(data) ~= "table" then return end
    -- Only players who hold the officer channel's password can talk on it,
    -- and the game says who did: that makes them officer-grade (Presence).
    if scope == "OFFICERS" and ns.Presence and ns.Presence.NoteOfficer then
        ns.Presence:NoteOfficer(sender, nil, "channel")
    end
    local list = handlers[kind]
    if not list then return end
    for i = 1, #list do
        local ok, e = pcall(list[i], data, sender, scope)
        if not ok then ns.ReportError(e) end
    end
end

---------------------------------------------------------------------------
-- Hidden org channels
---------------------------------------------------------------------------
function Comms:HasChannel(scope)
    return channels[scope] and channels[scope].name ~= nil
end

function Comms:IsJoined(scope)
    return channelId(scope) ~= nil
end

-- The hidden channels are kept out of chat by message filters only. RUIN
-- never edits Blizzard's chat frames (removing channels from them tainted
-- the chat UI and caused "blocked from an action" popups).
local otherChannelCount        -- defined with channel ordering, below
local loadedAt = GetTime()

function Comms:JoinChannel(scope)
    local ch = channels[scope]
    if not ch or not ch.name or channelId(scope) then return end
    -- Never touch channel membership in combat; the upkeep timer retries later.
    if InCombatLockdown and InCombatLockdown() then return end
    -- Let the game's own channels (General, Trade...) take the low numbers
    -- first: right after login RUIN waits up to 45 seconds for one of them.
    if otherChannelCount() == 0 and GetTime() - loadedAt < 45 then return end
    ch.lastJoin = GetTime()
    if JoinTemporaryChannel then
        JoinTemporaryChannel(ch.name, ch.password)
    else
        JoinChannelByName(ch.name, ch.password)
    end
end

-- name = nil leaves the channel
function Comms:SetChannel(scope, name, password)
    local ch = channels[scope]
    if ch.name == name and ch.password == password then
        if name then Comms:JoinChannel(scope) end
        return
    end
    local oldName = ch.name
    if oldName and oldName ~= name then
        -- Linger briefly so queued announcements can still go out on the old
        -- channel, and wait until out of combat before leaving it.
        local function leaveOld()
            if channels[scope].name == oldName or not idForName(oldName) then return end
            if InCombatLockdown and InCombatLockdown() then
                C_Timer.After(5, leaveOld)
                return
            end
            LeaveChannelByName(oldName)
        end
        C_Timer.After(15, leaveOld)
    end
    ch.name, ch.password, ch.joined = name, password, false
    if name then knownNames[name:lower()] = true end
    warnedPassword[scope] = nil
    if name then Comms:JoinChannel(scope) end
    ns:Fire("CHANNELS_CHANGED")
end

local function isOurChannel(...)
    for lname in pairs(knownNames) do
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "string" and v:lower():find(lname, 1, true) then return true end
        end
    end
    return false
end
Comms.IsOurChannel = isOurChannel

---------------------------------------------------------------------------
-- Channel numbers: RUIN's hidden channels always come after the player's
-- other channels (General is /1, Trade /2 ... RUIN last), never /1. The game
-- gives a new channel the lowest free number, so RUIN joins after the game's
-- channels and then moves its own to the end, one swap at a time, keeping
-- the other channels in their order. Nothing happens in combat.
---------------------------------------------------------------------------
local function channelList()
    local out = {}
    if not GetChannelList then return out end
    local t = { GetChannelList() }
    local step = (type(t[3]) == "number") and 2 or 3           -- id, name[, disabled]
    for i = 1, #t, step do
        if tonumber(t[i]) and type(t[i + 1]) == "string" then out[#out + 1] = { id = tonumber(t[i]), name = t[i + 1] } end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end
Comms.ChannelList = channelList

otherChannelCount = function()
    if not GetChannelList then return 1 end                    -- can't tell: don't wait
    local n = 0
    for _, ch in ipairs(channelList()) do if not isOurChannel(ch.name) then n = n + 1 end end
    return n
end

local swapPending = false
function Comms:SortChannels()
    local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
    if not swap or (InCombatLockdown and InCombatLockdown()) then return false end
    local list = channelList()
    for i, ch in ipairs(list) do
        local nxt = list[i + 1]
        if nxt and isOurChannel(ch.name) and not isOurChannel(nxt.name) then
            local ok = pcall(swap, ch.id, nxt.id)
            if ok and not swapPending then
                -- the next swap once the game has moved this one
                swapPending = true
                C_Timer.After(1, function() swapPending = false; Comms:SortChannels() end)
            end
            return ok
        end
    end
    return false
end

ns:RegisterEvent("CHANNEL_UI_UPDATE", function()
    if swapPending then return end
    swapPending = true
    C_Timer.After(1, function() swapPending = false; Comms:SortChannels() end)
end)

-- Keep join/leave notices and any stray text from the hidden channels out of chat.
local function channelFilter(_, _, _, _, _, channelString, _, _, _, _, channelBaseName)
    if isOurChannel(channelString, channelBaseName) then return true end
    return false
end

local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if addFilter then
    for _, ev in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER",
                          "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
        addFilter(ev, channelFilter)
    end
end

ns:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", function(_, notice, _, _, channelString, _, _, _, _, channelBaseName)
    if notice ~= "WRONG_PASSWORD" or not isOurChannel(channelString, channelBaseName) then return end
    for scope, ch in pairs(channels) do
        if ch.name and not warnedPassword[scope] then
            local lname = ch.name:lower()
            if (type(channelBaseName) == "string" and channelBaseName:lower():find(lname, 1, true)) or
               (type(channelString) == "string" and channelString:lower():find(lname, 1, true)) then
                warnedPassword[scope] = true
                ns:Print(("Could not join the %s channel: wrong password. Your org key may be out of date; ask an officer or the org admin."):format(scope == "ORG" and "org" or "officer"))
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Upkeep: rejoin dropped channels, notice new joins, drop stale partials
---------------------------------------------------------------------------
local function upkeep()
    local now = GetTime()
    if not swapPending then Comms:SortChannels() end
    for key, p in pairs(partials) do
        if now - p.t > PARTIAL_MAX_AGE then partials[key] = nil end
    end
    for scope, ch in pairs(channels) do
        if ch.name then
            local joined = channelId(scope) ~= nil
            if joined ~= ch.joined then
                ch.joined = joined
                ns:Fire("CHANNELS_CHANGED")
                if joined then Comms:SortChannels() end
            end
            if not joined and not warnedPassword[scope] and now - (ch.lastJoin or 0) > 30 then
                Comms:JoinChannel(scope)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
end
ns:RegisterEvent("CHAT_MSG_ADDON", function(_, ...) Comms:OnAddonMessage(...) end)
C_Timer.NewTicker(TICK, flush)
C_Timer.NewTicker(5, upkeep)
