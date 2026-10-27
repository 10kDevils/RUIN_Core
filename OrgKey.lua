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
    for name, g in pairs(k.guilds) do
        if type(name) ~= "string" or type(g) ~= "table" then return false end
    end
    if not validChannel(k.c) then return false end
    if k.oc ~= nil and not validChannel(k.oc) then return false end
    if k.links ~= nil and type(k.links) ~= "table" then return false end
    if k.ph ~= nil and type(k.ph) ~= "string" then return false end
    if k.bw ~= nil and type(k.bw) ~= "table" then return false end
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
    if err or not validKey(k) then return nil, "the key contents are invalid" end
    return k
end

---------------------------------------------------------------------------
-- Applying a key
---------------------------------------------------------------------------
-- source: "import" (user consented), "guild", "officer", "create", "edit"
function Org:Apply(k, source)
    if not validKey(k) then return false, "invalid key" end
    k = ns.DeepCopy(k)
    local cur = Org:Get()

    if cur then
        if cur.org ~= k.org and source ~= "import" then return false, "belongs to a different org" end
        if cur.org == k.org then
            if k.rev < cur.rev then return false, "older than the key you have" end
            if k.rev == cur.rev then
                if k.oc and not cur.oc then
                    cur.oc = k.oc
                    ns:Fire("KEY_CHANGED", source)
                    return true
                end
                return false, "same as the key you have"
            end
        end
    end

    -- Only officers of their own guild (or the admin) keep the officer channel.
    if k.oc and not accountIsAdmin(k) then
        local g = ns.guildName and k.guilds[ns.guildName]
        local officerRank = (g and tonumber(g.o)) or 1
        if not (type(ns.guildRank) == "number" and ns.guildRank <= officerRank) then
            k.oc = nil
        end
    end

    ns.db.orgKey = k
    ns:Fire("KEY_CHANGED", source)
    return true
end

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
    }
    ns.db.orgKey = k
    ns:Fire("KEY_CHANGED", "create")
    return true
end

local function editableKey()
    local k = Org:Get()
    if not k then return nil, "No org key loaded." end
    if not Org:IsAdmin() then return nil, "Only the org admin can change the org key." end
    return k
end

-- After an admin edit, announce the new key to every guild's officers on the
-- officer channel they are on *now* (it may be about to change), then switch.
local function publishEdit(k, oldOfficerChannel)
    if oldOfficerChannel then
        ns.Comms:Send("ORGKEY", { k = ns.DeepCopy(k) }, "OFFICERS", oldOfficerChannel, ns.Comms.PRIORITY.ALERT)
    end
    ns:Fire("KEY_CHANGED", "edit")
end

function Org:AddGuild(name, rank, tag)
    local k, err = editableKey()
    if not k then return false, err end
    name = ns.Trim(name or "")
    if name == "" then return false, "Usage: /ruin key addguild <guild>, <officer rank>[, <tag>]" end
    local oldOC = k.oc and k.oc.n
    k.guilds[name] = { o = tonumber(rank) or 1, tag = (tag and tag ~= "") and tag or defaultTag(name) }
    k.rev = k.rev + 1
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
    k.rev = k.rev + 1
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
    k.rev = k.rev + 1
    -- A removed guild still knows the old passwords, so rotate them too.
    -- Honest clients of the removed guild ignore the announcement because
    -- their guild is no longer listed; see README for the limits of this.
    -- With a key phrase the org channel stays the phrase's (the admin
    -- chooses a new phrase to lock them out of it).
    if not k.ph then k.c = newChannel() end
    k.oc = newChannel()
    publishEdit(k, oldOC)
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
    k.c, k.oc, k.ph = ph and Org.PhraseChannel(ph) or newChannel(), newChannel(), ph
    k.rev = k.rev + 1
    publishEdit(k, oldOC)
    return true
end

function Org:Rotate() return Org:ChooseNewKey(Org:Phrase()) end

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
    k.rev = k.rev + 1
    publishEdit(k, k.oc and k.oc.n)
    return true
end

-- The org's shared block words (Chat.lua hides lines with them), set by the admin.
function Org:SetBlockWords(list)
    local k, err = editableKey()
    if not k then return false, err end
    k.bw = (type(list) == "table" and #list > 0) and list or nil
    k.rev = k.rev + 1
    publishEdit(k, k.oc and k.oc.n)
    return true
end

-- An updated key from the officer channel, or whispered by an org officer.
local function acceptOrgKey(d, sender)
    if not validKey(d.k) then return end
    local cur = Org:Get()
    if not cur or cur.org ~= d.k.org or d.k.rev <= cur.rev then return end
    if not ns.guildName or not d.k.guilds[ns.guildName] then
        ns:Print("The org key was updated, but your guild is no longer listed in it.")
        return
    end
    if Org:Apply(d.k, "officer") then
        ns:Print(("Org key updated to rev %d (from %s)."):format(d.k.rev, ns.ShortName(sender)))
    end
end

ns.Comms:Register("ORGKEY", function(d, sender, scope)
    if scope == "OFFICERS" then
        acceptOrgKey(d, sender)
    elseif scope == "PEER" and ns.Presence:IsOrgPeer(sender) then
        acceptOrgKey(d, sender)
    end
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
    C_Timer.After(2 + math.random() * 6, function()
        guildSharePending = false
        local k = Org:Get()
        if not k or GetTime() < guildShareSuppressedUntil then return end
        if not (Org:MyGuildInOrg() and Org:AmOfficer()) then return end
        ns.Comms:Send("KEY", { k = memberCopy(k) }, "GUILD", nil, ns.Comms.PRIORITY.BULK)
        guildShareSuppressedUntil = GetTime() + 30
    end)
end

local function scheduleOfficerShare(name)
    local norm = ns.NormalizeName(name)
    if officerShareCooldown[norm] and GetTime() < officerShareCooldown[norm] then return end
    officerShareCooldown[norm] = GetTime() + 120
    C_Timer.After(1 + math.random() * 3, function()
        local k = Org:Get()
        if not (k and k.oc and Org:AmOfficer()) then return end
        local entry = ns.roster[norm]
        if not (entry and Org:IsOfficerRank(entry.rank)) then return end
        ns.Comms:Send("OKEY", { org = k.org, rev = k.rev, oc = k.oc }, "PEER", name, ns.Comms.PRIORITY.BULK)
    end)
end

-- Called by Presence whenever a guildmate's HELLO arrives.
function Org:OnPeerKeyState(peer)
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
    ns.Comms:Send("FULLKEY", { k = k }, "PEER", target, ns.Comms.PRIORITY.BULK)
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
