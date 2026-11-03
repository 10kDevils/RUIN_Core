-- RUIN Core: Party Dungeon Signal
-- When the Ruinous Forever Planner says the best next step is a dungeon, tell
-- the people you are grouped with. Each player's planner is scored into a
-- tiny report ("DM: Need"), the party's reports are tallied into a heat per
-- dungeon, and the heat sets how loud the signal is:
--
--   Heat = 2 x Need + 1 x Could use          (summed over everyone reporting)
--
-- Per player and dungeon:
--   * Gear is the primary decider.
--       gear upgrade is among the next steps  -> Need      (weight 2)
--       gear drop, but later / lower down     -> Could use (weight 1)
--   * Open quests in the dungeon count as Could use (weight 1), however few.
--   * Open quests AND a gear drop for you     -> Need      (weight 2)
--   * Tie-breaker only: open quests count 0.5 each (half a Could use). It
--     never changes the tier, only the order of dungeons with equal heat.
--
-- Parts: pure scoring (testable without the game), the party report
-- (Comms scope PARTY), the strip + toasts, and the optional party-chat post.
-- Phase 1 only: see PartyPlan notes in CHANGELOG for what is still to do.
local ADDON, ns = ...

local Wd = ns.Widgets
local PP = {}
ns.PartyPlan = PP

---------------------------------------------------------------------------
-- Tuning (one place, so play-testing can adjust it)
---------------------------------------------------------------------------
PP.W_NEED, PP.W_COULD, PP.W_QUEST_TIE = 2, 1, 0.5
PP.TOP_STEPS = 3            -- a gear drop in the first N plan steps is a Need
PP.NEED_PRIORITY = 35       -- plan priority 35 or lower (smaller = sooner) is a current target
PP.MAX_DUNGEONS = 4         -- dungeons per report
PP.MAX_ITEMS = 3            -- item ids per dungeon, for the tooltip
PP.EXPIRE = 180             -- seconds before a silent player's report is dropped
PP.RESEND_MIN = 20          -- never send more often than this
PP.AUTOPOST_COOLDOWN = 300  -- per dungeon
-- lowest heat that reaches each tier
PP.TIERS = {
    { name = "Full party", min = 8, level = 4 },
    { name = "Loud",       min = 5, level = 3 },
    { name = "Noticed",    min = 3, level = 2 },
    { name = "Quiet",      min = 1, level = 1 },
}

local KIND_NEED, KIND_COULD = "N", "C"

---------------------------------------------------------------------------
-- Short dungeon names: Codex id, then the built-in list, then initials
---------------------------------------------------------------------------
local BUILTIN = {
    ["ragefire chasm"] = "RFC", ["wailing caverns"] = "WC", ["the deadmines"] = "DM", ["deadmines"] = "DM",
    ["shadowfang keep"] = "SFK", ["blackfathom deeps"] = "BFD", ["the stockade"] = "STOCK", ["stormwind stockade"] = "STOCK",
    ["gnomeregan"] = "GNOMER", ["razorfen kraul"] = "RFK", ["razorfen downs"] = "RFD", ["scarlet monastery"] = "SM",
    ["uldaman"] = "ULD", ["zul'farrak"] = "ZF", ["maraudon"] = "MARA", ["the temple of atal'hakkar"] = "ST",
    ["sunken temple"] = "ST", ["blackrock depths"] = "BRD", ["lower blackrock spire"] = "LBRS",
    ["upper blackrock spire"] = "UBRS", ["blackrock spire"] = "BRS", ["stratholme"] = "STRAT", ["scholomance"] = "SCHOLO",
    ["dire maul"] = "DIRE", ["hall of thanes"] = "HT", ["ruins of lordaeron"] = "RL",
}
local SKIP = { the = true, of = true, ["and"] = true }
local REVERSE = {}   -- short -> full name, for tooltips (first writer wins)
for full, short in pairs(BUILTIN) do
    if not REVERSE[short] or #full > #REVERSE[short] then REVERSE[short] = full end
end

-- Optional: RUIN Codex can offer its own short id (its dungeon ids are rfc, wc, dm ...).
function PP.CodexShort(name)
    local R = rawget(_G, "RUIN_API")
    local mod = R and R.GetModule and R:GetModule("Codex")
    if mod and type(mod.DungeonShort) == "function" then
        local ok, v = pcall(mod.DungeonShort, mod, name)
        if ok and type(v) == "string" and v ~= "" then return v:upper():sub(1, 6) end
    end
    return nil
end

function PP.ShortName(name)
    name = tostring(name or ""):gsub("[|\r\n%c]", ""):sub(1, 60)
    if name == "" then return "?" end
    local key = name:lower()
    local s = PP.CodexShort(name) or BUILTIN[key]
    if s then return s end
    local letters = {}
    for word in name:gmatch("[%a']+") do
        if not SKIP[word:lower()] then letters[#letters + 1] = word:sub(1, 1):upper() end
    end
    if #letters == 0 then return name:sub(1, 3):upper() end
    return table.concat(letters):sub(1, 4)
end

function PP.FullName(short)
    local f = REVERSE[short]
    if not f then return short end
    return (f:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

---------------------------------------------------------------------------
-- Scoring (pure)
---------------------------------------------------------------------------
-- gear: nil | "need" | "could"      quests: number of open quests there
-- Returns "N", "C" or nil
function PP.Classify(gear, quests)
    quests = tonumber(quests) or 0
    if gear == "need" then return KIND_NEED end
    if gear == "could" then return quests > 0 and KIND_NEED or KIND_COULD end   -- quests + a gear drop = a Need
    if quests > 0 then return KIND_COULD end                                     -- quests alone = a Could use
    return nil
end

function PP.Weight(kind)
    if kind == KIND_NEED then return PP.W_NEED end
    if kind == KIND_COULD then return PP.W_COULD end
    return 0
end

function PP.TierFor(heat)
    for _, t in ipairs(PP.TIERS) do
        if heat >= t.min then return t end
    end
    return nil
end

-- reports: name -> { d = { { n = short, k = "N"|"C", q = openQuests, i = { ids } } } }
-- Returns a list of { short, heat, tie, need, could, members = {name = entry}, tier }, hottest first.
function PP.Tally(reports)
    local by, out = {}, {}
    for name, rep in pairs(reports) do
        for _, e in ipairs(rep.d or {}) do
            local k = e.k
            if (k == KIND_NEED or k == KIND_COULD) and type(e.n) == "string" then
                local row = by[e.n]
                if not row then
                    row = { short = e.n, heat = 0, tie = 0, need = 0, could = 0, members = {} }
                    by[e.n] = row
                    out[#out + 1] = row
                end
                row.heat = row.heat + PP.Weight(k)
                row.tie = row.tie + PP.W_QUEST_TIE * (tonumber(e.q) or 0)
                if k == KIND_NEED then row.need = row.need + 1 else row.could = row.could + 1 end
                row.members[name] = e
            end
        end
    end
    for _, row in ipairs(out) do row.tier = PP.TierFor(row.heat) end
    table.sort(out, function(a, b)
        if a.heat ~= b.heat then return a.heat > b.heat end
        if a.tie ~= b.tie then return a.tie > b.tie end      -- final tie-breaker: open quests
        return a.short < b.short
    end)
    return out
end

---------------------------------------------------------------------------
-- Collecting my report from the planner
---------------------------------------------------------------------------
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

-- Open quests per dungeon name, from the planner's own dungeon data.
-- NEEDS CHECKING against a live planner: see the PartyPlan notes.
local function openQuestsByDungeon(P)
    local out = {}
    local level = tonumber(call(UnitLevel, "player")) or 1
    for _, d in ipairs(call(P.WindowDungeons) or {}) do
        local n = 0
        for _, q in ipairs(d.quests or {}) do
            local _, status = call(P.QuestNext, q.id)
            if status ~= "completed" and status ~= "restricted"
                and (not q.minLevel or q.minLevel <= level + 2)
                and not (P.KnownQuestBlock and call(P.KnownQuestBlock, q.id)) then
                n = n + 1
            end
        end
        if n > 0 then out[tostring(d.name)] = n end
    end
    return out
end

-- Returns the report's dungeon list for the local player (may be empty).
function PP.Collect(P)
    local gear, items = {}, {}      -- full dungeon name -> "need"/"could"; -> { ids }
    local plan = call(P.Plan) or {}
    local groupSteps = 0
    for idx, a in ipairs(plan) do
        local it = a.item
        if it and it.mode == "group" and it.activity and a.kind ~= "owned" and a.kind ~= "unknown"
            and a.kind ~= "completed" and a.kind ~= "levelFirst" and a.kind ~= "blocked" then
            local act = tostring(it.activity)
            local current = (tonumber(a.priority) or 99) <= PP.NEED_PRIORITY + (P.char and P.char.mode == "solo" and 5 or 0)
            -- an active party plays as group: the solo +5 does not apply
            local level = (current and idx <= PP.TOP_STEPS) and "need" or "could"
            if gear[act] ~= "need" then gear[act] = level end
            items[act] = items[act] or {}
            if #items[act] < PP.MAX_ITEMS and tonumber(it.id) then items[act][#items[act] + 1] = tonumber(it.id) end
        end
    end
    local quests = openQuestsByDungeon(P)
    local names = {}
    for act in pairs(gear) do names[act] = true end
    for act in pairs(quests) do names[act] = true end
    local out = {}
    for act in pairs(names) do
        local kind = PP.Classify(gear[act], quests[act])
        if kind then
            out[#out + 1] = { n = PP.ShortName(act), k = kind, q = quests[act] or 0, i = items[act] or {}, _full = act }
        end
    end
    table.sort(out, function(a, b)
        local wa, wb = PP.Weight(a.k), PP.Weight(b.k)
        if wa ~= wb then return wa > wb end
        if (a.q or 0) ~= (b.q or 0) then return (a.q or 0) > (b.q or 0) end
        return a.n < b.n
    end)
    while #out > PP.MAX_DUNGEONS do table.remove(out) end
    return out
end

---------------------------------------------------------------------------
-- The party: who is in it, what everyone reported
---------------------------------------------------------------------------
local reports = {}          -- normalized name -> { name, t, ap, d }
local lastSig, lastSent = nil, -999
local lastTier = {}         -- short -> tier level, to toast only on a rise
local lastPost = {}         -- short -> time
PP.reports = reports

-- Names of the other party members (nil in a raid or when not grouped).
function PP.Roster()
    if not (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) then return nil end
    local names = {}
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 1) - 1 do
        local n, realm = UnitName("party" .. i)
        if n then names[#names + 1] = (realm and realm ~= "") and (n .. "-" .. realm) or n end
    end
    return names
end

function PP:InGroup(sender)
    local want = ns.NormalizeName(sender)
    for _, n in ipairs(PP.Roster() or {}) do
        if ns.NormalizeName(n) == want then return true end
    end
    return false
end

function PP:Enabled() return not (ns.db and ns.db.settings.partySignal == false) end
function PP:AutoPost() return not (ns.db and ns.db.settings.partyAutoPost == false) end

local function mine()
    return { name = ns.playerName or "me", t = GetTime(), ap = PP:AutoPost(), d = PP.mineD or {} }
end

-- Everyone's reports that are still fresh, me included.
function PP.Current()
    local now, out = GetTime(), {}
    local roster = {}
    for _, n in ipairs(PP.Roster() or {}) do roster[ns.NormalizeName(n)] = true end
    for key, rep in pairs(reports) do
        if roster[key] and now - rep.t <= PP.EXPIRE then out[rep.name] = rep end
    end
    if PP.Roster() then out[ns.playerName or "me"] = mine() end
    return out
end

function PP.Counts()
    local roster = PP.Roster()
    local size = roster and (#roster + 1) or 1
    local cur = PP.Current()
    local n = 0
    for _ in pairs(cur) do n = n + 1 end
    return n, size
end

---------------------------------------------------------------------------
-- Sending and receiving
---------------------------------------------------------------------------
local function strip(d)
    local out = {}
    for _, e in ipairs(d) do out[#out + 1] = { n = e.n, k = e.k, q = e.q, i = e.i } end
    return out
end
PP.Strip = strip

function PP:Send(force)
    if not self:Enabled() or not PP.Roster() then return end
    local sig = {}
    for _, e in ipairs(PP.mineD or {}) do sig[#sig + 1] = e.n .. e.k .. (e.q or 0) end
    sig = table.concat(sig, ",") .. (PP:AutoPost() and "!" or "")
    if not force and sig == lastSig then return end
    if GetTime() - lastSent < PP.RESEND_MIN then
        if C_Timer then C_Timer.After(PP.RESEND_MIN - (GetTime() - lastSent) + 1, function() PP:Send(false) end) end
        return
    end
    lastSig, lastSent = sig, GetTime()
    ns.Comms:Send("PARTYPLAN", { v = 1, ap = PP:AutoPost() and 1 or 0, d = strip(PP.mineD or {}) }, "PARTY", nil, ns.Comms.PRIORITY.NORMAL)
end

ns.Comms:Register("PARTYPLAN", function(d, sender, scope)
    if scope ~= "PARTY" or type(d) ~= "table" or not PP:Enabled() then return end
    -- the verified sender name must be in my group; nothing inside the data decides who they are
    if not PP:InGroup(sender) then return end
    local rep = { name = ns.ShortName(sender), t = GetTime(), ap = tonumber(d.ap) == 1, d = {} }
    for i, e in ipairs(type(d.d) == "table" and d.d or {}) do
        if i > PP.MAX_DUNGEONS then break end
        if type(e) == "table" and type(e.n) == "string" and (e.k == KIND_NEED or e.k == KIND_COULD) then
            local item = { n = e.n:gsub("[|%c]", ""):sub(1, 8), k = e.k, q = math.min(99, math.max(0, math.floor(tonumber(e.q) or 0))), i = {} }
            for j, id in ipairs(type(e.i) == "table" and e.i or {}) do
                if j <= PP.MAX_ITEMS and tonumber(id) then item.i[#item.i + 1] = tonumber(id) end
            end
            rep.d[#rep.d + 1] = item
        end
    end
    reports[ns.NormalizeName(sender)] = rep
    PP:Evaluate()
end)

-- A newcomer asks for everyone's report; the rest answer after a short random wait.
ns.Comms:Register("PARTYPLANQ", function(_, sender, scope)
    if scope ~= "PARTY" or not PP:InGroup(sender) then return end
    if C_Timer then C_Timer.After(1 + math.random() * 3, function() PP:Send(true) end) end
end)

---------------------------------------------------------------------------
-- Evaluate: tally, toast on a rise, maybe post to party chat
---------------------------------------------------------------------------
local function line(row, size, reporting)
    local of = reporting < size and (" (" .. reporting .. " of " .. size .. " reporting)") or ""
    return ("%d of %d need %s%s"):format(row.need, size, row.short, of)
end
PP.Line = line

-- The poster is the lowest-sorting name among the reporters who allow auto-posting.
local function iAmPoster(cur)
    local best
    for name, rep in pairs(cur) do
        if rep.ap then
            local key = ns.NormalizeName(name)
            if not best or key < best then best = key end
        end
    end
    return best ~= nil and best == ns.NormalizeName(ns.playerName or "")
end

function PP:Evaluate()
    if not self:Enabled() then self:Draw({}, 0, 0); return end
    local cur = PP.Current()
    local rows = PP.Tally(cur)
    local reporting, size = PP.Counts()
    PP.rows, PP.reporting, PP.size = rows, reporting, size
    for _, row in ipairs(rows) do
        local lvl = row.tier and row.tier.level or 0
        local before = lastTier[row.short] or 0
        if lvl > before and lvl >= 2 and row.need + row.could >= 2 then
            local text = "Your party needs " .. line(row, size, reporting)
            if Wd and Wd.Toast then Wd.Toast(text, { sound = lvl >= 3 }) end
            if lvl >= 3 and PP:AutoPost() and iAmPoster(cur) and not (IsInInstance and IsInInstance())
                and GetTime() - (lastPost[row.short] or -9999) > PP.AUTOPOST_COOLDOWN then
                lastPost[row.short] = GetTime()
                if SendChatMessage then pcall(SendChatMessage, "[RUIN] " .. line(row, size, reporting) .. ".", "PARTY") end
            end
        end
        lastTier[row.short] = lvl
    end
    -- a dungeon that fell out of the tally can toast again later
    local present = {}
    for _, row in ipairs(rows) do present[row.short] = true end
    for short in pairs(lastTier) do if not present[short] then lastTier[short] = nil end end
    self:Draw(rows, reporting, size)
end

---------------------------------------------------------------------------
-- The strip (Phase 1: plain, movable, two chips)
---------------------------------------------------------------------------
local strip_ui

local function pips(row, size)
    local s = {}
    for i = 1, size do s[i] = "|cff6f86b8o|r" end
    local n = 0
    for _ = 1, row.need do n = n + 1; s[n] = "|cffe6b862O|r" end                           -- needs it
    for _ = 1, row.could do n = n + 1; if s[n] then s[n] = "|cffe6b862o|r" end end        -- could use it
    return table.concat(s, " ")
end

function PP:Draw(rows, reporting, size)
    if not (Wd and Wd.HudFrame and CreateFrame) then return end
    local shown = {}
    for _, r in ipairs(rows) do if r.tier and #shown < 2 and not (UnitAffectingCombat and UnitAffectingCombat("player") and r.tier.level < 3) then shown[#shown + 1] = r end end
    if #shown == 0 or not PP:Enabled() then
        if strip_ui then strip_ui:Hide() end
        return
    end
    if not strip_ui then
        strip_ui = Wd.HudFrame("RUIN_PartyPlanStrip", "Guild", ns.db.settings, "partyStripPos", { "CENTER", UIParent, "CENTER", -400, 220 })
        strip_ui:SetSize(250, 52)
        strip_ui.rows = {}
        for i = 1, 2 do
            local fs = strip_ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("TOPLEFT", 10, -8 - (i - 1) * 20)
            fs:SetJustifyH("LEFT")
            strip_ui.rows[i] = fs
        end
        strip_ui:EnableMouse(true)
        strip_ui:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            for _, r in ipairs(PP.rows or {}) do
                GameTooltip:AddLine(("%s (%s): %d need, %d could use"):format(PP.FullName(r.short), r.short, r.need, r.could))
                for name, e in pairs(r.members) do
                    GameTooltip:AddLine(("  %s: %s%s"):format(name, e.k == KIND_NEED and "needs it" or "could use it", (e.q or 0) > 0 and (", " .. e.q .. " quests") or ""), 0.8, 0.85, 0.95)
                end
            end
            GameTooltip:Show()
        end)
        strip_ui:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    for i = 1, 2 do
        local r = shown[i]
        strip_ui.rows[i]:SetText(r and ("|cfff2d48a" .. r.short .. "|r  " .. pips(r, size) .. (reporting < size and ("  " .. reporting .. "/" .. size) or "")
            .. (r.tier.level >= 3 and "  |cfff08a4bRun it?|r" or "")) or "")
    end
    strip_ui:Show()
end

---------------------------------------------------------------------------
-- Refreshing my own report, group changes, commands
---------------------------------------------------------------------------
function PP:Update()
    local Pl = ns.Planner
    local P = Pl and Pl:P()
    if not (P and Pl:Ready()) or not self:Enabled() then return end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return end
    PP.mineD = PP.Collect(P)
    self:Send(false)
    self:Evaluate()
end

local pending
function PP:Soon()
    if pending or not C_Timer then return end
    pending = true
    C_Timer.After(2, function() pending = false; PP:Update() end)
end

ns:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    local roster = PP.Roster()
    if not roster then
        for k in pairs(reports) do reports[k] = nil end
        lastTier, lastSig = {}, nil
        PP:Evaluate()
        return
    end
    local here = {}
    for _, n in ipairs(roster) do here[ns.NormalizeName(n)] = true end
    for k in pairs(reports) do if not here[k] then reports[k] = nil end end
    -- ask the party and tell it who I am
    if C_Timer and PP:Enabled() then
        C_Timer.After(1.5, function()
            ns.Comms:Send("PARTYPLANQ", {}, "PARTY", nil, ns.Comms.PRIORITY.NORMAL)
            PP:Update()
            PP:Send(true)
        end)
    end
    PP:Evaluate()
end)

-- Recheck now and then, and whenever the planner redraws.
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30, function() PP:Update() end) end
if ns.Planner and type(ns.Planner.Refresh) == "function" then
    local orig = ns.Planner.Refresh
    ns.Planner.Refresh = function(...) local r = orig(...); PP:Soon(); return r end
end

function PP:Command(rest)
    rest = (rest or ""):lower()
    local s = ns.db.settings
    local function onoff(v) return v ~= "off" end
    local a, b = rest:match("^(%S*)%s*(%S*)$")
    if a == "off" or a == "on" then
        s.partySignal = onoff(a)
        ns:Print("Party dungeon signal " .. (s.partySignal and "on." or "off."))
    elseif a == "post" and (b == "on" or b == "off") then
        s.partyAutoPost = onoff(b)
        ns:Print("Posting the party's need to party chat is " .. (s.partyAutoPost and "on." or "off."))
    else
        local rows = PP.rows or {}
        if #rows == 0 then
            ns:Print("No dungeon is shared in your party right now. /ruin party on|off, /ruin party post on|off.")
        else
            for i, r in ipairs(rows) do
                if i > 3 then break end
                ns:Print(PP.Line(r, PP.size or 1, PP.reporting or 1) .. (r.tier and (" - " .. r.tier.name) or ""))
            end
        end
    end
    if a == "on" or a == "off" or a == "post" then PP:Evaluate() end
end
