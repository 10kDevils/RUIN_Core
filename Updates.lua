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
    { "0.5.4", {
        "The party dungeon strip hides while you're inside a dungeon or raid.",
        "With RUIN Exchange: opening the auction house scans every listing (once every 15 minutes), so prices fill in without searching. /ex scan asks for one.",
        "With RUIN Exchange: your profession window shows each recipe's cost per skill point.",
        "With RUIN Exchange: Leveling uses current RUIN prices, and the Prices list shows the newest prices with their names.",
    } },
    { "0.5.3", {
        "No more Disable / Ignore popup for RUIN Core on reload in WoW Forever.",
        "Fixed \"You're doing that too fast\" when hovering players.",
        "Settings > Org keeps the key phrase hidden, so it never shows on a stream. Show key phrase reveals it for 20 seconds.",
        "With RUIN Exchange: Find: Crafters shows one row per recipe, with the online member who has the lowest skill (they gain the most from crafting it). Click their name for everyone else who can craft it, and switch on Offline crafters to include members who are offline. Whisper now uses the full name.",
        "With RUIN Codex: click an item in the Dungeon Journal for its full tooltip. Each boss shows how often RUIN killed it and how often each listed drop dropped, and a new General list shows the greens and blues from the dungeon's mobs with their chance per mob looted.",
        "Gold accents on buttons, check boxes, tabs and section titles make every page easier to read.",
        "Buttons that open another RUIN addon wear its color: Post in Muster is orange, Quest route is Pathfinder green.",
        "With RUIN Codex: the Journal's sections fold (click a header); quests start folded.",
        "With RUIN Codex: every dungeon in the Journal shows everything that drops there, boss by boss, plus trash, read from QuestieDB while you play. Click an item for its tooltip.",
        "With RUIN Codex and Pathfinder: the Dungeon Journal lists every quest a dungeon has for your faction, with where it starts, the quests that unlock it and whether you've done it. Quest route opens a Pathfinder route through all of them, unlocking quests first; Pathfinder's Routes page has one for every dungeon.",
        "With RUIN Finder: the census mark on a zone's map is now just the winged R, in the corner with the member count. Continent and world maps still show a mark on each zone.",
    } },
    { "0.5.2", {
        "The party dungeon strip shows only the top dungeon now. The button under it opens the other dungeons your party could run, and Show less closes them again.",
        "With RUIN Codex, the party dungeon signal asks Codex whether a drop is an upgrade, so items whose spell damage or healing is on an \"Equip:\" line count for casters and healers.",
    } },
    { "0.5.1", {
        "Party dungeon signal: with Ruinous Forever Planner, RUIN tells your party which dungeon your planner wants. A small strip shows each dungeon, like DM, with a dot per player: filled gold needs a gear upgrade there, a gold ring could use it.",
        "The more of you need the same dungeon, the louder it gets: a toast, then a pulse, a sound and a Run it? button that says \"3 of 5 need DM\" in party chat. One player posts it automatically once it gets loud. Both switches are on the Planner page's Org tab, or /ruin party off.",
    } },
    { "0.5.0", {
        "RUIN 0.5.0: the whole suite moves to 0.5.0 together, with the RUIN emblem and a clean start on Retail.",
    } },
    { "0.4.9", {
        "The official RUIN emblem, the winged R, now marks RUIN across the app: the title bar, the Guild page and tab, the What's new window and the AddOns list.",
    } },
    { "0.4.8", {
        "Retail: the \"blocked from an action\" popup at login is gone (RUIN no longer asks for the combat log there).",
    } },
    { "0.4.7", {
        "Retail: RUIN no longer reorders your chat channels.",
    } },
    { "0.4.6", {
        "With Ruinous Forever Planner installed, the RUIN window has a Planner page: Now, Gear, Quests, Guide, Rating and more, plus Org, which shows who in RUIN needs drops from which dungeon.",
        "Pathfinder reads the QuestieDB addon (the one that comes with the planner) for quest places and routes, no Questie needed.",
        "Codex: dungeon and raid drops reach the whole org more reliably, including groupmates without RUIN, and you catch up on drops you missed while offline.",
        "Exchange: the Planner page shows who in RUIN can craft your targets and uses RUIN's auction prices for selling.",
    } },
    { "0.4.5", {
        "Security update: RUIN now checks who really sent every message. Only the org admin changes the org key, and only the admin and officers can sanction anyone.",
        "Chat: a line shows as its author's only when they sent it; a relayed line says who relayed it (via Name).",
        "Links in other players' text stay clickable; fake system lines, colors and links no longer get through.",
        "Muster, Exchange, Finder and Pathfinder check each message against its sender: nobody changes someone else's event, sign-up, listing, request or the treasury book.",
    } },
    { "0.4.4", {
        "Guild > Watch is for officers only. Members report a player by right-clicking them, from People or a chat line, or with /ruin report.",
        "Muster has five tabs: Events, Plan (Groups and Squads), Loot (Reserves and Drops), Wanted (Most Wanted and Bounties) and Sightings.",
        "Exchange: History sits right after Requests.",
        "Roster: the My note button fits its name.",
    } },
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
    f.emblem = ns.Brand.Draw(f, 40, "wide", "ARTWORK")
    f.emblem:SetPoint("TOP", 0, -12)
    f.title = Wd.Label(f, "", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f.emblem, "BOTTOM", 0, -6)
    f.body = Wd.Label(f, "", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT", 20, -86)
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
    f:SetHeight(math.max(220, math.min(560, (f.body:GetStringHeight() or 200) + 150)))
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
