-- RUIN Core
-- Namespace, saved data, event plumbing, guild state and slash commands.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.PREFIX = "RUIN"   -- addon message prefix shared by the whole suite
ns.PROTOCOL = 1      -- bump when the wire format changes incompatibly

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (getMeta and getMeta(ADDON, "Version")) or "0.0.0"

-- Which game this is. One codebase serves WoW Forever and Retail; data that
-- only fits one of them (routes, dungeon lists) checks ns.CLIENT. Each game
-- keeps its own SavedVariables, so profiles stay separate by themselves.
local mainline = WOW_PROJECT_MAINLINE or 1
ns.CLIENT = (WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == mainline) and "retail" or "forever"
ns.CLIENT_NAME = ns.CLIENT == "retail" and "Retail" or "WoW Forever"

local DEFAULTS = {
    settings = {
        showOrgChat = true,      -- show other guilds' guild chat
        showOfficerChat = true,  -- show other guilds' officer chat (officers only)
        allowBridge = true,      -- may relay lines from guildmates who lack the addon
        chatFrame = 1,           -- chat window number that shows RUIN lines
        couchMode = false,       -- larger window for Steam Deck / TV play
        animations = true,       -- ambient motion in page headers
        tabOrder = nil,          -- your own tab order (Settings > Options > Tab order): a list of page titles
        chatScope = "org",       -- Guild > Chat and the pop-out: "org" (every RUIN guild) or "guild"
        linkAlts = false,        -- count my characters as one player in the census (shares a random token)
        leaderAwayDays = 3,      -- tell officers when their guild master has been away this many days
        debug = false,
    },
}

local function report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) else print(err) end
end
ns.ReportError = report

---------------------------------------------------------------------------
-- Printing
---------------------------------------------------------------------------
-- "[RUIN] Waypoint set: ..." in RUIN teal, as in the brief's chat lines.
local TAG = "|cff54b7d9[RUIN]|r"

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(TAG .. " " .. tostring(msg))
end

function ns:Debug(msg)
    if ns.db and ns.db.settings.debug then
        DEFAULT_CHAT_FRAME:AddMessage(TAG .. " |cff888888debug|r: " .. tostring(msg))
    end
end

---------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- Events that exist in one client and not another (Classic vs Retail APIs)
-- are skipped quietly instead of raising an error, so a module can listen
-- for both styles and use whichever one fires. Returns false when skipped.
function ns:RegisterEvent(event, fn)
    if not eventHandlers[event] then
        if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
            ns:Debug("skipped event not in this client: " .. event)
            return false
        end
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            ns:Debug("skipped event not in this client: " .. event)
            return false
        end
        eventHandlers[event] = {}
    end
    table.insert(eventHandlers[event], fn)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then report(err) end
    end
end)

---------------------------------------------------------------------------
-- Internal callbacks (KEY_CHANGED, PEERS_CHANGED, ROSTER_UPDATED, ...)
---------------------------------------------------------------------------
local callbacks = {}

function ns:Subscribe(name, fn)
    callbacks[name] = callbacks[name] or {}
    table.insert(callbacks[name], fn)
end

function ns:Fire(name, ...)
    local list = callbacks[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then report(err) end
    end
end

---------------------------------------------------------------------------
-- Saved data
-- WoW Forever's beta has a SavedVariables loading bug, so the table is
-- adopted defensively on ADDON_LOADED and checked again on PLAYER_LOGIN.
---------------------------------------------------------------------------
local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function adoptDB()
    if type(RUIN_DB) ~= "table" then RUIN_DB = {} end
    applyDefaults(RUIN_DB, DEFAULTS)
    if ns.db ~= RUIN_DB then
        ns.db = RUIN_DB
        ns:Fire("DB_READY")
    end
end

ns:RegisterEvent("ADDON_LOADED", function(_, name)
    if name == ADDON then adoptDB() end
end)

---------------------------------------------------------------------------
-- Guild state and roster cache
---------------------------------------------------------------------------
ns.roster = {}        -- normalized name -> entry
ns.rosterByGUID = {}  -- GUID -> entry

function ns:RefreshGuild()
    local name, rank
    if IsInGuild() then
        local gName, _, rankIndex = GetGuildInfo("player")
        name, rank = gName, rankIndex
    end
    if name ~= ns.guildName or rank ~= ns.guildRank then
        ns.guildName, ns.guildRank = name, rank
        ns:Fire("GUILD_CHANGED")
    end
end

function ns:RequestRoster()
    if not IsInGuild() then return end
    -- The game lists offline members only while "Show offline members" is
    -- on; RUIN's roster shows everyone, so it turns that on.
    if SetGuildRosterShowOffline and GetGuildRosterShowOffline and not GetGuildRosterShowOffline() then
        pcall(SetGuildRosterShowOffline, true)
    end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

function ns:ScanRoster()
    local roster, byGUID = {}, {}
    local count = GetNumGuildMembers() or 0
    for i = 1, count do
        local name, rankName, rankIndex, level, className, zone, note, officerNote, online, status, classFile,
              _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if name then
            local entry = { name = name, rank = rankIndex, rankName = rankName, level = level, className = className, zone = zone,
                            note = note, officerNote = officerNote, online = online, status = status, class = classFile,
                            guid = guid, index = i }
            if not online and GetGuildRosterLastOnline then
                local y, mo, d, h = GetGuildRosterLastOnline(i)
                if y then entry.lastOnline = ((y * 365 + mo * 30 + d) * 24 + h) * 3600 end
            end
            roster[ns.NormalizeName(name)] = entry
            if guid then byGUID[guid] = entry end
        end
    end
    ns.roster, ns.rosterByGUID = roster, byGUID
    ns:Fire("ROSTER_UPDATED")
end

local rosterScanPending = false
local function scheduleRosterScan()
    if rosterScanPending then return end
    rosterScanPending = true
    C_Timer.After(1, function()
        rosterScanPending = false
        ns:ScanRoster()
    end)
end

ns:RegisterEvent("GUILD_ROSTER_UPDATE", function()
    ns:RefreshGuild()
    scheduleRosterScan()
end)

ns:RegisterEvent("PLAYER_GUILD_UPDATE", function()
    ns:RefreshGuild()
    ns:RequestRoster()
end)

---------------------------------------------------------------------------
-- Login
---------------------------------------------------------------------------
ns:RegisterEvent("PLAYER_LOGIN", function()
    adoptDB()
    ns.playerGUID = UnitGUID("player")
    ns.playerName = UnitName("player")
    ns.playerNorm = ns.NormalizeName(ns.playerName)
    ns.loggedIn = true

    ns:RefreshGuild()
    ns:RequestRoster()

    -- Guild info is often empty for a few seconds after login; poll briefly.
    local tries = 0
    local poll
    poll = C_Timer.NewTicker(2, function()
        tries = tries + 1
        ns:RefreshGuild()
        if (ns.guildName or not IsInGuild()) and tries > 1 or tries >= 15 then
            poll:Cancel()
        end
    end)
    C_Timer.NewTicker(60, function() ns:RequestRoster() end)

    ns:Fire("LOGIN")
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
    "/ruin - open or close the RUIN window",
    "/ruin guild | settings - open the Guild or Settings page",
    "/ruin roster | census | people | watch | bank - open that part of the Guild page",
    "/ruin chat - pop out guild chat  |  /ruin report [name] - report a player to the Watch",
    "/ruin news - what's new in this version",
    "/ruin status - print connection status",
    "/ruin versions - list RUIN versions seen online",
    "/ruin key import | join <key phrase> | send [name] | forget  |  export (org admin)",
    "/ruin key create <org name>  (guild master who runs the org)",
    "/ruin key addguild <guild>, <officer rank>[, <tag>]  (org admin)",
    "/ruin key editguild <guild>, <new name>, <officer rank>[, <tag>]  (org admin)",
    "/ruin key removeguild <guild>  |  /ruin key newkey [key phrase]  (org admin)",
    "/ruin key links - edit the org's community links  (org admin)",
    "/ruin bridge on|off - allow relaying for guildmates without RUIN",
    "/ruin chatframe <n> - chat window number for RUIN lines",
    "/ruin couch - toggle couch mode (larger window)",
    "/ruin tabs reset - put the tabs back in their usual order",
    "/ruin debug - toggle debug messages",
    "/ruin overlord - check whether RUIN can see Overlord Forever",
}

function ns:PrintStatus()
    local k = ns.Org:Get()
    if k then
        ns:Print(("Org %s, key rev %d%s."):format(k.org, k.rev, ns.Org:IsAdmin() and " (you are admin)" or ""))
    else
        ns:Print("No org key loaded.")
    end
    ns:Print(("Guild: %s%s%s"):format(ns.guildName or "none",
        ns.Org:MyGuildInOrg() and " (in org)" or " (not in org key)",
        ns.Org:AmOfficer() and ", officer" or ""))
    ns:Print(("Org channel: %s. Officer channel: %s."):format(
        ns.Comms:IsJoined("ORG") and "connected" or "not connected",
        ns.Comms:IsJoined("OFFICERS") and "connected" or "not connected"))
    local bridge = ns.Presence:BridgeGUID()
    ns:Print("Guild bridge: " .. (bridge and (bridge == ns.playerGUID and "you"
        or ns.ShortName(ns.Presence:NameForGUID(bridge) or "?")) or "none"))
    local members, guilds = ns.Presence:CountOnline()
    ns:Print(("Online with RUIN: %d in %d guild(s). Version %s."):format(members, guilds, ns.VERSION))
end

local function handleKey(rest)
    local sub, arg = rest:match("^(%S+)%s*(.*)$")
    sub = sub and sub:lower() or ""
    arg = ns.Trim(arg or "")
    local Org = ns.Org

    if sub == "import" then
        ns.UI:PromptImport()
    elseif sub == "export" then
        ns.UI:ShowExport()
    elseif sub == "send" then
        if arg ~= "" then
            local ok, err = Org:SendFullKey(arg)
            ns:Print(ok and ("Offered the org key to " .. arg .. ".") or err)
        else
            ns.UI:SendKeyToTarget()
        end
    elseif sub == "join" then
        local ok, err = Org:JoinWithPhrase(arg)
        ns:Print(ok and "Joining with the key phrase; a RUIN member online will send the key." or err)
    elseif sub == "create" then
        local ok, err = Org:Create(arg ~= "" and arg or "RUIN")
        ns:Print(ok and "Org key created. Add the other guilds with /ruin key addguild." or err)
    elseif sub == "addguild" then
        local name, rank, tag = ns.ParseGuildSpec(arg)
        local ok, err = Org:AddGuild(name, rank, tag)
        ns:Print(ok and ("Added " .. name .. " (officer rank " .. rank .. ").") or err)
    elseif sub == "editguild" then
        local old, new, rank, tag = arg:match("^([^,]+),%s*([^,]*),%s*(%d+)%s*,?%s*(.*)$")
        if not old then return ns:Print("Usage: /ruin key editguild <guild>, <new name>, <officer rank>[, <tag>]") end
        local ok, err = Org:EditGuild(ns.Trim(old), ns.Trim(new) ~= "" and ns.Trim(new) or ns.Trim(old), tonumber(rank), tag)
        ns:Print(ok and ("Updated " .. ns.Trim(old) .. ".") or err)
    elseif sub == "removeguild" then
        local ok, err = Org:RemoveGuild(arg)
        ns:Print(ok and ("Removed " .. arg .. ".") or err)
    elseif sub == "newkey" or sub == "phrase" or sub == "rotate" then
        if arg ~= "" then
            local ok, err = Org:ChooseNewKey(arg)
            ns:Print(ok and ("New key phrase set: " .. ns.Org.NormalizePhrase(arg) .. ".") or err)
        else
            ns.UI:PromptNewKey()
        end
    elseif sub == "links" then
        ns.UI:PromptLinks()
    elseif sub == "forget" then
        Org:Forget()
        ns:Print("Org key removed from this account.")
    else
        ns:Print("Key commands: import, join <phrase>, export, send [name], create, addguild, editguild, removeguild, newkey [phrase], links, forget")
    end
end

SLASH_RUIN1 = "/ruin"
SlashCmdList.RUIN = function(input)
    input = ns.Trim(input or "")
    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    rest = rest or ""

    if cmd == "" or cmd == "show" then
        RUIN_ToggleWindow()
    elseif cmd == "guild" or cmd == "settings" or cmd == "options" then
        ns.UI:OpenTab(cmd == "guild" and "Guild" or "Settings")
    elseif cmd == "tabs" then
        if rest:lower() == "reset" then
            ns.UI:ResetTabOrder()
            ns:Print("Tabs are back in their usual order.")
        else
            ns:Print("Tab order: " .. table.concat(ns.UI:TabLabels(), ", ") .. ". Change it under Settings > Options > Tab order, or /ruin tabs reset.")
        end
    elseif cmd == "chat" then
        ns.GuildUI.ToggleChatWindow()
    elseif cmd == "roster" then
        ns.UI:OpenGuildTab("Roster")
    elseif cmd == "watch" and not ns.Watch:IsModerator() then
        ns:Print("The Watch is for officers. To report a player: /ruin report <name>, or right-click them.")
    elseif cmd == "census" or cmd == "people" or cmd == "watch" or cmd == "bank" then
        ns.UI:OpenGuildTab(cmd)
    elseif cmd == "report" then
        ns.Watch:PromptReport(rest ~= "" and rest or (UnitExists and UnitExists("target") and UnitIsPlayer("target") and GetUnitName("target", true)) or nil)
    elseif cmd == "news" then
        ns.Updates:ShowLetter(nil)
    elseif cmd == "status" then
        ns:PrintStatus()
    elseif cmd == "versions" then
        ns.Presence:PrintVersions()
    elseif cmd == "key" then
        handleKey(rest)
    elseif cmd == "bridge" then
        local on = rest:lower() ~= "off"
        ns.db.settings.allowBridge = on
        ns:Print("Bridging " .. (on and "allowed." or "disabled."))
        ns:Fire("SETTINGS_CHANGED")
    elseif cmd == "chatframe" then
        local n = tonumber(rest)
        if n and _G["ChatFrame" .. n] then
            ns.db.settings.chatFrame = n
            ns:Print("RUIN lines now show in chat window " .. n .. ".")
        else
            ns:Print("Usage: /ruin chatframe <number>")
        end
    elseif cmd == "couch" then
        ns.db.settings.couchMode = not ns.db.settings.couchMode
        ns.UI:ApplyScale()
        ns:Print("Couch mode " .. (ns.db.settings.couchMode and "on." or "off."))
    elseif cmd == "overlord" or cmd == "ov" then
        ns.UI:PrintOverlord()
    elseif cmd == "debug" then
        ns.db.settings.debug = not ns.db.settings.debug
        ns:Print("Debug " .. (ns.db.settings.debug and "on." or "off."))
    else
        for _, line in ipairs(HELP) do ns:Print(line) end
    end
end
