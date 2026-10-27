-- RUIN Core: the census
-- Every guild of the org at a glance, worked out from the rosters RUIN
-- already has (your own guild live from the game, the others shared by their
-- members, see OrgRoster.lua): members, online, average level, guild master,
-- RUIN users and free slots per guild, the org's totals, and where the
-- members are. The census also keeps a little history on this computer
-- (characters per day for 30 days, online per hour for a day) and answers
-- searches for a guild, a leader, a player or a zone. Nothing is sent.
local ADDON, ns = ...

local Census = {}
ns.Census = Census

local GUILD_CAP = 1000
local SAMPLE_EVERY = 15 * 60
local KEEP_DAYS = 30

local function now() return GetServerTime and GetServerTime() or time() end

---------------------------------------------------------------------------
-- Per-guild rows and totals
---------------------------------------------------------------------------
-- { name, tag, own, members, online, avg, leader, leaderOnline, leaderSeen, ruin, free, updated, shared }
function Census:Rows()
    local by = {}
    for _, g in ipairs(ns.OrgRoster:Guilds()) do
        by[g.name] = { name = g.name, tag = g.tag or g.name, own = g.own, updated = g.updated, shared = not g.own,
                       members = 0, online = 0, levels = 0, leveled = 0, ruin = 0 }
    end
    for _, m in ipairs(ns.OrgRoster:Members()) do
        local r = by[m.guild]
        if r then
            r.members = r.members + 1
            if m.online then r.online = r.online + 1 end
            if tonumber(m.level) and m.level > 0 then r.levels, r.leveled = r.levels + m.level, r.leveled + 1 end
            if m.rank == 0 then
                r.leader, r.leaderOnline, r.leaderSeen, r.leaderClass = m.name, m.online, m.lastOnline, m.class
            end
        end
    end
    for _, p in ipairs(ns.Presence:GetOnlineList()) do
        if p.guild and by[p.guild] then by[p.guild].ruin = by[p.guild].ruin + 1 end
    end
    local rows = {}
    for _, r in pairs(by) do
        r.avg = r.leveled > 0 and math.floor(r.levels / r.leveled * 10) / 10 or nil
        r.free = math.max(0, GUILD_CAP - r.members)
        r.levels, r.leveled = nil, nil
        rows[#rows + 1] = r
    end
    return rows
end

local SORTS = {
    guild = function(a, b) return a.name < b.name end,
    members = function(a, b) if a.members ~= b.members then return a.members > b.members end return a.name < b.name end,
    online = function(a, b) if a.online ~= b.online then return a.online > b.online end return a.name < b.name end,
    avg = function(a, b) if (a.avg or -1) ~= (b.avg or -1) then return (a.avg or -1) > (b.avg or -1) end return a.name < b.name end,
    leader = function(a, b) return tostring(a.leader or "~") < tostring(b.leader or "~") end,
    ruin = function(a, b) if a.ruin ~= b.ruin then return a.ruin > b.ruin end return a.name < b.name end,
}
Census.SORTS = SORTS

function Census:SortedRows(key)
    local rows = Census:Rows()
    table.sort(rows, SORTS[key or "members"] or SORTS.members)
    return rows
end

-- Characters, people (each player once: characters linked as alts count once),
-- online, guilds, average level of the org.
function Census:Totals()
    local t = { characters = 0, online = 0, guilds = 0, levels = 0, leveled = 0 }
    for _, r in ipairs(Census:Rows()) do
        t.guilds = t.guilds + 1
        t.characters = t.characters + r.members
        t.online = t.online + r.online
        if r.avg then t.levels, t.leveled = t.levels + r.avg * r.members, t.leveled + r.members end
    end
    t.avg = t.leveled > 0 and math.floor(t.levels / t.leveled * 10) / 10 or nil
    t.people = math.max(0, t.characters - ns.Presence:LinkedAltExtras())
    return t
end

---------------------------------------------------------------------------
-- Where the members are: zones and continents, online members only
---------------------------------------------------------------------------
local continentOfZone = {}      -- zone name -> continent name (or false)

local function continentFor(zone)
    if continentOfZone[zone] ~= nil then return continentOfZone[zone] or nil end
    local id = ns.Map:ZoneMapID(zone)
    local found = false
    local guard = 0
    while id and C_Map and C_Map.GetMapInfo and guard < 8 do
        guard = guard + 1
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        if info.mapType == 2 then found = info.name; break end    -- Enum.UIMapType.Continent
        id = info.parentMapID
    end
    continentOfZone[zone] = found
    return found or nil
end

-- { zones = { { zone, count, guilds = { name -> n } } }, continents = { { name, count } }, total }
function Census:Where()
    local zones, total = {}, 0
    for _, m in ipairs(ns.OrgRoster:Members()) do
        if m.online and type(m.zone) == "string" and m.zone ~= "" then
            local z = zones[m.zone] or { zone = m.zone, count = 0, guilds = {} }
            z.count = z.count + 1
            z.guilds[m.guild or "?"] = (z.guilds[m.guild or "?"] or 0) + 1
            zones[m.zone] = z
            total = total + 1
        end
    end
    local zl, conts = {}, {}
    for _, z in pairs(zones) do
        zl[#zl + 1] = z
        local c = continentFor(z.zone) or "Elsewhere"
        conts[c] = (conts[c] or 0) + z.count
    end
    table.sort(zl, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.zone < b.zone end)
    local cl = {}
    for name, n in pairs(conts) do cl[#cl + 1] = { name = name, count = n } end
    table.sort(cl, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.name < b.name end)
    return { zones = zl, continents = cl, total = total }
end

---------------------------------------------------------------------------
-- Search: a guild, a leader, a player, a zone, or "recruiting" / "free 50"
---------------------------------------------------------------------------
-- Letters that look alike count as one (l, I and 1; 0 and O), and case doesn't matter.
local function fold(s)
    return (tostring(s or ""):lower():gsub("[1i|]", "l"):gsub("0", "o"))
end
Census.Fold = fold

-- Returns a list of { kind = "guild"|"leader"|"player"|"zone"|"recruiting", text, guild, name, count, free }.
function Census:Search(query)
    query = ns.Trim(query or "")
    local out = {}
    if query == "" then return out end
    local q = fold(query)
    local rows = Census:Rows()
    -- recruiting: guilds with room, most free slots first
    local freeMin = query:lower():match("^free%s*(%d+)$")
    if query:lower() == "recruiting" or query:lower() == "free" or freeMin then
        local n = tonumber(freeMin) or 1
        table.sort(rows, function(a, b) return a.free > b.free end)
        for _, r in ipairs(rows) do
            if r.free >= n then out[#out + 1] = { kind = "recruiting", guild = r.name, free = r.free, count = r.members } end
        end
        return out
    end
    for _, r in ipairs(rows) do
        if fold(r.name):find(q, 1, true) or fold(r.tag):find(q, 1, true) then
            out[#out + 1] = { kind = "guild", guild = r.name, count = r.members, online = r.online, free = r.free }
        end
        if r.leader and fold(ns.ShortName(r.leader)):find(q, 1, true) then
            out[#out + 1] = { kind = "leader", guild = r.name, name = r.leader, online = r.leaderOnline }
        end
    end
    local players = 0
    for _, m in ipairs(ns.OrgRoster:Members()) do
        if m.rank ~= 0 and fold(ns.ShortName(m.name)):find(q, 1, true) then
            players = players + 1
            if players <= 40 then
                out[#out + 1] = { kind = "player", guild = m.guild, name = m.name, online = m.online, level = m.level,
                                  class = m.class, zone = m.zone, rankName = m.rankName }
            end
        end
    end
    for _, z in ipairs(Census:Where().zones) do
        if fold(z.zone):find(q, 1, true) then
            out[#out + 1] = { kind = "zone", zone = z.zone, count = z.count, guilds = z.guilds }
        end
    end
    return out, players
end

---------------------------------------------------------------------------
-- History: characters per day (30 days) and online per hour (the last day),
-- written down every 15 minutes while you play. Kept on this computer only.
---------------------------------------------------------------------------
local function store()
    if not ns.db then return nil end
    local h = ns.db.census
    if type(h) ~= "table" then h = {}; ns.db.census = h end
    h.days = type(h.days) == "table" and h.days or {}     -- "2026-10-27" -> { c = max characters, o = max online }
    h.hours = type(h.hours) == "table" and h.hours or {}  -- hour start (server time) -> max online
    return h
end

function Census:Sample()
    local h = store()
    if not h or not ns.Org:Get() then return end
    local t = Census:Totals()
    if t.characters == 0 then return end
    local ts = now()
    local day = date("%Y-%m-%d", ts)
    local d = h.days[day] or { c = 0, o = 0 }
    d.c, d.o = math.max(d.c, t.characters), math.max(d.o, t.online)
    h.days[day] = d
    local hour = ts - ts % 3600
    h.hours[hour] = math.max(h.hours[hour] or 0, t.online)
    -- forget what's too old
    local oldestDay = date("%Y-%m-%d", ts - KEEP_DAYS * 86400)
    for k in pairs(h.days) do if k < oldestDay then h.days[k] = nil end end
    for k in pairs(h.hours) do if k < ts - 48 * 3600 then h.hours[k] = nil end end
    ns:Fire("CENSUS_SAMPLED")
end

-- The last 30 days: { { day = "10-27", value = characters } } oldest first (missing days are 0).
function Census:DaySeries()
    local h = store()
    local out, ts = {}, now()
    for i = KEEP_DAYS - 1, 0, -1 do
        local key = date("%Y-%m-%d", ts - i * 86400)
        local d = h and h.days[key]
        out[#out + 1] = { label = key:sub(6), value = d and d.c or 0, online = d and d.o or 0 }
    end
    return out
end

-- The last 24 hours: { { label = "14:00", value = online } } oldest first.
function Census:HourSeries()
    local h = store()
    local out, ts = {}, now()
    local cur = ts - ts % 3600
    for i = 23, 0, -1 do
        local hour = cur - i * 3600
        out[#out + 1] = { label = date("%H:00", hour), value = h and h.hours[hour] or 0 }
    end
    return out
end

-- Most online at once today on this client, and when.
function Census:PeakToday()
    local h = store()
    if not h then return nil end
    local ts = now()
    local start = ts - (ts % 86400)
    local best, at = 0, nil
    for hour, n in pairs(h.hours) do
        if hour >= start and n > best then best, at = n, hour end
    end
    return best > 0 and best or nil, at
end

-- Sample a few minutes after login (once rosters have arrived), then every 15 minutes.
ns:Subscribe("LOGIN", function()
    C_Timer.After(180, function() Census:Sample() end)
    C_Timer.NewTicker(SAMPLE_EVERY, function() Census:Sample() end)
end)

---------------------------------------------------------------------------
-- The Census tab on the Guild page
---------------------------------------------------------------------------
local Wd = ns.Widgets
local P = Wd.PALETTE
local C = Wd.COLORS
local GREY, GREEN, RED = C.dim, C.good, C.bad

ns.GuildUI = ns.GuildUI or {}
local ui = { sort = "members", query = "" }
local SORT_NAMES = { members = "Members", online = "Online", avg = "Average level", guild = "Guild name", leader = "Guild master", ruin = "With RUIN" }

-- A small bar graph: n bars that fill the frame.
local function graph(parent, n, title)
    local f = CreateFrame("Frame", nil, parent)
    f.title = Wd.Label(f, title, "GameFontHighlightSmall")
    f.title:SetPoint("TOPLEFT", 0, 0)
    f.peak = Wd.Label(f, "", "GameFontHighlightSmall")
    f.peak:SetPoint("TOPRIGHT", 0, 0)
    f.first = Wd.Label(f, "", "GameFontDisableSmall")
    f.first:SetPoint("BOTTOMLEFT", 0, 0)
    f.last = Wd.Label(f, "", "GameFontDisableSmall")
    f.last:SetPoint("BOTTOMRIGHT", 0, 0)
    f.bars = {}
    for i = 1, n do
        local b = f:CreateTexture(nil, "ARTWORK")
        b:SetColorTexture(P.glow[1], P.glow[2], P.glow[3], 0.85)
        f.bars[i] = b
    end
    function f:SetSeries(series, fmt)
        local w, h = (self:GetWidth() or 200), (self:GetHeight() or 80) - 30
        local max = 0
        for _, s in ipairs(series) do max = math.max(max, s.value or 0) end
        local bw = w / math.max(1, #series)
        for i, b in ipairs(self.bars) do
            local s = series[i]
            if s and max > 0 and (s.value or 0) > 0 then
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", (i - 1) * bw + 1, 14)
                b:SetSize(math.max(1, bw - 2), math.max(1, h * s.value / max))
                b:Show()
            else
                b:Hide()
            end
        end
        self.peak:SetText(max > 0 and (GREY .. (fmt or "most: %d"):format(max) .. "|r") or (GREY .. "no data yet|r"))
        self.first:SetText(series[1] and series[1].label or "")
        self.last:SetText(series[#series] and series[#series].label or "")
    end
    return f
end

local function seen(online, lastOnline)
    if online then return GREEN .. "online|r" end
    if type(lastOnline) == "number" and lastOnline > 0 then return GREY .. "seen " .. Wd.Ago(math.max(60, now() - lastOnline)) .. "|r" end
    return GREY .. "offline|r"
end

function ns.GuildUI.BuildCensus(page)
    ui.page = page
    ui.totals = Wd.Label(page, "", "GameFontHighlight")
    ui.totals:SetPoint("TOPLEFT", 2, -4)
    ui.totals:SetPoint("RIGHT", page, "RIGHT", -340, 0)
    ui.totals:SetWordWrap(false)
    ui.sortBtn = Wd.Dropdown(page, 170, { "members", "online", "avg", "ruin", "guild", "leader" },
        function() return ui.sort end, function(v) ui.sort = v; Census:Refresh() end, "Sort: ")
    ui.sortBtn.format = function(v) return SORT_NAMES[v] or v end
    ui.sortBtn:Refresh()
    ui.sortBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -166, 0)
    ui.search = Wd.EditBox(page, 160, function(t) ui.query = t or ""; Census:Refresh() end, "Search guild, player, zone")
    ui.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -2)
    ui.search:SetScript("OnTextChanged", function(self, user) if user then ui.query = self:GetText() or ""; Census:Refresh() end end)
    ui.search.tipTitle = "Census search"
    ui.search.tip = "A guild or its tag, a guild master, a player or a zone. Look-alike letters match (l, I, 1 and 0, O). Type recruiting, or free 50, for guilds with room."

    ui.head = Wd.Label(page, "", "GameFontHighlightSmall")
    ui.head:SetPoint("TOPLEFT", 6, -32)

    ui.list = Wd.List(page, 22, function(row)
        row.a = Wd.Label(row, "")
        row.a:SetPoint("LEFT", 6, 0); row.a:SetWidth(200); row.a:SetWordWrap(false)
        row.b = Wd.Label(row, "", "GameFontHighlightSmall")
        row.b:SetPoint("LEFT", 210, 0); row.b:SetWidth(170); row.b:SetWordWrap(false)
        row.c = Wd.Label(row, "", "GameFontHighlightSmall")
        row.c:SetPoint("LEFT", 384, 0); row.c:SetWidth(330); row.c:SetWordWrap(false)
    end, function(row, e)
        if e.kind == "row" then
            local r = e.r
            row.a:SetText((r.own and GREEN or C.gold) .. "[" .. ns.Escape(r.tag) .. "]|r " .. ns.Escape(r.name))
            row.b:SetText(("%s%d|r members  ·  %s%d|r on"):format(C.white, r.members, GREEN, r.online))
            local gm = r.leader and (Wd.ClassName(r.leader, r.leaderClass) .. " " .. seen(r.leaderOnline, r.leaderSeen)) or (GREY .. "guild master unknown|r")
            row.c:SetText(("%s  ·  %savg %s  ·  %d RUIN  ·  %d free|r"):format(gm, GREY, r.avg and tostring(r.avg) or "?", r.ruin, r.free))
            row.tip = function(tt)
                tt:AddLine(ns.Escape(r.name))
                tt:AddLine(r.own and "Your guild: live from the game." or
                    (r.updated and ("Roster shared by a member " .. Wd.Ago(math.max(60, now() - r.updated)) .. ".") or "No roster shared yet."), 0.8, 0.8, 0.8)
            end
        elseif e.kind == "guild" or e.kind == "recruiting" then
            row.a:SetText(C.gold .. "Guild|r  " .. ns.Escape(e.guild))
            row.b:SetText(("%d members"):format(e.count or 0))
            row.c:SetText(GREY .. ("%d free slots"):format(e.free or 0) .. (e.online and ("  ·  " .. e.online .. " online") or "") .. "|r")
            row.tip = nil
        elseif e.kind == "leader" then
            row.a:SetText(C.gold .. "Guild master|r  " .. ns.Escape(ns.ShortName(e.name)))
            row.b:SetText(ns.Escape(e.guild))
            row.c:SetText(seen(e.online))
            row.tip = nil
        elseif e.kind == "player" then
            row.a:SetText(Wd.ClassName(e.name, e.class))
            row.b:SetText(GREY .. ns.Escape(e.guild or "") .. "|r")
            row.c:SetText(GREY .. tostring(e.level or "?") .. "  ·  " .. ns.Escape(e.rankName or "") .. "|r" .. (e.online and ("  ·  " .. GREEN .. ns.Escape(e.zone or "online") .. "|r") or ""))
            row.tip = nil
        elseif e.kind == "zone" then
            local gs = {}
            for g, n in pairs(e.guilds or {}) do gs[#gs + 1] = g .. " " .. n end
            table.sort(gs)
            row.a:SetText(C.gold .. "Zone|r  " .. ns.Escape(e.zone))
            row.b:SetText(("%d online"):format(e.count))
            row.c:SetText(GREY .. ns.Escape(table.concat(gs, ", ")) .. "|r")
            row.tip = nil
        end
    end)
    ui.list.frame:SetPoint("TOPLEFT", 0, -48)
    ui.list.frame:SetPoint("RIGHT", page, "RIGHT", -24, 0)
    ui.list.frame:SetPoint("BOTTOM", page, "BOTTOM", 0, 156)

    local card = Wd.Card(page)
    card:SetPoint("BOTTOMLEFT", 0, 0)
    card:SetPoint("BOTTOMRIGHT", 0, 0)
    card:SetHeight(146)
    ui.days = graph(card, 30, "Characters in the org, last 30 days")
    ui.days:SetPoint("TOPLEFT", 10, -8)
    ui.days:SetSize(260, 128)
    ui.hours = graph(card, 24, "Online at once, last 24 hours")
    ui.hours:SetPoint("TOPLEFT", 286, -8)
    ui.hours:SetSize(240, 128)
    ui.where = Wd.Label(card, "", "GameFontHighlightSmall")
    ui.where:SetPoint("TOPLEFT", 542, -8)
    ui.where:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
    ui.where:SetJustifyH("LEFT")
    ui.where:SetJustifyV("TOP")
    page:SetScript("OnShow", function() Census:Refresh() end)
end

function Census:Refresh()
    if not (ui.page and ui.page:IsVisible()) then return end
    local t = Census:Totals()
    local peak = Census:PeakToday()
    ui.totals:SetText(("%s%d|r guilds  ·  %s%d|r characters%s  ·  %s%d|r online%s  ·  avg level %s"):format(
        C.gold, t.guilds, C.white, t.characters,
        t.people ~= t.characters and (GREY .. " (" .. t.people .. " players)|r") or "",
        GREEN, t.online, peak and (GREY .. " (peak today " .. peak .. ")|r") or "", t.avg and tostring(t.avg) or "?"))
    local items = {}
    if ns.Trim(ui.query or "") ~= "" then
        local res, players = Census:Search(ui.query)
        for _, r in ipairs(res) do items[#items + 1] = r end
        ui.head:SetText(GREY .. ("%d results%s|r"):format(#res, (players or 0) > 40 and (" (first 40 of " .. players .. " players)") or ""))
        ui.list:SetEmptyText("Nothing matches.")
    else
        for _, r in ipairs(Census:SortedRows(ui.sort)) do items[#items + 1] = { kind = "row", r = r } end
        ui.head:SetText(GREY .. "Every guild of the org: other guilds' numbers come from the rosters their members share (Roster tab).|r")
        ui.list:SetEmptyText(ns.Org:Get() and "No guild rosters yet." or "No org key yet.")
    end
    ui.list:SetItems(items)
    ui.days:SetSeries(Census:DaySeries(), "most: %d")
    ui.hours:SetSeries(Census:HourSeries(), "most: %d")
    local w = Census:Where()
    local lines = { C.white .. "Where members are|r" }
    for i, c in ipairs(w.continents) do
        if i > 3 then break end
        lines[#lines + 1] = ("%s  %s%d|r"):format(ns.Escape(c.name), GREEN, c.count)
    end
    for i, z in ipairs(w.zones) do
        if i > 4 then break end
        lines[#lines + 1] = GREY .. ns.Escape(z.zone) .. "  " .. z.count .. "|r"
    end
    if w.total == 0 then lines[#lines + 1] = GREY .. "Nobody online with a known zone.|r" end
    ui.where:SetText(table.concat(lines, "\n"))
end

ns:Subscribe("CENSUS_SAMPLED", function() Census:Refresh() end)
ns:Subscribe("ORG_ROSTER_UPDATED", function() Census:Refresh() end)
ns:Subscribe("ROSTER_UPDATED", function() Census:Refresh() end)
