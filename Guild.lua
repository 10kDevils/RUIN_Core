-- RUIN Core: the Guild page's Roster and Chat tabs, and the pop-out chat
-- The roster shows what the game's guild window shows (zone, rank, public
-- and officer notes, last online) for every guild in the org (the other
-- guilds' rosters come from OrgRoster.lua), and lets members with the right guild
-- rank promote, demote, remove and invite members and edit notes and the
-- message of the day. The game decides who may do what (the guild's rank
-- permissions); RUIN only offers what your rank allows and asks first before
-- removing anyone. Chat shows your guild's chat, or every RUIN guild's, and
-- can pop out into its own small window like the game's guild chat.
local ADDON, ns = ...

local Wd = ns.Widgets
local P = Wd.PALETTE
local C = Wd.COLORS
local GREY, GREEN = C.dim, C.good

local G = {}
ns.Guild = G
local GUI = ns.GuildUI or {}
ns.GuildUI = GUI

---------------------------------------------------------------------------
-- What your rank allows, and the actions themselves
---------------------------------------------------------------------------
local function can(globalName)
    local f = _G[globalName] or (C_GuildInfo and C_GuildInfo[globalName])
    if type(f) ~= "function" then return false end
    local ok, v = pcall(f)
    return ok and v and true or false
end

-- what: "promote", "demote", "remove", "invite", "publicNote", "officerNote", "viewOfficerNote", "motd"
function G:Can(what)
    if not IsInGuild() then return false end
    if what == "promote" then return can("CanGuildPromote")
    elseif what == "demote" then return can("CanGuildDemote")
    elseif what == "remove" then return can("CanGuildRemove")
    elseif what == "invite" then return can("CanGuildInvite")
    elseif what == "publicNote" then return can("CanEditPublicNote")
    elseif what == "officerNote" then return can("CanEditOfficerNote")
    elseif what == "viewOfficerNote" then return can("CanViewOfficerNote") or can("CanEditOfficerNote")
    elseif what == "motd" then return can("CanEditMOTD") end
    return false
end

local function numRanks()
    local n = GuildControlGetNumRanks and GuildControlGetNumRanks()
    return tonumber(n) or 10
end

local function isMe(entry)
    return entry ~= nil and ns.NormalizeName(entry.name) == ns.NormalizeName(UnitName("player") or "")
end
G.IsMe = isMe

-- Can you do this to that member? Returns true, or false and why.
function G:CanOn(what, entry)
    if not entry then return false, "Pick a member first." end
    if entry.guild and entry.guild ~= ns.guildName then return false, "Only for members of your own guild." end
    -- your own public note: offered to everyone; the game decides (some
    -- guilds let only some ranks edit notes)
    if what == "publicNote" and isMe(entry) then return true end
    if not G:Can(what) then return false, "Your guild rank doesn't allow this." end
    if what == "publicNote" or what == "officerNote" then return true end
    if isMe(entry) then return false, "Not on yourself." end
    local mine, theirs = tonumber(ns.guildRank), tonumber(entry.rank)
    if not (mine and theirs) or theirs <= mine then return false, "Only members ranked below you." end
    if what == "promote" and theirs - 1 <= mine then return false, "They are already one rank below you." end
    if what == "demote" and theirs >= numRanks() - 1 then return false, "They are already at the lowest rank." end
    return true
end

local function first(...)
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        if type(f) == "function" then return f end
    end
end

local function after()
    C_Timer.After(1, function() ns:RequestRoster() end)
end

function G:Promote(name)
    local f = first(GuildPromote, C_GuildInfo and C_GuildInfo.Promote)
    if not f then return false end
    f(name); after(); return true
end

function G:Demote(name)
    local f = first(GuildDemote, C_GuildInfo and C_GuildInfo.Demote)
    if not f then return false end
    f(name); after(); return true
end

function G:Remove(name)
    local f = first(GuildUninvite, C_GuildInfo and C_GuildInfo.Uninvite)
    if not f then return false end
    f(name); after(); return true
end

function G:Invite(name)
    name = ns.Trim(name or "")
    if name == "" then return false end
    local f = first(GuildInvite, C_GuildInfo and C_GuildInfo.Invite)
    if not f then return false end
    f(name); return true
end

-- The roster index of a member right now (the game wants an index for notes).
local function rosterIndex(name)
    local want = ns.NormalizeName(name)
    for i = 1, GetNumGuildMembers() or 0 do
        local n = GetGuildRosterInfo(i)
        if n and ns.NormalizeName(n) == want then return i end
    end
end

function G:SetNote(name, note, officer)
    local i = rosterIndex(name)
    local f = officer and GuildRosterSetOfficerNote or GuildRosterSetPublicNote
    if not (i and f) then return false end
    note = ns.Trim(note or ""):sub(1, 31)
    f(i, note)
    after()
    -- If the game didn't take it (the guild rank can't edit notes), say why.
    C_Timer.After(4, function()
        local e = ns.roster and ns.roster[ns.NormalizeName(name)]
        local now = e and (officer and e.officerNote or e.note)
        if e and (now or "") ~= note then
            ns:Print("The game didn't change the note. Your guild rank may not be allowed to edit notes; the guild master can allow it in the guild's rank settings.")
        end
    end)
    return true
end

function G:SetMOTD(text)
    local f = first(GuildSetMOTD, C_GuildInfo and C_GuildInfo.SetMOTD)
    if not f then return false end
    f(ns.Trim(text or ""):sub(1, 128))
    after()
    return true
end

---------------------------------------------------------------------------
-- Guild settings that officers change for their guild (kept by everyone in
-- the guild, newest wins): which ranks can create events in RUIN Muster.
---------------------------------------------------------------------------
local function settingsStore()
    if not (ns.db and ns.guildName) then return nil end
    ns.db.guildSettings = type(ns.db.guildSettings) == "table" and ns.db.guildSettings or {}
    local s = ns.db.guildSettings[ns.guildName]
    if type(s) ~= "table" then s = {}; ns.db.guildSettings[ns.guildName] = s end
    return s
end

function G:SettingsStamp() local s = settingsStore(); return s and s.t or 0 end

-- The lowest rank that can create events (0 = guild master); officers by default.
function G:EventRank()
    local s = settingsStore()
    return (s and tonumber(s.er)) or ns.Org:OfficerRank()
end

function G:CanCreateEvents()
    if ns.Org:AmOfficer() then return true end
    local r = tonumber(ns.guildRank)
    return r ~= nil and r <= G:EventRank()
end

local function shareSettings(priority)
    local s = settingsStore()
    if not (s and s.t) then return end
    ns.Comms:Send("GSET", { gu = ns.guildName, er = s.er, t = s.t, by = s.by }, "GUILD", nil, priority or ns.Comms.PRIORITY.NORMAL)
end

-- Officers (and up) only. rank: 0..9
function G:SetEventRank(rank)
    rank = tonumber(rank)
    if not ns.Org:AmOfficer() then return false, "Only officers can change who creates events." end
    if not rank or rank < 0 or rank > 9 or rank ~= math.floor(rank) then return false, "Pick a rank from 0 to 9." end
    local s = settingsStore()
    if not s then return false, "You are not in a guild." end
    s.er, s.t, s.by = rank, (GetServerTime and GetServerTime() or time()), ns.playerName
    shareSettings(ns.Comms.PRIORITY.ALERT)
    ns:Fire("GUILD_SETTINGS_CHANGED")
    return true
end

local function isOfficerName(name)
    local e = name and ns.roster and ns.roster[ns.NormalizeName(name)]
    return e ~= nil and ns.Org:IsOfficerRank(e.rank)
end

ns.Comms:Register("GSET", function(d, sender, scope)
    if scope ~= "GUILD" or d.gu ~= ns.guildName then return end
    local t, er = tonumber(d.t), tonumber(d.er)
    if not (t and er and er >= 0 and er <= 9) then return end
    -- set by an officer of this guild (sent by them, or passed on by a guildmate)
    if not (isOfficerName(sender) or (type(d.by) == "string" and isOfficerName(d.by))) then return end
    local s = settingsStore()
    if not s or (s.t or 0) >= t then return end
    s.er, s.t, s.by = er, t, type(d.by) == "string" and d.by or sender
    ns:Fire("GUILD_SETTINGS_CHANGED")
end)

-- A guildmate's HELLO says how new their settings are; if ours are newer, pass them on.
local settingsCooldown = 0
function G:OnPeerSettings(stamp)
    if (tonumber(stamp) or 0) >= G:SettingsStamp() or G:SettingsStamp() == 0 then return end
    if GetTime() < settingsCooldown then return end
    settingsCooldown = GetTime() + 60
    C_Timer.After(1 + math.random() * 5, function() shareSettings(ns.Comms.PRIORITY.BULK) end)
end

---------------------------------------------------------------------------
-- Roster tab
---------------------------------------------------------------------------
local roster = { sort = "rank", showOffline = true, query = "", guild = "*" }
local STATUS = { [1] = { "Away", "warn" }, [2] = { "Busy", "bad" } }

local function lastSeen(e)
    if e.online then
        local st = STATUS[tonumber(e.status) or 0]
        return st and (Wd.Hex(st[2]) .. st[1] .. "|r") or (GREEN .. "Online|r")
    end
    local s = e.lastOnline
    if not s then return GREY .. "Offline|r" end
    local h = s / 3600
    if h < 1 then return GREY .. "< 1 hour|r" end
    if h < 24 then return GREY .. math.floor(h) .. " h|r" end
    local d = math.floor(h / 24)
    if d < 31 then return GREY .. d .. (d == 1 and " day|r" or " days|r") end
    local m = math.floor(d / 30)
    if m < 12 then return GREY .. m .. (m == 1 and " month|r" or " months|r") end
    return GREY .. math.floor(m / 12) .. " y|r"
end

local function guildTag(name)
    local g = ns.Org:GuildInfo(name)
    return (g and g.tag) or name or ""
end

local SORTS = {
    name = function(a, b) return a.name < b.name end,
    level = function(a, b) if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end return a.name < b.name end,
    zone = function(a, b) if (a.zone or "") ~= (b.zone or "") then return (a.zone or "") < (b.zone or "") end return a.name < b.name end,
    guild = function(a, b)
        if a.own ~= b.own then return a.own == true end
        if (a.guild or "") ~= (b.guild or "") then return (a.guild or "") < (b.guild or "") end
        if (a.rank or 99) ~= (b.rank or 99) then return (a.rank or 99) < (b.rank or 99) end
        return a.name < b.name
    end,
    rank = function(a, b)
        if (a.rank or 99) ~= (b.rank or 99) then return (a.rank or 99) < (b.rank or 99) end
        if a.own ~= b.own then return a.own == true end
        return a.name < b.name
    end,
    seen = function(a, b)
        if a.online ~= b.online then return a.online == true end
        if (a.lastOnline or 0) ~= (b.lastOnline or 0) then return (a.lastOnline or 0) < (b.lastOnline or 0) end
        return a.name < b.name
    end,
}

local function keyOf(e) return (e.guild or "") .. "\t" .. ns.NormalizeName(e.name) end

-- Rows for the roster: every guild in the org, or one; returns rows, online, total.
function GUI.RosterRows()
    local rows, online, total = {}, 0, 0
    local q = (roster.query or ""):lower()
    for _, e in ipairs(ns.OrgRoster:Members()) do
        if roster.guild == "*" or e.guild == roster.guild then
            total = total + 1
            if e.online then online = online + 1 end
            if (roster.showOffline or e.online) and (q == "" or e.name:lower():find(q, 1, true)
                or (e.zone or ""):lower():find(q, 1, true) or (e.note or ""):lower():find(q, 1, true)
                or (e.rankName or ""):lower():find(q, 1, true) or (e.guild or ""):lower():find(q, 1, true)
                or guildTag(e.guild):lower():find(q, 1, true)) then
                rows[#rows + 1] = e
            end
        end
    end
    local sorter = SORTS[roster.sort] or SORTS.rank
    table.sort(rows, function(a, b)
        if roster.sort ~= "seen" and a.online ~= b.online then return a.online == true end
        return sorter(a, b)
    end)
    return rows, online, total
end

local function selected()
    if not roster.sel then return nil end
    for _, e in ipairs(roster.rows or {}) do
        if keyOf(e) == roster.sel then return e end
    end
    return nil
end

local COLS = {   -- label, x, width, sort key
    { "Name", 24, 96, "name" }, { "Lvl", 122, 22, "level" }, { "Zone", 148, 104, "zone" }, { "Guild", 256, 66, "guild" },
    { "Rank", 326, 80, "rank" }, { "Note", 410, 116 }, { "Officer note", 530, 106 }, { "Last online", 640, 70, "seen" },
}

local function actionButton(parent, text, width, what, onClick)
    local b = Wd.Button(parent, text, width, onClick)
    b.what = what
    b:HookScript("OnEnter", function(self)
        if not GameTooltip or self:IsEnabled() then return end
        local why, _
        if self.what then _, why = G:CanOn(self.what, selected()) else why = selected() and "They are offline." or "Pick a member first." end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(why or "Not available", 1, 0.6, 0.4)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

local function editNote(e)
    local mine = isMe(e)
    ns.UI:ShowText(mine and "Your note" or "Public note",
        (mine and "Your note in the guild roster" or "The note everyone in the guild sees") .. " (up to 31 characters).",
        e.note or "", function(t) G:SetNote(e.name, t, false) end)
end

-- Show one guild ("*" for every guild), as the dropdown does.
function GUI.SetRosterGuild(name) roster.guild = name or "*"; roster.sel = nil; GUI.RefreshRoster() end

function GUI.EditMyNote()
    local me = ns.roster and ns.roster[ns.NormalizeName(UnitName("player") or "")]
    if not me then
        ns:Print(IsInGuild() and "Your guild roster hasn't loaded yet; try again in a moment." or "You are not in a guild.")
        ns:RequestRoster()
        return
    end
    local e = {}
    for k, v in pairs(me) do e[k] = v end
    e.guild = ns.guildName
    editNote(e)
end

function GUI.BuildRoster(page)
    roster.page = page
    local search = Wd.EditBox(page, 150, function(t) roster.query = t or ""; GUI.RefreshRoster() end, "Search name, zone, rank, note")
    search:SetPoint("TOPLEFT", 0, -2)
    search:SetScript("OnTextChanged", function(self, user) if user then roster.query = self:GetText() or ""; GUI.RefreshRoster() end end)
    roster.offline = Wd.Check(page, "Show offline", function() return roster.showOffline end,
        function(v) roster.showOffline = v; GUI.RefreshRoster() end)
    roster.offline:SetPoint("LEFT", search, "RIGHT", 10, 0)
    roster.guildBtn = Wd.Dropdown(page, 170, function()
        local list = { "*" }
        for _, g in ipairs(ns.OrgRoster:Guilds()) do list[#list + 1] = g.name end
        return list
    end, function() return roster.guild end, function(v) roster.guild = v; roster.sel = nil; GUI.RefreshRoster() end)
    roster.guildBtn.format = function(v) return v == "*" and "All guilds" or v end
    roster.guildBtn.tipTitle = "Show every guild in the org, or one"
    roster.guildBtn:SetPoint("LEFT", roster.offline, "RIGHT", 104, 0)
    roster.invite = Wd.Button(page, "Invite to guild", 112, function()
        ns.UI:ShowText("Invite to guild", "The character's name (add -Realm for another realm).", "", function(text)
            if G:Invite(text) then ns:Print("Guild invite sent to " .. ns.Trim(text) .. ".") end
        end)
    end)
    roster.invite:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    roster.myNote = Wd.Button(page, "My note", 78, function() GUI.EditMyNote() end)
    roster.myNote.tip = "Edit your own note in the guild roster"
    roster.myNote:SetPoint("RIGHT", roster.invite, "LEFT", -6, 0)

    -- column heads (click to sort)
    local heads = CreateFrame("Frame", nil, page)
    heads:SetPoint("TOPLEFT", 0, -30)
    heads:SetPoint("RIGHT", page, "RIGHT", -24, 0)
    heads:SetHeight(16)
    roster.heads = {}
    for _, c in ipairs(COLS) do
        local b = CreateFrame("Button", nil, heads)
        b:SetPoint("LEFT", c[2], 0)
        b:SetSize(c[3], 16)
        b.text = Wd.Label(b, c[1], "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 0, 0)
        b.key = c[4]
        if c[4] then b:SetScript("OnClick", function() roster.sort = c[4]; GUI.RefreshRoster() end) end
        roster.heads[#roster.heads + 1] = b
    end

    roster.list = Wd.List(page, 22, function(row)
        row.icon = Wd.Label(row, "")
        row.icon:SetPoint("LEFT", 4, 0)
        row.cols = {}
        for i, c in ipairs(COLS) do
            local fs = Wd.Label(row, "", i == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
            fs:SetPoint("LEFT", c[2], 0)
            fs:SetWidth(c[3])
            fs:SetWordWrap(false)
            row.cols[i] = fs
        end
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function(self) if self.e then roster.sel = keyOf(self.e); GUI.RefreshRoster() end end)
    end, function(row, e)
        row.e = e
        local on = roster.sel == keyOf(e)
        local dim = not e.online
        local function g(t) return (dim and GREY or "") .. ns.Escape(t or "") .. (dim and "|r" or "") end
        row.icon:SetText(Wd.ClassIcon(e.class, 16))
        row.cols[1]:SetText((on and C.gold .. "> |r" or "") .. (dim and (GREY .. ns.Escape(ns.ShortName(e.name)) .. "|r") or Wd.ClassName(e.name, e.class)))
        row.cols[2]:SetText(g(tostring(e.level or "")))
        row.cols[3]:SetText(g(e.zone))
        row.cols[4]:SetText(e.own and (GREEN .. ns.Escape(guildTag(e.guild)) .. "|r") or (C.gold .. ns.Escape(guildTag(e.guild)) .. "|r"))
        row.cols[5]:SetText(g(e.rankName or ("Rank " .. tostring(e.rank))))
        row.cols[6]:SetText(GREY .. ns.Escape(e.note or "") .. "|r")
        row.cols[7]:SetText((roster.viewOfficer and e.own) and (GREY .. ns.Escape(e.officerNote or "") .. "|r") or "")
        row.cols[8]:SetText(lastSeen(e))
        row.tip = function(tt)
            tt:AddLine(ns.Escape(ns.ShortName(e.name)), 1, 1, 1)
            tt:AddLine(("Level %s %s  ·  %s"):format(tostring(e.level or "?"), e.className or "", e.rankName or ""), 0.8, 0.8, 0.8)
            tt:AddLine(ns.Escape(e.guild or ""), 0.9, 0.75, 0.4)
            if e.zone and e.zone ~= "" then tt:AddLine(e.zone, 0.8, 0.8, 0.8) end
            if e.note and e.note ~= "" then tt:AddLine("Note: " .. ns.Escape(e.note), 0.9, 0.9, 0.6, true) end
            if roster.viewOfficer and e.own and e.officerNote and e.officerNote ~= "" then tt:AddLine("Officer note: " .. ns.Escape(e.officerNote), 0.6, 0.9, 0.6, true) end
            if e.shared then tt:AddLine(("Shared by their guild's RUIN %s ago"):format(ns.Guild.Ago(e.age)), 0.6, 0.7, 0.8) end
        end
    end)
    roster.list:SetEmptyText("No guild members to show.")
    roster.list.frame:SetPoint("TOPLEFT", 0, -48)
    roster.list.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 74)

    -- the selected member and what you can do
    local card = Wd.Card(page)
    card:SetPoint("BOTTOMLEFT", 0, 0)
    card:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    card:SetHeight(68)
    roster.selName = Wd.Label(card, "", "GameFontNormal")
    roster.selName:SetPoint("TOPLEFT", 10, -8)
    roster.selName:SetPoint("RIGHT", card, "RIGHT", -230, 0)
    roster.selName:SetWordWrap(false)
    roster.count = Wd.Label(card, "", "GameFontHighlightSmall")
    roster.count:SetPoint("TOPRIGHT", -10, -10)
    roster.count:SetJustifyH("RIGHT")
    roster.count:SetWidth(220)
    roster.count:SetWordWrap(false)
    local function go(fn) return function() local e = selected(); if e then fn(e) end end end
    roster.whisper = actionButton(card, "Whisper", 72, nil, go(function(e)
        local send = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
        if send then send(e.name) end
    end))
    roster.group = actionButton(card, "Invite to group", 116, nil, go(function(e)
        local f = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if f then f(e.name) end
    end))
    roster.promote = actionButton(card, "Promote", 74, "promote", go(function(e) G:Promote(e.name) end))
    roster.demote = actionButton(card, "Demote", 70, "demote", go(function(e) G:Demote(e.name) end))
    roster.remove = actionButton(card, "Remove", 70, "remove", go(function(e)
        ns.UI:ShowConfirm("Remove from guild", ("Remove %s from %s? This can't be undone from RUIN; they would need a new invite.")
            :format(ns.Escape(ns.ShortName(e.name)), ns.Escape(ns.guildName or "the guild")), function() G:Remove(e.name) end)
    end))
    roster.note = actionButton(card, "Note", 56, "publicNote", go(editNote))
    roster.onote = actionButton(card, "Officer note", 100, "officerNote", go(function(e)
        ns.UI:ShowText("Officer note", "The note only ranks allowed to see officer notes can read (up to 31 characters).", e.officerNote or "", function(t)
            G:SetNote(e.name, t, true)
        end)
    end))
    roster.buttons = { roster.whisper, roster.group, roster.promote, roster.demote, roster.remove, roster.note, roster.onote }
    page:SetScript("OnShow", function() ns:RequestRoster(); ns.OrgRoster:AskMissing(); GUI.RefreshRoster() end)
end

function G.Ago(sec)
    sec = tonumber(sec) or 0
    if sec < 90 then return "a minute" end
    if sec < 5400 then return math.floor(sec / 60 + 0.5) .. " minutes" end
    if sec < 129600 then return math.floor(sec / 3600 + 0.5) .. " hours" end
    return math.floor(sec / 86400 + 0.5) .. " days"
end

function GUI.RefreshRoster()
    if not (roster.page and roster.page:IsVisible()) then return end
    roster.viewOfficer = G:Can("viewOfficerNote")
    -- a guild that left the org (or the filter's guild was renamed)
    if roster.guild ~= "*" then
        local found = false
        for _, g in ipairs(ns.OrgRoster:Guilds()) do if g.name == roster.guild then found = true end end
        if not found then roster.guild = "*" end
    end
    local rows, online, total = GUI.RosterRows()
    roster.rows = rows
    local where
    if roster.guild == "*" then
        local n = #ns.OrgRoster:Guilds()
        where = n > 1 and ("%d guilds"):format(n) or ns.Escape(ns.guildName or "")
    else
        where = ns.Escape(roster.guild)
        for _, g in ipairs(ns.OrgRoster:Guilds()) do
            if g.name == roster.guild and not g.own then
                where = where .. (g.updated and ("  ·  shared " .. G.Ago(g.updated) .. " ago") or "  ·  not shared yet")
            end
        end
    end
    roster.count:SetText(GREY .. ("%d/%d online  ·  %s|r"):format(online, total, where))
    roster.offline:Refresh()
    roster.guildBtn:Refresh()
    roster.invite:SetShown(G:Can("invite"))
    roster.myNote:SetShown(IsInGuild() and true or false)
    for _, h in ipairs(roster.heads) do
        local on = h.key and h.key == roster.sort
        h.text:SetTextColor(on and P.gold[1] or P.sub[1], on and P.gold[2] or P.sub[2], on and P.gold[3] or P.sub[3])
    end
    roster.heads[7]:SetShown(roster.viewOfficer)
    roster.list:SetEmptyText(roster.guild ~= "*" and roster.guild ~= ns.guildName
        and "This guild's roster hasn't been shared yet. It arrives when one of its members is online with RUIN."
        or "No guild members to show.")
    roster.list:SetItems(rows)
    local e = selected()
    if e then
        roster.selName:SetText(Wd.ClassName(e.name, e.class) .. GREY .. ("   %s  ·  level %s%s%s|r"):format(ns.Escape(e.rankName or ""),
            tostring(e.level or "?"), (e.zone and e.zone ~= "") and ("  ·  " .. ns.Escape(e.zone)) or "",
            e.own and "" or ("  ·  " .. ns.Escape(e.guild or ""))))
    else
        roster.selName:SetText(GREY .. "Click a member to see what you can do.|r")
    end
    roster.whisper:SetEnabled(e ~= nil and e.online == true and not isMe(e))
    roster.group:SetEnabled(e ~= nil and e.online == true and not isMe(e))
    for _, b in ipairs({ roster.promote, roster.demote, roster.remove, roster.note, roster.onote }) do
        b:SetEnabled((G:CanOn(b.what, e)))
    end
    -- moderation buttons only for ranks that have any of these rights, and
    -- only for members of your own guild
    local own = e == nil or e.own == true
    local any = own and (G:Can("promote") or G:Can("demote") or G:Can("remove"))
    roster.promote:SetShown(any); roster.demote:SetShown(any); roster.remove:SetShown(any)
    roster.onote:SetShown(own and G:Can("officerNote"))
    roster.note:SetShown(own and (G:Can("publicNote") or isMe(e)))
    roster.note:SetText(isMe(e) and "My note" or "Note")
    local prev
    for _, b in ipairs(roster.buttons) do
        if b:IsShown() then
            b:ClearAllPoints()
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("BOTTOMLEFT", roster.selName:GetParent(), "BOTTOMLEFT", 8, 8) end
            prev = b
        end
    end
end

---------------------------------------------------------------------------
-- Chat: a log of guild (or every RUIN guild's) chat with a line to type in.
-- Built twice: once in the Guild page's Chat tab, once in the pop-out.
---------------------------------------------------------------------------
local views = {}

local function scope() return (ns.db and ns.db.settings.chatScope) or "org" end

local function lineText(l)
    local tag
    if l.own then
        tag = GREEN .. "[Guild]|r"
    else
        local gi = ns.Org:GuildInfo(l.gu)
        tag = C.gold .. "[" .. ns.Escape((gi and gi.tag) or l.gu or "RUIN") .. "]|r"
    end
    return ("%s%s|r %s %s: %s"):format(GREY, date("%H:%M", l.t or time()), tag,
        ns.Chat.ColorName and ns.Chat.ColorName(l.a or "?", l.c) or ns.Escape(l.a or "?"), ns.Chat.Sanitize(l.text or ""))
end

-- The lines a view shows: its scope, its search, or only the pinned lines.
local function visibleLines(v)
    local out = {}
    if v and v.pins then
        for _, l in ipairs(ns.Chat:Pins()) do out[#out + 1] = l end
        return out
    end
    local own = scope() == "guild"
    local q = v and v.query and ns.Trim(v.query):lower() or ""
    for _, l in ipairs(ns.Chat.history) do
        if (l.own or not own) and not ns.Chat:Hidden(l.a, l.text)
            and (q == "" or tostring(l.text):lower():find(q, 1, true) or tostring(l.a):lower():find(q, 1, true)) then
            out[#out + 1] = l
        end
    end
    return out
end

-- Right-click (or click) a chat line: pin, whisper, report, delete for everyone.
local function lineMenu(l)
    local short = ns.ShortName(l.a or "?")
    local entries = { { title = short } }
    entries[#entries + 1] = { ns.Chat:IsPinned(l) and "Unpin" or "Pin", function() ns.Chat:TogglePin(l) end }
    if ns.NormalizeName(l.a or "") ~= ns.NormalizeName(ns.playerName or "") then
        entries[#entries + 1] = { "Whisper", function()
            if ChatFrame_SendTell then ChatFrame_SendTell(l.a) elseif ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. l.a .. " ") end
        end }
        entries[#entries + 1] = { "Report to the Watch", function() ns.Watch:PromptReport(l.a) end }
        if ns.Watch:IsModerator() then
            entries[#entries + 1] = { "Delete for everyone", function()
                local ok, e = ns.Watch:DeleteLine(l.a, l.text)
                if not ok then ns:Print(e) end
            end }
            entries[#entries + 1] = { "Mute 30 minutes", function()
                local ok, e = ns.Watch:Sanction("mute", l.a, 1800, "chat")
                ns:Print(ok and (short .. " is muted in RUIN chat for 30 minutes.") or e)
            end }
        end
    end
    entries[#entries + 1] = { "Copy text", function()
        ns.UI:ShowText("Copy", "Ctrl+C to copy.", l.text or "", function() end, true)
    end }
    Wd.ContextMenu(entries)
end
GUI.LineMenu = lineMenu

function GUI.EditBlockWords()
    local cur = table.concat(type(ns.db.blockWords) == "table" and ns.db.blockWords or {}, ", ")
    ns.UI:ShowText("Block words", "Lines with any of these words are hidden from your RUIN chat. Separate them with commas.", cur, function(text)
        ns.db.blockWords = ns.Chat.ParseWords(text)
        ns:Print(#ns.db.blockWords .. " block word" .. (#ns.db.blockWords == 1 and "" or "s") .. " set.")
        ns:Fire("CHAT_HISTORY")
    end)
end

-- view: { frame, log rows, offset (lines scrolled back from the newest) }
function GUI.BuildChatView(parent, popout)
    local v = { offset = 0, rows = {}, popout = popout }
    v.orgBtn = Wd.Button(parent, "All RUIN guilds", 122, function() ns.db.settings.chatScope = "org"; v.offset = 0; GUI.RefreshChat() end)
    v.orgBtn:SetPoint("TOPLEFT", popout and 8 or 0, popout and -26 or -2)
    v.guildBtn = Wd.Button(parent, "My guild", 84, function() ns.db.settings.chatScope = "guild"; v.offset = 0; GUI.RefreshChat() end)
    v.guildBtn:SetPoint("LEFT", v.orgBtn, "RIGHT", 4, 0)
    v.orgBtn.tip, v.guildBtn.tip = "Your guild and every other RUIN guild", "Just your own guild's chat"
    if not popout then
        v.pop = Wd.Button(parent, "Pop out", 80, function() GUI.ToggleChatWindow(true) end)
        v.pop:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -2)
        v.block = Wd.Button(parent, "Block words", 96, function() GUI.EditBlockWords() end)
        v.block:SetPoint("RIGHT", v.pop, "LEFT", -4, 0)
        v.block.tip = "Hide RUIN chat lines with words you choose."
        v.search = Wd.EditBox(parent, 130, nil, "Search chat")
        v.search:SetPoint("RIGHT", v.block, "LEFT", -6, 0)
        v.search:SetScript("OnTextChanged", function(self) v.query = self:GetText() or ""; v.offset = 0; GUI.RefreshChat() end)
    end
    v.pinsBtn = Wd.Button(parent, "Pins", 64, function() v.pins = not v.pins; v.offset = 0; GUI.RefreshChat() end)
    v.pinsBtn:SetPoint("LEFT", v.guildBtn, "RIGHT", 4, 0)
    v.pinsBtn.tip = "Lines you pinned (click a line to pin it)."
    v.info = Wd.Label(parent, "", "GameFontHighlightSmall")
    v.info:SetPoint("LEFT", v.pinsBtn, "RIGHT", 10, 0)
    if v.search then v.info:SetPoint("RIGHT", v.search, "LEFT", -8, 0) elseif popout then v.info:SetPoint("RIGHT", parent, "RIGHT", -8, 0) end
    v.info:SetWordWrap(false)

    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", popout and 8 or 0, popout and -54 or -30)
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", popout and -8 or 0, popout and 36 or 30)
    Wd.Skin(box, "bg", 0.85, "border")
    if box.SetClipsChildren then box:SetClipsChildren(true) end
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta)
        v.offset = math.max(0, math.min(#visibleLines(v) - 1, v.offset + (delta > 0 and 3 or -3)))
        GUI.RefreshChat()
    end)
    v.box = box
    v.empty = Wd.Label(box, "", "GameFontDisableSmall")
    v.empty:SetPoint("CENTER", 0, 0)

    v.input = Wd.EditBox(parent, 200, nil, "Type to your guild, Enter to send")
    v.input:SetPoint("BOTTOMLEFT", popout and 8 or 0, popout and 8 or 2)
    v.input:SetPoint("RIGHT", parent, "RIGHT", popout and -84 or -76, 0)
    local function send()
        if ns.Chat:SendGuild(v.input:GetText()) then v.input:SetText(""); v.offset = 0 end
    end
    v.input:SetScript("OnEnterPressed", function(self) send(); self:ClearFocus() end)
    v.send = Wd.Button(parent, "Send", 70, send)
    v.send:SetPoint("LEFT", v.input, "RIGHT", 6, 0)
    views[#views + 1] = v
    return v
end

local function refreshView(v)
    local s = scope()
    if s == "org" then v.orgBtn:LockHighlight(); v.guildBtn:UnlockHighlight() else v.guildBtn:LockHighlight(); v.orgBtn:UnlockHighlight() end
    if v.pins then v.pinsBtn:LockHighlight() else v.pinsBtn:UnlockHighlight() end
    v.pinsBtn:SetText("Pins" .. (#ns.Chat:Pins() > 0 and (" (" .. #ns.Chat:Pins() .. ")") or ""))
    local lines = visibleLines(v)
    local k = ns.Org:Get()
    v.info:SetText(GREY .. (v.pins and "Pinned lines (kept on this computer)" or (v.query or "") ~= "" and ("%d lines match"):format(#lines) or s == "org" and (k and ("%s: every RUIN guild"):format(ns.Escape(k.org)) or "No org key: your guild only")
        or ns.Escape(ns.guildName or "No guild")) .. (v.offset > 0 and ("  ·  scrolled back " .. v.offset) or "") .. "|r")
    -- newest at the bottom, filling upward until the box is full
    local width = math.max(100, (v.box:GetWidth() or 400) - 16)
    local height = (v.box:GetHeight() or 200) - 8
    local y, shown = 4, 0
    for i = #lines - v.offset, 1, -1 do
        shown = shown + 1
        local row = v.rows[shown]
        if not row then
            row = CreateFrame("Button", nil, v.box)
            row.text = Wd.Label(row, "", "ChatFontNormal")
            row.text:SetPoint("TOPLEFT", 0, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetJustifyV("TOP")
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(self) if self.line then lineMenu(self.line) end end)
            v.rows[shown] = row
        end
        row.line = lines[i]
        row.text:SetWidth(width)
        row:SetWidth(width)
        row.text:SetText((ns.Chat:IsPinned(lines[i]) and (C.gold .. "* |r") or "") .. lineText(lines[i]))
        local h = math.max(14, row.text:GetStringHeight() or 14)
        row:SetHeight(h)
        if y + h > height and shown > 1 then shown = shown - 1; row:Hide(); break end
        row:ClearAllPoints()
        row:SetPoint("BOTTOMLEFT", v.box, "BOTTOMLEFT", 8, y)
        row:Show()
        y = y + h + 2
    end
    for i = shown + 1, #v.rows do v.rows[i]:Hide() end
    v.empty:SetText(#lines == 0 and v.pins and "No pinned lines. Click a chat line to pin it." or #lines == 0 and (v.query or "") ~= "" and "Nothing matches." or #lines == 0 and ((s == "org" and "Guild chat from every RUIN guild shows here" or "Your guild's chat shows here") .. " while you're online.") or "")
    v.send:SetEnabled(IsInGuild() and true or false)
end

function GUI.RefreshChat()
    for _, v in ipairs(views) do
        local f = v.popout and GUI.window or v.box
        if f and f:IsVisible() then refreshView(v) end
    end
end

ns:Subscribe("CHAT_HISTORY", function() GUI.RefreshChat() end)

---------------------------------------------------------------------------
-- The pop-out chat window: movable, remembers where you put it, Escape closes it.
---------------------------------------------------------------------------
function GUI.ToggleChatWindow(show)
    if not GUI.window then
        local w = Wd.HudFrame("RUIN_GuildChatWindow", "Guild", ns.db.settings, "chatPos", { "LEFT", UIParent, "LEFT", 40, 0 })
        w:SetSize(460, 320)
        w:SetFrameStrata("HIGH")
        local title = Wd.Label(w, C.gold .. "RUIN|r  Guild chat", "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -8)
        local close = Wd.Button(w, "X", 24, function() w:Hide() end)
        close:SetPoint("TOPRIGHT", -4, -4)
        GUI.window = w
        GUI.BuildChatView(w, true)
        w:SetScript("OnShow", function() GUI.RefreshChat() end)
        if UISpecialFrames then tinsert(UISpecialFrames, "RUIN_GuildChatWindow") end
        w:Hide()
    end
    if show == nil then show = not GUI.window:IsShown() end
    if show then GUI.window:Show() else GUI.window:Hide() end
    GUI.RefreshChat()
end

ns:Subscribe("ROSTER_UPDATED", function() GUI.RefreshRoster() end)
ns:Subscribe("ORG_ROSTER_UPDATED", function() GUI.RefreshRoster() end)
ns:Subscribe("PEERS_CHANGED", function() GUI.RefreshRoster() end)
ns:Subscribe("GUILD_CHANGED", function() GUI.RefreshRoster() end)
