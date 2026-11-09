-- RUIN Core: "You're doing that too fast"
-- The server sends that when some request reaches it too often: the guild
-- roster, /who, a channel join, an item lookup, an addon message... The
-- message doesn't say which, or which addon asked. RUIN watches those
-- requests (from every addon, not only RUIN's: it can't change what they
-- do, only see them) and, when the message appears, names what was asked
-- in the seconds before and who asked. /ruin toofast shows the last ones.
local ADDON, ns = ...

local Throttle = {}
ns.Throttle = Throttle

local WINDOW = 4           -- seconds before the message that count
local KEEP = 400           -- calls remembered
local REPORT_GAP = 20      -- at most one chat line this often
local calls, head = {}, 0
local lastReport = -999

-- the addon a call came from: the first AddOns folder on the stack that
-- isn't a hook (this file) or an error catcher
local function caller()
    local st = debugstack and debugstack(2, 14, 0) or ""
    for line in st:gmatch("[^\n]+") do
        if not line:find("Throttle.lua", 1, true) then
            local name = line:match("AddOns[/\\]([^/\\]+)[/\\]") or line:match("[/\\](RUIN_%w+)[/\\]")
            if name and name ~= "!BugGrabber" and name ~= "BugSack" then return name end
        end
    end
    return "the game's own UI"
end

local function note(api)
    head = head % KEEP + 1
    if Throttle.selfSending then        -- RUIN's own send queue, marked by Comms.lua
        calls[head] = { t = GetTime(), api = api, who = ADDON }
        return
    end
    local ok, who = pcall(caller)
    calls[head] = { t = GetTime(), api = api, who = ok and who or "?" }
end
Throttle.Note = note

-- the requests that go to the server
local WATCH = {
    { nil, "GuildRoster" }, { nil, "SendWho" }, { nil, "JoinChannelByName" }, { nil, "JoinTemporaryChannel" },
    { nil, "SendChatMessage" }, { nil, "RequestRaidInfo" }, { nil, "RequestTimePlayed" }, { nil, "InviteUnit" },
    { "C_GuildInfo", "GuildRoster" }, { "C_FriendList", "SendWho" }, { "C_ChatInfo", "SendAddonMessage" },
    { "C_ChatInfo", "SendAddonMessageLogged" }, { "C_Item", "RequestLoadItemDataByID" }, { "C_Item", "RequestLoadItemData" },
    { "C_AuctionHouse", "ReplicateItems" }, { "C_AuctionHouse", "SendBrowseQuery" }, { "C_AuctionHouse", "SendSearchQuery" },
    { "C_PartyInfo", "InviteUnit" }, { "C_LFGList", "Search" }, { "C_QuestLog", "RequestLoadQuestByID" },
    { "C_Calendar", "OpenCalendar" }, { "C_PlayerInfo", "RequestPlayerInfo" },
}
local hooked = false
function Throttle.Hook()
    if hooked or not hooksecurefunc then return end
    hooked = true
    for _, w in ipairs(WATCH) do
        local t, f = w[1], w[2]
        local label = t and (t .. "." .. f) or f
        if t then
            local tbl = rawget(_G, t)
            if type(tbl) == "table" and type(tbl[f]) == "function" then
                pcall(hooksecurefunc, tbl, f, function() note(label) end)
            end
        elseif type(rawget(_G, f)) == "function" then
            pcall(hooksecurefunc, f, function() note(label) end)
        end
    end
end

-- { { api, who, n }, ... } most first, for the WINDOW seconds before now
function Throttle.Recent(now)
    now = now or GetTime()
    local count, order = {}, {}
    for _, c in pairs(calls) do
        if now - c.t <= WINDOW and now >= c.t then
            local k = c.api .. "\0" .. c.who
            if not count[k] then count[k] = { api = c.api, who = c.who, n = 0 }; order[#order + 1] = count[k] end
            count[k].n = count[k].n + 1
        end
    end
    table.sort(order, function(a, b) return a.n > b.n end)
    return order
end

-- addon messages other addons sent in the last `window` seconds
function Throttle.OthersSending(window)
    local now, n = GetTime(), 0
    for _, c in pairs(calls) do
        if now - c.t <= window and c.api:find("SendAddonMessage", 1, true) and not tostring(c.who):find("^RUIN") then n = n + 1 end
    end
    return n
end

local function isTooFast(msg)
    if type(msg) ~= "string" then return false end
    if ERR_GENERIC_THROTTLE and msg == ERR_GENERIC_THROTTLE then return true end
    return msg:lower():find("too fast", 1, true) ~= nil
end

local function describe(list)
    if #list == 0 then return "no watched requests in the seconds before (something the game itself asked for)" end
    local bits = {}
    for i = 1, math.min(#list, 4) do
        local e = list[i]
        bits[#bits + 1] = ("%d× %s (%s)"):format(e.n, e.api, e.who)
    end
    return table.concat(bits, ", ")
end

function Throttle.OnError(msg)
    if not isTooFast(msg) then return end
    if ns.Comms and ns.Comms.Backoff then ns.Comms:Backoff() end     -- RUIN goes quiet a moment either way
    local list = Throttle.Recent()
    local text = describe(list)
    if ns.db then
        ns.db.throttleLog = type(ns.db.throttleLog) == "table" and ns.db.throttleLog or {}
        table.insert(ns.db.throttleLog, 1, { t = time and time() or 0, text = text })
        for i = #ns.db.throttleLog, 11, -1 do ns.db.throttleLog[i] = nil end
    end
    if GetTime() - lastReport >= REPORT_GAP then
        lastReport = GetTime()
        ns:Print("The server said \"too fast\". Just before: " .. text .. ". /ruin toofast lists the last ones.")
    end
end

function Throttle.Show()
    local log = ns.db and ns.db.throttleLog or {}
    if #log == 0 then return ns:Print("No \"too fast\" messages seen since RUIN started watching.") end
    ns:Print("Last \"too fast\" messages, newest first:")
    for _, e in ipairs(log) do
        ns:Print(("  %s  %s"):format(date and date("%m/%d %H:%M", e.t) or "", e.text))
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:SetScript("OnEvent", function(_, event, a, b)
    if event == "PLAYER_LOGIN" then Throttle.Hook()
    else Throttle.OnError(type(b) == "string" and b or a) end
end)
Throttle.Hook()   -- hook early too, so calls made while addons load count
