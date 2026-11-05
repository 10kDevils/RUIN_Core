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
--       a current-level group target (plan priority 35 or better) -> Need (2)
--       a later drop (future level, quest step first, near the end) -> Could use (1)
--       drops the planner measured as no better than what you wear don't count
--   * Open quests (in your quest log) there count as Could use, however few.
--   * Open quests AND a gear drop for you there -> Need (2)
--   * Tie-breaker only: open quests count 0.5 each (half a Could use). It
--     never changes the tier, only the order of dungeons with equal heat.
--
-- Parts: names and scoring (pure, testable without the game), reading the
-- planner, the party report (Comms scope PARTY: only from members of your
-- group, only these message kinds, rate-limited), toasts and the one-player
-- party chat post after the tally settles, and the strip. Retail chat
-- lockdowns and instances keep it quiet.
local ADDON, ns = ...

local Wd = ns.Widgets
local PP = {}
ns.PartyPlan = PP

---------------------------------------------------------------------------
-- Tuning (one place, so play-testing can adjust it)
---------------------------------------------------------------------------
PP.W_NEED, PP.W_COULD, PP.W_QUEST_TIE = 2, 1, 0.5
PP.NEED_PRIORITY = 35       -- a group target at plan priority 35 or better (smaller = sooner) is a Need
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
-- Dungeon names
-- On the wire and in the tally every dungeon has one fixed key (PP.Key):
-- the built-in list below, else the initials of the main words. It never
-- depends on which addons someone has installed, so "DM" from one player
-- and "DM" from another are always the same dungeon. What you SEE is
-- PP.ShortName: RUIN Codex's own id when Codex knows the dungeon, else the key.
---------------------------------------------------------------------------
-- { full name (as the planner spells it), key }. Keys are at most 8 letters.
local BUILTIN = {
    { "Ragefire Chasm", "RFC" }, { "Wailing Caverns", "WC" }, { "The Deadmines", "DM" },
    { "Shadowfang Keep", "SFK" }, { "Blackfathom Deeps", "BFD" }, { "The Stockade", "STOCKS" },
    { "Stormwind Stockade", "STOCKS" }, { "Gnomeregan", "GNOMER" }, { "Razorfen Kraul", "RFK" },
    { "Razorfen Downs", "RFD" }, { "Scarlet Monastery", "SM" }, { "Scarlet Monastery Graveyard", "SMGY" },
    { "Scarlet Monastery Library", "SMLIB" }, { "Scarlet Monastery Armory", "SMARM" },
    { "Scarlet Monastery Cathedral", "SMCATH" }, { "Uldaman", "ULDA" }, { "Zul'Farrak", "ZF" },
    { "Maraudon", "MARA" }, { "Sunken Temple", "ST" }, { "The Temple of Atal'Hakkar", "ST" },
    { "Blackrock Depths", "BRD" }, { "Lower Blackrock Spire", "LBRS" }, { "Upper Blackrock Spire", "UBRS" },
    { "Dire Maul", "DIRE" }, { "Dire Maul East", "DME" }, { "Dire Maul North", "DMN" }, { "Dire Maul West", "DMW" },
    { "Stratholme", "STRAT" }, { "Stratholme Main Gate", "STRATL" }, { "Stratholme Service Gate", "STRATU" },
    { "Scholomance", "SCHOLO" },
    -- WoW Forever dungeons
    { "Hall of Thanes", "HT" }, { "Ruins of Lordaeron", "RL" }, { "Excavation Site: Wetlands", "EXCAV" },
    { "City of Dalaran", "DAL" }, { "The Drowned City", "DROWNED" }, { "Krol'dok Stronghold", "KROLDOK" },
    { "Alcaz Prison", "ALCAZ" }, { "Blackmaw Hold", "BLACKMAW" }, { "Shaper's Terrace", "SHAPER" },
}
local SKIP = { the = true, of = true, ["and"] = true, a = true, ["in"] = true }

local function norm(name)
    local s = tostring(name or ""):lower():gsub("[^%a%d']+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^the ", "")
    return s
end
PP.Norm = norm

local KEY_OF, FULL_OF = {}, {}     -- normalized full name -> key; key -> full name
for _, e in ipairs(BUILTIN) do
    KEY_OF[norm(e[1])] = e[2]
    if not FULL_OF[e[2]] then FULL_OF[e[2]] = e[1] end
end
local learned = {}                 -- key -> full name, from my own planner (initials keys)

local function clean(name) return (tostring(name or ""):gsub("[|%c]", ""):sub(1, 60)) end

-- The fixed key used on the wire and in the tally.
function PP.Key(name)
    name = clean(name)
    if name == "" then return "?" end
    local k = KEY_OF[norm(name)]
    if k then return k end
    local letters = {}
    for word in name:gmatch("[%a']+") do
        local first = word:match("%a")
        if first and not SKIP[word:lower()] then letters[#letters + 1] = first:upper() end
    end
    if #letters == 0 then return "?" end
    return table.concat(letters):sub(1, 4)
end

-- RUIN Codex's own short name for a dungeon ("dm" -> "DM", "hot" -> "HOT"), if it knows it.
function PP.CodexShort(name)
    local R = rawget(_G, "RUIN_API")
    local mod = R and R.GetModule and R:GetModule("Codex")
    if mod and type(mod.DungeonShort) == "function" then
        local ok, v = pcall(mod.DungeonShort, mod, name)
        if ok and type(v) == "string" and v ~= "" then return (v:gsub("[^%w]", ""):upper():sub(1, 8)) end
    end
    return nil
end

-- The short name you see: Codex first, then the key.
function PP.ShortName(name)
    name = clean(name)
    if name == "" then return "?" end
    return PP.CodexShort(name) or PP.Key(name)
end

-- Full name for a key, when the built-in list or my own planner knows it.
function PP.FullName(key)
    return FULL_OF[key] or learned[key] or key
end

-- What the strip shows for a key.
function PP.Display(key)
    local full = FULL_OF[key] or learned[key]
    return full and PP.ShortName(full) or key
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

-- Which planner dungeon a plan step belongs to. Plan steps from the planner's
-- dungeon data carry dungeonID; catalogue steps carry a label such as
-- "Cookie, The Deadmines" or "A quest of the Excavation Site, in the Wetlands".
-- A dungeon matches when every main word of its name is in the label; the
-- longest match wins ("Scarlet Monastery Graveyard" beats "Scarlet Monastery").
local function wordSet(text)
    local set, n = {}, 0
    for w in norm(text):gmatch("[%a%d']+") do
        if not SKIP[w] and not set[w] then set[w] = true; n = n + 1 end
    end
    return set, n
end

function PP.DungeonFor(it, dungeons)
    if type(it) ~= "table" then return nil end
    if it.dungeonID then
        for _, d in ipairs(dungeons) do if d.id == it.dungeonID then return d end end
    end
    local have = wordSet(it.activity)
    local best, bestN = nil, 0
    for _, d in ipairs(dungeons) do
        local want, n = wordSet(d.name)
        local all = n > 0
        for w in pairs(want) do if not have[w] then all = false; break end end
        if all and n > bestN then best, bestN = d, n end
    end
    return best
end

-- The name to use when no planner dungeon matches: the part after the last comma.
local function labelName(activity)
    local s = tostring(activity or "")
    local tail = s:match(",%s*([^,]+)$")
    return clean(tail or s)
end

-- Open quests the player has in a dungeon, judged by the planner itself
-- (P.DungeonQuestRows checks faction, class/race, completion, exclusive and
-- blocked quests, and level). Counted: quests in the quest log. With
-- PP.COUNT_AVAILABLE_QUESTS, quests the planner says you could pick up
-- ("check prerequisites") count too.
PP.COUNT_AVAILABLE_QUESTS = false
function PP.OpenQuests(P, d)
    local rows = call(P.DungeonQuestRows, d)
    if type(rows) ~= "table" then return 0 end
    local n = 0
    for _, r in ipairs(rows) do
        local st = r.state
        if st == "in log" or (PP.COUNT_AVAILABLE_QUESTS and st == "check prerequisites") then
            n = n + 1
        elseif st == "future / minimum unknown" and r.quest and type(r.quest.minLevel) ~= "number" then
            -- the planner can't confirm the level, but the quest is already in the log
            local obs = call(P.QuestObservation, r.quest.id)
            if type(obs) == "table" and obs.active == true and obs.completed ~= true then n = n + 1 end
        end
    end
    return n
end

-- Is a planner item NOT an upgrade for me? RUIN Codex decides when it can:
-- it reads the item's "Equip:" lines (spell damage, healing, crit, hit, mp5 ...)
-- that the item API, and so the planner's own estimate, can miss on
-- Classic-style items. Without Codex, or when Codex can't tell yet (item not
-- loaded), the planner's estimate decides. Unknown counts as an upgrade.
function PP.CodexVerdict(id)
    local R = rawget(_G, "RUIN_API")
    local codex = R and R.GetModule and R:GetModule("Codex")
    if not (codex and type(codex.IsUpgrade) == "function" and tonumber(id)) then return nil end
    local ok, v = pcall(codex.IsUpgrade, codex, tonumber(id))
    if ok and type(v) == "boolean" then return v end
    return nil
end

function PP.NotAnUpgrade(P, it)
    local v = PP.CodexVerdict(it.id)
    if v ~= nil then return not v end
    local est = call(P.UpgradeEstimate, it)
    return type(est) == "table" and type(est.percent) == "number" and est.percent <= 0
end

-- Plan steps that never make a dungeon worth running.
local SKIP_KIND = { owned = true, unknown = true, completed = true, levelFirst = true, blocked = true }

-- How a plan step for a group item scores: "need" or "could".
-- Need: a current-level upgrade the planner asks you to compare now
-- (priority 35 or better: 25 = the slot is empty, 35 = a normal target).
-- Could use: everything later (55 = future level, 40 = a quest step first,
-- +25 near the end of a level window). A solo profile adds 5 to group
-- steps ("Prepare for a future group"); in a party you play as a group, so
-- that 5 is taken back before judging.
function PP.GearLevel(P, a)
    local pr = tonumber(a.priority) or 99
    local id = tostring(a.id or "")
    if id:find("^prepare%-") then pr = pr - 5 end
    local isTarget = id:find("^target%-") or id:find("^prepare%-")
    if isTarget and pr <= PP.NEED_PRIORITY then return "need" end
    return "could"
end

-- Returns the report's dungeon list for the local player (may be empty):
-- { { n = key, k = "N"|"C", q = open quests, i = { item ids } } }, best first.
function PP.Collect(P)
    local all = (type(P.EfficiencyData) == "table" and type(P.EfficiencyData.dungeons) == "table" and P.EfficiencyData.dungeons)
        or call(P.WindowDungeons) or {}
    local byKey = {}       -- key -> { full, gear, items, q }
    local order = {}
    local function slot(full)
        local key = PP.Key(full)
        local e = byKey[key]
        if not e then e = { key = key, full = full, items = {}, q = 0 }; byKey[key] = e; order[#order + 1] = e end
        return e
    end
    for _, a in ipairs(call(P.Plan) or {}) do
        local it = a.item
        local notBetter = type(it) == "table" and it.mode == "group" and PP.NotAnUpgrade(P, it)
        if type(it) == "table" and it.mode == "group" and not SKIP_KIND[a.kind] and (it.activity or it.dungeonID) and not notBetter then
            local d = PP.DungeonFor(it, all)
            local e = slot(d and d.name or labelName(it.activity))
            local lvl = PP.GearLevel(P, a)
            if e.gear ~= "need" then e.gear = lvl end
            if lvl == "need" then e.needs = (e.needs or 0) + 1 end
            local pr = tonumber(a.priority) or 99
            if not e.best or pr < e.best then e.best = pr end
            local id = tonumber(it.id)
            local dup = false
            for _, x in ipairs(e.items) do if x == id then dup = true end end
            if id and not dup and #e.items < PP.MAX_ITEMS then e.items[#e.items + 1] = id end
        end
    end
    for _, d in ipairs(call(P.WindowDungeons) or {}) do
        local n = PP.OpenQuests(P, d)
        if n > 0 then local e = slot(d.name); e.q = e.q + n end
    end
    local out = {}
    for _, e in ipairs(order) do
        local kind = PP.Classify(e.gear, e.q)
        if kind then
            if not FULL_OF[e.key] then learned[e.key] = e.full end
            out[#out + 1] = { n = e.key, k = kind, q = math.min(99, e.q), i = e.items, needs = e.needs or 0, best = e.best or 99 }
        end
    end
    table.sort(out, function(x, y)
        -- Need before Could use; then more upgrades there, the most urgent one, more quests
        local wx, wy = PP.Weight(x.k), PP.Weight(y.k)
        if wx ~= wy then return wx > wy end
        if x.needs ~= y.needs then return x.needs > y.needs end
        if x.best ~= y.best then return x.best < y.best end
        if x.q ~= y.q then return x.q > y.q end
        return x.n < y.n
    end)
    while #out > PP.MAX_DUNGEONS do table.remove(out) end
    return out
end

---------------------------------------------------------------------------
-- The party: who is in it, what everyone reported
---------------------------------------------------------------------------
local reports = {}          -- normalized name -> { name, t, ap, d }
local lastSig, lastSent = nil, -999
local sendQueued = false
local heard = {}            -- normalized sender -> { t = first in window, n = count }
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
    -- me too, once my planner has given me a report (without a planner I only listen)
    if PP.Roster() and PP.mineD then out[ns.playerName or "me"] = mine() end
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
-- On the wire each dungeon is one short string, "DM:N:2:273298,273840"
-- (key, N or C, open quests, up to three item ids), so a full report of
-- four dungeons stays well inside one addon message.
local function encode(d)
    local out = {}
    for _, e in ipairs(d) do
        local ids = {}
        for j, id in ipairs(e.i or {}) do if j <= PP.MAX_ITEMS then ids[#ids + 1] = tostring(math.floor(id)) end end
        out[#out + 1] = ("%s:%s:%d:%s"):format(e.n, e.k, math.min(99, e.q or 0), table.concat(ids, ","))
    end
    return out
end
PP.Encode = encode

-- Parses a received report strictly; anything malformed is dropped. One entry per dungeon.
function PP.Decode(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    for i = 1, math.min(#list, PP.MAX_DUNGEONS) do
        local e = list[i]
        if type(e) == "string" and #e <= 64 then
            local key, k, q, ids = e:match("^(%u[%u%d]?[%u%d]?[%u%d]?[%u%d]?[%u%d]?[%u%d]?[%u%d]?):([NC]):(%d%d?):([%d,]*)$")
            if key and not seen[key] then
                seen[key] = true
                local item = { n = key, k = k, q = tonumber(q), i = {} }
                for id in ids:gmatch("%d+") do
                    if #item.i < PP.MAX_ITEMS and #id <= 7 then item.i[#item.i + 1] = tonumber(id) end
                end
                out[#out + 1] = item
            end
        end
    end
    return out
end

function PP:Send(force)
    -- no planner, no report: a player without one only listens
    if not self:Enabled() or not PP.Roster() or not PP.mineD then return end
    local sig = {}
    for _, e in ipairs(PP.mineD or {}) do sig[#sig + 1] = e.n .. e.k .. (e.q or 0) end
    sig = table.concat(sig, ",") .. (PP:AutoPost() and "!" or "")
    if not force and sig == lastSig then return end
    if GetTime() - lastSent < PP.RESEND_MIN then
        -- one waiting send at most, however many times we are asked
        if C_Timer and not sendQueued then
            sendQueued = true
            C_Timer.After(PP.RESEND_MIN - (GetTime() - lastSent) + 1, function() sendQueued = false; PP:Send(true) end)
        end
        return
    end
    lastSig, lastSent = sig, GetTime()
    ns.Comms:Send("PARTYPLAN", { v = 1, ap = PP:AutoPost() and 1 or 0, d = encode(PP.mineD or {}) }, "PARTY", nil, ns.Comms.PRIORITY.NORMAL)
end

-- At most PP.RECV_MAX reports per sender every PP.RECV_WINDOW seconds; the rest are ignored.
PP.RECV_MAX, PP.RECV_WINDOW = 4, 20
local function allowFrom(key)
    local now = GetTime()
    local h = heard[key]
    if not h or now - h.t > PP.RECV_WINDOW then h = { t = now, n = 0 }; heard[key] = h end
    h.n = h.n + 1
    return h.n <= PP.RECV_MAX
end

ns.Comms:Register("PARTYPLAN", function(d, sender, scope)
    if scope ~= "PARTY" or type(d) ~= "table" or not PP:Enabled() then return end
    -- the verified sender name must be in my group; nothing inside the data decides who they are
    if not PP:InGroup(sender) then return end
    local key = ns.NormalizeName(sender)
    if not allowFrom(key) then return end
    reports[key] = { name = ns.ShortName(sender), t = GetTime(), ap = tonumber(d.ap) == 1, d = PP.Decode(d.d) }
    PP:Evaluate()
end)

-- A newcomer asks for everyone's report; the rest answer after a short random wait.
local answerQueued = false
ns.Comms:Register("PARTYPLANQ", function(_, sender, scope)
    if scope ~= "PARTY" or not PP:Enabled() or not PP:InGroup(sender) then return end
    if not allowFrom(ns.NormalizeName(sender)) or answerQueued or not C_Timer then return end
    answerQueued = true
    C_Timer.After(1 + math.random() * 3, function() answerQueued = false; PP:Send(true) end)
end)

---------------------------------------------------------------------------
-- Chat and instances
-- Retail 12.x locks addon chat during instance encounters, Mythic+ keys and
-- PvP matches: SendChatMessage from an addon is then a blocked action (the
-- "blocked from an action" popup) and addon messages are refused. RUIN
-- checks first and stays quiet. WoW Forever has none of these functions, so
-- there the checks are simply false.
---------------------------------------------------------------------------
function PP.ChatLocked()
    local CI = rawget(_G, "C_ChatInfo")
    if CI and type(CI.InChatMessagingLockdown) == "function" then
        local ok, v = pcall(CI.InChatMessagingLockdown)
        if ok and v then return true end
    end
    local RA = rawget(_G, "C_RestrictedActions")
    if RA and type(RA.IsAddOnRestrictionActive) == "function" then
        local E = rawget(_G, "Enum") and Enum.AddOnRestrictionType
        -- Encounter, ChallengeMode, PvPMatch, Chat
        local types = E and { E.Encounter, E.ChallengeMode, E.PvPMatch, E.Chat } or { 1, 2, 3, 5 }
        for _, t in ipairs(types) do
            local ok, v = pcall(RA.IsAddOnRestrictionActive, t)
            if ok and v then return true end
        end
    end
    return false
end

function PP.InInstance()
    if not IsInInstance then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and inside and true or false
end

-- PARTY, or INSTANCE_CHAT in a group the dungeon finder made.
function PP.ChatType()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return "PARTY"
end

---------------------------------------------------------------------------
-- Evaluate: tally, toast on a rise, maybe post to party chat
---------------------------------------------------------------------------
local function line(row, size, reporting)
    local of = reporting < size and (" (" .. reporting .. " of " .. size .. " reporting)") or ""
    return ("%d of %d need %s%s"):format(row.need, size, PP.Display(row.short), of)
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

-- Says the line in party chat. Returns true when it was sent.
function PP:Post(row, manual)
    if not row or not SendChatMessage then return false end
    if PP.ChatLocked() then
        if manual then ns:Print("Party chat is locked by the game right now (an encounter, a key or a match). Try again after it.") end
        return false
    end
    if not manual and PP.InInstance() then return false end
    lastPost[row.short] = GetTime()
    local ok = pcall(SendChatMessage, "[RUIN] " .. line(row, PP.size or 1, PP.reporting or 1) .. ".", PP.ChatType())
    return ok
end

-- Evaluate redraws at once. Toasts and the party chat post wait until the
-- tally has settled (PP.SETTLE seconds with no new report), so a party that
-- is still hearing from everyone doesn't toast "Noticed" then "Loud", and
-- every client picks the same poster from the same reports.
PP.SETTLE = 4
local announceToken = 0

function PP:Evaluate()
    if not self:Enabled() then PP.rows = {}; self:Draw({}, 0, 0); return end
    local cur = PP.Current()
    local rows = PP.Tally(cur)
    local reporting, size = PP.Counts()
    PP.rows, PP.reporting, PP.size, PP.cur = rows, reporting, size, cur
    -- a dungeon that fell out of the tally can toast again later
    local present = {}
    for _, row in ipairs(rows) do present[row.short] = true end
    for short in pairs(lastTier) do if not present[short] then lastTier[short] = nil end end
    self:Draw(rows, reporting, size)
    announceToken = announceToken + 1
    local mine = announceToken
    if C_Timer then
        C_Timer.After(PP.SETTLE, function() if mine == announceToken then PP:Announce() end end)
    else
        PP:Announce()
    end
end

function PP:Announce()
    if not self:Enabled() or not PP.Roster() then return end
    local rows, size, reporting, cur = PP.rows or {}, PP.size or 1, PP.reporting or 1, PP.cur or {}
    local quiet = PP.InInstance() or PP.ChatLocked()
    for _, row in ipairs(rows) do
        local lvl = row.tier and row.tier.level or 0
        local before = lastTier[row.short] or 0
        if lvl > before and lvl >= 2 and not quiet then
            local text = "Your party: " .. line(row, size, reporting) .. (row.tier and (" (" .. row.tier.name .. ")") or "")
            if Wd and Wd.Toast then Wd.Toast(text, { sound = lvl >= 3 }) end
            if lvl >= 3 and PP:AutoPost() and iAmPoster(cur)
                and GetTime() - (lastPost[row.short] or -9999) > PP.AUTOPOST_COOLDOWN then
                PP:Post(row, false)
            end
        end
        if not quiet then lastTier[row.short] = lvl end
    end
end

-- Someone already said it in party chat (another RUIN player, or the poster
-- before me): don't say it again within the cooldown.
function PP:HeardPost(text)
    local secret = rawget(_G, "issecretvalue")
    if type(text) ~= "string" or (secret and secret(text)) then return end
    local what = text:match("^%[RUIN%] %d+ of %d+ need (%S+)")
    if not what then return end
    what = what:gsub("[%.%s]+$", "")
    for _, row in ipairs(PP.rows or {}) do
        if row.short == what or PP.Display(row.short) == what then lastPost[row.short] = GetTime() end
    end
end
for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    ns:RegisterEvent(ev, function(_, text) PP:HeardPost(text) end)
end

---------------------------------------------------------------------------
-- The strip: the top dungeon (a button opens the rest), a dot per party member
--   filled gold = needs it, gold ring = could use it,
--   grey ring = nothing there, faint grey ring = no RUIN report
-- Quiet and Noticed sit still; Loud pulses orange and shows "Run it?";
-- Full party turns gold. In combat the strip fades and stops pulsing.
---------------------------------------------------------------------------
local PIP = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Pip"
local GOLD, ORANGE, GREY = { 0.90, 0.72, 0.38 }, { 0.94, 0.54, 0.29 }, { 0.44, 0.53, 0.72 }
local ROW_H, ROW_GAP, PIPS = 28, 4, 5
local STRIP_W = 296
local strip_ui
PP.PIP = PIP

local function itemText(id)
    local get = (rawget(_G, "C_Item") and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
    if get then
        local ok, name, link = pcall(get, id)
        if ok and (link or name) then return link or name end
    end
    return "item " .. tostring(id)
end
PP.ItemText = itemText

-- Everyone in the party, me first, for the tooltip and the dots.
local function partyNames()
    local out = { ns.playerName or "me" }
    for _, n in ipairs(PP.Roster() or {}) do out[#out + 1] = ns.ShortName(n) end
    return out
end

function PP.Tooltip(owner, row)
    if not (GameTooltip and row) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    local full = PP.FullName(row.short)
    GameTooltip:AddLine(("%s (%s) - %d of %d need it"):format(full, PP.Display(row.short), row.need, PP.size or 1), GOLD[1], GOLD[2], GOLD[3])
    local cur = PP.cur or {}
    local byKey = {}
    for name, e in pairs(row.members) do byKey[ns.NormalizeName(name)] = { name = name, e = e } end
    for _, name in ipairs(partyNames()) do
        local m = byKey[ns.NormalizeName(name)]
        if m then
            local e = m.e
            local items = {}
            for _, id in ipairs(e.i or {}) do items[#items + 1] = itemText(id) end
            local what = e.k == KIND_NEED and "needs it" or "could use it"
            local extra = {}
            if #items > 0 then extra[#extra + 1] = table.concat(items, ", ") end
            if (e.q or 0) > 0 then extra[#extra + 1] = e.q == 1 and "1 quest" or (e.q .. " quests") end
            GameTooltip:AddLine(("%s %s%s"):format(name, what, #extra > 0 and (": " .. table.concat(extra, "; ")) or ""), 0.95, 0.96, 0.98, true)
        else
            local reported = false
            for n in pairs(cur) do if ns.NormalizeName(n) == ns.NormalizeName(name) then reported = true end end
            GameTooltip:AddLine(name .. (reported and " has nothing there" or " has no RUIN report"), GREY[1], GREY[2], GREY[3])
        end
    end
    local R = rawget(_G, "RUIN_API")
    local codex = R and R.GetModule and R:GetModule("Codex")
    local where = codex and codex.DungeonWhere and select(2, pcall(codex.DungeonWhere, codex, full))
    if type(where) == "string" then GameTooltip:AddLine("Entrance: " .. where, 0.79, 0.83, 0.90) end
    if row.tier and row.tier.level >= 3 then GameTooltip:AddLine("Run it? says it in party chat.", 0.79, 0.83, 0.90) end
    GameTooltip:Show()
end

-- One state per party member: "need", "could", "nothing" (reports nothing there), "none" (no report).
function PP.PipStates(row, size, reporting)
    local out = {}
    local nothing = math.max(0, (reporting or size) - row.need - row.could)
    for p = 1, math.min(size, PIPS) do
        out[p] = (p <= row.need and "need") or (p <= row.need + row.could and "could")
            or (p <= row.need + row.could + nothing and "nothing") or "none"
    end
    return out
end

local function buildRow(parent, i)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(STRIP_W - 16, ROW_H)
    r:SetPoint("TOPLEFT", 8, -8 - (i - 1) * (ROW_H + ROW_GAP))
    r.glow = r:CreateTexture(nil, "BACKGROUND")
    r.glow:SetAllPoints()
    r.chip = r:CreateTexture(nil, "ARTWORK")
    r.chip:SetSize(70, ROW_H - 4)
    r.chip:SetPoint("LEFT", 0, 0)
    r.key = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.key:SetPoint("CENTER", r.chip, "CENTER", 0, 0)
    r.pips = {}
    for p = 1, PIPS do
        local t = r:CreateTexture(nil, "ARTWORK")
        t:SetTexture(PIP)
        t:SetSize(14, 14)
        t:SetPoint("LEFT", r.chip, "RIGHT", 8 + (p - 1) * 17, 0)
        r.pips[p] = t
    end
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetPoint("LEFT", r.pips[PIPS], "RIGHT", 6, 0)
    r.run = Wd.Button(r, "Run it?", 66, function() PP:Post(r.row, true) end)
    r.run:SetPoint("RIGHT", 0, 0)
    r.run.tip = "Say it in party chat"
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self) PP.Tooltip(self, self.row) end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return r
end

local function paintRow(r, row, size)
    r.row = row
    local lvl = row.tier and row.tier.level or 1
    r.key:SetText(PP.Display(row.short))
    if lvl >= 4 then
        r.chip:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1); r.key:SetTextColor(0.04, 0.07, 0.19)
        r.glow:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
    elseif lvl == 3 then
        r.chip:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1); r.key:SetTextColor(0.04, 0.07, 0.19)
        r.glow:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.25)
    elseif lvl == 2 then
        r.chip:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85); r.key:SetTextColor(0.04, 0.07, 0.19)
        r.glow:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.08)
    else
        r.chip:SetColorTexture(0.10, 0.18, 0.44, 1); r.key:SetTextColor(GREY[1], GREY[2], GREY[3])
        r.glow:SetColorTexture(0, 0, 0, 0)
    end
    -- dots: needs, could use, then the rest (reporting with nothing, then no report)
    local states = PP.PipStates(row, size, PP.reporting or size)
    for p = 1, PIPS do
        local t, st = r.pips[p], states[p]
        t:SetShown(st ~= nil)
        if st == "need" then
            t:SetTexCoord(0, 0.5, 0, 1); t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        elseif st == "could" then
            t:SetTexCoord(0.5, 1, 0, 1); t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        elseif st == "nothing" then
            t:SetTexCoord(0.5, 1, 0, 1); t:SetVertexColor(GREY[1], GREY[2], GREY[3], 0.9)
        else
            t:SetTexCoord(0.5, 1, 0, 1); t:SetVertexColor(GREY[1], GREY[2], GREY[3], 0.35)
        end
    end
    r.count:SetText(("%d/%d"):format(row.need, size))
    r.run:SetShown(lvl >= 3)
    r.run:SetText(lvl >= 4 and "Let's go" or "Run it?")
    if r.run.SetEnabled then r.run:SetEnabled(not PP.ChatLocked()) end
    r.pulse = lvl == 3
end

local function inCombat() return UnitAffectingCombat and UnitAffectingCombat("player") and true or false end

-- Only the top dungeon shows; a toggle under it opens the rest (up to
-- PP.STRIP_MAX in all). Open or closed is remembered (settings.partyStripOpen).
PP.STRIP_MAX = 6
local TOGGLE_H = 18

function PP:StripOpen() return ns.db and ns.db.settings.partyStripOpen == true end
function PP:ToggleStrip()
    ns.db.settings.partyStripOpen = not PP:StripOpen()
    PP:Draw(PP.rows or {}, PP.reporting or 0, PP.size or 0)
end

function PP:Draw(rows, reporting, size)
    if not (Wd and Wd.HudFrame and CreateFrame) then return end
    local all = {}
    for _, r in ipairs(rows) do if r.tier and #all < PP.STRIP_MAX then all[#all + 1] = r end end
    if #all == 0 or not PP:Enabled() then
        if strip_ui then strip_ui:Hide() end
        return
    end
    if not strip_ui then
        strip_ui = Wd.HudFrame("RUIN_PartyPlanStrip", "Guild", ns.db.settings, "partyStripPos", { "TOPLEFT", UIParent, "TOPLEFT", 240, -160 })
        strip_ui.rows = {}
        strip_ui.toggle = Wd.Button(strip_ui, "", 120, function() PP:ToggleStrip() end)
        strip_ui.toggle:SetHeight(TOGGLE_H)
        strip_ui.toggle:SetPoint("BOTTOMRIGHT", -8, 6)
        strip_ui.toggle.tip = "Show or hide the other dungeons your party could run"
        local t = 0
        strip_ui:SetScript("OnUpdate", function(self, elapsed)
            t = t + (elapsed or 0)
            local fade = inCombat()
            self:SetAlpha(fade and 0.35 or 1)
            for _, r in ipairs(self.rows) do
                if r:IsShown() and r.pulse and not fade then
                    r.glow:SetAlpha(0.45 + 0.55 * math.abs(math.sin(t * 3)))
                else
                    r.glow:SetAlpha(1)
                end
            end
        end)
        PP.strip = strip_ui
    end
    local open = PP:StripOpen()
    local count = open and #all or 1
    for i = #strip_ui.rows + 1, count do strip_ui.rows[i] = buildRow(strip_ui, i) end
    for i, r in ipairs(strip_ui.rows) do
        if i <= count then paintRow(r, all[i], size); r:Show() else r.row = nil; r.pulse = false; r:Hide() end
    end
    local more = #all - 1
    strip_ui.more = more
    local tog = strip_ui.toggle
    if more > 0 then
        tog:SetText(open and "Show less" or (more == 1 and "1 more dungeon" or (more .. " more dungeons")))
        tog:Show()
    else
        tog:Hide()
    end
    strip_ui:SetSize(STRIP_W, 16 + count * ROW_H + (count - 1) * ROW_GAP + (more > 0 and (TOGGLE_H + 4) or 0))
    strip_ui:SetAlpha(inCombat() and 0.35 or 1)
    strip_ui:Show()
end

-- Settings switches (Planner page checkboxes and /ruin party)
function PP:SetSetting(key, on)
    ns.db.settings[key] = on and true or false
    if key == "partySignal" then
        if on then PP:Update(); PP:Send(true) else PP:Evaluate() end
    else
        lastSig = nil
        PP:Send(false)
    end
end

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() PP:Soon() end)

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
        PP:SetSetting("partySignal", onoff(a))
        ns:Print("Party dungeon signal " .. (s.partySignal and "on." or "off."))
    elseif a == "post" and (b == "on" or b == "off") then
        PP:SetSetting("partyAutoPost", onoff(b))
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
end
