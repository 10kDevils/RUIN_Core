-- RUIN Core: the Planner page (Ruinous Forever Planner inside the RUIN window)
-- When the Ruinous Forever Planner addon is installed, RUIN adds a Planner
-- page that shows and drives it: Now, Gear, Quests, Guide, Rating and the
-- planner's other pages, the class and spec it plans for, PvE or PvP, solo
-- or group, and its own windows (targets, quest catalogue, settings, sell
-- estimates, dungeon/XP and route import). Nothing of the planner is copied
-- or replaced: every line and every action comes from the planner itself,
-- through its RuinousForeverPlanner table, and its own /rfp window keeps
-- working.
--
-- What RUIN adds:
-- * Org goals: your planner's group goals (which dungeon drops you still
--   need) are shared with the org, and the Org tab shows who needs what
--   from where, with Find group (RUIN Finder) and whisper.
-- * Crafters: gear targets someone in RUIN can craft show who (RUIN Exchange).
-- * Sell prices: the Sell page can take the auction price RUIN knows for an
--   item as your estimate (RUIN Exchange).
local ADDON, ns = ...

local Wd = ns.Widgets
local C = Wd.COLORS
local GREY, GREEN, GOLD = C.dim, C.good, C.gold

local Planner = {}
ns.Planner = Planner

local PAGES = { "Now", "Gear", "Quests", "Guide", "Rating", "More", "Org" }
local MORE = { "Class quests", "Professions", "Sell", "Group", "Inventory", "Preparation", "Priorities", "Help" }
local CLASS_NAMES = { DRUID = "Druid", HUNTER = "Hunter", MAGE = "Mage", PALADIN = "Paladin", PRIEST = "Priest",
                      ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior" }
local SHARE_GAP, KEEP = 60, 3 * 3600

local ui = { more = "Class quests" }
local peers = {}                -- name -> { t, c, s, l, g = { { a, i, n } } }
local lastSig, lastSent = nil, -999

-- The planner, once it's loaded and knows your character; else nil.
function Planner:P()
    local P = rawget(_G, "RuinousForeverPlanner")
    if type(P) == "table" and type(P.Render) == "function" then return P end
    return nil
end
function Planner:Ready()
    local P = Planner:P()
    return P and P.char ~= nil and P.profile ~= nil
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

local function clean(v) return (tostring(v or ""):gsub("|", "||")) end

---------------------------------------------------------------------------
-- RUIN Exchange helpers (when installed)
---------------------------------------------------------------------------
local function exchange() return RUIN_API and RUIN_API:GetModule("Exchange") end

local function craftersText(name)
    local X = exchange()
    if not (X and X.CraftersOf and name) then return nil end
    local who = call(X.CraftersOf, name)
    if type(who) ~= "table" or #who == 0 then return nil end
    local short = {}
    for i, n in ipairs(who) do if i > 4 then short[#short + 1] = "+" .. (#who - 4); break end; short[#short + 1] = ns.ShortName(n) end
    return GREEN .. "RUIN crafters: " .. table.concat(short, ", ") .. "|r"
end

---------------------------------------------------------------------------
-- The pages: lines from the planner's own functions
---------------------------------------------------------------------------
local function itemText(item)
    if not item then return "Empty / not applicable (when scan is complete)" end
    return clean(item.name or "Item data pending") .. " [ID " .. tostring(item.id or "?") .. "]"
end

local function pageLines(P, page)
    local lines = {}
    local function add(t) lines[#lines + 1] = t end
    local function addAll(list) for _, l in ipairs(type(list) == "table" and list or {}) do add(l) end end
    local c = P.char
    local level = call(P.Safe, UnitLevel, "player") or 0
    local faction = call(P.Safe, UnitFactionGroup, "player") or "Unknown"
    local opts = type(P.UIOptions) == "function" and (call(P.UIOptions) or {}) or {}
    if c.class ~= P.actualClass then add(C.warn .. "Preview profile: scanned gear belongs to your current character.|r") end
    if P.deferred or P.scanStale then add(C.warn .. "Gear scan needs refreshing before comparing upgrades (Scan gear).|r") end
    if P.snapshot and #(P.snapshot.errors or {}) > 0 then add(C.warn .. "Some gear could not be read. Use Scan gear to retry.|r") end
    if page == "Gear" or page == "Quests" then add(GREY .. clean(call(P.CoverageMessage) or "") .. "|r") end
    if (page == "Gear" or page == "Priorities") and opts.optimization then add(clean(call(P.OptimizationSummary) or "")) end
    if #lines > 0 then add(" ") end

    if page == "Now" then
        addAll(call(P.NextActionLines, false))
    elseif page == "Gear" then
        if opts.gear == false then add("Gear is turned off in the planner's settings."); return lines end
        local targets = call(P.Targets, level) or {}
        local snap = P.snapshot
        if #targets == 0 then
            add("No verified current-level gear targets in this profile / activity filter.")
            addAll(call(P.ClassLevelNotes, level)); addAll(call(P.UpcomingTargetLines, level))
        end
        local index = P.inspectIndex or 1
        add(GREY .. ("Page %d / %d  ·  %d candidates. Previous / Next pick a candidate.|r"):format(math.floor((index - 1) / 6) + 1, math.max(1, math.ceil(#targets / 6)), #targets))
        for i, g in ipairs(targets) do
            if math.floor((i - 1) / 6) == math.floor((index - 1) / 6) then
                add(" ")
                add((i == index and (GOLD .. "> |r") or "") .. C.white .. clean(g.name) .. "|r" .. GREY .. "  ·  " .. clean(g.mode) .. "  ·  " .. clean(g.levelNote or ("source wear level " .. tostring(g.min))) .. "|r")
                local est = call(P.UpgradeEstimate, g)
                if est then add(clean(call(P.UpgradeDisplay, est) or "")) end
                add(("State: %s  ·  slot %s"):format(clean(call(P.CandidateOwned, g) or "?"), clean(P.slotNames and P.slotNames[g.slot] or g.slot)))
                add("Equipped: " .. itemText(snap and snap.equipped and snap.equipped[g.slot]))
                local crafters = craftersText(g.name)
                if crafters then add(crafters) end
                if g.acquire then add(GREY .. clean(g.acquire) .. "|r") end
                if g.materials then add(GREY .. clean(g.materials) .. "|r") end
            end
        end
    elseif page == "Quests" then
        add(GOLD .. "Quest rewards for your gear, level and profile|r")
        local rewards = call(P.QuestRecommendations) or {}
        if #rewards == 0 then add("No unfinished reward candidate for your current gear, level and profile.") end
        for i, r in ipairs(rewards) do
            if i > 6 then break end
            add(" ")
            add(C.white .. clean(r.item and r.item.name) .. "|r  " .. clean(call(P.UpgradeDisplay, r.estimate) or ""))
            add("Next: " .. clean(r.nextText)); add(GREY .. clean(r.reason) .. "|r")
            if r.item and r.item.acquire then add(GREY .. clean(r.item.acquire) .. "|r") end
        end
        add(" "); add(GREY .. clean(P.baselineMessage or "QuestieDB baseline not initialized.") .. "|r")
        add(GREY .. "Quest catalogue searches every quest the planner knows; Track pins one.|r")
    elseif page == "Guide" then
        if opts.leveling == false then add("Leveling is turned off in the planner's settings."); return lines end
        call(P.StartEfficiencyLoad)
        addAll(call(P.EfficiencyLines))
        addAll(call(P.ProfessionLines, true))
        local stage = call(P.Stage, call(P.ViewLevel) or level)
        add(" "); add(GOLD .. "Staged quest / crafting plan|r")
        if stage then
            add(stage.min .. "-" .. stage.max .. ": " .. clean(call(P.StageTitle, stage) or ""))
            for _, note in ipairs(call(P.MilestoneNotes, stage) or {}) do add(" "); add(clean(note)) end
            add("Hubs: " .. clean(faction == "Alliance" and stage.alliance or faction == "Horde" and stage.horde or "faction unknown"))
            for i, t in ipairs(call(P.Tasks, stage) or {}) do
                add((c.done[t.id] and (GREEN .. "[done]|r ") or "[  ] ") .. i .. ". " .. clean(t.mode):upper() .. ": " .. clean(t.text))
            end
            add(GREY .. "Toggle a numbered task with Done # below.|r")
        else
            add("No leveling stage for this level.")
        end
    elseif page == "Rating" then
        if opts.optimization == false then add("Gear rating is turned off in the planner's settings."); return lines end
        local report = call(P.OptimizationReport)
        if not report then add("The rating isn't available right now."); return lines end
        add(clean(call(P.OptimizationSummary, report) or ""))
        addAll(call(P.EnchantLines, false))
        if report.source then add(GREY .. "Reference: " .. clean(report.source) .. "|r") end
        add(" "); add(GOLD .. "Increase your rating|r")
        if #(report.recommendations or {}) == 0 then add("No measurable increase in the evaluated slots.") end
        for i, rec in ipairs(report.recommendations or {}) do
            if i > 5 then break end
            add(GREEN .. ("+%.1f rating points: "):format(rec.gainPoints or 0) .. "|r" .. clean(rec.title))
            add(GREY .. clean(rec.why) .. "|r")
            local crafters = rec.item and craftersText(rec.item.name)
            if crafters then add(crafters) end
        end
        add(" "); add(GOLD .. "Slot breakdown|r")
        for _, row in ipairs(report.slots or {}) do
            add(clean(row.label) .. ": " .. (row.certified and "matches the certified item and enchant" or row.ratio and ("%.1f%% of the weighted benchmark"):format(row.ratio * 100) or clean(row.reason or "unknown")))
        end
    elseif page == "Class quests" then
        addAll(call(P.ClassQuestLines, false))
    elseif page == "Professions" then
        addAll(call(P.ProfessionLines, false))
    elseif page == "Sell" then
        addAll(call(P.SellLines))
        local item = call(P.SelectedSellItem)
        local X = exchange()
        if item and X and X.PriceOf then
            local price = call(X.PriceOf, item.id)
            add(" ")
            add(price and (GREEN .. "RUIN Exchange: about " .. Wd.Money(price) .. " each on the auction house. Use RUIN price takes it as your estimate.|r")
                or (GREY .. "RUIN Exchange has no auction price for this item yet.|r"))
        end
    elseif page == "Group" then
        add(GOLD .. "Your group objectives|r  " .. GREY .. "(the Org tab shows the whole org's)|r")
        local groups, names = {}, {}
        for _, a in ipairs(call(P.GroupGoals) or {}) do
            local act = a.item and a.item.activity or "Other group activity"
            if not groups[act] then groups[act] = {}; names[#names + 1] = act end
            table.insert(groups[act], a)
        end
        table.sort(names)
        if #names == 0 then add("No outstanding group objectives.") end
        for _, n in ipairs(names) do
            add(" "); add(C.white .. clean(n) .. "|r: " .. #groups[n] .. " objective(s)")
            for _, a in ipairs(groups[n]) do add(clean(a.title)); add(GREY .. clean(a.why) .. "|r") end
        end
    elseif page == "Inventory" then
        local snap = P.snapshot
        if not snap then add("No scan yet: Scan gear."); return lines end
        add(GOLD .. "Equipped|r")
        for _, slot in ipairs(P.slotOrder or {}) do add(clean(P.slotNames[slot]) .. ": " .. itemText(snap.equipped[slot])) end
        add(" "); add(GOLD .. "Carried bags|r")
        for _, it in ipairs(snap.bags or {}) do add(("Bag %s/%s x%s: %s"):format(it.bag, it.slot, tostring(it.count), itemText(it))) end
    elseif page == "Preparation" then
        add(GOLD .. "Preparation for milestone " .. clean(call(P.Milestone) or "?") .. "|r")
        for _, a in ipairs(call(P.Plan) or {}) do
            if a.item then
                add(" "); add(clean(a.title)); add(GREY .. clean(a.item.acquire) .. "|r"); add(GREY .. clean(a.item.materials) .. "|r")
                add("Gate: " .. clean(P.profile.gates[tostring(a.item.id)] or "unknown") .. " (manual)  ·  item " .. tostring(a.item.id))
            end
        end
    elseif page == "Priorities" then
        call(P.StartEfficiencyLoad)
        addAll(call(P.EfficiencyLines, nil, true))
        add(" "); add(GOLD .. "Personalized next actions|r")
        local plan = call(P.Plan) or {}
        if #plan == 0 then add("No outstanding gear actions. Continue nearby leveling quests.") end
        for i, a in ipairs(plan) do
            if i > 4 then break end
            add(" "); add(clean(a.title))
            if a.item then local est = call(P.UpgradeEstimate, a.item); if est and est.percent then add(clean(call(P.UpgradeDisplay, est) or "")) end end
        end
    else -- Help
        add("This page shows Ruinous Forever Planner inside the RUIN window. Its own window (/rfp) keeps working; both show the same planner.")
        add(" ")
        add("Now: the next actions. Gear: target items for your profile and level. Quests: quest rewards worth doing. Guide: the ten-level plan. Rating: how close your gear is to the reference.")
        add("More: class quests, professions, the sell advisor, group objectives, inventory, preparation and priorities. Org: who in RUIN needs what from which dungeon.")
        add(" ")
        add("Commands: /rfp opens the planner's own window; /rfp doctor reports what it can and can't read.")
    end
    return lines
end

Planner.PageLines = pageLines

---------------------------------------------------------------------------
-- Org goals: share your group goals, see everyone's
---------------------------------------------------------------------------
local function myGoals(P)
    local out, seen = {}, {}
    for _, a in ipairs(call(P.GroupGoals) or {}) do
        local it = a.item
        if it and it.id and not seen[it.id] and #out < 10 then
            seen[it.id] = true
            out[#out + 1] = { a = tostring(it.activity or "Group"):sub(1, 40), i = tonumber(it.id), n = tostring(it.name or ""):gsub("|", ""):sub(1, 60) }
        end
    end
    return out
end

function Planner:Share(force)
    local P = Planner:P()
    if not (P and Planner:Ready() and ns.Comms:IsJoined("ORG")) then return end
    if ns.db and ns.db.settings.plannerShare == false then return end
    local goals = myGoals(P)
    local parts = {}
    for _, g in ipairs(goals) do parts[#parts + 1] = g.a .. ":" .. tostring(g.i) end
    local sig = (P.char.class or "") .. (P.char.spec or "") .. table.concat(parts, ",")
    if not force and sig == lastSig then return end
    if GetTime() - lastSent < SHARE_GAP then
        C_Timer.After(SHARE_GAP - (GetTime() - lastSent) + 1, function() Planner:Share(false) end)
        return
    end
    lastSig, lastSent = sig, GetTime()
    ns.Comms:Send("PLAN", { c = P.char.class, s = P.char.spec, l = UnitLevel("player"), g = goals }, "ORG", nil, ns.Comms.PRIORITY.BULK)
end

ns.Comms:Register("PLAN", function(d, sender, scope)
    if scope ~= "ORG" or type(d) ~= "table" or type(d.g) ~= "table" then return end
    local e = { t = GetTime(), c = type(d.c) == "string" and d.c or nil, s = type(d.s) == "string" and d.s:sub(1, 20) or nil, l = tonumber(d.l), g = {} }
    for i, g in ipairs(d.g) do
        if i > 10 then break end
        if type(g) == "table" and type(g.a) == "string" and tonumber(g.i) then
            e.g[#e.g + 1] = { a = g.a:sub(1, 40), i = tonumber(g.i), n = type(g.n) == "string" and g.n:gsub("|", ""):sub(1, 60) or "" }
        end
    end
    peers[sender] = #e.g > 0 and e or nil
    Planner:Refresh()
end)

ns.Comms:Register("PLANQ", function(_, _, scope)
    if scope ~= "ORG" then return end
    C_Timer.After(2 + math.random() * 8, function() Planner:Share(true) end)
end)

-- { { activity, people = { { name, class, level, items = { names } } } } }, most people first
function Planner:OrgGoals()
    local by, out = {}, {}
    local P = Planner:P()
    local function add(name, class, level, goals)
        for _, g in ipairs(goals) do
            local a = by[g.a]
            if not a then a = { activity = g.a, people = {}, idx = {} }; by[g.a] = a; out[#out + 1] = a end
            local p = a.idx[name]
            if not p then p = { name = name, class = class, level = level, items = {} }; a.idx[name] = p; a.people[#a.people + 1] = p end
            p.items[#p.items + 1] = g.n ~= "" and g.n or ("item " .. g.i)
        end
    end
    for name, e in pairs(peers) do
        if GetTime() - e.t > KEEP then peers[name] = nil else add(name, e.c, e.l, e.g) end
    end
    if P and Planner:Ready() then add(ns.playerName or "you", P.actualClass, UnitLevel("player"), myGoals(P)) end
    table.sort(out, function(a, b) if #a.people ~= #b.people then return #a.people > #b.people end return a.activity < b.activity end)
    return out
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function refreshSoon() C_Timer.After(0.1, function() Planner:Refresh() end) end

local function act(fn) return function(...) local P = Planner:P(); if P and Planner:Ready() then call(fn, P, ...); refreshSoon() end end end

local function buildText(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(700, 10)
    sf:SetScrollChild(child)
    local fs = Wd.Label(child, "", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 4, -4)
    fs:SetWidth(690)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    if fs.SetSpacing then fs:SetSpacing(3) end
    sf:EnableMouseWheel(true)
    return { frame = sf, child = child, text = fs }
end

local function setText(view, lines)
    view.text:SetWidth(math.max(200, (view.frame:GetWidth() or 700) - 10))
    view.text:SetText(table.concat(lines, "\n"))
    view.child:SetWidth(math.max(200, (view.frame:GetWidth() or 700) - 4))
    view.child:SetHeight(math.max(10, (view.text:GetStringHeight() or 10) + 12))
    if Wd.FitScrollBar then Wd.FitScrollBar(view.frame) end
end

local function buildPage(panel)
    ui.panel = panel
    ui.tabs = Wd.SubTabs(panel, PAGES, function() ui.view.frame:SetVerticalScroll(0); Planner:Refresh() end)
    -- the page body lives on one frame below the tabs, shared by every sub-tab
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", 0, -Wd.SUBTAB_HEIGHT)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.body = body

    -- profile row
    ui.class = Wd.Dropdown(body, 120, function()
        local P, out = Planner:P(), {}
        for k in pairs(P and P.Data and P.Data.profiles or {}) do out[#out + 1] = k end
        table.sort(out)
        return out
    end, function() local P = Planner:P(); return P and P.char and P.char.class end, act(function(P, v)
        local spec = (P.char.preferredSpecs and P.char.preferredSpecs[v]) or P.Data.profiles[v][1]
        P.Profile(v, spec); P.inspectIndex = 1
    end))
    ui.class.format = function(v) return CLASS_NAMES[v] or tostring(v) end
    ui.class:SetPoint("TOPLEFT", 0, 0)
    ui.spec = Wd.Dropdown(body, 120, function()
        local P = Planner:P()
        return P and P.char and P.Data.profiles[P.char.class] or {}
    end, function() local P = Planner:P(); return P and P.char and P.char.spec end, act(function(P, v) P.Profile(P.char.class, v); P.inspectIndex = 1 end))
    ui.spec:SetPoint("LEFT", ui.class, "RIGHT", 4, 0)
    ui.context = Wd.Button(body, "PvE", 64, act(function(P) P.Context(P.char.context == "PvE" and "PvP" or "PvE") end))
    ui.context:SetPoint("LEFT", ui.spec, "RIGHT", 4, 0)
    ui.context.tip = "Plan for PvE or PvP gear"
    ui.mode = Wd.Button(body, "Solo", 70, act(function(P) P.char.mode = P.char.mode == "solo" and "group" or "solo" end))
    ui.mode:SetPoint("LEFT", ui.context, "RIGHT", 4, 0)
    ui.mode.tip = "Solo targets only, or group (dungeon) targets too"
    ui.scan = Wd.Button(body, "Scan gear", 84, act(function(P) P.Scan() end))
    ui.scan:SetPoint("LEFT", ui.mode, "RIGHT", 4, 0)
    ui.window = Wd.Button(body, "Planner window", 116, function() local P = Planner:P(); if P then call(P.Show) end end)
    ui.window:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    ui.window.tip = "The planner's own window (/rfp)"
    ui.moreBtn = Wd.Dropdown(body, 140, MORE, function() return ui.more end, function(v) ui.more = v; Planner:Refresh() end, "Page: ")
    ui.moreBtn:SetPoint("RIGHT", ui.window, "LEFT", -4, 0)

    ui.info = Wd.Label(body, "", "GameFontHighlightSmall")
    ui.info:SetPoint("TOPLEFT", 2, -30)
    ui.info:SetWidth(740)
    ui.info:SetJustifyH("LEFT")
    ui.info:SetWordWrap(false)

    ui.view = buildText(body)
    ui.view.frame:SetPoint("TOPLEFT", 0, -46)
    ui.view.frame:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -24, 64)

    -- Org goals list (the Org tab)
    ui.org = Wd.List(body, 22, function(row)
        row.a = Wd.Label(row, "")
        row.a:SetPoint("LEFT", 6, 0); row.a:SetWidth(220); row.a:SetWordWrap(false)
        row.b = Wd.Label(row, "", "GameFontHighlightSmall")
        row.b:SetPoint("LEFT", 232, 0); row.b:SetPoint("RIGHT", row, "RIGHT", -110, 0); row.b:SetWordWrap(false)
        row.btn = Wd.Button(row, "Find group", 100)
        row.btn:SetPoint("RIGHT", -2, 0)
    end, function(row, e)
        if e.head then
            row.a:SetText(GOLD .. clean(e.g.activity) .. "|r")
            row.b:SetText(GREY .. #e.g.people .. " member" .. (#e.g.people == 1 and "" or "s") .. " need drops here|r")
            local F = RUIN_API:GetModule("Finder")
            row.btn:SetText("Find group")
            row.btn:SetShown(F and F.QuickList ~= nil)
            row.btn:SetScript("OnClick", function()
                local Fi = RUIN_API:GetModule("Finder")
                if Fi and Fi.QuickList then Fi:QuickList("Dungeon", e.g.activity); ns:Print("Listed you in RUIN Finder for " .. clean(e.g.activity) .. ".") end
            end)
        else
            local p = e.p
            row.a:SetText("   " .. Wd.ClassName(p.name, p.class) .. GREY .. (p.level and ("  " .. p.level) or "") .. "|r")
            row.b:SetText(GREY .. clean(table.concat(p.items, ", ")) .. "|r")
            local me = ns.NormalizeName(p.name) == ns.NormalizeName(ns.playerName or "")
            row.btn:SetText("Whisper")
            row.btn:SetShown(not me)
            row.btn:SetScript("OnClick", function() if ChatFrame_SendTell then ChatFrame_SendTell(p.name) end end)
        end
    end)
    ui.org.frame:SetPoint("TOPLEFT", 0, -46)
    ui.org.frame:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -24, 124)
    ui.shareCheck = Wd.Check(body, "Share my group goals with the org", function() return not (ns.db and ns.db.settings.plannerShare == false) end,
        function(v) ns.db.settings.plannerShare = v and true or false; if v then Planner:Share(true) end end)
    ui.shareCheck:SetPoint("BOTTOMLEFT", 2, 36)
    -- Party dungeon signal (PartyPlan.lua): both on unless switched off
    local function partyOn(key) return function() return not (ns.db and ns.db.settings[key] == false) end end
    ui.partyCheck = Wd.Check(body, "Show my party which dungeons I need", partyOn("partySignal"),
        function(v) if ns.PartyPlan then ns.PartyPlan:SetSetting("partySignal", v) end end)
    ui.partyCheck:SetPoint("BOTTOMLEFT", 2, 92)
    ui.partyCheck.tip = "Your planner's dungeon needs go to the people you are grouped with, and their needs show on a small strip."
    ui.postCheck = Wd.Check(body, "Say it in party chat when most of us need it", partyOn("partyAutoPost"),
        function(v) if ns.PartyPlan then ns.PartyPlan:SetSetting("partyAutoPost", v) end end)
    ui.postCheck:SetPoint("BOTTOMLEFT", 2, 64)
    ui.postCheck.tip = "When a dungeon gets loud (heat 5 or more), one player in the party posts \"3 of 5 need DM\" once. Never inside an instance."

    -- action rows
    local function btn(text, w, fn, tip) local b = Wd.Button(body, text, w, fn); b.tip = tip; return b end
    ui.primary = btn("Pin next action", 140, function()
        local P = Planner:P()
        if not (P and Planner:Ready()) then return end
        local page = ui.page
        if page == "Now" then call(P.PinNextAction)
        elseif page == "Sell" then call(P.ShowSellEstimates)
        elseif page == "Class quests" then local first = (call(P.ClassQuestPlan) or { rows = {} }).rows[1]; if first then call(P.PinClassQuest, first.quest.id) end
        elseif page == "Guide" then local first = (call(P.EfficiencyPlan) or { actions = {} }).actions[1]; if first then call(P.PinEfficiencyGoal, first) end
        else
            local first = ((call(P.OptimizationReport) or {}).recommendations or {})[1]
            if first and first.kind == "enchant" then call(P.PinEnchantGoal, first)
            elseif first and first.item then
                call(P.UIOptions); P.profile.tracked = P.profile.tracked or {}
                P.profile.tracked[tostring(first.item.id)] = true
                if first.partner then P.profile.tracked[tostring(first.partner.id)] = true end
                call(P.UpdateControls)
            end
        end
        refreshSoon()
    end)
    ui.primary:SetPoint("BOTTOMLEFT", 0, 4)
    ui.prev = btn("Previous", 80, function()
        local P = Planner:P(); if not P then return end
        if ui.page == "Sell" then P.sellIndex = math.max(1, (P.sellIndex or 1) - 1) else P.inspectIndex = math.max(1, (P.inspectIndex or 1) - 1) end
        refreshSoon()
    end)
    ui.prev:SetPoint("LEFT", ui.primary, "RIGHT", 4, 0)
    ui.next = btn("Next", 70, function()
        local P = Planner:P(); if not P then return end
        if ui.page == "Sell" then P.sellIndex = (P.sellIndex or 1) + 1 else P.inspectIndex = (P.inspectIndex or 1) + 1 end
        refreshSoon()
    end)
    ui.next:SetPoint("LEFT", ui.prev, "RIGHT", 4, 0)
    ui.done = Wd.Dropdown(body, 96, { 1, 2, 3, 4, 5, 6, 7, 8 }, function() return nil end, act(function(P, n)
        if ui.page == "Professions" then call(P.ToggleProfessionTask, n); return end
        local tasks = call(P.Tasks, call(P.Stage, call(P.ViewLevel))) or {}
        if tasks[n] then call(P.Toggle, tasks[n].id) end
    end), "Done # ")
    ui.done.format = function(v) return tostring(v) end
    ui.done:SetPoint("LEFT", ui.next, "RIGHT", 4, 0)
    ui.price = btn("Use RUIN price", 120, function()
        local P, X = Planner:P(), exchange()
        local item = P and call(P.SelectedSellItem)
        local price = item and X and X.PriceOf and call(X.PriceOf, item.id)
        if not price then ns:Print("RUIN Exchange has no auction price for this item yet."); return end
        local e = call(P.EconomyDB)
        local old = e and e.estimates and e.estimates[tostring(item.id)]
        if call(P.SetSellEstimate, item.id, price, old and old.de) then ns:Print(("Auction estimate for %s set to %s (RUIN Exchange)."):format(clean(item.name or item.id), Wd.Money(price))) end
        refreshSoon()
    end, "Take the auction price RUIN Exchange knows as your estimate")
    ui.price:SetPoint("LEFT", ui.next, "RIGHT", 4, 0)
    ui.targets = btn("Track targets", 110, function() local P = Planner:P(); if P then call(P.ShowTargets) end end, "The planner's target catalogue")
    ui.targets:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -232, 4)
    ui.catalogue = btn("Quest catalogue", 120, function() local P = Planner:P(); if P then call(P.ShowQuestBrowser) end end)
    ui.catalogue:SetPoint("LEFT", ui.targets, "RIGHT", 4, 0)
    ui.settings = btn("Settings", 104, function() local P = Planner:P(); if P then call(P.ShowOptions) end end, "The planner's own settings")
    ui.settings:SetPoint("LEFT", ui.catalogue, "RIGHT", 4, 0)
    ui.dungeon = btn("Dungeon / XP", 110, function() local P = Planner:P(); if P then call(P.ShowDungeonAdvisor) end end)
    ui.dungeon:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -232, 34)
    ui.route = btn("Import route", 110, function() local P = Planner:P(); if P then call(P.ShowRouteImport) end end)
    ui.route:SetPoint("LEFT", ui.dungeon, "RIGHT", 4, 0)
    ui.waypoint = btn("Map waypoint", 110, function()
        local P = Planner:P(); if not P then return end
        local _, msg = call(P.RouteWaypoint)
        if msg then ns:Print(clean(msg)) end
    end)
    ui.waypoint:SetPoint("LEFT", ui.route, "RIGHT", 4, 0)

    panel:SetScript("OnShow", function() Planner:Refresh() end)
    ui.tabs:Select(1)
end

function Planner:Refresh()
    if not (ui.panel and ui.panel:IsVisible()) then return end
    local P = Planner:P()
    local tab = PAGES[ui.tabs.selected or 1]
    local page = tab == "More" and ui.more or tab
    ui.page = page
    ui.moreBtn:SetShown(tab == "More")
    ui.moreBtn:Refresh()
    local ready = P and Planner:Ready()
    for _, f in ipairs({ ui.class, ui.spec, ui.context, ui.mode, ui.scan }) do f:SetEnabled(ready and true or false) end
    if not ready then
        ui.info:SetText("")
        ui.org.frame:Hide(); ui.shareCheck:Hide(); ui.partyCheck:Hide(); ui.postCheck:Hide(); ui.view.frame:Show()
        setText(ui.view, { P and ("The planner isn't ready: " .. clean(P.dbError or "log in fully, then open this page again.")) or "Ruinous Forever Planner isn't loaded." })
        for _, b in ipairs({ ui.primary, ui.prev, ui.next, ui.done, ui.price, ui.targets, ui.catalogue, ui.settings, ui.dungeon, ui.route, ui.waypoint }) do b:Hide() end
        return
    end
    local c = P.char
    ui.class:Refresh(); ui.spec:Refresh()
    ui.context:SetText(c.context or "PvE")
    ui.mode:SetText(c.mode == "group" and "Group" or "Solo")
    local level = UnitLevel("player") or 0
    ui.info:SetText(GREY .. ("Level %d  ·  %s / %s / %s / %s%s|r"):format(level, CLASS_NAMES[c.class] or c.class, clean(c.spec), clean(c.context), clean(c.mode),
        P.profileDetection and ("  ·  " .. clean(P.profileDetection)) or ""))

    local org = tab == "Org"
    ui.org.frame:SetShown(org); ui.shareCheck:SetShown(org); ui.partyCheck:SetShown(org); ui.postCheck:SetShown(org); ui.view.frame:SetShown(not org)
    if org then ui.partyCheck:Refresh(); ui.postCheck:Refresh() end
    ui.primary:SetShown(not org)
    ui.primary:SetText(page == "Now" and "Pin next action" or page == "Sell" and "Sell estimates" or page == "Class quests" and "Track class quest"
        or page == "Guide" and "Pin top goal" or "Track top upgrade")
    local stepper = page == "Gear" or page == "Sell"
    ui.prev:SetShown(stepper); ui.next:SetShown(stepper)
    ui.done:SetShown(page == "Guide" or page == "Professions")
    ui.done:ClearAllPoints()
    ui.done:SetPoint("LEFT", ui.primary, "RIGHT", 4, 0)
    ui.price:SetShown(page == "Sell" and exchange() ~= nil and exchange().PriceOf ~= nil)
    for _, b in ipairs({ ui.targets, ui.catalogue, ui.settings, ui.dungeon, ui.route }) do b:Show() end
    ui.waypoint:SetShown(page == "Now")

    if org then
        local items = {}
        for _, g in ipairs(Planner:OrgGoals()) do
            items[#items + 1] = { head = true, g = g }
            for _, p in ipairs(g.people) do items[#items + 1] = { p = p } end
        end
        ui.org:SetEmptyText("No one in RUIN has shared group goals yet. Members with the planner share theirs automatically.")
        ui.org:SetItems(items)
        return
    end
    local ok, lines = pcall(pageLines, P, page)
    if not ok then lines = { C.bad .. "The planner couldn't build this page: " .. clean(lines) .. "|r", GREY .. "/rfp doctor reports what it can and can't read.|r" } end
    setText(ui.view, lines)
end

---------------------------------------------------------------------------
-- Setup: the page appears when the planner is installed
---------------------------------------------------------------------------
local added = false
function Planner:Enabled()
    return Planner:P() ~= nil and not (ns.db and ns.db.settings.plannerTab == false)
end

function Planner:AddPage()
    if added or not Planner:Enabled() then return end
    added = true
    ns.UI:AddTab("Planner", buildPage)
    local P = Planner:P()
    -- follow the planner's own refreshes
    if type(P.Refresh) == "function" and hooksecurefunc then
        pcall(hooksecurefunc, P, "Refresh", function() Planner:Refresh(); Planner:Share(false) end)
    end
end

ns:Subscribe("LOGIN", function()
    C_Timer.After(1, function() Planner:AddPage() end)
    C_Timer.NewTicker(300, function() Planner:Share(false) end)
end)
ns:Subscribe("CHANNELS_CHANGED", function()
    if not Planner:P() then return end
    C_Timer.After(20, function()
        if ns.Comms:IsJoined("ORG") then
            ns.Comms:Send("PLANQ", {}, "ORG", nil, ns.Comms.PRIORITY.BULK)
            Planner:Share(true)
        end
    end)
end)
ns:Subscribe("PEERS_CHANGED", function() Planner:Refresh() end)
