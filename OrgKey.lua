-- RUIN Core: the org key
-- The key says which guilds belong to the org, which rank counts as officer
-- in each, and the names/passwords of the hidden org and officer channels.
--
-- Distribution:
--   * The org admin creates it and offers the full key to each guild's
--     leader in-game (/ruin key send, or the button with them targeted).
--   * Or the admin gives the org a key phrase ("dragons eat at dawn"): the
--     org channel's name and password come from the phrase, so typing it
--     under Import key joins that channel, and a RUIN member already on it
--     hands over the member key (the officer channel is never derived from
--     the phrase). Easier to share than the long key; easier to guess too.
--   * Inside a guild, officers share the member key (no officer channel)
--     over guild addon messages automatically when someone lacks it.
--   * Officers whisper the officer part to other officers in their guild.
local ADDON, ns = ...

local Org = {}
ns.Org = Org

local KEY_HEADER = "RUIN1:"
local MAX_REV = 2147483647        -- a sane revision: a huge one would freeze the key for good
local REV_JUMP = 1000             -- an update may not run further ahead than this
local REV_SEEN_SLACK = 500        -- how far ahead a reported revision may move the admin's next one
local MAX_ADMIN_NAMES = 10
local guildShareSuppressedUntil = 0
local guildSharePending = false
local officerShareCooldown = {}   -- normalized name -> time
local lastOfferPopup = -999

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
function Org:Get() return ns.db and ns.db.orgKey end
function Org:Rev() local k = Org:Get(); return k and k.rev or 0 end
function Org:HasOfficerPart() local k = Org:Get(); return k ~= nil and k.oc ~= nil end
-- The org admin is the character that created the key, and every other
-- character on the same WoW account: the first time the admin character
-- logs in, RUIN notes in the account-wide RUIN_DB that this account holds the
-- admin. A key imported on another account never carries that note.
local function accountIsAdmin(k)
    if not (k and ns.db) then return false end
    if ns.playerGUID ~= nil and k.admin == ns.playerGUID then
        ns.db.adminOf = type(ns.db.adminOf) == "table" and ns.db.adminOf or {}
        ns.db.adminOf[k.org] = k.admin
        return true
    end
    return type(ns.db.adminOf) == "table" and k.admin ~= nil and ns.db.adminOf[k.org] == k.admin
end
Org.AccountIsAdmin = accountIsAdmin

function Org:IsAdmin() return accountIsAdmin(Org:Get()) end

-- The admin's characters by name (key field `an`). The game vouches for the
-- name a message comes from and nothing else, so this list (not a GUID a
-- message claims) is how every client recognizes the org admin.
function Org:AdminNames(k)
    k = k or Org:Get()
    return (k and type(k.an) == "table") and k.an or {}
end

function Org:IsAdminName(name, k)
    if type(name) ~= "string" or name == "" then return false end
    local n = ns.NormalizeName(name)
    for _, a in ipairs(Org:AdminNames(k)) do
        if type(a) == "string" and ns.NormalizeName(a) == n then return true end
    end
    return false
end

local function addAdminName(k, name)
    if not (k and name) or Org:IsAdminName(name, k) then return false end
    k.an = type(k.an) == "table" and k.an or {}
    table.insert(k.an, 1, name)
    while #k.an > MAX_ADMIN_NAMES do table.remove(k.an) end
    return true
end

-- The highest key revision others report (hellos, keys passed on), so the
-- admin's next edit always lands above any copy in circulation.
local revSeen = 0
function Org:NoteRev(rev)
    rev = tonumber(rev)
    local k = Org:Get()
    if not (rev and k) or rev ~= math.floor(rev) then return end
    if rev > k.rev and rev <= k.rev + REV_SEEN_SLACK and rev > revSeen then revSeen = rev end
end

local function nextRev(k)
    return math.max(k.rev, revSeen) + 1
end
-- The admin character itself (rather than an alt on the same account).
function Org:IsAdminCharacter() local k = Org:Get(); return k ~= nil and ns.playerGUID ~= nil and k.admin == ns.playerGUID end

function Org:GuildInfo(name)
    local k = Org:Get()
    return k and name and k.guilds[name] or nil
end

function Org:MyGuildInOrg()
    return ns.guildName ~= nil and Org:GuildInfo(ns.guildName) ~= nil
end

function Org:OfficerRank(guildName)
    local g = Org:GuildInfo(guildName or ns.guildName)
    return (g and tonumber(g.o)) or 1
end

function Org:IsOfficerRank(rankIndex, guildName)
    return type(rankIndex) == "number" and rankIndex <= Org:OfficerRank(guildName)
end

function Org:AmOfficer()
    return Org:IsOfficerRank(ns.guildRank)
end

---------------------------------------------------------------------------
-- Validation and encoding
---------------------------------------------------------------------------
local function validChannel(c)
    return type(c) == "table" and type(c.n) == "string" and c.n ~= "" and type(c.p) == "string"
end

local function validKey(k)
    if type(k) ~= "table" or k.v ~= 1 then return false end
    if type(k.org) ~= "string" or k.org == "" then return false end
    if type(k.rev) ~= "number" or type(k.guilds) ~= "table" then return false end
    if k.rev < 1 or k.rev > MAX_REV or k.rev ~= math.floor(k.rev) then return false end
    if k.an ~= nil then
        if type(k.an) ~= "table" or #k.an > MAX_ADMIN_NAMES then return false end
        for _, a in pairs(k.an) do if type(a) ~= "string" or a == "" or #a > 48 then return false end end
    end
    for name, g in pairs(k.guilds) do
        if type(name) ~= "string" or type(g) ~= "table" then return false end
    end
    if not validChannel(k.c) then return false end
    if k.oc ~= nil and not validChannel(k.oc) then return false end
    if k.links ~= nil and type(k.links) ~= "table" then return false end
    if k.ph ~= nil and type(k.ph) ~= "string" then return false end
    if k.bw ~= nil and type(k.bw) ~= "table" then return false end
    if k.xt ~= nil and (type(k.xt) ~= "table" or type(k.xt.f) ~= "string" or type(k.xt.t) ~= "string") then return false end
    if k.ocr ~= nil and type(k.ocr) ~= "number" then return false end
    return true
end
Org.ValidKey = validKey

-- Members get neither the officer channel nor the key phrase (officers and
-- the admin hand the phrase out).
local function memberCopy(k)
    local copy = ns.DeepCopy(k)
    copy.oc, copy.ph = nil, nil
    return copy
end

---------------------------------------------------------------------------
-- Key phrases
---------------------------------------------------------------------------
local PHRASE_MIN, PHRASE_MAX = 6, 40

function Org.NormalizePhrase(text)
    text = tostring(text or ""):lower():gsub("%s+", " ")
    return ns.Trim(text)
end

-- Returns the normalized phrase, or nil and why.
function Org.CheckPhrase(text)
    local p = Org.NormalizePhrase(text)
    if #p < PHRASE_MIN then return nil, ("A key phrase needs at least %d characters."):format(PHRASE_MIN) end
    if #p > PHRASE_MAX then return nil, ("A key phrase can be at most %d characters."):format(PHRASE_MAX) end
    if p:find("|", 1, true) then return nil, "A key phrase can't contain the | character." end
    if p:sub(1, #KEY_HEADER):lower() == KEY_HEADER:lower() then return nil, "That looks like a full key, not a phrase." end
    return p
end

-- The org channel a phrase leads to (the same for everyone who types it).
function Org.PhraseChannel(phrase)
    local p = Org.NormalizePhrase(phrase)
    return { n = ("ruin" .. ns.Hash("RUIN channel|" .. p) .. ns.Hash("RUIN name|" .. p):sub(1, 4)):lower(),
             p = (ns.Hash("RUIN pass|" .. p) .. ns.Hash("RUIN word|" .. p)):lower() }
end

function Org:Phrase()
    local k = Org:Get()
    return k and k.ph or nil
end

function Org.Encode(k)
    local body = ns.Base64Encode(ns.Serialize(k))
    return KEY_HEADER .. body .. "." .. ns.Hash(body)
end

-- Returns key, err
function Org.Decode(text)
    if type(text) ~= "string" then return nil, "no text" end
    text = text:gsub("%s+", "")
    if text:sub(1, #KEY_HEADER) ~= KEY_HEADER then return nil, "that is not a RUIN key" end
    local body, sum = text:sub(#KEY_HEADER + 1):match("^(.+)%.(%x+)$")
    if not body then return nil, "the key is incomplete" end
    if ns.Hash(body) ~= sum then return nil, "the key is damaged (checksum mismatch)" end
    local raw = ns.Base64Decode(body)
    if not raw then return nil, "the key is damaged (encoding)" end
    local k, err = ns.Deserialize(raw)
    if err then return nil, "the key contents are invalid" end
    k = ns.SanitizeTree(k)
    if not validKey(k) then return nil, "the key contents are invalid" end
    return k
end

---------------------------------------------------------------------------
-- Applying a key
---------------------------------------------------------------------------
-- source: "import" (user consented), "admin" (from the admin, by name),
-- "guild" (an officer of your guild), "officer" (an officer passing it on),
-- "create", "edit"
function Org:Apply(k, source)
    if not validKey(k) then return false, "invalid key" end
    k = ns.DeepCopy(k)
    local cur = Org:Get()

    if cur then
        if cur.org ~= k.org and source ~= "import" then return false, "belongs to a different org" end
        if cur.org == k.org then
            if k.rev < cur.rev then return false, "older than the key you have" end
            if source ~= "import" then
                -- A new admin comes only from the admin handing it over: the
                -- key from the admin itself, or passed on by an officer with
                -- the hand-over's record (from the admin you know, to the new
                -- one). The admin's own account loses it only by handing it
                -- over itself (Org:TransferAdmin), never by a key from outside.
                local newAdmin = cur.admin ~= nil and k.admin ~= cur.admin
                if newAdmin then
                    if accountIsAdmin(cur) then return false, "names a different org admin" end
                    local handedOver = type(k.xt) == "table" and k.xt.f == cur.admin and k.xt.t == k.admin
                    if not (source == "admin" or ((source == "officer" or source == "guild") and handedOver)) then
                        return false, "names a different org admin"
                    end
                end
                if k.rev > cur.rev + REV_JUMP then return false, "jumps too far ahead" end
                -- Who counts as the admin changes only when the admin says so
                -- (or, for a key from before admin names, the first time).
                if source ~= "admin" and not newAdmin and type(cur.an) == "table" then k.an = ns.DeepCopy(cur.an) end
            end
            if k.rev == cur.rev then
                if k.oc and not cur.oc and (accountIsAdmin(cur) or Org:AmOfficer()) then
                    cur.oc, cur.ocr, cur.ph = k.oc, k.ocr, k.ph or cur.ph
                    ns:Fire("KEY_CHANGED", source)
                    return true
                end
                return false, "same as the key you have"
            end
        end
    end

    -- A key without the officer channel (the member copy): an officer keeps
    -- theirs while it's still the current one (same generation).
    if not k.oc and cur and cur.oc and cur.org == k.org and (k.ocr or 0) == (cur.ocr or 0) then k.oc = cur.oc end
    -- Only officers of their own guild (or the admin) keep the officer channel.
    if k.oc and not accountIsAdmin(k) then
        local g = ns.guildName and k.guilds[ns.guildName]
        local officerRank = (g and tonumber(g.o)) or 1
        if not (type(ns.guildRank) == "number" and ns.guildRank <= officerRank) then
            k.oc = nil
        end
    end

    ns.db.orgKey = k
    if source == "import" and type(ns.db.leftOrgs) == "table" then ns.db.leftOrgs[k.org] = nil end
    if source == "import" and type(ns.db.disbanded) == "table" then ns.db.disbanded[k.org] = nil end
    ns:Fire("KEY_CHANGED", source)
    return true
end

-- Orgs you left, or that were disbanded: their key isn't taken back on its
-- own (an officer of your guild shares it automatically otherwise); only
-- importing it again (a key, a phrase, an offered key you accept) does.
local function refused(org)
    if type(org) ~= "string" then return false end
    return (type(ns.db.leftOrgs) == "table" and ns.db.leftOrgs[org] ~= nil)
        or (type(ns.db.disbanded) == "table" and ns.db.disbanded[org] ~= nil)
end
Org.Refused = refused

function Org:Forget()
    if ns.db then ns.db.orgKey = nil end
    ns:Fire("KEY_CHANGED", "forget")
end

---------------------------------------------------------------------------
-- Admin actions
---------------------------------------------------------------------------
local function newChannel()
    return { n = "ruin" .. ns.RandomToken(10), p = ns.RandomToken(12) }
end

local function defaultTag(name)
    if #name <= 14 then return name end
    return name:sub(1, 12)
end

-- phrase (optional): the org's key phrase; without one the key is random.
function Org:Create(orgName, phrase)
    if not ns.guildName then return false, "You need to be in a guild to create an org key." end
    if Org:Get() then return false, "You already have an org key. Use /ruin key forget first if you really want a new org." end
    orgName = ns.Trim(orgName or "")
    if orgName == "" then orgName = "RUIN" end
    local ph
    if phrase and ns.Trim(phrase) ~= "" then
        local err
        ph, err = Org.CheckPhrase(phrase)
        if not ph then return false, err end
    end
    local k = {
        v = 1, org = orgName, rev = 1, admin = ns.playerGUID, t = ns.Now(),
        guilds = { [ns.guildName] = { o = 1, tag = defaultTag(ns.guildName) } },
        c = ph and Org.PhraseChannel(ph) or newChannel(), oc = newChannel(), ph = ph,
        an = { ns.playerName },
    }
    ns.db.orgKey = k
    ns:Fire("KEY_CHANGED", "create")
    return true
end

local function editableKey()
    local k = Org:Get()
    if not k then return nil, "No org key loaded." end
    if not Org:IsAdmin() then return nil, "Only the org admin can change the org key." end
    -- the character making the edit counts as the admin from now on
    addAdminName(k, ns.playerName)
    return k
end

-- After an admin edit, announce the new key to every guild's officers on the
-- officer channel they are on *now* (it may be about to change), then switch.
-- An edit reaches officers in full (officer channel) and every member online
-- at once (the member copy on the org channel): members used to wait for an
-- officer of their own guild to pass it on, which could take a while or,
-- with no officer online, never happen.
--
-- When the officer channel itself changes, the new one is never sent on the
-- old one: whoever still listens there (an officer since demoted, a removed
-- guild) would hear it. The old channel gets the key without it; the new one
-- goes by whisper to the officers RUIN can vouch for (your guild's roster,
-- other guilds' officers seen lately), minus anyone locked out, and each
-- guild's officers pass it to their own officer-rank guildmates (OKEY).
local function deliverOfficerChannel(k, exclude, removedGuild)
    exclude = exclude or {}
    local sent = 0
    for _, o in ipairs(ns.Presence:KnownOfficers()) do
        local n = ns.NormalizeName(o.name)
        local guildOk = not o.guild or (k.guilds[o.guild] and o.guild ~= removedGuild)
        if guildOk and not exclude[n] and n ~= ns.playerNorm and (o.online or o.roster) then
            ns.Comms:Send("ORGKEY", { k = ns.DeepCopy(k) }, "PEER", o.name, ns.Comms.PRIORITY.ALERT)
            sent = sent + 1
        end
    end
    return sent
end

local function publishEdit(k, oldOfficerChannel, exclude, removedGuild)
    if oldOfficerChannel then
        if k.oc and k.oc.n ~= oldOfficerChannel then
            ns.Comms:Send("ORGKEY", { k = memberCopy(k) }, "OFFICERS", oldOfficerChannel, ns.Comms.PRIORITY.ALERT)
            deliverOfficerChannel(k, exclude, removedGuild)
        else
            ns.Comms:Send("ORGKEY", { k = ns.DeepCopy(k) }, "OFFICERS", oldOfficerChannel, ns.Comms.PRIORITY.ALERT)
        end
    end
    ns.Comms:Send("MKEY", { k = memberCopy(k) }, "ORG", nil, ns.Comms.PRIORITY.ALERT)
    ns:Fire("KEY_CHANGED", "edit")
end

-- A new officer channel: the generation number moves on, so a key without
-- the officer channel tells an officer theirs is out of date.
local function newOfficerChannel(k)
    k.oc = newChannel()
    k.ocr = (tonumber(k.ocr) or 0) + 1
end

function Org:AddGuild(name, rank, tag)
    local k, err = editableKey()
    if not k then return false, err end
    name = ns.Trim(name or "")
    if name == "" then return false, "Usage: /ruin key addguild <guild>, <officer rank>[, <tag>]" end
    local oldOC = k.oc and k.oc.n
    k.guilds[name] = { o = tonumber(rank) or 1, tag = (tag and tag ~= "") and tag or defaultTag(name) }
    k.rev = nextRev(k)
    publishEdit(k, oldOC)
    return true
end

-- Change a guild's entry: its name (must match the in-game guild name
-- exactly), the lowest rank that counts as officer, and its short tag.
function Org:EditGuild(oldName, newName, rank, tag)
    local k, err = editableKey()
    if not k then return false, err end
    oldName = ns.Trim(oldName or "")
    local g = k.guilds[oldName]
    if not g then return false, "That guild is not in the org key." end
    newName = ns.Trim(newName or oldName)
    if newName == "" then return false, "The guild needs a name." end
    if newName ~= oldName and k.guilds[newName] then return false, "Another guild already has that name." end
    rank = tonumber(rank)
    if rank and (rank < 0 or rank > 9 or rank ~= math.floor(rank)) then return false, "The officer rank is 0 (guild master) to 9." end
    tag = tag and ns.Trim(tag) or nil
    local entry = { o = rank or g.o, tag = (tag and tag ~= "") and tag:sub(1, 14) or g.tag }
    local same = newName == oldName and entry.o == g.o and entry.tag == g.tag
    if same then return true end
    local oldOC = k.oc and k.oc.n
    k.guilds[oldName] = nil
    k.guilds[newName] = entry
    k.rev = nextRev(k)
    publishEdit(k, oldOC)
    return true
end

function Org:GuildNames()
    local k = Org:Get()
    local list = {}
    for name in pairs(k and k.guilds or {}) do list[#list + 1] = name end
    table.sort(list)
    return list
end

function Org:RemoveGuild(name)
    local k, err = editableKey()
    if not k then return false, err end
    name = ns.Trim(name or "")
    if not k.guilds[name] then return false, "That guild is not in the org key." end
    local oldOC = k.oc and k.oc.n
    k.guilds[name] = nil
    k.rev = nextRev(k)
    -- A removed guild still knows the old passwords, so rotate them too.
    -- Honest clients of the removed guild ignore the announcement because
    -- their guild is no longer listed; see README for the limits of this.
    -- With a key phrase the org channel stays the phrase's (the admin
    -- chooses a new phrase to lock them out of it).
    if not k.ph then k.c = newChannel() end
    newOfficerChannel(k)
    publishEdit(k, oldOC, nil, name)
    return true
end

-- A new key for everyone: a new key phrase (phrase given) or a random key
-- (phrase nil or ""). The org and officer channels both change; officers
-- online get the new key at once and pass it to their guilds.
function Org:ChooseNewKey(phrase)
    local k, err = editableKey()
    if not k then return false, err end
    local ph
    if phrase and ns.Trim(phrase) ~= "" then
        ph, err = Org.CheckPhrase(phrase)
        if not ph then return false, err end
    end
    local oldOC = k.oc and k.oc.n
    k.c, k.ph = ph and Org.PhraseChannel(ph) or newChannel(), ph
    newOfficerChannel(k)
    k.rev = nextRev(k)
    publishEdit(k, oldOC)
    return true
end

function Org:Rotate() return Org:ChooseNewKey(Org:Phrase()) end

-- Lock someone out of the officer channel (an officer demoted, kicked or
-- gone): a new officer channel, delivered to every other officer RUIN can
-- vouch for. `names` are the characters to leave out.
function Org:RotateOfficerChannel(names)
    local k, err = editableKey()
    if not k then return false, err end
    local exclude = {}
    for _, n in ipairs(type(names) == "table" and names or {}) do
        if type(n) == "string" and ns.Trim(n) ~= "" then
            exclude[ns.NormalizeName(ns.Trim(n))] = true
            ns.Presence:ForgetOfficer(ns.Trim(n))
        end
    end
    local oldOC = k.oc and k.oc.n
    newOfficerChannel(k)
    k.rev = nextRev(k)
    publishEdit(k, oldOC, exclude)
    return true
end

---------------------------------------------------------------------------
-- Leaving the org (anyone) and disbanding it (the admin)
---------------------------------------------------------------------------
-- Leave: this account drops the key, and won't take it back from your
-- guild's officers until you import it again yourself.
function Org:Leave()
    local k = Org:Get()
    if not k then return false, "You're not in an org." end
    if Org:IsAdmin() then
        return false, "You're the org admin: hand the admin over first (Transfer admin), or disband the org."
    end
    ns.db.leftOrgs = type(ns.db.leftOrgs) == "table" and ns.db.leftOrgs or {}
    ns.db.leftOrgs[k.org] = ns.Now()
    Org:Forget()
    return true, k.org
end

-- Disband: every member's RUIN drops the key. Members online get it at once
-- (org and officer channels); anyone offline hears it later from a member
-- who did (see relayDisband), and their guild's officers stop sharing it.
local function markDisbanded(k)
    ns.db.disbanded = type(ns.db.disbanded) == "table" and ns.db.disbanded or {}
    ns.db.disbanded[k.org] = { admin = k.admin, an = ns.DeepCopy(k.an or {}), t = ns.Now() }
end

function Org:Disband()
    local k, err = editableKey()
    if not k then return false, err end
    local note = { org = k.org, admin = k.admin }
    ns.Comms:Send("DISBAND", note, "ORG", nil, ns.Comms.PRIORITY.ALERT)
    if k.oc then ns.Comms:Send("DISBAND", note, "OFFICERS", nil, ns.Comms.PRIORITY.ALERT) end
    markDisbanded(k)
    if type(ns.db.adminOf) == "table" then ns.db.adminOf[k.org] = nil end
    -- leave the channels after the message has gone out
    local org = k.org
    C_Timer.After(3, function()
        local cur = Org:Get()
        if cur and cur.org == org then Org:Forget() end
    end)
    return true, org
end

local relayed = {}       -- name -> time: tell each straggler once in a while
local function relayDisband(org, name)
    if type(name) ~= "string" or name == "" then return end
    local n = ns.NormalizeName(name)
    if relayed[n] and GetTime() < relayed[n] then return end
    relayed[n] = GetTime() + 300
    local rec = ns.db.disbanded and ns.db.disbanded[org]
    if not rec then return end
    ns.Comms:Send("DISBAND", { org = org, admin = rec.admin, relay = 1 }, "PEER", name, ns.Comms.PRIORITY.BULK)
end
Org.RelayDisband = relayDisband

ns.Comms:Register("DISBAND", function(d, sender, scope)
    local k = Org:Get()
    if not (k and type(d) == "table" and d.org == k.org and d.admin == k.admin) then return end
    local fromAdmin = Org:IsAdminName(sender, k)
    if not fromAdmin then
        -- passed on: from an officer, or someone in your own guild
        if not (d.relay and scope == "PEER") then return end
        local entry = ns.roster[ns.NormalizeName(sender)]
        if not (ns.Presence:IsOfficerName(sender) or entry) then return end
    end
    if Org:IsAdmin() and not fromAdmin then return end      -- the admin's own org only ends by its own hand
    markDisbanded(k)
    ns:Print(("The %s org was disbanded by its admin%s. RUIN dropped the org key; import a new one to join another org.")
        :format(k.org, fromAdmin and (" (" .. ns.ShortName(sender) .. ")") or ""))
    Org:Forget()
end)

---------------------------------------------------------------------------
-- Officers who stop being officers
-- An officer's RUIN watches its own guild's roster. When someone who was at
-- officer rank is demoted, or leaves or is removed from the guild, it tells
-- the admin (on the officer channel), and the admin is asked to lock them out
-- of the officer channel (Org:RotateOfficerChannel).
---------------------------------------------------------------------------
local lostQueue, lostPrompted, lostTimer = {}, {}, false
local function promptLost()
    lostTimer = false
    local names, label = {}, {}
    for n, e in pairs(lostQueue) do
        if not lostPrompted[n] then
            lostPrompted[n] = true
            names[#names + 1] = e.name
            label[#label + 1] = ns.ShortName(e.name) .. (e.guild and (" (" .. e.guild .. ")") or "")
        end
    end
    lostQueue = {}
    if #names == 0 or not Org:IsAdmin() then return end
    table.sort(label)
    ns.UI:ShowConfirm("Lock out of the officer channel?",
        ("%s %s no longer an officer.\n\nThey still know the officer channel's password. Make a new officer channel and give it to every other officer?")
            :format(table.concat(label, ", "), #names == 1 and "is" or "are"),
        function()
            local ok, err = Org:RotateOfficerChannel(names)
            ns:Print(ok and "New officer channel made; the other officers get it now." or err)
        end)
end
local function noteLost(name, guild)
    local n = ns.NormalizeName(name)
    if lostPrompted[n] then return end
    lostQueue[n] = { name = name, guild = guild }
    if not lostTimer then
        lostTimer = true
        C_Timer.After(8, promptLost)
    end
end
Org.NoteLostOfficer = noteLost

ns:Subscribe("ROSTER_UPDATED", function()
    local k = Org:Get()
    if not (k and ns.guildName and k.guilds[ns.guildName] and (Org:AmOfficer() or Org:IsAdmin())) then return end
    local roster = ns.roster or {}
    local count, now = 0, {}
    for norm, e in pairs(roster) do
        count = count + 1
        if Org:IsOfficerRank(e.rank) then now[norm] = e.name end
    end
    if count == 0 then return end
    ns.db.guildOfficers = type(ns.db.guildOfficers) == "table" and ns.db.guildOfficers or {}
    local key = k.org .. "/" .. ns.guildName
    local before = ns.db.guildOfficers[key]
    -- a roster much smaller than last time is a partial one: wait for the full one
    if type(before) == "table" and (before._n or 0) > 0 and count < (before._n or 0) * 0.8 then return end
    if type(before) == "table" then
        for norm, name in pairs(before) do
            if norm ~= "_n" and not now[norm] and norm ~= ns.playerNorm then
                if Org:IsAdmin() then noteLost(name, ns.guildName)
                elseif k.oc then
                    ns.Comms:Send("OCLOST", { n = name, g = ns.guildName }, "OFFICERS", nil, ns.Comms.PRIORITY.ALERT)
                end
            end
        end
    end
    now._n = count
    ns.db.guildOfficers[key] = now
end)

ns.Comms:Register("OCLOST", function(d, sender, scope)
    if scope ~= "OFFICERS" or type(d.n) ~= "string" or not Org:IsAdmin() then return end
    local k = Org:Get()
    if not (k and type(d.g) == "string" and k.guilds[d.g]) then return end
    noteLost(d.n:sub(1, 48), d.g)
end)

---------------------------------------------------------------------------
-- Handing the org admin over to someone else
--   1. The admin offers it (Settings > Org > Transfer admin, or
--      /ruin key transfer <name>); the other player must be online, with
--      RUIN, in one of the org's guilds.
--   2. They accept (RUIN's own dialog) and answer with their character.
--   3. The admin's client makes the new key: that character is the admin,
--      only their name counts as the admin's, and the key records the
--      hand-over so officers can pass it on. It goes to every officer on
--      the officer channel and to the new admin directly; this account
--      stops being the admin.
---------------------------------------------------------------------------
local OFFER_WAIT = 120
local adminOffer                     -- { name, untilT } while waiting for an answer
local adminOfferSeen = -999

function Org:OfferAdmin(name)
    local k = Org:Get()
    if not k then return false, "No org key loaded." end
    if not Org:IsAdmin() then return false, "Only the org admin can hand the admin over." end
    name = ns.Trim(name or "")
    if name == "" then return false, "Whom should the admin go to? Type their character name." end
    if ns.NormalizeName(name) == ns.NormalizeName(ns.playerName or "") or Org:IsAdminName(name, k) then
        return false, "That character is already the org admin."
    end
    adminOffer = { name = ns.NormalizeName(name), untilT = GetTime() + OFFER_WAIT }
    ns.Comms:Send("ADMINOFFER", { org = k.org, rev = k.rev }, "PEER", name, ns.Comms.PRIORITY.ALERT)
    return true
end

function Org:PendingAdminOffer()
    if adminOffer and GetTime() < adminOffer.untilT then return adminOffer.name end
end

-- Makes `name` (character GUID `guid`) the org admin. Called when they accept.
function Org:TransferAdmin(name, guid)
    local k, err = editableKey()
    if not k then return false, err end
    if type(guid) ~= "string" or not guid:find("^Player%-") then return false, "That answer didn't name a character." end
    if guid == k.admin then return false, "That character is already the org admin." end
    local oldOC = k.oc and k.oc.n
    k.xt = { f = k.admin, t = guid }
    k.admin = guid
    k.an = { name }
    k.rev = nextRev(k)
    if type(ns.db.adminOf) == "table" then ns.db.adminOf[k.org] = nil end
    -- the new admin first (they may not be on the officer channel yet), then every officer
    ns.Comms:Send("ORGKEY", { k = ns.DeepCopy(k) }, "PEER", name, ns.Comms.PRIORITY.ALERT)
    publishEdit(k, oldOC)
    adminOffer = nil
    return true
end

ns.Comms:Register("ADMINOFFER", function(d, sender, scope)
    if scope ~= "PEER" then return end
    local k = Org:Get()
    if not (k and d.org == k.org and Org:IsAdminName(sender, k)) then return end
    if not Org:MyGuildInOrg() then
        ns:Print(ns.ShortName(sender) .. " offered you the org admin, but your guild isn't in the org.")
        return
    end
    if GetTime() - adminOfferSeen < 10 then return end
    adminOfferSeen = GetTime()
    ns.UI:ShowConfirm("Become the RUIN org admin?",
        ("%s wants to hand the %s org admin over to you.\n\nYou would manage the org key: its guilds, key phrase, links and block words. %s would no longer be the admin.\n\nAccept?")
            :format(ns.ShortName(sender), k.org, ns.ShortName(sender)),
        function()
            ns.Comms:Send("ADMINACCEPT", { org = k.org, g = ns.playerGUID }, "PEER", sender, ns.Comms.PRIORITY.ALERT)
            ns:Print("You accepted the org admin. The new key arrives in a moment.")
        end)
end)

ns.Comms:Register("ADMINACCEPT", function(d, sender, scope)
    if scope ~= "PEER" then return end
    local k = Org:Get()
    if not (k and d.org == k.org and Org:IsAdmin()) then return end
    if not (adminOffer and GetTime() < adminOffer.untilT and adminOffer.name == ns.NormalizeName(sender)) then return end
    local ok, err = Org:TransferAdmin(sender, d.g)
    ns:Print(ok and (ns.ShortName(sender) .. " is now the org admin. Everyone gets the new key from the officers.") or ("Didn't hand the admin over: " .. tostring(err)))
end)

---------------------------------------------------------------------------
-- Community links (Discord, website, streams...) travel inside the org key,
-- so every member gets them the same way they get the key. Old RUIN versions
-- simply carry the extra field along.
---------------------------------------------------------------------------
local MAX_LINKS = 8

function Org:GetLinks()
    local k = Org:Get()
    local out = {}
    if not (k and type(k.links) == "table") then return out end
    for _, l in ipairs(k.links) do
        if #out >= MAX_LINKS then break end
        if type(l) == "table" and type(l.l) == "string" and type(l.u) == "string" and l.l ~= "" and l.u ~= "" then
            out[#out + 1] = { label = l.l:sub(1, 24), url = l.u:sub(1, 160) }
        end
    end
    return out
end

-- "Discord = https://discord.gg/..." one per line.
function Org.ParseLinks(text)
    local list = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local label, url = line:match("^%s*(.-)%s*=%s*(%S+)%s*$")
        if label and label ~= "" and url and #list < MAX_LINKS then
            list[#list + 1] = { label = label, url = url }
        end
    end
    return list
end

function Org.LinksText()
    local lines = {}
    for _, l in ipairs(Org:GetLinks()) do lines[#lines + 1] = l.label .. " = " .. l.url end
    return table.concat(lines, "\n")
end

function Org:SetLinks(list)
    local k, err = editableKey()
    if not k then return false, err end
    local clean = {}
    for _, l in ipairs(list or {}) do
        local label, url = ns.Trim(l.label or l.l or ""), ns.Trim(l.url or l.u or "")
        if label ~= "" and url ~= "" and #clean < MAX_LINKS then
            clean[#clean + 1] = { l = label:sub(1, 24), u = url:sub(1, 160) }
        end
    end
    k.links = #clean > 0 and clean or nil
    k.rev = nextRev(k)
    publishEdit(k, k.oc and k.oc.n)
    return true
end

-- The org's shared block words (Chat.lua hides lines with them), set by the admin.
function Org:SetBlockWords(list)
    local k, err = editableKey()
    if not k then return false, err end
    k.bw = (type(list) == "table" and #list > 0) and list or nil
    k.rev = nextRev(k)
    publishEdit(k, k.oc and k.oc.n)
    return true
end

-- An updated key from the admin (officer channel or a whisper), or passed on
-- by an officer to someone who was offline during the edit.
-- source: "admin" (from the admin, by name) or "officer"
local function acceptOrgKey(d, sender, source)
    if not validKey(d.k) then return end
    local cur = Org:Get()
    if not cur or cur.org ~= d.k.org or d.k.rev < cur.rev then return end
    -- the same rev again only to hand an officer the new officer channel
    if d.k.rev == cur.rev and not (d.k.oc and not cur.oc) then return end
    if not ns.guildName or not d.k.guilds[ns.guildName] then
        if not Org:IsAdmin() then
            ns:Print("The org key was updated, but your guild is no longer listed in it.")
            return
        end
    end
    local ok, why = Org:Apply(d.k, source)
    if ok then
        ns:Print(("Org key updated to rev %d (from %s)."):format(d.k.rev, ns.ShortName(sender)))
    else
        ns:Debug(("ignored an org key from %s: %s"):format(tostring(sender), tostring(why)))
    end
end

local function nameInList(list, name)
    local n = ns.NormalizeName(name)
    for _, a in ipairs(type(list) == "table" and list or {}) do
        if type(a) == "string" and ns.NormalizeName(a) == n then return true end
    end
    return false
end

-- Is the sender (the name the game reports) the org admin?
local function senderIsAdmin(sender, d, scope)
    local cur = Org:Get()
    if not cur then return false end
    if type(cur.an) == "table" then return Org:IsAdminName(sender, cur) end
    -- A key from before admin names (RUIN 0.4.4 and older): the game may know
    -- the admin character's name from its GUID; if not, a key on the officer
    -- channel, where only officers can talk, that keeps the admin and names
    -- its sender among the admin's characters is taken as the admin's.
    if cur.admin and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, cur.admin)
        if ok and type(name) == "string" and name ~= "" then
            return ns.NormalizeName(name) == ns.NormalizeName(sender)
        end
    end
    return scope == "OFFICERS" and type(d.k) == "table" and d.k.admin == cur.admin and nameInList(d.k.an, sender)
end
Org.SenderIsAdmin = function(sender) return senderIsAdmin(sender, {}, "PEER") end

ns.Comms:Register("ORGKEY", function(d, sender, scope)
    if (scope ~= "OFFICERS" and scope ~= "PEER") or type(d.k) ~= "table" then return end
    if senderIsAdmin(sender, d, scope) then
        acceptOrgKey(d, sender, "admin")
    elseif ns.Presence:IsOfficerName(sender) then
        if type(d.k.rev) == "number" then Org:NoteRev(d.k.rev) end
        -- an officer can pass the key on; Apply keeps the admin as it is
        acceptOrgKey(d, sender, "officer")
    else
        ns:Debug("ignored an org key from " .. tostring(sender) .. " (not the admin or an officer)")
    end
end)

-- The member copy of an edit, from the admin on the org channel. It has no
-- officer channel: an officer keeps theirs (a new one comes in full on the
-- officer channel).
ns.Comms:Register("MKEY", function(d, sender, scope)
    if scope ~= "ORG" or type(d.k) ~= "table" or not validKey(d.k) then return end
    if not senderIsAdmin(sender, d, scope) then return end
    local cur = Org:Get()
    if not cur or cur.org ~= d.k.org or d.k.rev <= cur.rev then return end
    acceptOrgKey(d, sender, "admin")
end)

-- Keys made before admin names: the admin's characters add themselves the
-- first time they log in with this version (and any alt the first time it
-- logs in), so every client can tell the admin by name.
ns:Subscribe("LOGIN", function()
    C_Timer.After(20, function()
        local k = Org:Get()
        if not (k and Org:IsAdmin() and ns.playerName) or Org:IsAdminName(ns.playerName, k) then return end
        local oldOC = k.oc and k.oc.n
        addAdminName(k, ns.playerName)
        k.rev = nextRev(k)
        if oldOC then
            ns.Comms:Send("ORGKEY", { k = ns.DeepCopy(k) }, "OFFICERS", oldOC, ns.Comms.PRIORITY.ALERT)
        end
        ns:Fire("KEY_CHANGED", "edit")
    end)
end)

-- Called by Presence for each OHELLO on the org channel: if an officer of
-- another guild is behind on the key (they were offline during an edit that
-- kept the same channels), whisper them the current one.
local orgCatchUpCooldown = {}
function Org:OnOrgPeer(peer)
    local k = Org:Get()
    if not (k and k.oc and Org:AmOfficer()) then return end
    if peer.o ~= 1 or (peer.kr or 0) >= k.rev or peer.guild == ns.guildName then return end
    local norm = ns.NormalizeName(peer.name)
    if orgCatchUpCooldown[norm] and GetTime() < orgCatchUpCooldown[norm] then return end
    orgCatchUpCooldown[norm] = GetTime() + 300
    C_Timer.After(2 + math.random() * 8, function()
        local cur = Org:Get()
        if cur and peer.kr < cur.rev then
            ns.Comms:Send("ORGKEY", { k = ns.DeepCopy(cur) }, "PEER", peer.name, ns.Comms.PRIORITY.BULK)
        end
    end)
end

---------------------------------------------------------------------------
-- Channels follow the key
---------------------------------------------------------------------------
local joining      -- { n, p, phrase, untilT } while joining by key phrase

function Org:ApplyChannels()
    if not ns.loggedIn then return end
    local k = Org:Get()
    if joining and GetTime() < joining.untilT and not (k and k.c.n == joining.n) then
        ns.Comms:SetChannel("ORG", joining.n, joining.p)
        ns.Comms:SetChannel("OFFICERS", nil)
        return
    end
    -- the admin stays connected on every character of the account, so the
    -- org can be run from an alt in another guild
    local admin = Org:IsAdmin()
    if k and (Org:MyGuildInOrg() or admin) then
        ns.Comms:SetChannel("ORG", k.c.n, k.c.p)
        if k.oc and (Org:AmOfficer() or admin) then
            ns.Comms:SetChannel("OFFICERS", k.oc.n, k.oc.p)
        else
            ns.Comms:SetChannel("OFFICERS", nil)
        end
    else
        ns.Comms:SetChannel("ORG", nil)
        ns.Comms:SetChannel("OFFICERS", nil)
    end
end

ns:Subscribe("KEY_CHANGED", function() Org:ApplyChannels() end)
ns:Subscribe("GUILD_CHANGED", function() Org:ApplyChannels() end)
ns:Subscribe("LOGIN", function() C_Timer.After(3, function() Org:ApplyChannels() end) end)

---------------------------------------------------------------------------
-- Sharing inside a guild
---------------------------------------------------------------------------
local function scheduleGuildShare()
    if guildSharePending then return end
    guildSharePending = true
    -- shared in the last 30 s: wait until then (a late joiner asking right
    -- after a share used to be dropped until their next hello)
    local wait = math.max(0, guildShareSuppressedUntil - GetTime())
    C_Timer.After(wait + 2 + math.random() * 6, function()
        guildSharePending = false
        local k = Org:Get()
        if not k then return end
        if not (Org:MyGuildInOrg() and Org:AmOfficer()) then return end
        ns.Comms:Send("KEY", { k = memberCopy(k) }, "GUILD", nil, ns.Comms.PRIORITY.BULK)
        guildShareSuppressedUntil = GetTime() + 30
    end)
end

local function scheduleOfficerShare(name, tries)
    local norm = ns.NormalizeName(name)
    if not tries and officerShareCooldown[norm] and GetTime() < officerShareCooldown[norm] then return end
    officerShareCooldown[norm] = GetTime() + 120
    C_Timer.After(1 + math.random() * 3, function()
        local k = Org:Get()
        if not (k and k.oc and Org:AmOfficer()) then return end
        local entry = ns.roster[norm]
        if not entry then
            -- someone new to the guild isn't in our roster yet: refresh it and
            -- look again (the roster is asked for at most every 15 seconds)
            if (tries or 0) < 3 then
                ns:RequestRoster()
                C_Timer.After(16, function() scheduleOfficerShare(name, (tries or 0) + 1) end)
            end
            return
        end
        if not Org:IsOfficerRank(entry.rank) then return end
        ns.Comms:Send("OKEY", { org = k.org, rev = k.rev, oc = k.oc }, "PEER", name, ns.Comms.PRIORITY.BULK)
    end)
end

-- Called by Presence whenever a guildmate's HELLO arrives.
function Org:OnPeerKeyState(peer)
    if type(peer.org) == "string" and peer.org ~= "" and ns.db and type(ns.db.disbanded) == "table" and ns.db.disbanded[peer.org] then
        relayDisband(peer.org, peer.name)
    end
    local k = Org:Get()
    if not k or not Org:MyGuildInOrg() or not Org:AmOfficer() then return end
    if peer.org and peer.org ~= "" and peer.org ~= k.org then return end
    if (peer.kr or 0) < k.rev then
        scheduleGuildShare()
    elseif peer.o == 1 and peer.ko ~= 1 and k.oc and peer.kr == k.rev then
        scheduleOfficerShare(peer.name)
    end
end

-- An officer whose key just changed (created, edited, accepted, updated)
-- shares it with the guild right away instead of waiting for HELLOs.
ns:Subscribe("KEY_CHANGED", function(source)
    if source == "guild" or source == "forget" or source == "officer-part" then return end
    if Org:Get() and Org:MyGuildInOrg() and Org:AmOfficer() then scheduleGuildShare() end
end)

ns.Comms:Register("KEY", function(d, sender, scope)
    if scope ~= "GUILD" or not validKey(d.k) then return end
    if refused(d.k.org) then
        -- tell an officer still sharing a disbanded org's key
        if ns.db.disbanded and ns.db.disbanded[d.k.org] then relayDisband(d.k.org, sender) end
        return
    end
    local cur = Org:Get()
    if cur and cur.org == d.k.org and d.k.rev <= cur.rev then
        guildShareSuppressedUntil = GetTime() + 30   -- someone else already shared
        return
    end
    if not ns.guildName or not d.k.guilds[ns.guildName] then return end

    -- Only accept from someone at or above the officer rank we already trust.
    local entry = ns.roster[ns.NormalizeName(sender)]
    if not entry then
        ns:RequestRoster()
        return
    end
    local trustedRank = (cur and cur.org == d.k.org and Org:OfficerRank()) or 1
    if type(entry.rank) ~= "number" or entry.rank > trustedRank then
        ns:Debug("ignored an org key from non-officer " .. tostring(sender))
        return
    end

    local k = memberCopy(d.k)
    if cur and cur.org == k.org and cur.oc then k.oc = nil end
    local ok = Org:Apply(k, "guild")
    if ok then
        ns:Print(("Received the %s org key (rev %d) from %s."):format(k.org, k.rev, ns.ShortName(sender)))
    end
end)

ns.Comms:Register("OKEY", function(d, sender, scope)
    if scope ~= "PEER" or not validChannel(d.oc) then return end
    local cur = Org:Get()
    if not cur or cur.org ~= d.org or cur.rev ~= d.rev or cur.oc then return end
    if not Org:AmOfficer() then return end
    local entry = ns.roster[ns.NormalizeName(sender)]
    if not (entry and Org:IsOfficerRank(entry.rank)) then return end
    cur.oc = ns.DeepCopy(d.oc)
    ns:Print("Received the officer channel from " .. ns.ShortName(sender) .. ".")
    ns:Fire("KEY_CHANGED", "officer-part")
end)

---------------------------------------------------------------------------
-- Offering the full key to another guild's leader
---------------------------------------------------------------------------
function Org:SendFullKey(target)
    local k = Org:Get()
    if not k then return false, "No org key loaded." end
    if not (Org:IsAdmin() or (k.oc and Org:AmOfficer())) then
        return false, "Only the org admin or an officer with the officer channel can send the full key."
    end
    target = ns.Trim(target or "")
    if target == "" then return false, "No target." end
    -- only the admin hands out the officer channel and key phrase this way
    -- (to a new guild's leader); an officer's offer is the member key, and
    -- their guild's officers pass the officer channel on once they're in
    local send = Org:IsAdmin() and k or memberCopy(k)
    ns.Comms:Send("FULLKEY", { k = send }, "PEER", target, ns.Comms.PRIORITY.BULK)
    return true
end

-- The offer uses RUIN's own dialog, not Blizzard's StaticPopup system, so
-- nothing RUIN does can taint popups Blizzard shows later.

function Org:AcceptOffered(k)
    if not validKey(k) then return end
    local ok, err = Org:Apply(k, "import")
    if not ok then
        ns:Print("Did not apply the key: " .. tostring(err) .. ".")
        return
    end
    ns:Print(("Org key for %s (rev %d) accepted."):format(k.org, k.rev))
    if not Org:MyGuildInOrg() then
        ns:Print("Your guild is not listed in this key yet. Ask the org admin to add it with /ruin key addguild.")
    end
end

ns.Comms:Register("FULLKEY", function(d, sender, scope)
    if scope ~= "PEER" or not validKey(d.k) then return end
    local cur = Org:Get()
    -- With a key already, only the org admin or a verified officer may offer
    -- one (nobody talks you into swapping orgs); without one, anyone may.
    if cur and not (Org:IsAdminName(sender) or ns.Presence:IsOfficerName(sender)) then return end
    if cur and cur.org == d.k.org and d.k.rev <= cur.rev and (cur.oc or not d.k.oc) then return end
    if GetTime() - lastOfferPopup < 30 then return end
    lastOfferPopup = GetTime()
    local offered = d.k
    ns.UI:ShowConfirm("RUIN org key offered",
        ("%s is offering you the RUIN org key for \"%s\".\n\nAccept it? Your guild's members will receive it from you automatically.")
            :format(ns.ShortName(sender), offered.org),
        function() Org:AcceptOffered(offered) end)
end)

---------------------------------------------------------------------------
-- Joining with a key phrase: join the phrase's channel, ask for the key,
-- and take the first member key whose org channel is that channel.
---------------------------------------------------------------------------
local JOIN_WAIT = 90
local lastKeyAnswerSeen = -999
local joinTicker

local function stopJoining(msg)
    joining = nil
    if joinTicker then joinTicker:Cancel(); joinTicker = nil end
    if msg then ns:Print(msg) end
    Org:ApplyChannels()
    ns:Fire("KEY_JOIN_CHANGED")
end

function Org:IsJoining() return joining ~= nil end

function Org:JoinWithPhrase(text)
    local ph, err = Org.CheckPhrase(text)
    if not ph then return false, err end
    if not ns.loggedIn then return false, "Log in first." end
    local ch = Org.PhraseChannel(ph)
    local k = Org:Get()
    if k and k.c.n == ch.n then return false, "You already have this org's key." end
    joining = { n = ch.n, p = ch.p, phrase = ph, untilT = GetTime() + JOIN_WAIT }
    Org:ApplyChannels()
    local asked = -999
    if joinTicker then joinTicker:Cancel() end
    joinTicker = C_Timer.NewTicker(3, function()
        if not joining then return end
        if GetTime() >= joining.untilT then
            stopJoining("No RUIN member answered on that key phrase. Check the phrase, or try again when someone from the org is online.")
            return
        end
        if ns.Comms:IsJoined("ORG") and GetTime() - asked >= 15 then
            asked = GetTime()
            ns.Comms:Send("KEYREQ", { gu = ns.guildName }, "ORG", nil, ns.Comms.PRIORITY.ALERT)
        end
    end)
    ns:Fire("KEY_JOIN_CHANGED")
    return true
end

-- A member on the org channel hands over the member key.
ns.Comms:Register("KEYREQ", function(d, sender, scope)
    if scope ~= "ORG" or joining then return end
    local k = Org:Get()
    if not (k and (Org:MyGuildInOrg() or Org:IsAdmin())) then return end
    C_Timer.After(1 + math.random() * 4, function()
        if GetTime() - lastKeyAnswerSeen < 10 then return end    -- someone else answered
        local cur = Org:Get()
        if not cur then return end
        lastKeyAnswerSeen = GetTime()
        ns.Comms:Send("PKEY", { k = memberCopy(cur) }, "ORG", nil, ns.Comms.PRIORITY.ALERT)
    end)
end)

ns.Comms:Register("PKEY", function(d, sender, scope)
    if scope ~= "ORG" then return end
    lastKeyAnswerSeen = GetTime()
    if not joining or not validKey(d.k) then return end
    if type(ns.db.disbanded) == "table" and ns.db.disbanded[d.k.org] and d.k.admin == ns.db.disbanded[d.k.org].admin then return end
    if d.k.c.n ~= joining.n or d.k.c.p ~= joining.p then return end
    local k = memberCopy(d.k)
    local ok, why = Org:Apply(k, "import")
    if not ok and why ~= "same as the key you have" then
        stopJoining("Did not apply the key: " .. tostring(why) .. ".")
        return
    end
    local msg = ("Joined the %s org with its key phrase (from %s)."):format(k.org, ns.ShortName(sender))
    if not ns.guildName then
        msg = msg .. " You are not in a guild: RUIN connects members of the org's guilds."
    elseif not Org:MyGuildInOrg() then
        msg = msg .. (" Your guild, %s, is not in the org yet: ask the org admin to add it (Settings > Org > Add guild)."):format(ns.guildName)
    end
    stopJoining(msg)
end)
