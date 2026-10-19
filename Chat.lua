-- RUIN Core: unified guild chat and cross-guild officer chat
--
-- What you type in /g (or /o) is mirrored to the other RUIN guilds:
--   * your own client re-broadcasts your line on the org (or officer) channel;
--   * the elected bridge relays lines from guildmates who lack the addon;
--   * other guilds show it in chat as [RUIN·Tag] Name: text.
local ADDON, ns = ...

local Chat = {}
ns.Chat = Chat

local DEDUP_WINDOW = 15     -- long enough to cover relay delay, short enough to allow repeats
local seen = {}             -- dedup key -> time
local officerLists = {}     -- guild name -> { set = { [guid] = true }, t = time }
local attestRequested = {}  -- guild name -> time

local function dedupKey(guid, text)
    return (guid or "?") .. ":" .. ns.Hash(text)
end

local function isDuplicate(key)
    local now = GetTime()
    local t = seen[key]
    seen[key] = now
    return t ~= nil and (now - t) < DEDUP_WINDOW
end

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

---------------------------------------------------------------------------
-- Outgoing: mirror guild/officer lines to the org
---------------------------------------------------------------------------
local function onGuildLine(officer, text, author, guid)
    if isSecret(text) or isSecret(author) then return end
    if type(text) ~= "string" or text == "" then return end
    local k = ns.Org:Get()
    if not k or not ns.Org:MyGuildInOrg() then return end
    if officer and not (k.oc and ns.Org:AmOfficer()) then return end

    if type(guid) ~= "string" or guid == "" then
        local e = ns.roster[ns.NormalizeName(author)]
        guid = e and e.guid
    end
    if not guid then return end

    if guid ~= ns.playerGUID then
        -- Someone else's line: only the bridge relays, and only for guildmates without RUIN.
        if ns.Presence:HasAddon(guid) then return end
        if officer then
            if not ns.Presence:IsOfficerBridge() then return end
        elseif not ns.Presence:IsBridge() then
            return
        end
    end

    local e = ns.rosterByGUID[guid]
    local class = e and e.class
    if not class and guid == ns.playerGUID then
        local _, classFile = UnitClass("player")
        class = classFile
    end
    ns.Comms:Send(officer and "OCHAT" or "GCHAT", {
        a = author, g = guid, gu = ns.guildName, t = text, c = class, r = ns.playerGUID,
    }, officer and "OFFICERS" or "ORG", nil, ns.Comms.PRIORITY.ALERT)
end

ns:RegisterEvent("CHAT_MSG_GUILD", function(_, text, author, _, _, _, _, _, _, _, _, _, guid)
    onGuildLine(false, text, author, guid)
end)

ns:RegisterEvent("CHAT_MSG_OFFICER", function(_, text, author, _, _, _, _, _, _, _, _, _, guid)
    onGuildLine(true, text, author, guid)
end)

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function colorName(name, class)
    local short = ns.ShortName(name)
    local link = "|Hplayer:" .. tostring(name) .. "|h[" .. short .. "]|h"
    local color
    if class then
        if C_ClassColor and C_ClassColor.GetClassColor then color = C_ClassColor.GetClassColor(class) end
        if not color and RAID_CLASS_COLORS then color = RAID_CLASS_COLORS[class] end
    end
    if not color then return link end
    local hex
    if color.GenerateHexColor then
        hex = color:GenerateHexColor()
    else
        hex = string.format("ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
    end
    return "|c" .. hex .. link .. "|r"
end

-- Strip embedded textures/atlases so a crafted line cannot flood the chat frame.
local function sanitize(text)
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    return text
end

function Chat:Display(officer, d, unverified)
    local frame = _G["ChatFrame" .. (ns.db.settings.chatFrame or 1)] or DEFAULT_CHAT_FRAME
    local info = ChatTypeInfo and ChatTypeInfo[officer and "OFFICER" or "GUILD"]
    local r, g, b = 0.25, 1.0, 0.25
    if info then r, g, b = info.r, info.g, info.b end
    local gi = ns.Org:GuildInfo(d.gu)
    local tag = (gi and gi.tag) or d.gu
    local label = officer and ("RUIN Officer·" .. tag) or ("RUIN·" .. tag)
    local mark = unverified and " |cffff8800(unverified)|r" or ""
    frame:AddMessage(("[%s] %s%s: %s"):format(label, colorName(d.a, d.c), mark, sanitize(d.t)), r, g, b)
end

---------------------------------------------------------------------------
-- Incoming
---------------------------------------------------------------------------
local function validLine(d)
    return type(d.t) == "string" and d.t ~= "" and #d.t <= 512
        and type(d.gu) == "string" and type(d.a) == "string"
end

ns.Comms:Register("GCHAT", function(d, sender, scope)
    if scope ~= "ORG" or not validLine(d) then return end
    if d.gu == ns.guildName then return end              -- we already saw it in /g
    if not ns.Org:GuildInfo(d.gu) then return end       -- not an org guild
    if isDuplicate(dedupKey(d.g, d.t)) then return end
    if not ns.db.settings.showOrgChat then return end
    Chat:Display(false, d, false)
end)

ns.Comms:Register("OCHAT", function(d, sender, scope)
    if scope ~= "OFFICERS" or not validLine(d) then return end
    if not ns.Org:AmOfficer() then return end
    if d.gu == ns.guildName then return end
    if not ns.Org:GuildInfo(d.gu) then return end
    if isDuplicate(dedupKey(d.g, d.t)) then return end

    local list = officerLists[d.gu]
    local verified = list ~= nil and type(d.r) == "string" and list.set[d.r] == true
    if not list and (not attestRequested[d.gu] or GetTime() - attestRequested[d.gu] > 60) then
        attestRequested[d.gu] = GetTime()
        ns.Comms:Send("ATTREQ", { gu = d.gu }, "OFFICERS", nil, ns.Comms.PRIORITY.BULK)
    end
    if not ns.db.settings.showOfficerChat then return end
    Chat:Display(true, d, not verified)
end)

---------------------------------------------------------------------------
-- Officer attestation: each guild's officer bridge publishes the GUIDs of
-- its officers so other guilds can mark officer lines as verified.
---------------------------------------------------------------------------
function Chat:SendAttest()
    if not ns.Presence:IsOfficerBridge() or not ns.Comms:IsJoined("OFFICERS") then return end
    local list = {}
    for guid, e in pairs(ns.rosterByGUID) do
        if ns.Org:IsOfficerRank(e.rank) then list[#list + 1] = guid end
    end
    ns.Comms:Send("ATTEST", { gu = ns.guildName, l = list }, "OFFICERS", nil, ns.Comms.PRIORITY.BULK)
end

ns.Comms:Register("ATTEST", function(d, sender, scope)
    if scope ~= "OFFICERS" or type(d.gu) ~= "string" or type(d.l) ~= "table" then return end
    if d.gu == ns.guildName or not ns.Org:GuildInfo(d.gu) then return end
    local set = {}
    for _, guid in ipairs(d.l) do
        if type(guid) == "string" then set[guid] = true end
    end
    officerLists[d.gu] = { set = set, t = GetTime() }
end)

local lastAttestReply = -999
ns.Comms:Register("ATTREQ", function(d, sender, scope)
    if scope ~= "OFFICERS" or d.gu ~= ns.guildName then return end
    if GetTime() - lastAttestReply < 30 then return end
    lastAttestReply = GetTime()
    C_Timer.After(1 + math.random() * 3, function() Chat:SendAttest() end)
end)

---------------------------------------------------------------------------
-- Upkeep
---------------------------------------------------------------------------
C_Timer.NewTicker(60, function()
    local now = GetTime()
    for key, t in pairs(seen) do
        if now - t > DEDUP_WINDOW then seen[key] = nil end
    end
end)

C_Timer.NewTicker(300, function() Chat:SendAttest() end)

ns:Subscribe("CHANNELS_CHANGED", function()
    if ns.Comms:IsJoined("OFFICERS") then
        C_Timer.After(20, function() Chat:SendAttest() end)
    end
end)
