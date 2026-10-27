-- RUIN Core: the Guild page's People tab
-- The org's people seen several ways, from the same rosters as the Roster
-- tab: the hierarchy (each guild's master, officers and appointed offices,
-- with how long they've been away), your guild's inactive members (with
-- one-at-a-time removal for ranks allowed to remove), and the members grouped
-- by class, zone, level or profession. Guild masters appoint offices (Raid
-- leader, Recruiter, Treasurer, squad leaders...) that every RUIN member sees
-- and that modules use (Muster's War Room, Exchange's treasury).
local ADDON, ns = ...

local Wd = ns.Widgets
local P = Wd.PALETTE
local C = Wd.COLORS
local GREY, GREEN, RED, YELLOW = C.dim, C.good, C.bad, C.warn

local People = {}
ns.People = People

local MAX_OFFICES = 25
People.TITLES = { "Raid leader", "PvP leader", "Recruiter", "Treasurer", "Squad leader", "Class leader",
                  "Quartermaster", "Event organizer", "Diplomat" }

local function now() return GetServerTime and GetServerTime() or time() end
local function norm(n) return ns.NormalizeName(n or "") end

---------------------------------------------------------------------------
-- Offices: per guild, set by its guild master (or the org admin), seen by all
---------------------------------------------------------------------------
local function officeStore()
    if not ns.db then return {} end
    ns.db.offices = type(ns.db.offices) == "table" and ns.db.offices or {}
    return ns.db.offices
end

-- { { title, name } } for a guild (default your own).
function People:Offices(guild)
    local e = officeStore()[guild or ns.guildName or ""]
    return e and e.list or {}
end

-- The offices a player holds: { "Raid leader", ... }.
function People:OfficesOf(name, guild)
    local out, n = {}, norm(name)
    for g, e in pairs(officeStore()) do
        if not guild or g == guild then
            for _, o in ipairs(e.list or {}) do
                if norm(o.name) == n then out[#out + 1] = o.title end
            end
        end
    end
    return out
end

-- Does this player hold an office whose title contains `title` (any case)?
function People:HasOffice(name, title)
    title = (title or ""):lower()
    for _, t in ipairs(People:OfficesOf(name)) do
        if t:lower():find(title, 1, true) then return true end
    end
    return false
end

-- Can you change your guild's offices? The guild master, or the org admin.
function People:CanAppoint()
    return ns.guildName ~= nil and (ns.guildRank == 0 or ns.Org:IsAdmin())
end

local function publishOffices(guild)
    local e = officeStore()[guild]
    if not (e and ns.Comms:IsJoined("ORG")) then return end
    ns.Comms:Send("OFFICES", { gu = guild, t = e.t, by = e.by, l = e.list }, "ORG", nil, ns.Comms.PRIORITY.BULK)
end
People.Publish = publishOffices

local function cleanList(list)
    local out = {}
    for _, o in ipairs(type(list) == "table" and list or {}) do
        if type(o) == "table" and type(o.title) == "string" and type(o.name) == "string" and #out < MAX_OFFICES then
            local title, name = ns.Trim(o.title):gsub("|", ""):sub(1, 24), ns.Trim(o.name):gsub("|", ""):sub(1, 48)
            if title ~= "" and name ~= "" then out[#out + 1] = { title = title, name = name } end
        end
    end
    return out
end

local function setOffices(list, why)
    if not People:CanAppoint() then return false, "Only your guild master (or the org admin) appoints offices." end
    officeStore()[ns.guildName] = { t = now(), by = ns.playerName, list = cleanList(list) }
    publishOffices(ns.guildName)
    if ns.Watch then ns.Watch:Log(ns.playerName, "offices", why) end
    ns:Fire("OFFICES_CHANGED", ns.guildName)
    return true
end

-- Appoint a member of your guild to an office. Returns true, or false and why.
function People:Appoint(title, name)
    title, name = ns.Trim(title or ""), ns.Trim(name or "")
    if title == "" or name == "" then return false, "An office needs a title and a member." end
    if not (ns.roster and ns.roster[norm(name)]) then return false, name .. " isn't in your guild's roster." end
    local list = {}
    for _, o in ipairs(People:Offices()) do
        if not (o.title:lower() == title:lower() and norm(o.name) == norm(name)) then list[#list + 1] = o end
    end
    if #list >= MAX_OFFICES then return false, ("A guild can have up to %d offices."):format(MAX_OFFICES) end
    local full = ns.roster[norm(name)].name
    list[#list + 1] = { title = title, name = full }
    return setOffices(list, ("%s appointed %s"):format(ns.ShortName(full), title))
end

function People:Dismiss(title, name)
    local list, found = {}, false
    for _, o in ipairs(People:Offices()) do
        if o.title == title and norm(o.name) == norm(name) then found = true else list[#list + 1] = o end
    end
    if not found then return false, "No such office." end
    return setOffices(list, ("%s no longer %s"):format(ns.ShortName(name), title))
end

local function guildLeaderName(guild)
    for _, m in ipairs(ns.OrgRoster:Members()) do
        if m.guild == guild and m.rank == 0 then return m.name end
    end
end

ns.Comms:Register("OFFICES", function(d, sender, scope)
    if scope ~= "ORG" or type(d.gu) ~= "string" or not ns.Org:GuildInfo(d.gu) then return end
    local t = tonumber(d.t)
    if not t then return end
    local cur = officeStore()[d.gu]
    if cur and (cur.t or 0) >= t then return end
    -- set by that guild's master (as its roster says), or by the org admin
    local by = type(d.by) == "string" and d.by or sender
    local leader = guildLeaderName(d.gu)
    local k = ns.Org:Get()
    local peer = ns.Presence:OrgPeerByName(by)
    local isAdmin = k and peer and peer.guid == k.admin
    if not ((leader and norm(leader) == norm(by)) or isAdmin) then return end
    officeStore()[d.gu] = { t = t, by = by, list = cleanList(d.l) }
    ns:Fire("OFFICES_CHANGED", d.gu)
end)

-- The roster sender also republishes the guild's offices, so new members get them.
ns:Subscribe("ORG_ROSTER_SENT", function() if ns.guildName then publishOffices(ns.guildName) end end)

---------------------------------------------------------------------------
-- Hierarchy: guild masters, officers and office holders of every guild
---------------------------------------------------------------------------
local function daysAway(m)
    if m.online then return 0 end
    return m.lastOnline and math.floor(m.lastOnline / 86400) or nil
end
People.DaysAway = daysAway

function People:AwayDays() return (ns.db and tonumber(ns.db.settings.leaderAwayDays)) or 3 end

-- { { guild, people = { { name, class, level, role, rankName, online, days, offices } } } }, leaders first in each.
function People:Hierarchy()
    local byGuild = {}
    for _, g in ipairs(ns.OrgRoster:Guilds()) do byGuild[g.name] = { guild = g.name, tag = g.tag, own = g.own, people = {} } end
    for _, m in ipairs(ns.OrgRoster:Members()) do
        local g = byGuild[m.guild]
        if g then
            local offices = People:OfficesOf(m.name, m.guild)
            local officer = ns.Org:IsOfficerRank(m.rank, m.guild)
            if m.rank == 0 or officer or #offices > 0 then
                g.people[#g.people + 1] = { name = m.name, class = m.class, level = m.level, rank = m.rank, rankName = m.rankName,
                    online = m.online, days = daysAway(m), offices = offices,
                    role = m.rank == 0 and "Guild master" or (officer and "Officer" or "Office") }
            end
        end
    end
    local list = {}
    for _, g in pairs(byGuild) do
        table.sort(g.people, function(a, b)
            if (a.rank or 99) ~= (b.rank or 99) then return (a.rank or 99) < (b.rank or 99) end
            return a.name < b.name
        end)
        list[#list + 1] = g
    end
    table.sort(list, function(a, b) if a.own ~= b.own then return a.own end return a.guild < b.guild end)
    return list
end

-- A leader away too long: one chat line per absence, to that guild's officers
-- (and to the org admin for every guild). Nothing is done to anyone.
local alerted = {}
function People:CheckAway()
    if not ns.db then return end
    local limit = People:AwayDays()
    local admin = ns.Org:IsAdmin()
    for _, m in ipairs(ns.OrgRoster:Members()) do
        if m.rank == 0 then
            local days = daysAway(m)
            local mine = m.guild == ns.guildName and ns.Org:AmOfficer()
            if days and days >= limit and (mine or admin) and not alerted[m.guild .. norm(m.name)] then
                alerted[m.guild .. norm(m.name)] = true
                ns:Print(("%s, guild master of %s, has been away %d days."):format(ns.ShortName(m.name), m.guild, days))
            elseif days and days < limit then
                alerted[m.guild .. norm(m.name)] = nil
            end
        end
    end
end

---------------------------------------------------------------------------
-- Inactive members of your own guild
---------------------------------------------------------------------------
-- Members offline at least `days` days, longest away first.
function People:Inactive(days)
    days = tonumber(days) or 7
    local out = {}
    for _, e in pairs(ns.roster or {}) do
        local d = daysAway(e)
        if not e.online and d and d >= days then
            out[#out + 1] = { name = e.name, class = e.class, level = e.level, rank = e.rank, rankName = e.rankName,
                              days = d, note = e.note, guild = ns.guildName, own = true }
        end
    end
    table.sort(out, function(a, b) if a.days ~= b.days then return a.days > b.days end return a.name < b.name end)
    return out
end

---------------------------------------------------------------------------
-- The same people, grouped
---------------------------------------------------------------------------
-- Modules can say which professions a player has (Exchange does): fn(name) -> { "Alchemy", ... }
local professionSources = {}
function People:AddProfessionSource(fn) if type(fn) == "function" then professionSources[#professionSources + 1] = fn end end

local function professionsOf(name)
    local set, out = {}, {}
    for _, fn in ipairs(professionSources) do
        local ok, list = pcall(fn, name)
        if ok and type(list) == "table" then
            for _, p in ipairs(list) do if not set[p] then set[p] = true; out[#out + 1] = p end end
        end
    end
    return out
end

local function classLabel(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    if names and class and names[class] then return names[class] end
    return class and (class:sub(1, 1) .. class:sub(2):lower()) or "Unknown"
end

-- mode: "class" | "zone" | "level" | "profession"; returns rows: headers { header, count } and people.
function People:Grouped(mode, query, onlineOnly)
    local groups, q = {}, (query or ""):lower()
    local function add(key, m)
        local g = groups[key] or { header = key, people = {} }
        g.people[#g.people + 1] = m
        groups[key] = g
    end
    for _, m in ipairs(ns.OrgRoster:Members()) do
        if (not onlineOnly or m.online) and (q == "" or m.name:lower():find(q, 1, true) or (m.guild or ""):lower():find(q, 1, true)) then
            if mode == "zone" then
                add((m.zone and m.zone ~= "") and m.zone or "Unknown", m)
            elseif mode == "level" then
                local lv = tonumber(m.level) or 0
                add(lv >= 60 and "Level 60" or ("Levels %d-%d"):format(math.floor(lv / 10) * 10, math.floor(lv / 10) * 10 + 9), m)
            elseif mode == "profession" then
                local list = professionsOf(m.name)
                if #list == 0 then add("Not shared", m) else for _, p in ipairs(list) do add(p, m) end end
            else
                add(classLabel(m.class), m)
            end
        end
    end
    local list = {}
    for _, g in pairs(groups) do list[#list + 1] = g end
    table.sort(list, function(a, b)
        if (a.header == "Unknown" or a.header == "Not shared") ~= (b.header == "Unknown" or b.header == "Not shared") then
            return b.header == "Unknown" or b.header == "Not shared"
        end
        if mode == "level" then return a.header > b.header end
        if #a.people ~= #b.people then return #a.people > #b.people end
        return a.header < b.header
    end)
    local rows = {}
    for _, g in ipairs(list) do
        table.sort(g.people, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return a.name < b.name
        end)
        rows[#rows + 1] = { header = g.header, count = #g.people }
        for _, m in ipairs(g.people) do rows[#rows + 1] = m end
    end
    return rows
end

---------------------------------------------------------------------------
-- The People tab
---------------------------------------------------------------------------
local ui = { mode = "Hierarchy", days = 7, query = "" }
local MODES = { "Hierarchy", "Offices", "Inactive", "By class", "By zone", "By level", "By profession" }
local removeCooldown = 0

local function tagOf(guild)
    local g = ns.Org:GuildInfo(guild)
    return (g and g.tag) or guild or ""
end

local function seenText(online, days)
    if online then return GREEN .. "Online|r" end
    if not days then return GREY .. "Offline|r" end
    if days == 0 then return GREY .. "today|r" end
    local away = days >= People:AwayDays()
    return (away and RED or GREY) .. days .. (days == 1 and " day|r" or " days|r")
end

local function rows()
    local out = {}
    if ui.mode == "Hierarchy" then
        for _, g in ipairs(People:Hierarchy()) do
            out[#out + 1] = { header = g.guild, count = #g.people, own = g.own }
            for _, p in ipairs(g.people) do
                p.guild = g.guild
                out[#out + 1] = p
            end
        end
    elseif ui.mode == "Offices" then
        for _, g in ipairs(ns.OrgRoster:Guilds()) do
            local list = People:Offices(g.name)
            if #list > 0 or g.own then
                out[#out + 1] = { header = g.name, count = #list, own = g.own }
                for _, o in ipairs(list) do
                    local m
                    for _, x in ipairs(ns.OrgRoster:Members()) do if x.guild == g.name and norm(x.name) == norm(o.name) then m = x end end
                    out[#out + 1] = { name = o.name, title = o.title, guild = g.name, office = true, class = m and m.class,
                                      online = m and m.online, days = m and daysAway(m), level = m and m.level }
                end
            end
        end
    elseif ui.mode == "Inactive" then
        out = People:Inactive(ui.days)
    else
        local mode = ({ ["By class"] = "class", ["By zone"] = "zone", ["By level"] = "level", ["By profession"] = "profession" })[ui.mode]
        out = People:Grouped(mode, ui.query, ui.onlineOnly)
    end
    return out
end

local function selected()
    for _, e in ipairs(ui.rows or {}) do
        if not e.header and ui.sel and e.name == ui.sel.name and e.guild == ui.sel.guild and e.title == ui.sel.title then return e end
    end
end

function ns.GuildUI.BuildPeople(page)
    ui.page = page
    ui.modeBtn = Wd.Dropdown(page, 150, MODES, function() return ui.mode end, function(v) ui.mode = v; ui.sel = nil; People:Refresh() end, "View: ")
    ui.modeBtn:SetPoint("TOPLEFT", 0, 0)
    ui.search = Wd.EditBox(page, 150, function(t) ui.query = t or ""; People:Refresh() end, "Search name or guild")
    ui.search:SetPoint("LEFT", ui.modeBtn, "RIGHT", 8, 0)
    ui.search:SetScript("OnTextChanged", function(self, user) if user then ui.query = self:GetText() or ""; People:Refresh() end end)
    ui.daysBtn = Wd.Dropdown(page, 140, { 7, 14, 30 }, function() return ui.days end, function(v) ui.days = v; People:Refresh() end, "Offline ")
    ui.daysBtn.format = function(v) return v .. "+ days" end
    ui.daysBtn:SetPoint("LEFT", ui.modeBtn, "RIGHT", 8, 0)
    ui.online = Wd.Check(page, "Online only", function() return ui.onlineOnly end, function(v) ui.onlineOnly = v; People:Refresh() end)
    ui.online:SetPoint("LEFT", ui.search, "RIGHT", 10, 0)
    ui.info = Wd.Label(page, "", "GameFontHighlightSmall")
    ui.info:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -6)
    ui.info:SetJustifyH("RIGHT")

    ui.list = Wd.List(page, 22, function(row)
        row.icon = Wd.Label(row, "")
        row.icon:SetPoint("LEFT", 4, 0)
        row.name = Wd.Label(row, "")
        row.name:SetPoint("LEFT", 24, 0)
        row.name:SetWidth(170)
        row.name:SetWordWrap(false)
        row.a = Wd.Label(row, "", "GameFontHighlightSmall")
        row.a:SetPoint("LEFT", 198, 0)
        row.a:SetWidth(170)
        row.a:SetWordWrap(false)
        row.b = Wd.Label(row, "", "GameFontHighlightSmall")
        row.b:SetPoint("LEFT", 372, 0)
        row.b:SetWidth(170)
        row.b:SetWordWrap(false)
        row.c = Wd.Label(row, "", "GameFontHighlightSmall")
        row.c:SetPoint("LEFT", 546, 0)
        row.c:SetWidth(150)
        row.c:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function(self)
            if self.e and not self.e.header then ui.sel = { name = self.e.name, guild = self.e.guild, title = self.e.title }; People:Refresh() end
        end)
    end, function(row, e)
        row.e = e
        if e.header then
            row.icon:SetText("")
            row.name:SetText(C.gold .. ns.Escape(e.header) .. "|r")
            row.a:SetText(GREY .. e.count .. "|r")
            row.b:SetText(""); row.c:SetText("")
            row.tip = nil
            return
        end
        local on = ui.sel and ui.sel.name == e.name and ui.sel.guild == e.guild and ui.sel.title == e.title
        row.icon:SetText(Wd.ClassIcon(e.class, 16))
        row.name:SetText((on and C.gold .. "> |r" or "") .. Wd.ClassName(e.name, e.class))
        if ui.mode == "Hierarchy" then
            local extra = (e.offices and #e.offices > 0) and (GREY .. "  ·  " .. ns.Escape(table.concat(e.offices, ", ")) .. "|r") or ""
            row.a:SetText((e.role == "Guild master" and C.gold or C.white) .. e.role .. "|r" .. extra)
            row.b:SetText(GREY .. ns.Escape(e.rankName or "") .. "  ·  " .. tostring(e.level or "") .. "|r")
            row.c:SetText(seenText(e.online, e.days))
        elseif ui.mode == "Offices" then
            row.a:SetText(C.white .. ns.Escape(e.title) .. "|r")
            row.b:SetText(GREY .. "[" .. ns.Escape(tagOf(e.guild)) .. "]|r")
            row.c:SetText(seenText(e.online, e.days))
        elseif ui.mode == "Inactive" then
            row.a:SetText(GREY .. ns.Escape(e.rankName or "") .. "  ·  " .. tostring(e.level or "") .. "|r")
            row.b:SetText(GREY .. ns.Escape(e.note or "") .. "|r")
            row.c:SetText(RED .. e.days .. " days|r")
        else
            row.a:SetText(GREY .. "[" .. ns.Escape(tagOf(e.guild)) .. "]  " .. ns.Escape(e.rankName or "") .. "|r")
            row.b:SetText(GREY .. tostring(e.level or "") .. "  ·  " .. ns.Escape(e.zone or "") .. "|r")
            row.c:SetText(seenText(e.online, daysAway(e)))
        end
        row.tip = function(tt)
            tt:AddLine(ns.Escape(ns.ShortName(e.name)), 1, 1, 1)
            if e.guild then tt:AddLine(ns.Escape(e.guild), 0.9, 0.75, 0.4) end
            local offices = People:OfficesOf(e.name)
            if #offices > 0 then tt:AddLine("Offices: " .. ns.Escape(table.concat(offices, ", ")), 0.7, 0.85, 1, true) end
        end
    end)
    ui.list.frame:SetPoint("TOPLEFT", 0, -32)
    ui.list.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 74)

    local card = Wd.Card(page)
    card:SetPoint("BOTTOMLEFT", 0, 0)
    card:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    card:SetHeight(68)
    ui.selName = Wd.Label(card, "", "GameFontNormal")
    ui.selName:SetPoint("TOPLEFT", 10, -8)
    ui.selName:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    ui.selName:SetWordWrap(false)
    local function go(fn) return function() local e = selected(); if e then fn(e) end end end
    ui.whisper = Wd.Button(card, "Whisper", 72, go(function(e)
        local send = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
        if send then send(e.name) end
    end))
    ui.remove = Wd.Button(card, "Remove from guild", 140, go(function(e)
        if GetTime() < removeCooldown then return ns:Print("One at a time: wait a few seconds.") end
        local ok, why = ns.Guild:CanOn("remove", e)
        if not ok then return ns:Print(why) end
        ns.UI:ShowConfirm("Remove from guild", ("Remove %s (%s, away %d days) from %s?\n\nThey would need a new invite to come back.")
            :format(ns.Escape(ns.ShortName(e.name)), ns.Escape(e.rankName or ""), e.days or 0, ns.Escape(ns.guildName or "the guild")), function()
            removeCooldown = GetTime() + 3
            ns.Guild:Remove(e.name)
            ns:Print("Removed " .. ns.ShortName(e.name) .. " from the guild.")
        end)
    end))
    ui.appoint = Wd.Button(card, "Appoint office", 120, function()
        ns.UI:ShowText("Appoint an office", "Office title, then the member's name. Example:  Raid leader, Grimlock\nTitles people use: " .. table.concat(People.TITLES, ", ") .. ".", "", function(text)
            local title, name = (text or ""):match("^%s*([^,]+),%s*(.-)%s*$")
            local ok, why = People:Appoint(title, name)
            ns:Print(ok and ("%s is now %s."):format(ns.Trim(name or ""), ns.Trim(title or "")) or why)
            People:Refresh()
        end)
    end)
    ui.dismiss = Wd.Button(card, "Dismiss", 80, go(function(e)
        local ok, why = People:Dismiss(e.title, e.name)
        ns:Print(ok and ("%s is no longer %s."):format(ns.ShortName(e.name), e.title) or why)
        People:Refresh()
    end))
    ui.report = Wd.Button(card, "Report to the Watch", 150, go(function(e) if ns.Watch then ns.Watch:PromptReport(e.name) end end))
    ui.buttons = { ui.whisper, ui.remove, ui.appoint, ui.dismiss, ui.report }
    page:SetScript("OnShow", function() People:Refresh() end)
end

function People:Refresh()
    if not (ui.page and ui.page:IsVisible()) then return end
    ui.rows = rows()
    ui.daysBtn:SetShown(ui.mode == "Inactive")
    ui.search:SetShown(ui.mode:find("^By") ~= nil)
    ui.online:SetShown(ui.mode:find("^By") ~= nil)
    ui.modeBtn:Refresh(); ui.daysBtn:Refresh(); ui.online:Refresh()
    local n = 0
    for _, e in ipairs(ui.rows) do if not e.header then n = n + 1 end end
    local info = ({ Hierarchy = "Guild masters, officers and office holders. Red: away " .. People:AwayDays() .. "+ days.",
                    Offices = "Offices each guild master appoints.",
                    Inactive = ("%d members of %s"):format(n, ns.guildName or "your guild") })[ui.mode] or (n .. " members")
    ui.info:SetText(GREY .. info .. "|r")
    ui.list:SetEmptyText(ui.mode == "Inactive" and "Nobody that long away." or (ui.mode == "Offices" and "No offices yet. Your guild master appoints them with Appoint office." or "Nobody to show yet."))
    ui.list:SetItems(ui.rows)
    local e = selected()
    ui.selName:SetText(e and (Wd.ClassName(e.name, e.class) .. GREY .. "   " .. ns.Escape(e.guild or "") .. (e.title and ("  ·  " .. ns.Escape(e.title)) or "") .. "|r")
        or (GREY .. "Click a member to see what you can do.|r"))
    ui.whisper:SetShown(true)
    ui.whisper:SetEnabled(e ~= nil and e.online == true)
    ui.remove:SetShown(ui.mode == "Inactive" and ns.Guild:Can("remove"))
    ui.remove:SetEnabled(e ~= nil and (ns.Guild:CanOn("remove", e)))
    ui.appoint:SetShown(ui.mode == "Offices" and People:CanAppoint())
    ui.dismiss:SetShown(ui.mode == "Offices" and People:CanAppoint())
    ui.dismiss:SetEnabled(e ~= nil and e.office == true and e.guild == ns.guildName)
    ui.report:SetShown(ns.Watch ~= nil)
    ui.report:SetEnabled(e ~= nil)
    local prev
    for _, b in ipairs(ui.buttons) do
        if b:IsShown() then
            b:ClearAllPoints()
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("BOTTOMLEFT", ui.selName:GetParent(), "BOTTOMLEFT", 8, 8) end
            prev = b
        end
    end
end

function ns.GuildUI.SetPeopleMode(mode) ui.mode = mode; ui.sel = nil; People:Refresh() end

for _, ev in ipairs({ "ROSTER_UPDATED", "ORG_ROSTER_UPDATED", "OFFICES_CHANGED", "PEERS_CHANGED" }) do
    ns:Subscribe(ev, function() People:Refresh() end)
end
local awayPending = false
local function scheduleAway()
    if awayPending then return end
    awayPending = true
    C_Timer.After(30, function() awayPending = false; People:CheckAway() end)
end
ns:Subscribe("ROSTER_UPDATED", scheduleAway)
ns:Subscribe("ORG_ROSTER_UPDATED", scheduleAway)
