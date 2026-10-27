-- RUIN Core: the Watch (moderation)
-- Any member reports a player (harassment, spam, cheating...) and the report
-- goes to an officer online, who opens a case every officer of the org sees
-- on the Watch page. Officers (and the org admin) act on cases and players:
--   * a warning, on a ladder: the 1st within a day mutes the player in RUIN
--     chat for 5 minutes, the 2nd for 30 minutes, the 3rd for 24 hours;
--   * a mute for a chosen time, or until lifted;
--   * hide from the network: every RUIN client ignores the player's RUIN
--     messages (chat, Finder, Muster...) until lifted;
--   * delete a line from RUIN chat for everyone.
-- Sanctions follow the player's BattleTag: each RUIN client shares a hash of
-- its own BattleTag (salted with the org's name, so it can't be read back or
-- matched across orgs), and a sanction applies to every character with that
-- hash. Moderators may act under a cover name. Every client keeps an action
-- log of what it saw done. RUIN can't change what the game itself shows
-- (guild chat, whispers): the Watch works inside RUIN, on honest clients.
local ADDON, ns = ...

local Wd = ns.Widgets
local P = Wd.PALETTE
local C = Wd.COLORS
local GREY, GREEN, RED, YELLOW = C.dim, C.good, C.bad, C.warn

local Watch = {}
ns.Watch = Watch

Watch.REASONS = { "Harassment", "Spam", "Cheating or exploits", "Griefing", "Scam", "Other" }
local LADDER = { 5 * 60, 30 * 60, 24 * 3600 }          -- mutes for the 1st, 2nd, 3rd warning within a day
local MAX_LOG, MAX_CASES = 400, 300
local CASE_KEEP = 60 * 86400
local RESEND = 300

local function now() return GetServerTime and GetServerTime() or time() end
local function norm(n) return ns.NormalizeName(n or "") end

local function store()
    if not ns.db then return nil end
    local w = ns.db.watch
    if type(w) ~= "table" then w = {}; ns.db.watch = w end
    for _, key in ipairs({ "cases", "sanctions", "outbox", "log", "mine" }) do
        if type(w[key]) ~= "table" then w[key] = {} end
    end
    return w
end

---------------------------------------------------------------------------
-- Who may moderate, and the BattleTag hash
---------------------------------------------------------------------------
function Watch:IsModerator()
    return ns.Org:IsAdmin() or (ns.Org:MyGuildInOrg() and ns.Org:AmOfficer())
end

-- Is this sender a moderator? Your guild's roster for guildmates; what their
-- RUIN reports for other guilds; the org admin by GUID.
local function senderIsModerator(name)
    local k = ns.Org:Get()
    local peer = ns.Presence:OrgPeerByName(name)
    if k and peer and peer.guid == k.admin then return true end
    return ns.Presence:IsOfficerName(name)
end
Watch.SenderIsModerator = senderIsModerator

function Watch:MyTagHash()
    local k = ns.Org:Get()
    if not (k and BNGetInfo) then return nil end
    local ok, _, tag = pcall(BNGetInfo)
    if not ok or type(tag) ~= "string" or tag == "" or (issecretvalue and issecretvalue(tag)) then return nil end
    tag = tag:lower()
    return ns.Hash(k.org .. "|" .. tag) .. ns.Hash(tag .. "|" .. k.org)
end

local function tagOf(name)
    if norm(name) == norm(ns.playerName) then return Watch:MyTagHash() end
    local p = ns.Presence:OrgPeerByName(name)
    return p and p.bt or nil
end

---------------------------------------------------------------------------
-- Action log: what this client saw done
---------------------------------------------------------------------------
function Watch:Log(actor, act, detail)
    local w = store()
    if not w then return end
    w.log[#w.log + 1] = { t = now(), a = tostring(actor or "?"):sub(1, 48), act = tostring(act or ""):sub(1, 24),
                          d = tostring(detail or ""):gsub("|", "/"):sub(1, 140) }
    while #w.log > MAX_LOG do table.remove(w.log, 1) end
    ns:Fire("WATCH_CHANGED")
end

function Watch:LogLines()
    local w, out = store(), {}
    for i = #(w and w.log or {}), 1, -1 do out[#out + 1] = w.log[i] end
    return out
end

---------------------------------------------------------------------------
-- Sanctions
---------------------------------------------------------------------------
local function active(s, at)
    at = at or now()
    return s and not s.lifted and (s.kind ~= "warn") and ((s.untilT or 0) == 0 or s.untilT > at)
end

local function matches(s, name, tag)
    if name and norm(s.target) == norm(name) then return true end
    if tag and s.tag and s.tag == tag then return true end
    return false
end

-- The strongest sanction in force on a player (by name, or any character on
-- the same BattleTag): the sanction, or nil.
function Watch:SanctionOn(name, kind)
    local w = store()
    if not w then return nil end
    local tag = tagOf(name)
    local at, best = now(), nil
    for _, s in pairs(w.sanctions) do
        if active(s, at) and matches(s, name, tag) and (not kind or s.kind == kind) then
            if not best or s.kind == "hide" then best = s end
        end
    end
    return best
end

function Watch:IsHidden(name) return Watch:SanctionOn(name, "hide") ~= nil end
-- Any hide in force at all? (a cheap check before the per-message one)
function Watch:AnyHidden()
    local w, at = store(), now()
    for _, s in pairs(w and w.sanctions or {}) do
        if s.kind == "hide" and active(s, at) then return true end
    end
    return false
end
function Watch:IsMuted(name) return Watch:SanctionOn(name) ~= nil end      -- a hide mutes too

-- Sanctions in force, newest first.
function Watch:Sanctions(all)
    local w, out, at = store(), {}, now()
    for _, s in pairs(w and w.sanctions or {}) do
        if all or active(s, at) then out[#out + 1] = s end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return out
end

local function whoDid(s)
    if s.cover and s.cover ~= "" then return "Moderator " .. s.cover end
    return ns.ShortName(s.by or "?")
end
Watch.WhoDid = whoDid

local function describe(s)
    local length = (s.untilT or 0) == 0 and "until lifted" or ("for " .. Wd.Duration(math.max(0, s.untilT - (s.t or now()))))
    if s.kind == "hide" then return "hidden from the RUIN network " .. length end
    if s.kind == "mute" then return "muted in RUIN chat " .. length end
    return "warned"
end
Watch.Describe = describe

-- Take in a sanction (yours or one heard): keep it, log it, tell its target.
local function accept(s, fresh)
    local w = store()
    local cur = w.sanctions[s.id]
    if cur and (cur.u or 0) >= (s.u or 0) then return false end
    w.sanctions[s.id] = s
    -- fill in the BattleTag once the target is seen online
    if not s.tag then s.tag = tagOf(s.target) end
    if fresh then
        if s.lifted then
            Watch:Log(whoDid(s), "lifted", ("%s: %s lifted"):format(ns.ShortName(s.target), s.kind))
        else
            Watch:Log(whoDid(s), s.kind, ("%s %s%s"):format(ns.ShortName(s.target), describe(s), s.reason and s.reason ~= "" and (": " .. s.reason) or ""))
        end
        -- the player concerned is told on their own screen
        local me = norm(s.target) == norm(ns.playerName) or (s.tag and s.tag == Watch:MyTagHash())
        if me then
            local msg = s.lifted and ("The RUIN moderators lifted your %s."):format(s.kind)
                or ("%s from the RUIN moderators (%s): %s. You are %s."):format(s.kind == "warn" and "A warning" or "A sanction",
                    whoDid(s), s.reason ~= "" and s.reason or "no reason given", describe(s))
            ns:Print(RED .. msg .. "|r")
            if ns.Widgets.Toast then ns.Widgets.Toast(msg, { sound = true }) end
        end
    end
    ns:Fire("WATCH_CHANGED")
    return true
end

local function send(kind, data, scope, target, prio)
    return ns.Comms:Send(kind, data, scope, target, prio or ns.Comms.PRIORITY.ALERT)
end

local function newId() return ns.RandomToken(6) .. tostring(now() % 100000) end

-- Is this player beyond your reach? Officers and the admin can only be
-- sanctioned by the org admin.
local function protectedTarget(name)
    if ns.Org:IsAdmin() then return false end
    local k = ns.Org:Get()
    local peer = ns.Presence:OrgPeerByName(name)
    if k and peer and peer.guid == k.admin then return true end
    return ns.Presence:IsOfficerName(name)
end

-- kind: "hide" | "mute" | "warn"; seconds: 0 = until lifted
function Watch:Sanction(kind, target, seconds, reason, caseId)
    if not Watch:IsModerator() then return false, "Only officers and the org admin can do that." end
    target = ns.Trim(target or "")
    if target == "" then return false, "Who?" end
    if norm(target) == norm(ns.playerName) then return false, "Not on yourself." end
    if protectedTarget(target) then return false, "Only the org admin can sanction an officer." end
    local w = store()
    local at = now()
    local s = { id = newId(), kind = kind, target = target, tag = tagOf(target), untilT = (seconds and seconds > 0) and (at + seconds) or 0,
                reason = ns.Trim(reason or ""):gsub("|", "/"):sub(1, 120), by = ns.playerName, cover = w.cover, t = at, u = at, case = caseId }
    accept(s, true)
    send("WSAN", s, "ORG")
    if caseId then Watch:CaseNote(caseId, ("%s: %s"):format(kind, describe(s))) end
    return true, s
end

-- A warning on the ladder: returns true and what it did.
function Watch:Warn(target, reason, caseId)
    local w = store()
    local strikes, at = 0, now()
    for _, s in pairs(w and w.sanctions or {}) do
        if s.kind == "warn" and not s.lifted and matches(s, target, tagOf(target)) and at - (s.t or 0) < 86400 then strikes = strikes + 1 end
    end
    local ok, err = Watch:Sanction("warn", target, 0, reason, caseId)
    if not ok then return false, err end
    local mute = LADDER[math.min(strikes + 1, #LADDER)]
    Watch:Sanction("mute", target, mute, ("warning %d: %s"):format(strikes + 1, reason or ""), caseId)
    return true, ("Warning %d: muted %s"):format(strikes + 1, Wd.Duration(mute))
end

function Watch:Lift(id)
    local w = store()
    local s = w and w.sanctions[id]
    if not s then return false, "No such sanction." end
    if not Watch:IsModerator() then return false, "Only officers and the org admin can do that." end
    local copy = {}
    for k, v in pairs(s) do copy[k] = v end
    copy.lifted, copy.liftedBy, copy.u = now(), ns.playerName, now()
    copy.cover = w.cover
    accept(copy, true)
    send("WSAN", copy, "ORG")
    return true
end

ns.Comms:Register("WSAN", function(d, sender, scope)
    if scope ~= "ORG" or type(d.id) ~= "string" or type(d.target) ~= "string" then return end
    if not (d.kind == "hide" or d.kind == "mute" or d.kind == "warn") then return end
    if not senderIsModerator(sender) then return end
    local s = { id = d.id:sub(1, 24), kind = d.kind, target = d.target:sub(1, 48), tag = type(d.tag) == "string" and d.tag:sub(1, 24) or nil,
                untilT = tonumber(d.untilT) or 0, reason = type(d.reason) == "string" and d.reason:gsub("|", "/"):sub(1, 120) or "",
                by = sender, cover = type(d.cover) == "string" and d.cover:sub(1, 24) or nil, t = tonumber(d.t) or now(),
                u = tonumber(d.u) or now(), lifted = tonumber(d.lifted), liftedBy = type(d.liftedBy) == "string" and d.liftedBy or nil,
                case = type(d.case) == "string" and d.case or nil }
    accept(s, true)
end)

-- Someone just connected: one member answers with the sanctions in force.
local lastSanList = -999
ns.Comms:Register("WSANQ", function(_, _, scope)
    if scope ~= "ORG" then return end
    C_Timer.After(2 + math.random() * 6, function()
        if GetTime() - lastSanList < 60 then return end
        lastSanList = GetTime()
        send("WSANL", {}, "ORG", nil, ns.Comms.PRIORITY.BULK)
        for _, s in ipairs(Watch:Sanctions(false)) do send("WSAN", s, "ORG", nil, ns.Comms.PRIORITY.BULK) end
    end)
end)
ns.Comms:Register("WSANL", function(_, _, scope) if scope == "ORG" then lastSanList = GetTime() end end)

---------------------------------------------------------------------------
-- Deleting a chat line for everyone
---------------------------------------------------------------------------
local deleted = {}                     -- line key -> true (this session)
function Watch.LineKey(author, text) return ns.Hash(norm(author) .. "|" .. tostring(text or "")) end
function Watch:IsDeleted(author, text) return deleted[Watch.LineKey(author, text)] == true end

local function dropLine(key)
    deleted[key] = true
    local h = ns.Chat and ns.Chat.history
    if h then
        for i = #h, 1, -1 do
            if Watch.LineKey(h[i].a, h[i].text) == key then table.remove(h, i) end
        end
        ns:Fire("CHAT_HISTORY")
    end
end

function Watch:DeleteLine(author, text)
    if not Watch:IsModerator() then return false, "Only officers and the org admin can do that." end
    local key = Watch.LineKey(author, text)
    dropLine(key)
    send("WDEL", { k = key, a = author, cv = store().cover }, "ORG")
    Watch:Log(store().cover and ("Moderator " .. store().cover) or ns.ShortName(ns.playerName), "deleted", "a chat line by " .. ns.ShortName(author))
    return true
end

ns.Comms:Register("WDEL", function(d, sender, scope)
    if scope ~= "ORG" or type(d.k) ~= "string" or not senderIsModerator(sender) then return end
    dropLine(d.k)
    Watch:Log(type(d.cv) == "string" and ("Moderator " .. d.cv) or ns.ShortName(sender), "deleted", "a chat line by " .. ns.ShortName(d.a or "?"))
end)

---------------------------------------------------------------------------
-- Reports and cases
---------------------------------------------------------------------------
-- An officer online to take a report: your own guild's first, then any.
local function officerOnline()
    local best
    for _, p in ipairs(ns.Presence:GetOnlineList()) do
        if not p.self and ns.Presence:IsOfficerName(p.name) then
            if p.guild == ns.guildName then return p.name end
            best = best or p.name
        end
    end
    return best
end

local function upsertCase(c)
    local w = store()
    local cur = w.cases[c.id]
    if cur and (cur.u or 0) >= (c.u or 0) then return false end
    w.cases[c.id] = c
    -- keep the book small
    local n, oldest, oldestId = 0, math.huge, nil
    for id, x in pairs(w.cases) do
        n = n + 1
        if now() - (x.u or 0) > CASE_KEEP then w.cases[id] = nil
        elseif (x.u or 0) < oldest then oldest, oldestId = x.u or 0, id end
    end
    if n > MAX_CASES and oldestId then w.cases[oldestId] = nil end
    ns:Fire("WATCH_CHANGED")
    return true
end

local function openCase(r, reporter)
    local at = now()
    local c = { id = r.id, target = r.target, tag = r.tag, reason = r.reason, note = r.note, reporter = reporter,
                gu = r.gu, tgu = r.tgu, t = at, u = at, status = "open",
                log = { { t = at, by = reporter, text = "Reported: " .. r.reason .. ((r.note or "") ~= "" and (" — " .. r.note) or "") } } }
    if upsertCase(c) then
        send("WCASE", c, "OFFICERS", nil, ns.Comms.PRIORITY.NORMAL)
        if ns.Watch:IsModerator() then ns:Print(("New report on %s (%s). Guild > Watch."):format(ns.ShortName(c.target), c.reason)) end
    end
end

local function trySend()
    local w = store()
    if not w or #w.outbox == 0 or not ns.Comms:IsJoined("ORG") then return end
    local officer = officerOnline()
    if not officer then return end
    for _, r in ipairs(w.outbox) do
        if GetTime() - (r.sentAt or -999) > RESEND then
            r.sentAt = GetTime()
            send("WREP", r, "PEER", officer, ns.Comms.PRIORITY.NORMAL)
        end
    end
end

-- Report a player. Returns true and "sent" | "queued", or false and why.
function Watch:Report(target, reason, note)
    target = ns.Trim(target or "")
    if target == "" then return false, "Type the player's name." end
    if norm(target) == norm(ns.playerName) then return false, "Not yourself." end
    local w = store()
    if not w then return false, "RUIN isn't ready yet." end
    local okReason = false
    for _, r in ipairs(Watch.REASONS) do if r == reason then okReason = true end end
    local r = { id = newId(), target = target, reason = okReason and reason or "Other", note = ns.Trim(note or ""):gsub("|", "/"):sub(1, 200),
                gu = ns.guildName, tag = tagOf(target), t = now() }
    local peer = ns.Presence:OrgPeerByName(target)
    r.tgu = peer and peer.guild or nil
    w.mine[#w.mine + 1] = { id = r.id, target = r.target, reason = r.reason, t = r.t, status = "waiting for an officer" }
    if Watch:IsModerator() then
        openCase(r, ns.playerName)
        w.mine[#w.mine].status = "opened as a case"
        return true, "opened"
    end
    w.outbox[#w.outbox + 1] = r
    r.sentAt = nil
    trySend()
    ns:Fire("WATCH_CHANGED")
    return true, officerOnline() and "sent" or "queued"
end

ns.Comms:Register("WREP", function(d, sender, scope)
    if scope ~= "PEER" or not Watch:IsModerator() or type(d.id) ~= "string" or type(d.target) ~= "string" then return end
    if not ns.Presence:IsOrgPeer(sender) and not (ns.roster and ns.roster[norm(sender)]) then return end
    local r = { id = d.id:sub(1, 24), target = d.target:sub(1, 48), reason = type(d.reason) == "string" and d.reason:sub(1, 40) or "Other",
                note = type(d.note) == "string" and d.note:gsub("|", "/"):sub(1, 200) or "", gu = type(d.gu) == "string" and d.gu or nil,
                tgu = type(d.tgu) == "string" and d.tgu or nil, tag = type(d.tag) == "string" and d.tag or nil }
    openCase(r, sender)
    send("WACK", { id = r.id }, "PEER", sender)
end)

ns.Comms:Register("WACK", function(d, _, scope)
    if scope ~= "PEER" or type(d.id) ~= "string" then return end
    local w = store()
    for i = #w.outbox, 1, -1 do if w.outbox[i].id == d.id then table.remove(w.outbox, i) end end
    for _, m in ipairs(w.mine) do if m.id == d.id then m.status = "received by an officer" end end
    ns:Print("Your report reached an officer. Thank you.")
    ns:Fire("WATCH_CHANGED")
end)

local function caseValid(d)
    return type(d) == "table" and type(d.id) == "string" and type(d.target) == "string" and type(d.log) == "table"
end

ns.Comms:Register("WCASE", function(d, sender, scope)
    if scope ~= "OFFICERS" or not caseValid(d) or not senderIsModerator(sender) then return end
    local c = { id = d.id:sub(1, 24), target = d.target:sub(1, 48), tag = d.tag, reason = tostring(d.reason or "Other"):sub(1, 40),
                note = tostring(d.note or ""):sub(1, 200), reporter = tostring(d.reporter or "?"), gu = d.gu, tgu = d.tgu,
                t = tonumber(d.t) or now(), u = tonumber(d.u) or now(), status = (d.status == "resolved" or d.status == "dismissed") and d.status or "open",
                log = {} }
    for i, l in ipairs(d.log) do
        if i > 60 then break end
        if type(l) == "table" then c.log[#c.log + 1] = { t = tonumber(l.t) or 0, by = tostring(l.by or "?"):sub(1, 48), text = tostring(l.text or ""):gsub("|", "/"):sub(1, 200) } end
    end
    upsertCase(c)
end)

-- An officer who just joined asks for the cases; one answers.
local lastCaseList = -999
ns.Comms:Register("WCASEQ", function(d, _, scope)
    if scope ~= "OFFICERS" or not Watch:IsModerator() then return end
    local since = tonumber(d.since) or 0
    C_Timer.After(2 + math.random() * 6, function()
        if GetTime() - lastCaseList < 60 then return end
        lastCaseList = GetTime()
        send("WCASEL", {}, "OFFICERS", nil, ns.Comms.PRIORITY.BULK)
        for _, c in pairs(store().cases) do
            if (c.u or 0) > since then send("WCASE", c, "OFFICERS", nil, ns.Comms.PRIORITY.BULK) end
        end
    end)
end)
ns.Comms:Register("WCASEL", function(_, _, scope) if scope == "OFFICERS" then lastCaseList = GetTime() end end)

local function changeCase(id, fn)
    local w = store()
    local c = w and w.cases[id]
    if not c then return false, "No such case." end
    if not Watch:IsModerator() then return false, "Only officers and the org admin can do that." end
    fn(c)
    c.u = now()
    ns:Fire("WATCH_CHANGED")
    send("WCASE", c, "OFFICERS", nil, ns.Comms.PRIORITY.NORMAL)
    return true
end

function Watch:CaseNote(id, text)
    text = ns.Trim(text or ""):gsub("|", "/"):sub(1, 200)
    if text == "" then return false, "Write the note first." end
    local who = store().cover and (ns.playerName .. " (as " .. store().cover .. ")") or ns.playerName
    return changeCase(id, function(c) c.log[#c.log + 1] = { t = now(), by = who, text = text } end)
end

function Watch:SetStatus(id, status)
    if status ~= "open" and status ~= "resolved" and status ~= "dismissed" then return false end
    return changeCase(id, function(c)
        c.status = status
        c.log[#c.log + 1] = { t = now(), by = ns.playerName, text = "Marked " .. status }
        Watch:Log(ns.ShortName(ns.playerName), status, "case on " .. ns.ShortName(c.target))
    end)
end

-- Cases, open first then newest.
function Watch:Cases(filter)
    local out = {}
    for _, c in pairs(store() and store().cases or {}) do
        if filter == "all" or (filter == "closed" and c.status ~= "open") or ((filter or "open") == "open" and c.status == "open") then
            out[#out + 1] = c
        end
    end
    table.sort(out, function(a, b) return (a.u or 0) > (b.u or 0) end)
    return out
end

function Watch:MyReports()
    local out = {}
    for i = #(store() and store().mine or {}), 1, -1 do out[#out + 1] = store().mine[i] end
    return out
end

function Watch:SetCover(name)
    if not Watch:IsModerator() then return false, "Only officers and the org admin can use a cover name." end
    name = ns.Trim(name or ""):gsub("[^%a ]", ""):sub(1, 24)
    store().cover = name ~= "" and name or nil
    ns:Fire("WATCH_CHANGED")
    return true
end
function Watch:Cover() return store() and store().cover end

---------------------------------------------------------------------------
-- What the rest of RUIN logs here
---------------------------------------------------------------------------
ns:Subscribe("KEY_CHANGED", function(source)
    local k = ns.Org:Get()
    if source == "edit" or source == "officer" or source == "import" or source == "create" then
        Watch:Log(source == "edit" and ns.ShortName(ns.playerName) or "the org admin", "org key", ("rev %d (%s)"):format(k and k.rev or 0, source))
    end
end)
ns:Subscribe("GUILD_SETTINGS_CHANGED", function()
    Watch:Log("an officer", "guild setting", ("events: ranks 0-%d"):format(ns.Guild:EventRank()))
end)

---------------------------------------------------------------------------
-- Upkeep: ask for sanctions and cases on connecting, resend reports
---------------------------------------------------------------------------
ns:Subscribe("CHANNELS_CHANGED", function()
    if ns.Comms:IsJoined("ORG") then
        C_Timer.After(12, function() send("WSANQ", {}, "ORG", nil, ns.Comms.PRIORITY.BULK); trySend() end)
    end
    if ns.Comms:IsJoined("OFFICERS") and Watch:IsModerator() then
        C_Timer.After(15, function()
            local newest = 0
            for _, c in pairs(store().cases) do newest = math.max(newest, c.u or 0) end
            send("WCASEQ", { since = newest }, "OFFICERS", nil, ns.Comms.PRIORITY.BULK)
        end)
    end
end)
ns:Subscribe("PEERS_CHANGED", function() trySend() end)
C_Timer.NewTicker(60, function() trySend() end)

---------------------------------------------------------------------------
-- The Watch tab on the Guild page
--   everyone: Report (a form and your reports), Sanctions in force, Log
--   officers and the admin also: Cases (open and closed), acting on them,
--   sanctioning a player directly, and a cover name
---------------------------------------------------------------------------
ns.GuildUI = ns.GuildUI or {}
local ui = { reason = Watch.REASONS[1], kind = "mute", length = 1800 }   -- view: Cases first for moderators
local LENGTHS = { 300, 1800, 3600, 86400, 7 * 86400, 0 }
local function lengthName(v) return v == 0 and "until lifted" or Wd.Duration(v) end

local function views()
    if Watch:IsModerator() then return { "Cases", "Closed cases", "Report", "Sanctions", "Log" } end
    return { "Report", "Sanctions", "Log" }
end

local function ago(t) return Wd.Ago(math.max(60, now() - (t or now()))) end

-- Open Guild > Watch on the report form, with a name filled in.
function Watch:PromptReport(name)
    if not ns.Org:Get() then ns:Print("You need the org key to report a player."); return end
    ui.view, ui.prefill = "Report", name
    if ns.UI and ns.UI.OpenGuildTab then ns.UI:OpenGuildTab("Watch") end
    Watch:Refresh()
end

function ns.GuildUI.BuildWatch(page)
    ui.page = page
    ui.viewBtn = Wd.Dropdown(page, 170, views, function() return ui.view end, function(v) ui.view = v; ui.sel = nil; Watch:Refresh() end, "View: ")
    ui.viewBtn:SetPoint("TOPLEFT", 0, 0)
    ui.info = Wd.Label(page, "", "GameFontHighlightSmall")
    ui.info:SetPoint("LEFT", ui.viewBtn, "RIGHT", 10, 0)
    ui.info:SetWidth(560)
    ui.info:SetJustifyH("LEFT")
    ui.info:SetWordWrap(false)
    ui.coverBtn = Wd.Button(page, "Cover name", 130, function()
        ns.UI:ShowText("Cover name", "Act as \"Moderator <name>\" instead of your character's name (letters only). Leave empty to act as yourself.",
            Watch:Cover() or "", function(text) local ok, e = Watch:SetCover(text); if not ok then ns:Print(e) end end)
    end)
    ui.coverBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)

    ui.list = Wd.List(page, 22, function(row)
        row.a = Wd.Label(row, "")
        row.a:SetPoint("LEFT", 6, 0); row.a:SetWidth(180); row.a:SetWordWrap(false)
        row.b = Wd.Label(row, "", "GameFontHighlightSmall")
        row.b:SetPoint("LEFT", 190, 0); row.b:SetWidth(360); row.b:SetWordWrap(false)
        row.c = Wd.Label(row, "", "GameFontHighlightSmall")
        row.c:SetPoint("RIGHT", -6, 0); row.c:SetWidth(170); row.c:SetJustifyH("RIGHT"); row.c:SetWordWrap(false)
        row:SetScript("OnMouseUp", function(self) if self.e and self.e.id then ui.sel = self.e.id; Watch:Refresh() end end)
    end, function(row, e)
        row.e = e
        local on = e.id and ui.sel == e.id
        local mark = on and (C.gold .. "> |r") or ""
        if e.logLine then
            row.a:SetText(mark .. GREY .. ago(e.t) .. "|r")
            row.b:SetText(C.white .. ns.Escape(e.a) .. "|r " .. ns.Escape(e.act) .. GREY .. "  " .. ns.Escape(e.d) .. "|r")
            row.c:SetText("")
        elseif e.case then
            local c = e.case
            row.a:SetText(mark .. C.white .. ns.Escape(ns.ShortName(c.target)) .. "|r" .. (c.tgu and (GREY .. " [" .. ns.Escape(c.tgu) .. "]|r") or ""))
            row.b:SetText(YELLOW .. ns.Escape(c.reason) .. "|r" .. GREY .. "  ·  by " .. ns.Escape(ns.ShortName(c.reporter or "?")) .. "  ·  " .. ns.Escape(c.note or "") .. "|r")
            row.c:SetText((c.status == "open" and RED or GREY) .. c.status .. "|r" .. GREY .. "  " .. ago(c.u) .. "|r")
        elseif e.sanction then
            local x = e.sanction
            row.a:SetText(mark .. C.white .. ns.Escape(ns.ShortName(x.target)) .. "|r")
            row.b:SetText((x.kind == "hide" and RED or YELLOW) .. describe(x) .. "|r" .. GREY .. ((x.reason or "") ~= "" and ("  ·  " .. ns.Escape(x.reason)) or "") .. "|r")
            row.c:SetText(GREY .. ns.Escape(whoDid(x)) .. "  " .. ago(x.t) .. "|r")
        elseif e.mine then
            local m = e.mine
            row.a:SetText(C.white .. ns.Escape(ns.ShortName(m.target)) .. "|r")
            row.b:SetText(GREY .. ns.Escape(m.reason) .. "  ·  " .. ns.Escape(m.status or "") .. "|r")
            row.c:SetText(GREY .. ago(m.t) .. "|r")
        end
    end)
    ui.list.frame:SetPoint("TOPLEFT", 0, -32)
    ui.list.frame:SetPoint("RIGHT", page, "RIGHT", -24, 0)
    ui.list.frame:SetPoint("BOTTOM", page, "BOTTOM", 0, 178)

    -- the card under the list: a form or the selected case / sanction
    local card = Wd.Card(page)
    card:SetPoint("BOTTOMLEFT", 0, 0)
    card:SetPoint("BOTTOMRIGHT", 0, 0)
    card:SetHeight(168)
    ui.card = card
    ui.title = Wd.Header(card, "")
    ui.title:SetPoint("TOPLEFT", 10, -8)
    ui.text = Wd.Label(card, "", "GameFontHighlightSmall")
    ui.text:SetPoint("TOPLEFT", 12, -30)
    ui.text:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    ui.text:SetJustifyH("LEFT"); ui.text:SetJustifyV("TOP")
    ui.text:SetHeight(64)

    -- report form (everyone) / sanction form (moderators)
    ui.name = Wd.EditBox(card, 170, nil, "Player name (Name-Realm)")
    ui.name:SetPoint("TOPLEFT", 12, -100)
    ui.reasonBtn = Wd.Dropdown(card, 190, Watch.REASONS, function() return ui.reason end, function(v) ui.reason = v end, "Reason: ")
    ui.reasonBtn:SetPoint("LEFT", ui.name, "RIGHT", 8, 0)
    ui.kindBtn = Wd.Dropdown(card, 130, { "mute", "hide", "warn" }, function() return ui.kind end, function(v) ui.kind = v end)
    ui.kindBtn.format = function(v) return v == "hide" and "Hide from RUIN" or v == "warn" and "Warn" or "Mute in chat" end
    ui.kindBtn:Refresh()
    ui.kindBtn:SetPoint("LEFT", ui.name, "RIGHT", 8, 0)
    ui.lengthBtn = Wd.Dropdown(card, 120, LENGTHS, function() return ui.length end, function(v) ui.length = v end)
    ui.lengthBtn.format = lengthName
    ui.lengthBtn:Refresh()
    ui.lengthBtn:SetPoint("LEFT", ui.kindBtn, "RIGHT", 6, 0)
    ui.note = Wd.EditBox(card, 470, nil, "What happened (optional)")
    ui.note:SetPoint("TOPLEFT", 12, -132)
    ui.send = Wd.Button(card, "Send report", 120, function()
        if ui.view == "Sanctions" then
            local ok, e
            if ui.kind == "warn" then ok, e = Watch:Warn(ui.name:GetText(), ui.note:GetText())
            else ok, e = Watch:Sanction(ui.kind, ui.name:GetText(), ui.length, ui.note:GetText()) end
            ns:Print(ok and (type(e) == "string" and e or "Done.") or e)
            if ok then ui.name:SetText(""); ui.note:SetText("") end
        else
            local ok, how = Watch:Report(ui.name:GetText(), ui.reason, ui.note:GetText())
            if ok then
                ns:Print(how == "opened" and "Case opened." or how == "sent" and "Report sent to an officer online."
                    or "No officer is online: your report waits and goes out when one is.")
                ui.name:SetText(""); ui.note:SetText("")
            else ns:Print(how) end
        end
        Watch:Refresh()
    end)
    ui.send:SetPoint("LEFT", ui.note, "RIGHT", 8, 0)

    -- case actions (moderators)
    ui.caseNote = Wd.EditBox(card, 400, nil, "Add a note to the case")
    ui.caseNote:SetPoint("TOPLEFT", 12, -100)
    ui.addNote = Wd.Button(card, "Add note", 90, function()
        local ok, e = Watch:CaseNote(ui.sel, ui.caseNote:GetText())
        if ok then ui.caseNote:SetText("") else ns:Print(e) end
    end)
    ui.addNote:SetPoint("LEFT", ui.caseNote, "RIGHT", 6, 0)
    local function caseOf() return store() and store().cases[ui.sel] end
    local function act(fn) return function()
        local c = caseOf()
        if not c then return end
        local ok, e = fn(c)
        if ok == false then ns:Print(e) elseif type(e) == "string" then ns:Print(e) end
        Watch:Refresh()
    end end
    local acts = {
        { "Warn", 64, act(function(c) return Watch:Warn(c.target, c.reason, c.id) end) },
        { "Mute 30m", 76, act(function(c) return Watch:Sanction("mute", c.target, 1800, c.reason, c.id) end) },
        { "Mute 24h", 76, act(function(c) return Watch:Sanction("mute", c.target, 86400, c.reason, c.id) end) },
        { "Mute", 56, act(function(c) return Watch:Sanction("mute", c.target, 0, c.reason, c.id) end) },
        { "Hide", 56, act(function(c) return Watch:Sanction("hide", c.target, 0, c.reason, c.id) end) },
        { "Resolve", 70, act(function(c) return Watch:SetStatus(c.id, "resolved") end) },
        { "Dismiss", 70, act(function(c) return Watch:SetStatus(c.id, "dismissed") end) },
        { "Reopen", 66, act(function(c) return Watch:SetStatus(c.id, "open") end) },
    }
    ui.acts = {}
    local prev
    for _, a in ipairs(acts) do
        local b = Wd.Button(card, a[1], a[2], a[3])
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, -134) end
        ui.acts[a[1]] = b
        prev = b
    end
    ui.acts["Mute"].tip = "Mute in RUIN chat until lifted."
    ui.acts["Hide"].tip = "Every RUIN client ignores this player's RUIN messages until lifted."
    ui.acts["Warn"].tip = "A warning mutes for 5 minutes, then 30 minutes, then 24 hours if they keep at it within a day."
    ui.lift = Wd.Button(card, "Lift", 70, function()
        local ok, e = Watch:Lift(ui.sel)
        if not ok then ns:Print(e) end
        Watch:Refresh()
    end)
    ui.lift:SetPoint("TOPRIGHT", -10, -6)
    page:SetScript("OnShow", function() Watch:Refresh() end)
end

local function setShown(list, on) for _, f in ipairs(list) do f:SetShown(on) end end

function Watch:Refresh()
    if not (ui.page and ui.page:IsVisible()) then return end
    local mod = Watch:IsModerator()
    local ok = false
    for _, v in ipairs(views()) do if v == ui.view then ok = true end end
    if not ok then ui.view = views()[1] end
    ui.viewBtn:Refresh()
    ui.coverBtn:SetShown(mod)
    ui.coverBtn:SetText(Watch:Cover() and ("As " .. Watch:Cover()) or "Cover name")
    if ui.prefill then ui.name:SetText(ui.prefill); ui.prefill = nil end

    local items = {}
    local formParts = { ui.name, ui.note, ui.send }
    local caseParts = { ui.caseNote, ui.addNote }
    for _, b in pairs(ui.acts) do caseParts[#caseParts + 1] = b end
    setShown(formParts, false); setShown(caseParts, false)
    ui.reasonBtn:Hide(); ui.kindBtn:Hide(); ui.lengthBtn:Hide(); ui.lift:Hide()
    ui.card:Show()

    if ui.view == "Cases" or ui.view == "Closed cases" then
        for _, c in ipairs(Watch:Cases(ui.view == "Cases" and "open" or "closed")) do items[#items + 1] = { id = c.id, case = c } end
        ui.list:SetEmptyText(ui.view == "Cases" and "No open cases." or "No closed cases.")
        ui.info:SetText(GREY .. "Reports from every guild of the org. Pick one to act on it.|r")
        local c = store().cases[ui.sel or ""]
        if c then
            ui.title:SetText(("Case: %s  ·  %s"):format(ns.Escape(ns.ShortName(c.target)), ns.Escape(c.reason)))
            local lines = {}
            for i = math.max(1, #c.log - 4), #c.log do
                local l = c.log[i]
                lines[#lines + 1] = GREY .. ago(l.t) .. "|r  " .. C.white .. ns.Escape(ns.ShortName(l.by)) .. "|r  " .. ns.Escape(l.text)
            end
            local s = Watch:SanctionOn(c.target)
            if s then lines[#lines + 1] = YELLOW .. "Now: " .. describe(s) .. "|r" end
            ui.text:SetText(table.concat(lines, "\n"))
            setShown(caseParts, true)
            ui.acts["Reopen"]:SetShown(c.status ~= "open")
            ui.acts["Resolve"]:SetShown(c.status == "open"); ui.acts["Dismiss"]:SetShown(c.status == "open")
        else
            ui.title:SetText("Cases")
            ui.text:SetText(GREY .. "Pick a case above. Warn mutes on a ladder (5 minutes, 30 minutes, 24 hours within a day); Mute and Hide last until lifted (Sanctions view). Everything you do is in the Log, under your cover name if you set one.|r")
        end
    elseif ui.view == "Report" then
        for _, m in ipairs(Watch:MyReports()) do items[#items + 1] = { mine = m } end
        ui.list:SetEmptyText("You haven't reported anyone.")
        ui.info:SetText(GREY .. "Your reports. Only officers see them.|r")
        ui.title:SetText("Report a player")
        ui.text:SetText(GREY .. "Harassment, spam, cheating, scams: tell the officers. Your report goes to an officer online (or waits until one is), and every officer of the org sees the case. You can also right-click a player and choose Report to the RUIN Watch.|r")
        setShown(formParts, true)
        ui.reasonBtn:Show(); ui.reasonBtn:Refresh()
        ui.send:SetText("Send report")
    elseif ui.view == "Sanctions" then
        for _, x in ipairs(Watch:Sanctions(false)) do items[#items + 1] = { id = x.id, sanction = x } end
        ui.list:SetEmptyText("No sanctions in force.")
        ui.info:SetText(GREY .. "Mutes and hides in force across the org. They follow the player's BattleTag.|r")
        local x = store().sanctions[ui.sel or ""]
        if mod then
            ui.title:SetText(x and ("%s: %s"):format(ns.Escape(ns.ShortName(x.target)), describe(x)) or "Sanction a player")
            ui.text:SetText(x and (GREY .. "By " .. ns.Escape(whoDid(x)) .. " " .. ago(x.t) .. ((x.reason or "") ~= "" and (": " .. ns.Escape(x.reason)) or "") .. ". Lift ends it for everyone.|r")
                or (GREY .. "Mute: their RUIN chat lines are hidden. Hide: every RUIN client ignores all their RUIN messages. Warn: a muting warning on the ladder. Officers can only be sanctioned by the org admin.|r"))
            ui.lift:SetShown(x ~= nil)
            setShown(formParts, true)
            ui.kindBtn:Show(); ui.lengthBtn:Show()
            ui.send:SetText("Apply")
        else
            ui.title:SetText("Sanctions")
            ui.text:SetText(GREY .. "Players the officers muted or hid. Their RUIN lines don't show for you while it lasts.|r")
        end
    else
        for _, l in ipairs(Watch:LogLines()) do items[#items + 1] = { logLine = true, t = l.t, a = l.a, act = l.act, d = l.d } end
        ui.list:SetEmptyText("Nothing logged yet.")
        ui.info:SetText(GREY .. "What this computer saw done: sanctions, deleted lines, cases, org key changes.|r")
        ui.card:Hide()
    end
    ui.list.frame:SetPoint("BOTTOM", ui.page, "BOTTOM", 0, ui.card:IsShown() and 178 or 0)
    ui.list:SetItems(items)
end

ns:Subscribe("WATCH_CHANGED", function() Watch:Refresh() end)
