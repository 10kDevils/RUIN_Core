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
        return p.b == 1 and p.o == 1 and p.ko == 1 and p.org == org
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

-- Is this player an officer? Checked against your own guild roster when they
-- are a guildmate; for other RUIN guilds, what their RUIN reported.
function Presence:IsOfficerName(name)
    if not name then return false end
    local norm = ns.NormalizeName(name)
    if norm == ns.NormalizeName(ns.playerName or "") then return ns.Org:AmOfficer() end
    local e = ns.roster and ns.roster[norm]
    if e then return ns.Org:IsOfficerRank(e.rank) end
    for _, p in pairs(orgPeers) do
        if ns.NormalizeName(p.name) == norm then return p.o == 1 end
    end
    return false
end

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
    if ns.Comms:IsJoined("ORG") then
        C_Timer.After(2, function() Presence:SendOrgHello(true) end)
    else
        wipe(orgPeers)
        ns:Fire("PEERS_CHANGED")
    end
end)
