-- RUIN Core: update tools
-- * What's new: after RUIN updates, once per version, a short letter of what
--   changed (Settings > Options > What's new, or /ruin news, shows it again).
-- * The game's right-click menu on a player (target, party, raid, chat name,
--   friends) gets a RUIN part: their RUIN version (or "Check RUIN version"),
--   "Ask to update" for officers when they are behind, and "Report to the
--   Watch". Nothing of Blizzard's is replaced: RUIN adds lines through the
--   game's own menu API, and a client without it simply shows no RUIN lines.
local ADDON, ns = ...

local Wd = ns.Widgets
local P = Wd.PALETTE
local C = Wd.COLORS
local GREY, GREEN, RED = C.dim, C.good, C.bad

local Updates = {}
ns.Updates = Updates

Updates.DOWNLOAD = "github.com/10kDevils/RUIN_Suite/releases/latest"

-- What changed, newest first. Short, in players' words.
Updates.NOTES = {
    { "0.4.3", {
        "Guild page: a census of every guild (members, online, average level, guild master), with search and 30-day history.",
        "Guild > People: the hierarchy, inactive members, members by class, zone, level or profession, and offices guild masters appoint.",
        "Guild > Watch: report a player to the officers; officers warn, mute, hide players and handle cases. Sanctions follow the BattleTag.",
        "Guild > Chat: search, pinned lines and block words. Right-click a line for more.",
        "Guild > Bank: the guild bank as a guildmate last saw it.",
        "Not in a RUIN guild yet? The Guild page helps you find members and ask to join.",
        "Right-click a player: their RUIN version, and Report to the Watch.",
        "Finder: where members are, layers and layer hops, RUIN marks on members' nameplates, and the world boss and buff timers (moved from Muster).",
        "Muster: an automatic Most Wanted list, the War Room for squads and after-action reports, and loot notes.",
        "Exchange: the guild treasury book and a crafting history both sides confirm.",
    } },
    { "0.4.2", { "Settings > Feedback opens a new issue on the Companion App's GitHub." } },
}

local function newer(a, b) return ns.CompareVersions(a, b) > 0 end

-- Notes for versions after `since` (nil = all), newest first.
function Updates:NotesSince(since)
    local out = {}
    for _, v in ipairs(Updates.NOTES) do
        if not since or newer(v[1], since) then out[#out + 1] = v end
    end
    return out
end

---------------------------------------------------------------------------
-- The What's new letter
---------------------------------------------------------------------------
local letter
local function getLetter()
    if letter then return letter end
    local f = CreateFrame("Frame", "RUIN_WhatsNew", UIParent)
    f:SetSize(520, 340)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    Wd.Skin(f, "panel", 0.97, "glow")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = Wd.Label(f, "", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -14)
    f.body = Wd.Label(f, "", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT", 20, -46)
    f.body:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    if f.body.SetSpacing then f.body:SetSpacing(4) end
    f.foot = Wd.Label(f, "", "GameFontHighlightSmall")
    f.foot:SetPoint("BOTTOMLEFT", 20, 22)
    f.ok = Wd.Button(f, "Got it", 96, function() f:Hide() end)
    f.ok:SetPoint("BOTTOMRIGHT", -16, 14)
    if UISpecialFrames then tinsert(UISpecialFrames, "RUIN_WhatsNew") end
    f:Hide()
    letter = f
    return f
end

function Updates:ShowLetter(since)
    local notes = Updates:NotesSince(since)
    if #notes == 0 then notes = { Updates.NOTES[1] } end
    local lines = {}
    for i, v in ipairs(notes) do
        if i > 3 then break end
        lines[#lines + 1] = C.gold .. "RUIN " .. v[1] .. "|r"
        for _, l in ipairs(v[2]) do lines[#lines + 1] = "  •  " .. l end
        lines[#lines + 1] = " "
    end
    local f = getLetter()
    f.title:SetText(C.gold .. "What's new in RUIN|r")
    f.body:SetText(table.concat(lines, "\n"))
    f:SetHeight(math.max(220, math.min(560, (f.body:GetStringHeight() or 200) + 110)))
    f.foot:SetText(GREY .. "Shown once per update. Settings > Options > What's new, or /ruin news, shows it again.|r")
    f:Show()
end

-- After an update (not a first install), once, out of combat.
ns:Subscribe("LOGIN", function()
    C_Timer.After(12, function()
        if not ns.db then return end
        local seen = ns.db.lastSeenVersion
        ns.db.lastSeenVersion = ns.VERSION
        if seen and newer(ns.VERSION, seen) and #Updates:NotesSince(seen) > 0 then
            local function show()
                if InCombatLockdown and InCombatLockdown() then return C_Timer.After(10, show) end
                Updates:ShowLetter(seen)
            end
            show()
        end
    end)
end)

---------------------------------------------------------------------------
-- Versions of other players
---------------------------------------------------------------------------
local known = {}          -- normalized name -> { v, t }
local asked = {}          -- normalized name -> time asked

function Updates:VersionOf(name)
    local n = ns.NormalizeName(name or "")
    local p = ns.Presence:OrgPeerByName(name)
    if p and p.v then return p.v, "online now" end
    if known[n] then return known[n].v, "asked" end
    return nil
end

function Updates:Newest()
    local best = ns.VERSION
    for _, p in ipairs(ns.Presence:GetOnlineList()) do
        if p.version and newer(p.version, best) then best = p.version end
    end
    for _, k in pairs(known) do if k.v and newer(k.v, best) then best = k.v end end
    return best
end

function Updates:Check(name)
    local n = ns.NormalizeName(name or "")
    if asked[n] and GetTime() - asked[n] < 120 then return false, "Asked a moment ago." end
    asked[n] = GetTime()
    ns.Comms:Send("VREQ", {}, "PEER", name, ns.Comms.PRIORITY.NORMAL)
    C_Timer.After(10, function()
        if not known[n] or known[n].t < GetTime() - 15 then ns:Print(ns.ShortName(name) .. " didn't answer: no RUIN, an older one, or they're busy.") end
    end)
    return true
end

ns.Comms:Register("VREQ", function(_, sender, scope)
    if scope ~= "PEER" then return end
    ns.Comms:Send("VANS", { v = ns.VERSION }, "PEER", sender, ns.Comms.PRIORITY.NORMAL)
end)

ns.Comms:Register("VANS", function(d, sender, scope)
    if scope ~= "PEER" or type(d.v) ~= "string" then return end
    known[ns.NormalizeName(sender)] = { v = d.v:sub(1, 12), t = GetTime() }
    ns:Print(("%s runs RUIN %s%s."):format(ns.ShortName(sender), d.v, newer(Updates:Newest(), d.v) and (" (newest: " .. Updates:Newest() .. ")") or ""))
end)

-- Officers ask a player who is behind to update; they see it once a day.
function Updates:AskToUpdate(name)
    if not (ns.Watch and ns.Watch:IsModerator()) then return false, "Only officers can ask." end
    ns.Comms:Send("UPDASK", { v = Updates:Newest() }, "PEER", name, ns.Comms.PRIORITY.NORMAL)
    return true
end

ns.Comms:Register("UPDASK", function(d, sender, scope)
    if scope ~= "PEER" or type(d.v) ~= "string" or not newer(d.v, ns.VERSION) then return end
    if not (ns.Watch and ns.Watch.SenderIsModerator(sender)) then return end
    local today = date("%Y-%m-%d")
    if ns.db.updAskDay == today then return end
    ns.db.updAskDay = today
    ns:Print(("%s asks you to update RUIN: you have %s, %s is out. Get it at %s"):format(ns.ShortName(sender), ns.VERSION, d.v, Updates.DOWNLOAD))
end)

---------------------------------------------------------------------------
-- The right-click menu
---------------------------------------------------------------------------
local MENUS = { "PLAYER", "TARGET", "FOCUS", "PARTY", "RAID_PLAYER", "FRIEND", "CHAT_ROSTER", "COMMUNITIES_WOW_MEMBER" }

local function nameFrom(ctx)
    if type(ctx) ~= "table" then return nil end
    local name = ctx.name
    if (not name or name == "") and ctx.unit and UnitName then
        local n, realm = UnitName(ctx.unit)
        name = n and (realm and realm ~= "" and (n .. "-" .. realm) or n)
    end
    if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then return nil end
    if ctx.server and ctx.server ~= "" and not name:find("-", 1, true) then name = name .. "-" .. ctx.server end
    return name
end

function Updates:MenuLines(name)
    local lines = {}
    if not name or ns.NormalizeName(name) == ns.NormalizeName(ns.playerName or "") then return lines end
    local v, src = Updates:VersionOf(name)
    if v then
        lines[#lines + 1] = { title = ("RUIN %s%s"):format(v, newer(Updates:Newest(), v) and " (out of date)" or " (up to date)") }
        if newer(Updates:Newest(), v) and ns.Watch and ns.Watch:IsModerator() then
            lines[#lines + 1] = { text = "Ask to update RUIN", fn = function() local ok, e = Updates:AskToUpdate(name); ns:Print(ok and ("Asked " .. ns.ShortName(name) .. " to update.") or e) end }
        end
    else
        lines[#lines + 1] = { text = "Check RUIN version", fn = function() local ok, e = Updates:Check(name); if not ok then ns:Print(e) end end }
    end
    if ns.Watch and ns.Org:Get() then
        lines[#lines + 1] = { text = "Report to the RUIN Watch", fn = function() ns.Watch:PromptReport(name) end }
    end
    return lines
end

local hooked = false
function Updates:HookMenus()
    if hooked or not (Menu and type(Menu.ModifyMenu) == "function") then return end
    hooked = true
    for _, which in ipairs(MENUS) do
        pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, function(_, root, ctx)
            if not ns.db or (InCombatLockdown and InCombatLockdown()) then return end
            local lines = Updates:MenuLines(nameFrom(ctx))
            if #lines == 0 then return end
            root:CreateDivider()
            root:CreateTitle("RUIN")
            for _, l in ipairs(lines) do
                if l.title then root:CreateTitle(l.title) else root:CreateButton(l.text, l.fn) end
            end
        end)
    end
end

ns:Subscribe("LOGIN", function() Updates:HookMenus() end)
