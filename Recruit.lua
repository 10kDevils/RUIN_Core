-- RUIN Core: joining the org
-- For players who aren't in one of the org's guilds yet: the Guild page's
-- Join screen lists the org's guilds (from the org key, which anyone can get
-- with the key phrase), finds a guild's members online with the game's /who
-- (one search per click, as the game requires), and sends one of them a join
-- request. The request reaches the members of that guild who can invite: on
-- the Guild page they see who asks, with Invite and Decline.
local ADDON, ns = ...

local Wd = ns.Widgets
local C = Wd.COLORS
local GREY, GREEN, RED = C.dim, C.good, C.bad

local Recruit = {}
ns.Recruit = Recruit

local ASK_GAP = 600                  -- one ask per guild every 10 minutes
local KEEP_ASKS = 3 * 86400

local function now() return GetServerTime and GetServerTime() or time() end
local function norm(n) return ns.NormalizeName(n or "") end

-- Show the Join screen? When you're not in one of the org's guilds.
function Recruit:Needed() return not ns.Org:MyGuildInOrg() and not ns.Org:IsAdmin() end

-- The org's guilds, from the key (empty without one).
function Recruit:Guilds()
    local k, out = ns.Org:Get(), {}
    for name, g in pairs(k and k.guilds or {}) do out[#out + 1] = { name = name, tag = g.tag } end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

---------------------------------------------------------------------------
-- /who: one search per click
---------------------------------------------------------------------------
local whoFor, whoResults, lastWho = nil, {}, -999

-- Must be called from a click.
function Recruit:FindMembers(guild)
    if GetTime() - lastWho < 6 then return false, "One search every few seconds." end
    if type(guild) ~= "string" or guild == "" then return false, "Pick a guild first." end
    lastWho = GetTime()
    whoFor, whoResults = guild, {}
    local q = 'g-"' .. guild .. '"'
    if C_FriendList and C_FriendList.SendWho then C_FriendList.SendWho(q)
    elseif SendWho then SendWho(q) else return false, "This game client has no /who." end
    return true
end

local function readWho()
    if not whoFor then return end
    local n = 0
    if C_FriendList and C_FriendList.GetNumWhoResults then n = C_FriendList.GetNumWhoResults() or 0
    elseif GetNumWhoResults then n = GetNumWhoResults() or 0 end
    local out = {}
    for i = 1, math.min(n, 50) do
        local name, guild, level, class, zone
        if C_FriendList and C_FriendList.GetWhoInfo then
            local w = C_FriendList.GetWhoInfo(i)
            if w then name, guild, level, class, zone = w.fullName, w.fullGuildName, w.level, w.filename, w.area end
        elseif GetWhoInfo then
            local _, file
            name, guild, level, _, _, zone, file = GetWhoInfo(i)
            class = file
        end
        if name and guild == whoFor then out[#out + 1] = { name = name, level = level, class = class, zone = zone, guild = guild } end
    end
    whoResults = out
    ns:Fire("RECRUIT_CHANGED")
end
ns:RegisterEvent("WHO_LIST_UPDATE", readWho)

function Recruit:WhoResults() return whoResults, whoFor end

---------------------------------------------------------------------------
-- Asking to join
---------------------------------------------------------------------------
local askedGuild = {}

function Recruit.DefaultMessage(guild)
    return ("Hi! I'd like to join %s. Could you invite me?"):format(guild or "your guild")
end

-- Ask a member of a guild (seen online) for an invite: a whisper they can
-- read without RUIN, and a request RUIN shows to whoever can invite.
function Recruit:Ask(member, guild, message)
    if not member or member == "" then return false, "Pick a member first." end
    if askedGuild[guild] and GetTime() - askedGuild[guild] < ASK_GAP then
        return false, "You asked " .. guild .. " a few minutes ago; give them time to answer."
    end
    askedGuild[guild] = GetTime()
    message = ns.Trim(message or ""):gsub("|", "/"):sub(1, 200)
    if message == "" then message = Recruit.DefaultMessage(guild) end
    SendChatMessage(message, "WHISPER", nil, member)
    local _, class = UnitClass("player")
    ns.Comms:Send("JOINASK", { m = message, c = class, l = UnitLevel("player"), gu = guild }, "PEER", member, ns.Comms.PRIORITY.ALERT)
    return true
end

---------------------------------------------------------------------------
-- The other side: who asks to join your guild
---------------------------------------------------------------------------
local function asks()
    if not ns.db then return {} end
    ns.db.joinAsks = type(ns.db.joinAsks) == "table" and ns.db.joinAsks or {}
    local list = ns.db.joinAsks
    for i = #list, 1, -1 do if now() - (list[i].t or 0) > KEEP_ASKS then table.remove(list, i) end end
    return list
end

function Recruit:Asks() return ns.Guild:Can("invite") and asks() or {} end

local function addAsk(d, who)
    local list = asks()
    for _, a in ipairs(list) do if norm(a.name) == norm(who) then a.t, a.m = now(), d.m; ns:Fire("RECRUIT_CHANGED"); return end end
    list[#list + 1] = { name = who, m = tostring(d.m or ""):gsub("|", "/"):sub(1, 200), c = type(d.c) == "string" and d.c or nil,
                        l = tonumber(d.l), t = now() }
    if ns.Guild:Can("invite") then ns:Print(("%s asks to join %s (Guild > Overview)."):format(ns.ShortName(who), ns.guildName or "your guild")) end
    ns:Fire("RECRUIT_CHANGED")
end

ns.Comms:Register("JOINASK", function(d, sender, scope)
    if scope ~= "PEER" or not IsInGuild() or (d.gu and d.gu ~= ns.guildName) then return end
    if ns.roster and ns.roster[norm(sender)] then return end                -- already a guildmate
    addAsk(d, sender)
    -- members who can't invite pass it to those who can
    if not ns.Guild:Can("invite") then
        ns.Comms:Send("JOINFWD", { n = sender, m = d.m, c = d.c, l = d.l }, "GUILD", nil, ns.Comms.PRIORITY.NORMAL)
    end
end)

ns.Comms:Register("JOINFWD", function(d, sender, scope)
    if scope ~= "GUILD" or type(d.n) ~= "string" then return end
    if not (ns.roster and ns.roster[norm(sender)]) then return end
    addAsk(d, d.n)
end)

local function drop(name)
    local list = asks()
    for i = #list, 1, -1 do if norm(list[i].name) == norm(name) then table.remove(list, i) end end
    ns:Fire("RECRUIT_CHANGED")
end

function Recruit:Invite(name)
    if not ns.Guild:Can("invite") then return false, "Your guild rank can't invite." end
    ns.Guild:Invite(name)
    drop(name)
    return true
end

function Recruit:Decline(name)
    SendChatMessage(("Thanks for asking! %s isn't taking new members right now."):format(ns.guildName or "We"), "WHISPER", nil, name)
    drop(name)
    return true
end

function Recruit:Dismiss(name) drop(name) end

---------------------------------------------------------------------------
-- The Join screen (on the Guild page's Overview, for non-members)
---------------------------------------------------------------------------
local ui = {}

function ns.GuildUI.BuildJoin(card)
    ui.card = card
    local h = Wd.Header(card, "Join RUIN")
    h:SetPoint("TOPLEFT", 10, -8)
    ui.text = Wd.Label(card, "", "GameFontHighlightSmall")
    ui.text:SetPoint("TOPLEFT", 12, -32)
    ui.text:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    ui.text:SetJustifyH("LEFT")
    ui.phrase = Wd.EditBox(card, 200, nil, "The org's key phrase")
    ui.phrase:SetPoint("TOPLEFT", 12, -80)
    ui.phraseGo = Wd.Button(card, "Get the guild list", 140, function()
        local ok, err = ns.Org:JoinWithPhrase(ui.phrase:GetText())
        ns:Print(ok and "Asking a RUIN member online for the org's guild list..." or err)
    end)
    ui.phraseGo:SetPoint("LEFT", ui.phrase, "RIGHT", 6, 0)
    ui.guild = Wd.Dropdown(card, 220, function()
        local out = {}
        for _, g in ipairs(Recruit:Guilds()) do out[#out + 1] = g.name end
        return out
    end, function() return ui.pick end, function(v)
        if ui.msg:GetText() == Recruit.DefaultMessage(ui.pick) then ui.msg:SetText(Recruit.DefaultMessage(v)) end
        ui.pick = v
        Recruit:RefreshJoin()
    end, "Guild: ")
    ui.guild:SetPoint("TOPLEFT", 12, -80)
    ui.find = Wd.Button(card, "Find members online", 150, function()
        local ok, err = Recruit:FindMembers(ui.pick)
        if not ok then ns:Print(err) end
    end)
    ui.find:SetPoint("LEFT", ui.guild, "RIGHT", 6, 0)
    ui.msg = Wd.EditBox(card, 340, nil, "Your message")
    ui.msg:SetPoint("TOPLEFT", 12, -112)
    ui.list = Wd.List(card, 24, function(row)
        row.name = Wd.Label(row, "")
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetWidth(150)
        row.info = Wd.Label(row, "", "GameFontHighlightSmall")
        row.info:SetPoint("LEFT", 160, 0)
        row.info:SetWidth(120)
        row.info:SetWordWrap(false)
        row.ask = Wd.Button(row, "Ask to join", 96)
        row.ask:SetPoint("RIGHT", -2, 0)
    end, function(row, e)
        row.name:SetText(Wd.ClassName(e.name, e.class))
        row.info:SetText(GREY .. tostring(e.level or "") .. "  ·  " .. ns.Escape(e.zone or "") .. "|r")
        row.ask:SetScript("OnClick", function()
            local ok, err = Recruit:Ask(e.name, e.guild, ui.msg:GetText())
            ns:Print(ok and ("Asked %s to invite you to %s."):format(ns.ShortName(e.name), e.guild) or err)
        end)
    end)
    ui.list.frame:SetPoint("TOPLEFT", 6, -142)
    ui.list.frame:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -26, 10)
end

function Recruit:RefreshJoin()
    if not (ui.card and ui.card:IsVisible()) then return end
    local guilds = Recruit:Guilds()
    local hasKey = #guilds > 0
    if hasKey and not ui.pick then ui.pick = guilds[1].name end
    ui.text:SetText(hasKey and (GREY .. "Pick a guild and find its members online, then ask one of them for an invite. Your request reaches the members of that guild who can invite.|r")
        or (GREY .. "No org key yet. Type the org's key phrase (ask a member for it): if your guild is in the org, you're connected; if not, you'll see the org's guilds and can ask to join one.|r"))
    ui.phrase:SetShown(not hasKey); ui.phraseGo:SetShown(not hasKey)
    ui.guild:SetShown(hasKey); ui.find:SetShown(hasKey); ui.msg:SetShown(hasKey)
    ui.guild:Refresh()
    if hasKey and (ui.msg:GetText() or "") == "" then ui.msg:SetText(Recruit.DefaultMessage(ui.pick)) end
    local results, forGuild = Recruit:WhoResults()
    ui.list:SetEmptyText(hasKey and (forGuild and ("Nobody from " .. forGuild .. " is online right now.") or "Press Find members online.") or "")
    ui.list:SetItems(hasKey and results or {})
end

ns:Subscribe("RECRUIT_CHANGED", function() Recruit:RefreshJoin(); if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end end)
ns:Subscribe("KEY_CHANGED", function() Recruit:RefreshJoin() end)
