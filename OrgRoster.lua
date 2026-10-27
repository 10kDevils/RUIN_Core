-- RUIN Core: every connected guild's roster
-- The game only shows you your own guild's roster. So one RUIN member online
-- in each guild (the lowest GUID among them, the same answer for everyone)
-- sends their guild's roster to the org channel: name, level, class, zone,
-- rank, public note, online state and last online. Officer notes never leave
-- the guild. A guild's roster is sent when it changes, at most every few
-- minutes, and when someone asks for it; everyone keeps the last copy of each
-- guild's roster (account-wide), so the Roster tab shows every guild even
-- when nobody from that guild is online.
local ADDON, ns = ...

local OR = {}
ns.OrgRoster = OR

local PAGE = 30                 -- members per message
local MAX_MEMBERS = 1000
local MIN_GAP = 300             -- seconds between two sends of your guild's roster
local REFRESH = 900             -- resend even when nothing changed
local ANSWER_GAP = 60           -- answer requests at most this often
local ASK_GAP = 60

local lastSent, lastSig, lastAnswer, lastAsk = -999, nil, -999, -999
local sendPending = false
local inbound = {}              -- guild -> { s, n, pages = {}, got, t, ranks, sent }
local TAB = "\t"

---------------------------------------------------------------------------
-- The stored rosters of the other guilds
---------------------------------------------------------------------------
local function store()
    local k = ns.Org:Get()
    if not (k and ns.db) then return nil end
    local s = ns.db.orgRosters
    if type(s) ~= "table" or s.org ~= k.org or type(s.guilds) ~= "table" then
        s = { org = k.org, guilds = {} }
        ns.db.orgRosters = s
    end
    for name in pairs(s.guilds) do                       -- guilds that left the org
        if not k.guilds[name] then s.guilds[name] = nil end
    end
    return s.guilds
end

local function clean(v, n)
    return (tostring(v or ""):gsub("[\t\r\n|]", " ")):sub(1, n)
end

-- One member as a short line: name, level, class, zone, rank, note, state, hours offline.
-- state: 0 offline, 1 online, 2 away, 3 busy
local function encode(e)
    local state = e.online and (1 + (tonumber(e.status) or 0)) or 0
    local hours = (not e.online and e.lastOnline) and math.floor(e.lastOnline / 3600) or ""
    return table.concat({ clean(e.name, 48), tonumber(e.level) or 0, clean(e.class, 12), clean(e.zone, 40),
        tonumber(e.rank) or 9, clean(e.note, 31), state, hours }, TAB)
end

local function decode(line)
    if type(line) ~= "string" then return nil end
    local f = {}
    for part in (line .. TAB):gmatch("(.-)" .. TAB) do f[#f + 1] = part end
    if not f[1] or f[1] == "" then return nil end
    local state = tonumber(f[7]) or 0
    return { name = f[1], level = tonumber(f[2]), class = f[3] ~= "" and f[3] or nil, zone = f[4],
             rank = tonumber(f[5]) or 9, note = f[6], online = state > 0, status = state > 1 and (state - 1) or 0,
             hours = tonumber(f[8]) }
end
OR.Encode, OR.Decode = encode, decode

---------------------------------------------------------------------------
-- Sending your guild's roster
---------------------------------------------------------------------------
local function myLines()
    local lines = {}
    for _, e in pairs(ns.roster or {}) do lines[#lines + 1] = encode(e) end
    table.sort(lines)
    while #lines > MAX_MEMBERS do table.remove(lines) end
    return lines
end

-- The guild's rank names by rank (index 1 = rank 0), from the roster itself
-- and, for ranks nobody holds, the game's rank list.
local function rankNames()
    local out = {}
    for _, e in pairs(ns.roster or {}) do
        local r = tonumber(e.rank)
        if r and r >= 0 and r <= 9 and type(e.rankName) == "string" and e.rankName ~= "" then out[r + 1] = e.rankName:sub(1, 20) end
    end
    if GuildControlGetNumRanks and GuildControlGetRankName then
        for i = 1, math.min(10, GuildControlGetNumRanks() or 0) do
            if not out[i] then
                local ok, n = pcall(GuildControlGetRankName, i)
                if ok and type(n) == "string" and n ~= "" then out[i] = n:sub(1, 20) end
            end
        end
    end
    for i = 1, 10 do if not out[i] then out[i] = "" end end
    return out
end

-- Am I the one who sends this guild's roster?
local function amSender()
    return ns.Comms:IsJoined("ORG") and ns.Org:MyGuildInOrg() and ns.Presence:IsRosterSender()
end

function OR:Send(force)
    if not amSender() or not ns.roster or not next(ns.roster) then return false end
    local now = GetTime()
    local lines = myLines()
    local sig = ns.Hash(table.concat(lines, "\n"))
    if not force and sig == lastSig and now - lastSent < REFRESH then return false end
    if now - lastSent < (force and ANSWER_GAP or MIN_GAP) then
        OR:Schedule(lastSent + MIN_GAP - now + 1)
        return false
    end
    lastSent, lastSig = now, sig
    local id = ns.RandomToken(4)
    local pages = math.max(1, math.ceil(#lines / PAGE))
    local stamp = GetServerTime and GetServerTime() or time()
    for p = 1, pages do
        local m = {}
        for i = (p - 1) * PAGE + 1, math.min(#lines, p * PAGE) do m[#m + 1] = lines[i] end
        ns.Comms:Send("OROSTER", { gu = ns.guildName, s = id, p = p, n = pages, t = stamp,
                                   r = p == 1 and rankNames() or nil, m = m }, "ORG", nil, ns.Comms.PRIORITY.BULK)
    end
    ns:Fire("ORG_ROSTER_SENT")
    return true
end

function OR:Schedule(delay)
    if sendPending then return end
    sendPending = true
    C_Timer.After(math.max(5, delay or 10), function()
        sendPending = false
        OR:Send(false)
    end)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
ns.Comms:Register("OROSTER", function(d, sender, scope)
    if scope ~= "ORG" or type(d.gu) ~= "string" or d.gu == ns.guildName then return end
    if not ns.Org:GuildInfo(d.gu) then return end
    -- only a member of that guild may send its roster
    if ns.Presence:GuildOfName(sender) ~= d.gu then return end
    local p, n = tonumber(d.p), tonumber(d.n)
    if not (p and n and p >= 1 and p <= n and n <= 40 and type(d.m) == "table") then return end
    local box = inbound[d.gu]
    if not box or box.s ~= d.s then
        box = { s = d.s, n = n, pages = {}, got = 0, t = GetTime(), sent = tonumber(d.t) }
        inbound[d.gu] = box
    end
    if type(d.r) == "table" then box.ranks = d.r end
    if not box.pages[p] then box.pages[p] = d.m; box.got = box.got + 1 end
    if box.got < box.n then return end
    inbound[d.gu] = nil
    local members = {}
    for i = 1, box.n do
        for _, line in ipairs(box.pages[i]) do
            local e = decode(line)
            if e and #members < MAX_MEMBERS then members[#members + 1] = e end
        end
    end
    local s = store()
    if not s then return end
    local ranks = {}
    for i, r in ipairs(box.ranks or {}) do ranks[i] = clean(r, 20) end
    s[d.gu] = { t = (GetServerTime and GetServerTime() or time()), members = members, ranks = ranks,
                by = ns.ShortName(sender) }
    ns:Fire("ORG_ROSTER_UPDATED", d.gu)
end)

-- Someone asks for rosters (they opened the Roster tab and some are missing or old).
ns.Comms:Register("ORREQ", function(d, sender, scope)
    if scope ~= "ORG" or not amSender() then return end
    if type(d.gu) == "table" then
        local wanted = false
        for _, g in ipairs(d.gu) do if g == ns.guildName then wanted = true end end
        if not wanted then return end
    end
    if GetTime() - lastAnswer < ANSWER_GAP then return end
    lastAnswer = GetTime()
    C_Timer.After(1 + math.random() * 4, function() OR:Send(true) end)
end)

-- Ask for the rosters we don't have, or that are older than REFRESH.
function OR:AskMissing()
    if not ns.Comms:IsJoined("ORG") or GetTime() - lastAsk < ASK_GAP then return end
    local k, s = ns.Org:Get(), store()
    if not (k and s) then return end
    local now, want = (GetServerTime and GetServerTime() or time()), {}
    for name in pairs(k.guilds) do
        if name ~= ns.guildName and (not s[name] or now - (s[name].t or 0) > REFRESH) then want[#want + 1] = name end
    end
    if #want == 0 then return end
    lastAsk = GetTime()
    ns.Comms:Send("ORREQ", { gu = want }, "ORG", nil, ns.Comms.PRIORITY.BULK)
end

---------------------------------------------------------------------------
-- Lists for the Roster tab
---------------------------------------------------------------------------
-- Every member of every guild in the org: your own guild live from the game,
-- the others from their last shared roster. RUIN members seen online on the
-- org channel count as online even if their roster is older.
function OR:Members()
    local out = {}
    for _, e in pairs(ns.roster or {}) do
        local c = {}
        for key, v in pairs(e) do c[key] = v end
        c.guild, c.own = ns.guildName, true
        out[#out + 1] = c
    end
    local s, k = store(), ns.Org:Get()
    local now = GetServerTime and GetServerTime() or time()
    for gname, g in pairs(s or {}) do
        if gname ~= ns.guildName and k and k.guilds[gname] then
            local age = math.max(0, now - (g.t or now))
            for _, m in ipairs(g.members or {}) do
                local c = { name = m.name, level = m.level, class = m.class, zone = m.zone, rank = m.rank,
                            rankName = g.ranks and g.ranks[(m.rank or 9) + 1] or nil, note = m.note,
                            online = m.online, status = m.status, guild = gname, shared = true, age = age }
                if m.hours then c.lastOnline = m.hours * 3600 + age end
                local live = ns.Presence:OrgPeerByName(m.name)
                if live then
                    c.online, c.status = true, 0
                    if live.l then c.level = live.l end
                    if live.z and live.z ~= "" then c.zone = live.z end
                elseif m.online and age > 1800 then
                    c.online, c.lastOnline = false, age      -- the shared copy is too old to trust "online"
                end
                out[#out + 1] = c
            end
        end
    end
    return out
end

-- { name, members, online, updated (seconds ago or nil for your own guild), by } for each guild in the org
function OR:Guilds()
    local k, s = ns.Org:Get(), store()
    local now = GetServerTime and GetServerTime() or time()
    local list = {}
    if not k then
        if ns.guildName then list[1] = { name = ns.guildName, own = true } end
        return list
    end
    for name in pairs(k.guilds) do
        local g = { name = name, tag = k.guilds[name].tag, own = name == ns.guildName }
        if not g.own and s and s[name] then g.updated = now - (s[name].t or now); g.by = s[name].by end
        list[#list + 1] = g
    end
    if ns.guildName and not k.guilds[ns.guildName] then list[#list + 1] = { name = ns.guildName, own = true } end
    table.sort(list, function(a, b)
        if a.own ~= b.own then return a.own end
        return a.name < b.name
    end)
    return list
end

ns:Subscribe("ROSTER_UPDATED", function() OR:Schedule(10) end)
ns:Subscribe("CHANNELS_CHANGED", function()
    if ns.Comms:IsJoined("ORG") then
        C_Timer.After(20, function() OR:Send(false); OR:AskMissing() end)
    end
end)
ns:Subscribe("KEY_CHANGED", function() store() end)
