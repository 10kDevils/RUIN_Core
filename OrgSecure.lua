-- RUIN Core: org security
--   * The data key: a random secret that encrypts org traffic (Comms.lua).
--     It never travels inside the org key and never comes from the key
--     phrase: it goes only to members of the org's guilds, over their own
--     guild's chat (the game delivers that only to the guild), to officers
--     with the key, and by whisper to members a guild roster vouches for.
--     So the key phrase alone, leaked or guessed, reads nothing.
--   * Encryption starts once the admin sets the org minimum version to the
--     first RUIN that encrypts (ns.CRYPTO_VERSION); older RUINs can't read it.
--   * The data key changes (and with it, who can read): weekly, when members
--     leave a guild, when a guild is removed, and with every new key.
--   * Admin attestations: the admin's client signs, for a week, that each of
--     its characters is the admin's, so a reused name isn't.
--   * The org minimum version (set by the admin) and update notices.
--   * The admin's recovery code: the signing seed, to restore on a new PC.
local ADDON, ns = ...

local Org = ns.Org
local C = ns.Crypto
local Sec = {}
ns.OrgSecure = Sec

local GRACE = 900                 -- the previous data key still opens messages this long
local ROTATE_WEEK = 7 * 86400
local ROTATE_GAP = 1800           -- departures rotate the data key at most this often
local ATTEST_FOR = 7 * 86400
local ROSTER_TRUST = 6 * 3600     -- an org roster copy vouches for its members this long

local function now() return ns.Now() end
local function dkHash(hex) return C.SHA256Hex("RUIN dk|" .. hex):sub(1, 16) end
Sec.DkHash = dkHash

---------------------------------------------------------------------------
-- The data key
---------------------------------------------------------------------------
local prev        -- { r, raw, untilT }: the data key before the current one
local pending = {}  -- r -> hex, a data key that arrived before its org key

local function dkStore()
    if not ns.db then return {} end
    ns.db.orgData = type(ns.db.orgData) == "table" and ns.db.orgData or {}
    return ns.db.orgData
end

local function storedFor(k)
    local s = k and dkStore()[k.org]
    if s and s.r == k.dkr and type(s.k) == "string" and k.dkh and dkHash(s.k) == k.dkh then return s end
    return nil
end

-- The current data key (raw bytes) and its generation, or nil.
function Org:DataKey()
    local k = Org:Get()
    local s = storedFor(k)
    if not s then return nil end
    return C.Unhex(s.k), s.r
end
function Org:DataKeyHex()
    local s = storedFor(Org:Get())
    if s then return s.k, s.r end
end

-- The data key of generation r: the current one, or the one before it for a
-- while after a change.
function Org:DataKeyFor(r)
    local raw, cur = Org:DataKey()
    if raw and r == cur then return raw end
    if prev and prev.r == r and GetTime() < prev.untilT then return prev.raw end
    return nil
end

local function keepPrevious(org)
    local s = dkStore()[org]
    if s and type(s.k) == "string" then prev = { r = s.r, raw = C.Unhex(s.k), untilT = GetTime() + GRACE } end
end

-- Take a data key someone handed over; it must match the org key's check value.
function Org:SetDataKey(r, hex)
    r = tonumber(r)
    if not (r and type(hex) == "string" and #hex == 64 and not hex:find("[^0-9a-f]")) then return false end
    local k = Org:Get()
    if not k then return false end
    if k.dkr and r > k.dkr then pending[r] = hex; return false end
    if not (k.dkr and r == k.dkr and k.dkh and dkHash(hex) == k.dkh) then return false end
    local s = dkStore()[k.org]
    if s and s.r == r and s.k == hex then return true end
    keepPrevious(k.org)
    dkStore()[k.org] = { r = r, k = hex }
    ns:Fire("DATA_KEY_CHANGED")
    return true
end

-- A new data key in k (the admin): stored here, its check value in the key.
function Org.NewDataKey(k)
    local hex = C.Hex(C.Random(32))
    keepPrevious(k.org)
    k.dkr = (tonumber(k.dkr) or 0) + 1
    k.dkh = dkHash(hex)
    k.dkt = now()
    dkStore()[k.org] = { r = k.dkr, k = hex }
    ns:Fire("DATA_KEY_CHANGED")
    return hex
end

-- Is org traffic encrypted? Once the admin has set the minimum version to a
-- RUIN that encrypts, and the key has a data key.
function Org:Encrypted()
    local k = Org:Get()
    return k ~= nil and k.dkr ~= nil and type(k.mv) == "string" and ns.CompareVersions(k.mv, ns.CRYPTO_VERSION) >= 0
end

ns:Subscribe("KEY_CHANGED", function()
    local k = Org:Get()
    if not k then return end
    for r, hex in pairs(pending) do
        if k.dkr and r <= k.dkr then
            pending[r] = nil
            if r == k.dkr then Org:SetDataKey(r, hex) end
        end
    end
end)

---------------------------------------------------------------------------
-- Who is a member: the game's own roster for your guild, the other guilds'
-- rosters as their members last sent them, and the admin.
---------------------------------------------------------------------------
local function rosterGuildOf(name, trust)
    local n = ns.NormalizeName(name)
    if ns.roster and ns.roster[n] then return ns.guildName, true end
    local s = ns.db and ns.db.orgRosters
    local k = Org:Get()
    if not (s and k and s.org == k.org and type(s.guilds) == "table") then return nil end
    for g, snap in pairs(s.guilds) do
        if k.guilds[g] and type(snap.members) == "table" and now() - (snap.t or 0) < (trust or ROSTER_TRUST) then
            for _, m in ipairs(snap.members) do
                if ns.NormalizeName(m.name) == n then return g, true end
            end
        end
    end
    return nil
end

-- Is name in one of the org's guilds? true, false, or nil when nobody can
-- tell yet (no recent roster of the guild they say they're in).
function Org:VerifyMember(name, trust)
    if type(name) ~= "string" then return false end
    local k = Org:Get()
    if not k then return false end
    if Org:IsAdminName(name) then return true end
    local g = rosterGuildOf(name, trust)
    if g and k.guilds[g] then return true end
    -- their guild's roster is known and they're not on it: not a member
    local claimed = ns.Presence and ns.Presence:GuildOfName(name)
    if claimed and k.guilds[claimed] then
        local snap = ns.db and ns.db.orgRosters and ns.db.orgRosters.guilds and ns.db.orgRosters.guilds[claimed]
        if claimed == ns.guildName or (snap and now() - (snap.t or 0) < 1800) then return false end
        return nil
    end
    if claimed then return false end
    return nil
end

---------------------------------------------------------------------------
-- Handing the data key on
--   * in your guild: anyone with it answers a guildmate's hello that shows
--     an older one (DKEY on guild chat)
--   * across guilds: a member without it asks on the org channel (DKREQ);
--     an officer whose rosters show the asker in an org guild whispers it
---------------------------------------------------------------------------
local shareAt, shareSeen = 0, {}
local function scheduleGuildShare()
    if shareAt > GetTime() then return end
    shareAt = GetTime() + 30
    C_Timer.After(2 + math.random() * 6, function()
        local hex, r = Org:DataKeyHex()
        local k = Org:Get()
        if not (hex and k and Org:MyGuildInOrg()) then return end
        if shareSeen[r] and GetTime() - shareSeen[r] < 20 then return end
        shareSeen[r] = GetTime()
        ns.Comms:Send("DKEY", { org = k.org, r = r, k = hex }, "GUILD", nil, ns.Comms.PRIORITY.ALERT)
    end)
end

-- Presence calls this for each guildmate hello.
function Org:OnPeerDataKey(peer)
    local hex, r = Org:DataKeyHex()
    local k = Org:Get()
    if not (hex and k and peer.org == k.org) then return end
    if (tonumber(peer.dr) or 0) >= r then return end
    if not Sec.VersionOk(peer.v) then return end
    scheduleGuildShare()
end

ns.Comms:Register("DKEY", function(d, sender, scope)
    local k = Org:Get()
    if not (k and type(d) == "table" and d.org == k.org) then return end
    if scope == "GUILD" then
        shareSeen[tonumber(d.r) or -1] = GetTime()
        if not (ns.roster and ns.roster[ns.NormalizeName(sender)] and Org:MyGuildInOrg()) then return end
    elseif scope ~= "PEER" then
        return
    end
    -- the check value in the signed org key says whether it's the real one
    if Org:SetDataKey(d.r, d.k) then ns:Debug("data key " .. tostring(d.r) .. " from " .. tostring(sender)) end
end)

local lastAsk, missingSince = -999, nil
local function askForDataKey()
    local k = Org:Get()
    if not (k and k.dkr and Org:Encrypted()) or Org:DataKey() then missingSince = nil; return end
    if not (Org:MyGuildInOrg() and ns.Comms:IsJoined("ORG")) then return end
    missingSince = missingSince or GetTime()
    if GetTime() - missingSince < 20 or GetTime() - lastAsk < 120 then return end
    lastAsk = GetTime()
    ns.Comms:Send("DKREQ", { org = k.org, r = k.dkr, gu = ns.guildName, v = ns.VERSION }, "ORG", nil, ns.Comms.PRIORITY.NORMAL)
end

local answered = {}
ns.Comms:Register("DKREQ", function(d, sender, scope)
    if scope ~= "ORG" then return end
    local k = Org:Get()
    local hex, r = Org:DataKeyHex()
    if not (k and hex and d.org == k.org and tonumber(d.r) == r) then return end
    if not (Org:AmOfficer() or Org:IsAdmin()) then return end
    local n = ns.NormalizeName(sender)
    if answered[n] and GetTime() < answered[n] then return end
    if Org:VerifyMember(sender, 3 * 86400) ~= true or not Sec.VersionOk(d.v) then return end
    answered[n] = GetTime() + 120
    C_Timer.After(1 + math.random() * 5, function()
        local h2, r2 = Org:DataKeyHex()
        if h2 then ns.Comms:Send("DKEY", { org = k.org, r = r2, k = h2 }, "PEER", sender, ns.Comms.PRIORITY.ALERT) end
    end)
end)

-- Officers and the admin share a new data key with their guild right away.
ns:Subscribe("DATA_KEY_CHANGED", function()
    if Org:DataKey() and Org:MyGuildInOrg() then scheduleGuildShare() end
end)

---------------------------------------------------------------------------
-- New data keys: weekly, and when members leave a guild (officers' rosters
-- show it; the admin's client changes the key, at most every half hour)
---------------------------------------------------------------------------
local lastRotate, rotatePending = -999, false
function Org:RotateDataKey()
    local k = Org:Get()
    if not (k and Org:IsAdmin() and Org.MySeed(k)) then return false, "Only the org admin can change the data key." end
    Org.NewDataKey(k)
    k.rev = Org.NextRev(k)
    lastRotate = GetTime()
    Org.PublishEdit(k)
    return true
end

local departed = 0
function Org:NoteDepartures(n)
    if not Org:IsAdmin() then return end
    departed = departed + (tonumber(n) or 0)
    if rotatePending then return end
    rotatePending = true
    local wait = math.max(120, lastRotate + ROTATE_GAP - GetTime())
    C_Timer.After(wait, function()
        rotatePending = false
        if departed > 0 and Org:IsAdmin() then
            ns:Print(("%d player%s left an org guild: new data key, so they can't read org traffic any more."):format(departed, departed == 1 and "" or "s"))
            departed = 0
            Org:RotateDataKey()
        end
    end)
end

ns.Comms:Register("MLEFT", function(d, sender, scope)
    if scope ~= "OFFICERS" or not Org:IsAdmin() then return end
    local k = Org:Get()
    if not (k and type(d.g) == "string" and k.guilds[d.g]) then return end
    Org:NoteDepartures(math.min(50, tonumber(d.n) or 1))
end)

-- Officers (and the admin) watch their own guild's roster for departures.
ns:Subscribe("ROSTER_UPDATED", function()
    local k = Org:Get()
    if not (k and ns.guildName and k.guilds[ns.guildName] and (Org:AmOfficer() or Org:IsAdmin())) then return end
    local count, nowSet = 0, {}
    for norm in pairs(ns.roster or {}) do count = count + 1; nowSet[norm] = true end
    if count == 0 then return end
    ns.db.guildMembers = type(ns.db.guildMembers) == "table" and ns.db.guildMembers or {}
    local key = k.org .. "/" .. ns.guildName
    local before = ns.db.guildMembers[key]
    -- a roster much smaller than last time is a partial one: wait for the full one
    if type(before) == "table" and (before._n or 0) > 0 and count < (before._n or 0) * 0.8 and (before._n or 0) - count > 3 then return end
    local gone = 0
    if type(before) == "table" then
        for norm in pairs(before) do
            if norm ~= "_n" and not nowSet[norm] then gone = gone + 1 end
        end
    end
    nowSet._n = count
    ns.db.guildMembers[key] = nowSet
    if gone > 0 then
        if Org:IsAdmin() then Org:NoteDepartures(gone)
        elseif k.oc then ns.Comms:Send("MLEFT", { g = ns.guildName, n = gone }, "OFFICERS", nil, ns.Comms.PRIORITY.NORMAL) end
    end
end)

---------------------------------------------------------------------------
-- Admin attestations
---------------------------------------------------------------------------
local function attestMessage(org, pk, name, e) return ("RUINA1|%s|%s|%s|%d"):format(org, pk, ns.NormalizeName(name), e) end
local function attestStore(org)
    if not ns.db then return {} end
    ns.db.adminSeen = type(ns.db.adminSeen) == "table" and ns.db.adminSeen or {}
    local s = ns.db.adminSeen[org]
    if type(s) ~= "table" or s.pk ~= (Org:Get() or {}).pk then
        s = { pk = (Org:Get() or {}).pk, names = {} }
        ns.db.adminSeen[org] = s
    end
    return s.names
end

function Org.Attested(norm, k)
    k = k or Org:Get()
    if not k then return false end
    local e = attestStore(k.org)[norm]
    return type(e) == "number" and e > now()
end

local lastAttestSent = -999
function Org:SendAttestation(force)
    local k = Org:Get()
    local seed = k and Org.MySeed(k)
    if not (seed and ns.playerName) then return end
    if not force and GetTime() - lastAttestSent < 30 then return end
    lastAttestSent = GetTime()
    ns.db.myAttest = type(ns.db.myAttest) == "table" and ns.db.myAttest or {}
    local key = k.org .. "/" .. ns.NormalizeName(ns.playerName) .. "/" .. k.pk
    local a = ns.db.myAttest[key]
    if not (type(a) == "table" and type(a.e) == "number" and a.e - now() > ATTEST_FOR / 2) then
        local e = now() + ATTEST_FOR
        a = { e = e, s = C.Hex(C.Sign(seed, attestMessage(k.org, k.pk, ns.playerName, e))) }
        ns.db.myAttest[key] = a
    end
    local msg = { org = k.org, n = ns.playerName, e = a.e, s = a.s }
    if ns.Comms:IsJoined("ORG") then ns.Comms:Send("ADMINHI", msg, "ORG", nil, ns.Comms.PRIORITY.NORMAL)
    elseif IsInGuild and IsInGuild() then ns.Comms:Send("ADMINHI", msg, "GUILD", nil, ns.Comms.PRIORITY.NORMAL) end
end

local laterAttest = {}      -- attestations that may be for a key still on its way
local function takeAttestation(d, sender)
    local k = Org:Get()
    if not (k and type(k.pk) == "string" and d.org == k.org and type(d.n) == "string" and type(d.s) == "string") then return false end
    local e = tonumber(d.e)
    if not e or e <= now() or e > now() + ATTEST_FOR + 86400 then return false end
    if ns.NormalizeName(d.n) ~= ns.NormalizeName(sender) or not Org.NameListed(sender, k) then return false end
    local sig = C.Unhex(d.s)
    if not (sig and C.VerifyCached(C.Unhex(k.pk), attestMessage(k.org, k.pk, sender, e), sig)) then return false end
    local s = attestStore(k.org)
    local norm = ns.NormalizeName(sender)
    if (s[norm] or 0) < e then s[norm] = e; ns:Fire("PEERS_CHANGED") end
    return true
end

ns.Comms:Register("ADMINHI", function(d, sender, scope)
    if not takeAttestation(d, sender) and type(d.s) == "string" then
        laterAttest[ns.NormalizeName(sender)] = { d = d, sender = sender, t = GetTime() }
    end
end)
ns:Subscribe("KEY_CHANGED", function()
    for n, a in pairs(laterAttest) do
        if GetTime() - a.t > 300 or takeAttestation(a.d, a.sender) then laterAttest[n] = nil end
    end
end)

-- A hello asking for answers: the admin answers with an attestation.
function Org:OnHelloRequest()
    if Org:IsAdmin() then C_Timer.After(1 + math.random() * 3, function() Org:SendAttestation(false) end) end
end

---------------------------------------------------------------------------
-- The admin's client on login: signs a key from before signatures, keeps
-- the org's version up to date, changes the data key weekly, vouches for
-- this character.
---------------------------------------------------------------------------
function Org:Upgrade()
    local k = Org:Get()
    if not k then return end
    if type(k.pk) ~= "string" then
        if not Org:IsAdmin() then return end
        local seed = C.Random(32)
        ns.db.adminSeeds = type(ns.db.adminSeeds) == "table" and ns.db.adminSeeds or {}
        ns.db.adminSeeds[k.org] = C.Hex(seed)
        k.pk = Org.PkOf(seed)
        k.mv = k.mv or ns.MIN_SUPPORTED
        k.av = ns.VERSION
        Org.NewDataKey(k)
        k.rev = Org.NextRev(k)
        Org.PublishEdit(k)
        ns:Print("RUIN now signs the org key: only this account can change it. Save your admin recovery code (Settings > Org > Recovery code) in case you play on another PC.")
        Org:SendAttestation(true)
        return
    end
    if not Org:IsAdmin() then
        -- the admin's own character without its signing seed (a new PC, a reinstall)
        if ns.playerGUID and k.admin == ns.playerGUID then
            ns:Print("This is the org admin's character, but this PC doesn't have the admin's signing seed. Type your recovery code under Settings > Org > Recovery code to manage the org from here.")
        end
        return
    end
    local changed = false
    if type(k.av) ~= "string" or ns.CompareVersions(ns.VERSION, k.av) > 0 then k.av = ns.VERSION; changed = true end
    if not k.mv then k.mv = ns.MIN_SUPPORTED; changed = true end
    if not Org:DataKey() or now() - (tonumber(k.dkt) or 0) > ROTATE_WEEK then Org.NewDataKey(k); changed = true end
    if changed then
        k.rev = Org.NextRev(k)
        Org.PublishEdit(k)
    end
    Org:SendAttestation(true)
end

ns:Subscribe("LOGIN", function()
    C_Timer.After(25, function() Org:Upgrade() end)
end)
-- A new admin (a hand-over just arrived): vouch for this character at once.
local attestedPk
ns:Subscribe("KEY_CHANGED", function()
    local k = Org:Get()
    if k and type(k.pk) == "string" and attestedPk ~= k.pk and Org:IsAdmin() then
        attestedPk = k.pk
        C_Timer.After(2, function() Org:SendAttestation(true) end)
    end
end)
C_Timer.NewTicker(3600, function()
    local k = Org:Get()
    if k and Org:IsAdmin() and type(k.pk) == "string" and now() - (tonumber(k.dkt) or 0) > ROTATE_WEEK then Org:RotateDataKey() end
    if k and Org:IsAdmin() then Org:SendAttestation(false) end
end)
C_Timer.NewTicker(10, askForDataKey)

---------------------------------------------------------------------------
-- The org minimum version (the admin sets it) and update notices
---------------------------------------------------------------------------
-- The versions the admin can require: the oldest supported, the first that
-- encrypts, and the admin's own, never above what the admin runs.
function Org:MinVersionChoices()
    local out, seen = {}, {}
    for _, v in ipairs({ ns.MIN_SUPPORTED, "0.7.0", ns.CRYPTO_VERSION, ns.VERSION }) do
        if not seen[v] and ns.CompareVersions(v, ns.VERSION) <= 0 then seen[v] = true; out[#out + 1] = v end
    end
    return out
end

function Org:MinVersion()
    local k = Org:Get()
    return (k and type(k.mv) == "string") and k.mv or ns.MIN_SUPPORTED
end

function Org:SetMinVersion(v)
    local k = Org:Get()
    if not (k and Org:IsAdmin() and Org.MySeed(k)) then return false, "Only the org admin can set the org's minimum version." end
    local ok = false
    for _, c in ipairs(Org:MinVersionChoices()) do if c == v then ok = true end end
    if not ok then return false, "Pick one of the versions listed." end
    if k.mv == v then return true end
    k.mv = v
    if not Org:DataKey() then Org.NewDataKey(k) end
    k.rev = Org.NextRev(k)
    Org.PublishEdit(k)
    return true
end

-- A version (a string from a hello) the org takes? An unknown version counts
-- as the oldest supported one: RUIN before 0.7.2 didn't say.
function Sec.VersionOk(v)
    local min = Org:MinVersion()
    if type(v) ~= "string" or v == "" then return ns.CompareVersions(ns.MIN_SUPPORTED, min) >= 0 end
    return ns.CompareVersions(v, min) >= 0
end

-- This client too old for the org?
function Org:TooOld()
    return ns.CompareVersions(ns.VERSION, Org:MinVersion()) < 0
end

local promptedOld, notedNewer = nil, nil
local function checkMyVersion()
    local k = Org:Get()
    if not k then return end
    if Org:TooOld() then
        if promptedOld ~= k.mv then
            promptedOld = k.mv
            local text = ("Your RUIN is version %s. The %s org needs at least version %s, so you won't be able to connect to the org until you update.\n\nThe newest version is an easy update through CurseForge or GitHub."):format(ns.VERSION, k.org, k.mv)
            ns:Print(("You can't connect to the %s org until you update RUIN to at least %s (you have %s). Update through CurseForge or GitHub."):format(k.org, k.mv, ns.VERSION))
            if ns.UI and ns.UI.ShowNotice then ns.UI:ShowNotice("Update RUIN to connect", text)
            elseif ns.UI and ns.UI.ShowConfirm then ns.UI:ShowConfirm("Update RUIN to connect", text, function() end) end
        end
        return
    end
    if type(k.av) == "string" and ns.CompareVersions(ns.VERSION, k.av) < 0 and notedNewer ~= k.av then
        notedNewer = k.av
        ns:Print(("A newer RUIN (%s) is available; you have %s. Update any time through CurseForge or GitHub."):format(k.av, ns.VERSION))
    end
end
ns:Subscribe("KEY_CHANGED", function() C_Timer.After(2, checkMyVersion) end)
ns:Subscribe("LOGIN", function() C_Timer.After(12, checkMyVersion) end)

-- RUIN below the org's minimum version: the guild's roster sender (one per
-- guild) has RUIN tell it, app to app, once a day per player: it can't
-- connect until it updates, and where the newest version is. (RUIN before
-- 0.7.3 doesn't understand this; it still hears from its own hellos that a
-- newer version is about, and gets no keys.)
local toldOld = {}
function Org:OnOldPeer(peer)
    if not (peer and peer.name and ns.Presence:IsRosterSender()) then return end
    local k = Org:Get()
    if not k or Sec.VersionOk(peer.v) then return end
    local n = ns.NormalizeName(peer.name)
    ns.db.toldOld = type(ns.db.toldOld) == "table" and ns.db.toldOld or {}
    if (ns.db.toldOld[n] or 0) > now() - 86400 or toldOld[n] then return end
    toldOld[n] = true
    ns.db.toldOld[n] = now()
    C_Timer.After(3 + math.random() * 5, function()
        ns.Comms:Send("OLDVER", { org = k.org, mv = k.mv or ns.MIN_SUPPORTED, v = ns.VERSION }, "PEER", peer.name, ns.Comms.PRIORITY.NORMAL)
    end)
end

-- Told (app to app) that this RUIN is below an org's minimum version.
ns.Comms:Register("OLDVER", function(d, sender)
    if type(d) ~= "table" or type(d.mv) ~= "string" or type(d.org) ~= "string" then return end
    local k = Org:Get()
    if k and k.org ~= d.org then return end
    if ns.CompareVersions(ns.VERSION, d.mv) >= 0 then return end
    if ns.Release then ns.Release.Heard(d.v, sender) end
    if promptedOld == d.mv then return end
    promptedOld = d.mv
    local text = ("Your RUIN is version %s. The %s org needs at least version %s, so you won't be able to connect to the org until you update.\n\nThe newest version is an easy update through CurseForge or GitHub."):format(ns.VERSION, d.org, d.mv)
    ns:Print(("You can't connect to the %s org until you update RUIN to at least %s (you have %s). Update through CurseForge or GitHub."):format(d.org, d.mv, ns.VERSION))
    if ns.UI and ns.UI.ShowNotice then ns.UI:ShowNotice("Update RUIN to connect", text) end
end)

---------------------------------------------------------------------------
-- The admin's recovery code: the signing seed in letters and digits.
---------------------------------------------------------------------------
local B32 = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
local function toB32(raw)
    local bits, out = "", {}
    for i = 1, #raw do
        local b = raw:byte(i)
        for j = 7, 0, -1 do bits = bits .. (math.floor(b / 2 ^ j) % 2) end
    end
    while #bits % 5 ~= 0 do bits = bits .. "0" end
    for i = 1, #bits, 5 do
        local v = tonumber(bits:sub(i, i + 4), 2)
        out[#out + 1] = B32:sub(v + 1, v + 1)
    end
    return table.concat(out)
end
local function fromB32(text)
    text = tostring(text or ""):upper():gsub("[^%w]", ""):gsub("^RUIN", "")
    local bits = {}
    for i = 1, #text do
        local p = B32:find(text:sub(i, i), 1, true)
        if not p then return nil end
        local v = p - 1
        for j = 4, 0, -1 do bits[#bits + 1] = math.floor(v / 2 ^ j) % 2 end
    end
    if #bits < 256 then return nil end
    local out = {}
    for i = 1, 32 do
        local b = 0
        for j = 1, 8 do b = b * 2 + bits[(i - 1) * 8 + j] end
        out[i] = string.char(b)
    end
    return table.concat(out)
end

function Org:RecoveryCode()
    local seed = Org.MySeed(Org:Get())
    if not seed then return nil end
    local s = toB32(seed)
    local groups = {}
    for i = 1, #s, 4 do groups[#groups + 1] = s:sub(i, i + 3) end
    return "RUIN-" .. table.concat(groups, "-")
end

function Org:Recover(code)
    local k = Org:Get()
    if not (k and type(k.pk) == "string") then return false, "Load the org key first (Import key), then type the recovery code." end
    local seed = fromB32(code)
    if not seed or Org.PkOf(seed) ~= k.pk then return false, "That recovery code isn't this org's admin code." end
    ns.db.adminSeeds = type(ns.db.adminSeeds) == "table" and ns.db.adminSeeds or {}
    ns.db.adminSeeds[k.org] = C.Hex(seed)
    ns:Fire("KEY_CHANGED", "edit")
    C_Timer.After(1, function() Org:Upgrade() end)
    return true
end

---------------------------------------------------------------------------
-- The Watch's account token: random, per org, account-wide. It follows a
-- player's characters for sanctions without saying anything about their
-- Battle.net account (it used to be a hash of the BattleTag, which a list of
-- likely BattleTags could undo).
---------------------------------------------------------------------------
function Sec.AccountToken()
    local k = Org:Get()
    if not (k and ns.db) then return nil end
    ns.db.watchTokens = type(ns.db.watchTokens) == "table" and ns.db.watchTokens or {}
    local t = ns.db.watchTokens[k.org]
    if type(t) ~= "string" then
        t = C.Token(16)
        ns.db.watchTokens[k.org] = t
    end
    return t
end
