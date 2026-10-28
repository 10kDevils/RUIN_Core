-- RUIN Core: presence, bridge election and version check
-- HELLO on the guild channel says "I run RUIN" (used to pick the bridge and
-- to spread the org key); OHELLO on the org channel builds the org-wide
-- online list and carries versions for the update notice.
local ADDON, ns = ...

local Presence = {}
ns.Presence = Presence

local GUILD_EVERY, ORG_EVERY = 60, 120
local GUILD_EXPIRE, ORG_EXPIRE = 150, 300

local guildPeers = {}   -- GUID -> { guid, name, t, v, p, kr, ko, b, o, org }
local orgPeers = {}     -- GUID -> { guid, name, guild, t, v, c, l, kr, o }
local lastGuildHello, lastOrgHello = -999, -999
local newestNotified

local function myClass()
    local _, classFile = UnitClass("player")
    return classFile
end

local function myZone()
    local z = GetRealZoneText and GetRealZoneText()
    return type(z) == "string" and z:sub(1, 40) or nil
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
function Presence:SendGuildHello(request)
    if not IsInGuild() or not ns.playerGUID or not ns.db then return end
    lastGuildHello = GetTime()
    local k = ns.Org:Get()
    ns.Comms:Send("HELLO", {
        g = ns.playerGUID, v = ns.VERSION, p = ns.PROTOCOL,
        kr = ns.Org:Rev(), ko = ns.Org:HasOfficerPart() and 1 or 0,
        b = ns.db.settings.allowBridge and 1 or 0,
        o = ns.Org:AmOfficer() and 1 or 0,
        org = k and k.org or "", gs = ns.Guild and ns.Guild:SettingsStamp() or nil,
        rq = request and 1 or nil,
    }, "GUILD")
end

function Presence:SendOrgHello(request)
    if not ns.playerGUID or not ns.Comms:IsJoined("ORG") then return end
    lastOrgHello = GetTime()
    ns.Comms:Send("OHELLO", {
        g = ns.playerGUID, v = ns.VERSION, p = ns.PROTOCOL,
        gu = ns.guildName, c = myClass(), l = UnitLevel("player"), z = myZone(),
        al = Presence:AltToken(), bt = ns.Watch and ns.Watch.MyTagHash and ns.Watch:MyTagHash() or nil,
        kr = ns.Org:Rev(), o = ns.Org:AmOfficer() and 1 or 0,
        rq = request and 1 or nil,
    }, "ORG")
end

---------------------------------------------------------------------------
-- Version notice
---------------------------------------------------------------------------
local function noteVersion(v, name)
    if type(v) ~= "string" or ns.CompareVersions(v, ns.VERSION) <= 0 then return end
    if newestNotified and ns.CompareVersions(v, newestNotified) <= 0 then return end
    newestNotified = v
    ns:Print(("%s is running RUIN Core %s; you have %s. Update when you can."):format(
        ns.ShortName(name), v, ns.VERSION))
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
ns.Comms:Register("HELLO", function(d, sender, scope)
    if scope ~= "GUILD" or type(d.g) ~= "string" or d.g == ns.playerGUID then return end
    -- the GUID must be the sender's own (the guild roster comes from the game)
    local e = ns.roster and ns.roster[ns.NormalizeName(sender)]
    if e and e.guid and e.guid ~= d.g then return end
    local old = guildPeers[d.g]
    if old and ns.NormalizeName(old.name) ~= ns.NormalizeName(sender) and GetTime() - old.t <= GUILD_EXPIRE then return end
    if Presence:IsOfficerName(sender) then ns.Org:NoteRev(d.kr) end
    local p = guildPeers[d.g] or {}
    p.guid, p.name, p.t = d.g, sender, GetTime()
    p.v, p.p = d.v, d.p
    p.kr = tonumber(d.kr) or 0
    p.ko, p.b, p.o, p.org = d.ko, d.b, d.o, d.org
    guildPeers[d.g] = p

    noteVersion(d.v, sender)
    ns.Org:OnPeerKeyState(p)
    if ns.Guild then ns.Guild:OnPeerSettings(d.gs) end

    if d.rq == 1 and GetTime() - lastGuildHello > 15 then
        C_Timer.After(1 + math.random() * 4, function()
            if GetTime() - lastGuildHello > 15 then Presence:SendGuildHello(false) end
        end)
    end
    ns:Fire("PEERS_CHANGED")
end)

ns.Comms:Register("OHELLO", function(d, sender, scope)
    if scope ~= "ORG" or type(d.g) ~= "string" or d.g == ns.playerGUID then return end
    if type(d.gu) ~= "string" or not ns.Org:GuildInfo(d.gu) then return end
    -- one GUID, one character: nobody takes over another member's record
    local old = orgPeers[d.g]
    if old and ns.NormalizeName(old.name) ~= ns.NormalizeName(sender) and GetTime() - old.t <= ORG_EXPIRE then return end
    if d.gu == ns.guildName then
        local e = ns.roster and ns.roster[ns.NormalizeName(sender)]
        if e and e.guid and e.guid ~= d.g then return end
    end
    if Presence:IsOfficerName(sender) or ns.Org:IsAdminName(sender) then ns.Org:NoteRev(d.kr) end
    local p = orgPeers[d.g] or {}
    p.guid, p.name, p.t = d.g, sender, GetTime()
    p.guild, p.v, p.c, p.l = d.gu, d.v, d.c, tonumber(d.l)
    p.z = type(d.z) == "string" and d.z:sub(1, 40) or nil
    p.al = type(d.al) == "string" and d.al:sub(1, 16) or nil      -- same token = same player (alts they chose to link)
    if p.al and ns.db then
        ns.db.altSeen = type(ns.db.altSeen) == "table" and ns.db.altSeen or {}
        local grp = ns.db.altSeen[p.al] or {}
        grp[ns.NormalizeName(sender)] = GetServerTime and GetServerTime() or time()
        ns.db.altSeen[p.al] = grp
    end
    p.bt = type(d.bt) == "string" and d.bt:sub(1, 24) or nil      -- the Watch's BattleTag hash
    p.kr, p.o = tonumber(d.kr) or 0, d.o
    orgPeers[d.g] = p

    noteVersion(d.v, sender)
    ns.Org:OnOrgPeer(p)

    if d.rq == 1 and GetTime() - lastOrgHello > 20 then
        C_Timer.After(1 + math.random() * 6, function()
            if GetTime() - lastOrgHello > 20 then Presence:SendOrgHello(false) end
        end)
    end
    ns:Fire("PEERS_CHANGED")
end)

---------------------------------------------------------------------------
-- Bridge election: the lowest GUID among online RUIN users in this guild
-- who allow bridging. Everyone computes the same answer independently.
---------------------------------------------------------------------------
local function fresh(p) return p ~= nil and (GetTime() - p.t) <= GUILD_EXPIRE end

local function elect(selfEligible, peerEligible)
    local best = selfEligible and ns.playerGUID or nil
    for guid, p in pairs(guildPeers) do
        if fresh(p) and peerEligible(p) and (best == nil or guid < best) then best = guid end
    end
    return best
end

local function currentOrg()
    local k = ns.Org:Get()
    return k and k.org
end

function Presence:BridgeGUID()
    local org = currentOrg()
    if not org or not ns.Org:MyGuildInOrg() or not ns.db then return nil end
    return elect(ns.db.settings.allowBridge, function(p)
        return p.b == 1 and p.org == org and (p.kr or 0) > 0
    end)
end

function Presence:OfficerBridgeGUID()
    local org = currentOrg()
    if not org or not ns.Org:MyGuildInOrg() or not ns.db then return nil end
    local selfEligible = ns.db.settings.allowBridge and ns.Org:AmOfficer() and ns.Org:HasOfficerPart()
    return elect(selfEligible, function(p)
        -- an officer by the guild roster, not by their own say-so
        local e = ns.rosterByGUID[p.guid]
        return p.b == 1 and p.ko == 1 and p.org == org and e ~= nil and ns.Org:IsOfficerRank(e.rank)
    end)
end

-- Who sends this guild's roster to the org channel: the lowest GUID among
-- guildmates running RUIN with the org key (no bridging setting needed).
function Presence:RosterSenderGUID()
    local org = currentOrg()
    if not org or not ns.Org:MyGuildInOrg() then return nil end
    -- only RUIN 0.3.17 or later shares rosters
    return elect(true, function(p)
        return p.org == org and (p.kr or 0) > 0 and type(p.v) == "string" and ns.CompareVersions(p.v, "0.3.17") >= 0
    end)
end
function Presence:IsRosterSender() return ns.playerGUID ~= nil and Presence:RosterSenderGUID() == ns.playerGUID end

function Presence:IsBridge() return ns.playerGUID ~= nil and Presence:BridgeGUID() == ns.playerGUID end
function Presence:IsOfficerBridge() return ns.playerGUID ~= nil and Presence:OfficerBridgeGUID() == ns.playerGUID end

function Presence:HasAddon(guid)
    return guid == ns.playerGUID or fresh(guildPeers[guid])
end

function Presence:NameForGUID(guid)
    if guid == ns.playerGUID then return ns.playerName end
    local p = guildPeers[guid] or orgPeers[guid]
    if p then return p.name end
    local e = ns.rosterByGUID[guid]
    return e and e.name
end

---------------------------------------------------------------------------
-- Verified officers
-- What a message says about its sender proves nothing; the game vouches for
-- the sender's name only. So an officer of another guild counts as one when
--   * they talked on the officer channel (only officers hold its password,
--     and the game says who talked), or
--   * an officer of your own guild (checked against your guild roster)
--     passed on the list of officers their client saw there (OLIST).
-- Guildmates are always checked against your own guild roster instead.
-- Entries last a week after an officer was last seen.
---------------------------------------------------------------------------
local OFFICER_KEEP = 7 * 86400
local OFFHI_EVERY, OLIST_EVERY = 300, 600
local MAX_OFFICERS = 300
local lastOffHi, lastOList, lastOListHeard = -999, -999, -999

local function officerStore()
    if not ns.db then return {} end
    local k = ns.Org:Get()
    local s = ns.db.officersSeen
    if type(s) ~= "table" or (k and s.org ~= k.org) or type(s.list) ~= "table" then
        s = { org = k and k.org, list = {} }
        ns.db.officersSeen = s
    end
    return s.list
end

local function serverNow() return GetServerTime and GetServerTime() or time() end

function Presence:NoteOfficer(name, guild, via, t)
    if type(name) ~= "string" or name == "" or not ns.Org:Get() then return end
    local n = ns.NormalizeName(name)
    if n == ns.playerNorm then return end
    local list = officerStore()
    local e = list[n]
    t = t or serverNow()
    if e and (e.t or 0) >= t and (e.via == "channel" or via ~= "channel") then return end
    if not e then
        local count = 0
        for _ in pairs(list) do count = count + 1 end
        if count >= MAX_OFFICERS then return end
        e = {}
        list[n] = e
    end
    e.n, e.t = ns.ShortName(name):sub(1, 48), math.max(e.t or 0, t)
    if type(guild) == "string" and guild ~= "" then e.gu = guild:sub(1, 48) end
    if via == "channel" or not e.via then e.via = via end
end

-- name -> { n, gu, t, via } for a verified officer of another guild, or nil.
function Presence:VerifiedOfficer(name)
    if type(name) ~= "string" then return nil end
    local e = officerStore()[ns.NormalizeName(name)]
    if e and serverNow() - (e.t or 0) <= OFFICER_KEEP then return e end
    return nil
end

-- Is this player an officer? Guildmates by your own guild roster; others by
-- the verified list above. What a player's own RUIN claims never counts.
function Presence:IsOfficerName(name)
    if not name then return false end
    local norm = ns.NormalizeName(name)
    if norm == ns.NormalizeName(ns.playerName or "") then return ns.Org:AmOfficer() end
    local e = ns.roster and ns.roster[norm]
    if e then return ns.Org:IsOfficerRank(e.rank) end
    return Presence:VerifiedOfficer(name) ~= nil
end

-- Officers say hello on the officer channel, so other guilds' officers can verify them.
function Presence:SendOfficerHello()
    if not (ns.Comms:IsJoined("OFFICERS") and ns.playerGUID) then return end
    lastOffHi = GetTime()
    ns.Comms:Send("OFFHI", { gu = ns.guildName }, "OFFICERS", nil, ns.Comms.PRIORITY.BULK)
end

ns.Comms:Register("OFFHI", function(d, sender, scope)
    if scope ~= "OFFICERS" then return end
    Presence:NoteOfficer(sender, type(d.gu) == "string" and d.gu or nil, "channel")
end)

-- An officer passes the verified list on to their guild, so members can tell
-- other guilds' officers too.
function Presence:SendOfficerList()
    if not (ns.Org:AmOfficer() and ns.Comms:IsJoined("OFFICERS")) then return end
    if GetTime() - lastOListHeard < OLIST_EVERY / 2 then return end
    lastOList = GetTime()
    local out, now = {}, serverNow()
    for _, e in pairs(officerStore()) do
        if e.via == "channel" and now - (e.t or 0) <= OFFICER_KEEP and #out < 120 then
            out[#out + 1] = { n = e.n, gu = e.gu, t = e.t }
        end
    end
    if #out > 0 then ns.Comms:Send("OLIST", { l = out }, "GUILD", nil, ns.Comms.PRIORITY.BULK) end
end

ns.Comms:Register("OLIST", function(d, sender, scope)
    if scope ~= "GUILD" or type(d.l) ~= "table" then return end
    local e = ns.roster and ns.roster[ns.NormalizeName(sender)]
    if not (e and ns.Org:IsOfficerRank(e.rank)) then return end
    lastOListHeard = GetTime()
    for i, o in ipairs(d.l) do
        if i > 120 then break end
        local t = type(o) == "table" and ns.SaneTime(o.t)
        if t and type(o.n) == "string" and serverNow() - t <= OFFICER_KEEP then
            Presence:NoteOfficer(o.n, type(o.gu) == "string" and o.gu or nil, "guild", t)
        end
    end
end)

-- An org peer (fresh OHELLO) by character name, or nil.
function Presence:OrgPeerByName(name)
    if not name then return nil end
    local norm = ns.NormalizeName(name)
    for _, p in pairs(orgPeers) do
        if ns.NormalizeName(p.name) == norm and GetTime() - p.t <= ORG_EXPIRE then return p end
    end
    return nil
end

-- Alt links: characters that send the same token belong to one player. Only
-- players who tick "Count my characters as one player" send one (Settings >
-- Options); it is random per account and says nothing else about them.
function Presence:AltToken()
    if not (ns.db and ns.db.settings.linkAlts) then return nil end
    if type(ns.db.altToken) ~= "string" then ns.db.altToken = ns.RandomToken(8) end
    return ns.db.altToken
end

-- How many characters to take off the census so each linked player counts
-- once: for each token seen on several characters, all but one.
-- Groups are remembered for 30 days (RUIN_DB.altSeen), so offline alts count once too.
function Presence:LinkedAltExtras()
    local seen = ns.db and type(ns.db.altSeen) == "table" and ns.db.altSeen or {}
    local cutoff = (GetServerTime and GetServerTime() or time()) - 30 * 86400
    local mine = Presence:AltToken()
    if mine and ns.playerName then
        seen[mine] = seen[mine] or {}
        seen[mine][ns.NormalizeName(ns.playerName)] = GetServerTime and GetServerTime() or time()
    end
    local extra = 0
    for token, grp in pairs(seen) do
        local n = 0
        for name, t in pairs(grp) do
            if t < cutoff then grp[name] = nil else n = n + 1 end
        end
        if n == 0 then seen[token] = nil elseif n > 1 then extra = extra + (n - 1) end
    end
    return extra
end

-- Another org member's online record by name (OHELLO), with alt token and
-- BattleTag hash, or nil.
function Presence:Peer(name) return Presence:OrgPeerByName(name) end

-- The guild a RUIN member on the org channel says they are in.
function Presence:GuildOfName(name)
    local p = Presence:OrgPeerByName(name)
    return p and p.guild or nil
end

function Presence:IsOrgPeer(name)
    local norm = ns.NormalizeName(name)
    for _, p in pairs(orgPeers) do
        if ns.NormalizeName(p.name) == norm then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Lists for the UI and modules
---------------------------------------------------------------------------
-- Everyone online with RUIN across the org, including yourself.
function Presence:GetOnlineList()
    local list = {}
    if ns.playerGUID then
        list[#list + 1] = { guid = ns.playerGUID, name = ns.playerName, guild = ns.guildName, zone = myZone(),
                            class = myClass(), level = UnitLevel("player"), version = ns.VERSION, self = true }
    end
    local seen = { [ns.playerGUID or ""] = true }
    for guid, p in pairs(orgPeers) do
        seen[guid] = true
        local e = p.guild == ns.guildName and ns.rosterByGUID[guid]
        list[#list + 1] = { guid = guid, name = p.name, guild = p.guild, class = p.c, zone = (e and e.zone) or p.z,
                            level = p.l, version = p.v, status = e and tonumber(e.status) or 0 }
    end
    -- Guildmates whose org channel is not up yet still count.
    for guid, p in pairs(guildPeers) do
        if not seen[guid] and fresh(p) then
            local e = ns.rosterByGUID[guid]
            list[#list + 1] = { guid = guid, name = p.name, guild = ns.guildName, zone = e and e.zone,
                                class = e and e.class, level = e and e.level, version = p.v, status = e and tonumber(e.status) or 0 }
        end
    end
    return list
end

function Presence:CountOnline()
    local guilds, members = {}, 0
    for _, row in ipairs(Presence:GetOnlineList()) do
        members = members + 1
        guilds[row.guild or "?"] = true
    end
    local n = 0
    for _ in pairs(guilds) do n = n + 1 end
    return members, n
end

function Presence:PrintVersions()
    local rows = Presence:GetOnlineList()
    table.sort(rows, function(a, b)
        local c = ns.CompareVersions(a.version, b.version)
        if c ~= 0 then return c > 0 end
        return tostring(a.name) < tostring(b.name)
    end)
    for _, r in ipairs(rows) do
        ns:Print(("%s (%s): %s"):format(ns.ShortName(r.name), r.guild or "?", r.version or "?"))
    end
end

---------------------------------------------------------------------------
-- Timers and triggers
---------------------------------------------------------------------------
local function tick()
    local now, changed = GetTime(), false
    for guid, p in pairs(guildPeers) do
        if now - p.t > GUILD_EXPIRE then guildPeers[guid] = nil; changed = true end
    end
    for guid, p in pairs(orgPeers) do
        if now - p.t > ORG_EXPIRE then orgPeers[guid] = nil; changed = true end
    end
    if changed then ns:Fire("PEERS_CHANGED") end
    if not ns.loggedIn then return end
    if now - lastGuildHello >= GUILD_EVERY then Presence:SendGuildHello(false) end
    if now - lastOrgHello >= ORG_EVERY then Presence:SendOrgHello(false) end
    if now - lastOffHi >= OFFHI_EVERY then Presence:SendOfficerHello() end
    if now - lastOList >= OLIST_EVERY then
        lastOList = now - OLIST_EVERY + 30 + math.random() * 60    -- spread officers out; try again soon if skipped
        Presence:SendOfficerList()
    end
end

C_Timer.NewTicker(5, tick)

ns:Subscribe("LOGIN", function()
    C_Timer.After(5, function() Presence:SendGuildHello(true) end)
end)

ns:Subscribe("KEY_CHANGED", function()
    C_Timer.After(1, function() Presence:SendGuildHello(false) end)
end)

ns:Subscribe("GUILD_CHANGED", function()
    wipe(guildPeers)
    C_Timer.After(2, function() Presence:SendGuildHello(true) end)
end)

ns:Subscribe("SETTINGS_CHANGED", function()
    Presence:SendGuildHello(false)
end)

ns:Subscribe("CHANNELS_CHANGED", function()
    if ns.Comms:IsJoined("OFFICERS") then
        C_Timer.After(3, function() Presence:SendOfficerHello() end)
        C_Timer.After(8 + math.random() * 8, function() Presence:SendOfficerList() end)
    end
    if ns.Comms:IsJoined("ORG") then
        C_Timer.After(2, function() Presence:SendOrgHello(true) end)
    else
        wipe(orgPeers)
        ns:Fire("PEERS_CHANGED")
    end
end)
