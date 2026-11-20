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
-- History for the Guild page's Chat tab and the pop-out chat window: your
-- guild's chat and the other RUIN guilds' chat, this session only.
---------------------------------------------------------------------------
local MAX_HISTORY = 300
Chat.history = {}      -- { t, gu, a, c, text, own }

-- Block words: your own list (RUIN_DB.blockWords) and the org's, set by the
-- org admin (it travels in the org key). A line with one of them is hidden
-- from RUIN chat and from other guilds' lines in your chat window.
function Chat:BlockWords()
    local out = {}
    for _, w in ipairs(ns.db and type(ns.db.blockWords) == "table" and ns.db.blockWords or {}) do out[#out + 1] = w end
    local k = ns.Org:Get()
    for _, w in ipairs(k and type(k.bw) == "table" and k.bw or {}) do if type(w) == "string" then out[#out + 1] = w end end
    return out
end

function Chat.ParseWords(text)
    local out, seenW = {}, {}
    for w in tostring(text or ""):gmatch("[^,\n]+") do
        w = ns.Trim(w):lower():gsub("|", "")
        if w ~= "" and #w <= 40 and not seenW[w] and #out < 100 then seenW[w] = true; out[#out + 1] = w end
    end
    return out
end

function Chat:Blocked(text)
    if type(text) ~= "string" then return false end
    local low = text:lower()
    for _, w in ipairs(Chat:BlockWords()) do
        if w ~= "" and low:find(w, 1, true) then return true end
    end
    return false
end

-- Hidden from RUIN chat: blocked words, a muted or hidden author, a deleted line.
function Chat:Hidden(author, text)
    if Chat:Blocked(text) then return true end
    if ns.Watch and (ns.Watch:IsMuted(author) or ns.Watch:IsDeleted(author, text)) then return true end
    return false
end

-- Pinned lines (yours, kept on this computer).
function Chat:Pins()
    ns.db.chatPins = type(ns.db.chatPins) == "table" and ns.db.chatPins or {}
    return ns.db.chatPins
end

function Chat:IsPinned(line)
    for _, p in ipairs(Chat:Pins()) do
        if p.a == line.a and p.text == line.text then return true end
    end
    return false
end

function Chat:TogglePin(line)
    local pins = Chat:Pins()
    for i, p in ipairs(pins) do
        if p.a == line.a and p.text == line.text then table.remove(pins, i); ns:Fire("CHAT_HISTORY"); return false end
    end
    pins[#pins + 1] = { t = line.t, gu = line.gu, a = line.a, c = line.c, text = line.text, own = line.own, org = line.org, warn = line.warn }
    while #pins > 10 do table.remove(pins, 1) end
    ns:Fire("CHAT_HISTORY")
    return true
end

local function record(line)
    local h = Chat.history
    h[#h + 1] = line
    if #h > MAX_HISTORY then table.remove(h, 1) end
    ns:Fire("CHAT_HISTORY", line)
end

-- Send a line to your guild chat (RUIN mirrors it to the other guilds).
function Chat:SendGuild(text)
    text = ns.Trim(text or "")
    if text == "" or not IsInGuild() then return false end
    SendChatMessage(text:sub(1, 255), "GUILD")
    return true
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
    -- muted (or hidden) by the Watch: not passed on to the other guilds
    if not officer and ns.Watch and ns.Watch:IsMuted(author) then return end

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
    if not (isSecret(text) or isSecret(author)) and type(text) == "string" and not Chat:Hidden(author, text) then
        local e = (type(guid) == "string" and ns.rosterByGUID[guid]) or ns.roster[ns.NormalizeName(author or "")]
        record({ t = time(), gu = ns.guildName, a = author, c = e and e.class, text = text, own = true })
    end
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

Chat.ColorName = colorName

-- Strip embedded textures/atlases so a crafted line cannot flood the chat frame.
function Chat.Sanitize(text) return (text:gsub("|T.-|t", ""):gsub("|A.-|a", "")) end
local function sanitize(text)
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    return text
end

-- via: who relayed the line when the author couldn't send it themselves
-- (the guild's bridge, for a guildmate without RUIN); shown after the name,
-- so a relayed line never passes for one the author sent.
function Chat:Display(officer, d, via)
    local frame = _G["ChatFrame" .. (ns.db.settings.chatFrame or 1)] or DEFAULT_CHAT_FRAME
    local info = ChatTypeInfo and ChatTypeInfo[officer and "OFFICER" or "GUILD"]
    local r, g, b = 0.25, 1.0, 0.25
    if info then r, g, b = info.r, info.g, info.b end
    local gi = ns.Org:GuildInfo(d.gu)
    local tag = (gi and gi.tag) or d.gu
    local label = officer and ("RUIN Officer·" .. tag) or ("RUIN·" .. tag)
    local mark = via and (" |cff888888(via " .. ns.ShortName(via) .. ")|r") or ""
    frame:AddMessage(("[%s] %s%s: %s"):format(label, colorName(d.a, d.c), mark, sanitize(d.t)), r, g, b)
end

---------------------------------------------------------------------------
-- Incoming
-- The game says who sent each message. A line whose author is the sender is
-- shown as theirs; any other line is a relay, shown with who relayed it, and
-- only accepted from a member of the author's guild.
---------------------------------------------------------------------------
local function validLine(d)
    return type(d.t) == "string" and d.t ~= "" and #d.t <= 512
        and type(d.gu) == "string" and type(d.a) == "string" and d.a ~= "" and #d.a <= 48
        and not d.a:find("[:%[%]/]")
        and (d.c == nil or (type(d.c) == "string" and d.c:match("^%u+$") ~= nil))
end

-- nil when the sender wrote the line, the sender's name when they relayed it,
-- false when the line should be dropped (the relayer is known to be in
-- another guild). A relayer whose hello hasn't arrived yet still gets the
-- line through, always labeled with their name.
local function relayOf(d, sender)
    local g = ns.Presence:GuildOfName(sender)
    if g ~= nil and g ~= d.gu then return false end            -- a line from another guild than the sender's
    if ns.NormalizeName(d.a) == ns.NormalizeName(sender) then return nil end
    return sender
end

ns.Comms:Register("GCHAT", function(d, sender, scope)
    if scope ~= "ORG" or not validLine(d) then return end
    if d.gu == ns.guildName then return end              -- we already saw it in /g
    if not ns.Org:GuildInfo(d.gu) then return end       -- not an org guild
    local via = relayOf(d, sender)
    if via == false then return end
    if isDuplicate(dedupKey(ns.NormalizeName(d.a), d.t)) then return end
    if Chat:Hidden(d.a, d.t) then return end
    record({ t = time(), gu = d.gu, a = d.a, c = d.c, text = d.t, own = false, via = via })
    if not ns.db.settings.showOrgChat then return end
    Chat:Display(false, d, via)
end)

ns.Comms:Register("OCHAT", function(d, sender, scope)
    if scope ~= "OFFICERS" or not validLine(d) then return end
    if not ns.Org:AmOfficer() then return end
    if d.gu == ns.guildName then return end
    if not ns.Org:GuildInfo(d.gu) then return end
    local via = relayOf(d, sender)
    if via == false then return end
    if isDuplicate(dedupKey(ns.NormalizeName(d.a), d.t)) then return end
    if not ns.db.settings.showOfficerChat then return end
    Chat:Display(true, d, via)
end)

---------------------------------------------------------------------------
-- Org chat (/org): the org's own channel. Only members of the org's guilds
-- who run RUIN see it or talk in it: it travels on the org's hidden channel
-- (sealed with the org's data key once the org encrypts), and every line is
-- the sender's own (no relays, so the game vouches for who wrote it).
--
-- Org announcements (/orgwarn, /ow): the org's raid warning. An officer or
-- the org admin sends one; it shows in the middle of every member's screen
-- with the raid warning sound.
---------------------------------------------------------------------------
Chat.ORG_COLOR = { r = 0.62, g = 0.89, b = 1.0 }      -- sky blue, well lighter than party chat
local ORG_BURST, ORG_WINDOW = 5, 10                   -- lines you may send per 10 seconds
local WARN_GAP = 10                                   -- seconds between your announcements
local WARN_GAP_IN = 5                                 -- an announcement per sender at most this often on screen
local sentAt, lastWarnOut, lastWarnIn = {}, -999, {}

function Chat:OrgColor()
    local c = ns.db and ns.db.settings.orgChatColor
    if type(c) == "table" and tonumber(c.r) and tonumber(c.g) and tonumber(c.b) then return c end
    return Chat.ORG_COLOR
end

function Chat:OrgHex()
    local c = Chat:OrgColor()
    return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

function Chat:SetOrgColor(r, g, b)
    if r == nil then ns.db.settings.orgChatColor = nil
    else ns.db.settings.orgChatColor = { r = r, g = g, b = b } end
    ns:Fire("CHAT_HISTORY")
end

-- nil when you can talk in org chat, or why not.
function Chat:OrgProblem()
    if not ns.Org:Get() then return "You're not in a RUIN org (no org key)." end
    if not ns.Org:MyGuildInOrg() then return "Your guild isn't one of the org's guilds." end
    if not ns.Comms:HasChannel("ORG") then return "RUIN hasn't joined the org channel yet." end
    return nil
end

function Chat:CanAnnounce()
    return ns.Org:IsAdmin() or (ns.Org:MyGuildInOrg() and ns.Org:AmOfficer())
end

local function myClass()
    local _, classFile = UnitClass("player")
    return classFile
end

local function orgLabel(d, warn)
    local gi = ns.Org:GuildInfo(d.gu)
    local tag = (gi and gi.tag) or d.gu
    return (warn and "Org Announcement·" or "Org·") .. tostring(tag)
end

function Chat:DisplayOrg(d, warn)
    local frame = _G["ChatFrame" .. (ns.db.settings.chatFrame or 1)] or DEFAULT_CHAT_FRAME
    local c = Chat:OrgColor()
    frame:AddMessage(("[%s] %s: %s"):format(orgLabel(d, warn), colorName(d.a, d.c), sanitize(d.t)), c.r, c.g, c.b)
end

-- In the middle of the screen, as a raid warning shows, with its sound.
function Chat:ShowAnnouncement(d)
    if ns.db.settings.orgWarnings == false then return end
    local text = Chat:OrgHex() .. ns.ShortName(d.a) .. ":|r " .. sanitize(d.t)
    local c = Chat:OrgColor()
    local frame = rawget(_G, "RaidWarningFrame")
    if frame and RaidNotice_AddMessage then
        pcall(RaidNotice_AddMessage, frame, text, { r = c.r, g = c.g, b = c.b }, 8)
    elseif UIErrorsFrame then
        UIErrorsFrame:AddMessage(text, c.r, c.g, c.b)
    end
    local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
    if PlaySound then pcall(PlaySound, kit, "Master") end
end

local function orgLine(text, warn)
    local d = { a = ns.playerName, gu = ns.guildName, t = text, c = myClass() }
    ns.Comms:Send(warn and "OANN" or "OSAY", d, "ORG", nil, ns.Comms.PRIORITY.ALERT)
    isDuplicate(dedupKey(ns.NormalizeName(d.a), d.t))
    record({ t = time(), gu = d.gu, a = d.a, c = d.c, text = text, own = true, org = true, warn = warn or nil })
    if warn then Chat:ShowAnnouncement(d) end
    Chat:DisplayOrg(d, warn)
end

-- Send a line to org chat. Returns true when it went.
function Chat:SendOrg(text)
    text = ns.Trim(text or ""):gsub("[\r\n]+", " "):sub(1, 255)
    if text == "" then return false end
    local why = Chat:OrgProblem()
    if why then ns:Print(why); return false end
    if ns.Watch and ns.Watch:IsMuted(ns.playerName) then ns:Print("You're muted in RUIN chat."); return false end
    local now = GetTime()
    for i = #sentAt, 1, -1 do if now - sentAt[i] > ORG_WINDOW then table.remove(sentAt, i) end end
    if #sentAt >= ORG_BURST then ns:Print("Slow down: org chat takes a few lines every ten seconds."); return false end
    sentAt[#sentAt + 1] = now
    orgLine(text, false)
    return true
end

-- Send an org announcement (officers and the org admin).
function Chat:Announce(text)
    text = ns.Trim(text or ""):gsub("[\r\n]+", " "):sub(1, 200)
    if text == "" then ns:Print("Usage: /orgwarn <message>  (or /ow)"); return false end
    local why = Chat:OrgProblem()
    if why then ns:Print(why); return false end
    if not Chat:CanAnnounce() then ns:Print("Org announcements are for officers and the org admin. /org talks in org chat."); return false end
    if GetTime() - lastWarnOut < WARN_GAP then
        ns:Print(("One org announcement every %d seconds."):format(WARN_GAP)); return false
    end
    lastWarnOut = GetTime()
    orgLine(text, true)
    return true
end

-- An org member's own line: the author is the sender, from one of the org's
-- guilds, and from your own guild only if they're on your roster.
local function orgSender(d, sender)
    if not validLine(d) then return false end
    if ns.NormalizeName(d.a) ~= ns.NormalizeName(sender) then return false end
    if not ns.Org:GuildInfo(d.gu) then return false end
    local g = ns.Presence:GuildOfName(sender)
    if g ~= nil and g ~= d.gu then return false end
    if d.gu == ns.guildName and ns.roster and next(ns.roster) and not ns.roster[ns.NormalizeName(sender)] then return false end
    return true
end

local function onOrgLine(d, sender, scope, warn)
    if scope ~= "ORG" or not orgSender(d, sender) then return end
    if not ns.Org:MyGuildInOrg() then return end
    if isDuplicate(dedupKey(ns.NormalizeName(d.a), d.t)) then return end
    if Chat:Hidden(d.a, d.t) then return end
    -- an announcement counts only from an officer or the org admin RUIN can
    -- vouch for; anyone else's shows as a plain org line
    if warn and not (ns.Presence:IsOfficerName(sender) or ns.Org:IsAdminName(sender)) then warn = false end
    if warn then
        local n = ns.NormalizeName(sender)
        if GetTime() - (lastWarnIn[n] or -999) < WARN_GAP_IN then warn = false else lastWarnIn[n] = GetTime() end
    end
    record({ t = time(), gu = d.gu, a = d.a, c = d.c, text = d.t, own = false, org = true, warn = warn or nil })
    if warn then Chat:ShowAnnouncement(d) end
    Chat:DisplayOrg(d, warn)
end

ns.Comms:Register("OSAY", function(d, sender, scope) onOrgLine(d, sender, scope, false) end)
ns.Comms:Register("OANN", function(d, sender, scope) onOrgLine(d, sender, scope, true) end)

SLASH_RUINORG1 = "/org"
SlashCmdList.RUINORG = function(input)
    input = ns.Trim(input or "")
    if input == "" then
        ns.db.settings.chatScope = "orgchat"
        ns.UI:OpenGuildTab("Chat")
        return
    end
    Chat:SendOrg(input)
end

SLASH_RUINORGWARN1 = "/orgwarn"
SLASH_RUINORGWARN2 = "/ow"
SlashCmdList.RUINORGWARN = function(input) Chat:Announce(input) end

---------------------------------------------------------------------------
-- Upkeep
---------------------------------------------------------------------------
C_Timer.NewTicker(60, function()
    local now = GetTime()
    for key, t in pairs(seen) do
        if now - t > DEDUP_WINDOW then seen[key] = nil end
    end
end)
