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
    { "0.7.2", {
        "Security: the org key is signed by the admin, so nobody else can change it, and the admin can't be impersonated by taking a character's old name. Save your admin recovery code (Settings > Org).",
        "Security: once the admin raises the org's minimum version (Settings > Org), org traffic is encrypted. Only members of the org's guilds can read it, even if the key phrase leaks, and people who leave a guild are locked out.",
        "Privacy: RUIN no longer sends anything derived from your BattleTag.",
        "RUIN older than the org's minimum version can't connect, and says how to update (CurseForge or GitHub).",
    } },
    { "0.7.0", {
        "A new look for the whole suite: flat tabs with RUIN's own icons, a drawing in each page's header, buttons that take the page's color when you use them, real check marks, slim scroll bars and cleaner menus.",
        "Security: a new officer channel goes only to officers RUIN can vouch for, and the admin can lock a demoted officer out (Settings > Org > Lock out officer). Shared prices, quest places, drop counts and crafts are checked before they count.",
        "Privacy: Settings > Display > What RUIN shares about you, to switch off each thing RUIN shares (your zone, recipes, prices, loot, quest log, quest places).",
        "The org admin can hand the admin over to another player (Settings > Org > Transfer admin). Anyone can Leave org, and the admin can Disband it (/ruin leave, /ruin disband).",
        "Community links are read however you write them, and changes reach every member online at once.",
        "With RUIN Pathfinder: the quest database is built in now, so zone and dungeon routes work with nothing else installed. If you still have a RUIN_QuestData folder, you can delete it.",
        "With RUIN Pathfinder: a new route planner walks less (quests that share targets are done in one step), and \"Quests in your log\" in the Guide plans the best order for every quest you have.",
        "With RUIN Pathfinder: reminders when you walk past a quest giver on your route, or into a quest's targets without the quest, in a small alert window with Mark on map.",
        "With RUIN Pathfinder: the Waypoint Editor holds everything about the waypoint: what it shows, its position, when it hides, and when it moves to the screen edge (10% from each side to start). Its card shows at the edge too.",
        "With RUIN Pathfinder: the atlas learns where RUIN members really pick up and hand in quests on WoW Forever. Tabs are now Quests, Guide, Routes, Record, Options, and the original key bindings are back.",
        "With RUIN Codex: Auto spec reads your talent points, so the upgrade line weighs the right spec. A one-hander is compared with your best off hand against a two-hander, and spell math shows on macros too.",
        "With RUIN Exchange: prices keep the lowest buyout, the tooltip's advice is colored (vendor green, AH gold, craft or disenchant red), and the Working Overtime talent counts in skill-up costs (Leveling page).",
    } },
    { "0.6.0", {
        "With RUIN Pathfinder: the step gets the game's waypoint, a pin in the world over the spot with the distance under it.",
        "With RUIN Pathfinder: the tracker's arrow now shows and points the way, even to the next zone over.",
        "Money everywhere shows the game's gold, silver and copper coin icons.",
        "With RUIN Pathfinder: a RUIN waypoint pin over what you're tracking, and Route and Tracked tabs on the tracker.",
    } },
    { "0.5.4", {
        "The party dungeon strip hides while you're inside a dungeon or raid.",
        "Item lookups go out a few at a time, and \"You're doing that too fast\" now says what was asked just before (/ruin toofast).",
        "RUIN waits while other addons are sending and slows down after \"too fast\", so the two don't trip the server's limit together.",
        "With RUIN Pathfinder: City of Dalaran's quest route has every quest, in order, from the attunement to the follow-ups.",
        "With RUIN Pathfinder: a route to the Cozy Sleeping Bag for each faction.",
        "With RUIN Pathfinder: a quest route for every zone, all routes in the Guide's list, and a checkbox to hide the ones you don't want there.",
        "With RUIN Exchange: opening the auction house scans every listing (once every 15 minutes), so prices fill in without searching. /ex scan asks for one.",
        "With RUIN Exchange: your profession window and profession trainers show each recipe's Price per Point, using how close it is to grey.",
        "With RUIN Exchange: vendor prices are tracked and used when they beat the auction house, marked as vendor.",
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
        "With RUIN Codex: every dungeon in the Journal shows everything that drops there, boss by boss, plus trash, read from the quest database while you play. Click an item for its tooltip.",
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
        "Pathfinder reads the quest database that comes with the planner for quest places and routes.",
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
local LETTER_W = 560
local BODY_W = LETTER_W - 56
local function getLetter()
    if letter then return letter end
    local f = CreateFrame("Frame", "RUIN_WhatsNew", UIParent)
    f:SetSize(LETTER_W, 340)
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
    -- the notes scroll between the title and the footer, however long they are
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 20, -86)
    sf:SetPoint("BOTTOMRIGHT", -30, 50)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(BODY_W, 10)
    sf:SetScrollChild(child)
    if Wd.SmoothScroll then Wd.SmoothScroll(sf, 48) end
    f.scroll, f.child = sf, child
    f.body = Wd.Label(child, "", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT", 0, 0)
    f.body:SetWidth(BODY_W)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    if f.body.SetSpacing then f.body:SetSpacing(4) end
    f.ok = Wd.Button(f, "Got it", 96, function() f:Hide() end)
    f.ok:SetPoint("BOTTOMRIGHT", -16, 14)
    f.foot = Wd.Label(f, "", "GameFontHighlightSmall")
    f.foot:SetPoint("LEFT", f, "BOTTOMLEFT", 20, 26)
    f.foot:SetPoint("RIGHT", f.ok, "LEFT", -12, 0)
    f.foot:SetWordWrap(false)
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
    local textH = f.body:GetStringHeight() or 200
    f.child:SetHeight(math.max(10, textH + 4))
    f:SetHeight(math.max(220, math.min(560, textH + 150)))
    f.scroll:SetVerticalScroll(0)
    if Wd.FitScrollBar then Wd.FitScrollBar(f.scroll) end
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
