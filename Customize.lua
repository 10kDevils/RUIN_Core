-- RUIN Core: Settings > Customization. The looks for the game's own frames
-- (the minimap, the objective tracker, the world map and quest log), every
-- look at once, and the sections modules add (Pathfinder's tracker and
-- waypoint). The frames' settings are kept per character.
local ADDON, ns = ...
local R = RUIN_API
if not R then return end
local W = R.Widgets
local C = W.COLORS

local CU = {}
ns.Customize = CU

-- the settings that came from Pathfinder (0.8.11 and before kept them there)
local MOVED = { "mmStyle", "mmAlpha", "mmIcons", "northCal", "otStyle", "otAlpha", "wmStyle", "wmAlpha" }

local cdb
function CU.DB() return cdb end

-- the looks you had set in Pathfinder come along, once
function CU.Migrate(to, old)
    if to.lookFromPathfinder then return end
    if type(old) == "table" then
        for _, k in ipairs(MOVED) do
            if to[k] == nil and old[k] ~= nil then to[k] = old[k] end
        end
    end
    to.lookFromPathfinder = true
end

-- Called once at login, before the modules start (Modules.lua).
function CU.Init()
    if cdb then return end
    if type(RUIN_CoreCharDB) ~= "table" then RUIN_CoreCharDB = {} end
    cdb = RUIN_CoreCharDB
    CU.Migrate(cdb, rawget(_G, "RUIN_PathfinderCharDB"))
    local function try(f) if f then local ok, err = pcall(f, cdb); if not ok and ns.ReportError then ns.ReportError(err) end end end
    try(ns.Objectives and ns.Objectives.Init)
    try(ns.WorldMap and ns.WorldMap.Init)
    try(ns.Minimap and ns.Minimap.Init)
end

---------------------------------------------------------------------------
-- Every look at once: the game's frames plus the looks modules add
-- ({ name, Style, SetStyle, Alpha, SetAlpha }, e.g. Pathfinder's tracker).
---------------------------------------------------------------------------
local L = ns.Looks
local extra = {}
function L.AddLook(look) extra[#extra + 1] = look end

local function each()
    local list = {}
    if ns.Minimap then list[#list + 1] = { name = "minimap", Style = ns.Minimap.Style, SetStyle = ns.Minimap.SetStyle, Alpha = ns.Minimap.Alpha, SetAlpha = ns.Minimap.SetAlpha } end
    if ns.Objectives then list[#list + 1] = { name = "objective tracker", Style = ns.Objectives.Style, SetStyle = ns.Objectives.SetStyle, Alpha = ns.Objectives.Alpha, SetAlpha = ns.Objectives.SetAlpha } end
    if ns.WorldMap then list[#list + 1] = { name = "world map", Style = ns.WorldMap.Style, SetStyle = ns.WorldMap.SetStyle, Alpha = ns.WorldMap.Alpha, SetAlpha = ns.WorldMap.SetAlpha } end
    for _, x in ipairs(extra) do list[#list + 1] = x end
    return list
end

-- the one look they all have, or "mixed"
function L.AllStyles()
    local first
    for _, x in ipairs(each()) do
        local v = x.Style and x.Style()
        if v then
            if first == nil then first = v elseif v ~= first then return "mixed" end
        end
    end
    return first or "mixed"
end
function L.AllAlpha()
    local first
    for _, x in ipairs(each()) do
        local v = x.Alpha and x.Alpha()
        if type(v) == "number" then
            if first == nil then first = v elseif math.abs(v - first) > 0.001 then return "mixed" end
        end
    end
    return first or "mixed"
end
local function report(what, label, err)
    if R.Print then R:Print(("Couldn't %s the %s: %s"):format(what, label, tostring(err)))
    elseif print then print(("RUIN: couldn't %s the %s: %s"):format(what, label, tostring(err))) end
end
-- each in its own pcall: one that trips can't stop the rest
function L.SetAllStyles(v)
    if not L.Valid(v) then return false end
    for _, x in ipairs(each()) do
        if x.SetStyle then local ok, err = pcall(x.SetStyle, v); if not ok then report("restyle", x.name, err) end end
    end
    CU.Refresh()
    return true
end
function L.SetAllAlpha(a)
    if type(a) ~= "number" then return false end
    for _, x in ipairs(each()) do
        if x.SetAlpha then local ok, err = pcall(x.SetAlpha, a); if not ok then report("change", x.name, err) end end
    end
    CU.Refresh()
    return true
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local sections = {}          -- { order, title, height, build(card, kit) }
local widgets = {}           -- everything with a Refresh, refreshed when the page shows
local page, body, built

-- A module's own section on the page: build(card, kit) fills a card of the
-- given height under its header. Sections show in order (Game Frames is 0).
function CU.AddSection(order, title, height, build)
    sections[#sections + 1] = { order = order or 50, title = title, height = height, build = build }
    table.sort(sections, function(a, b) return a.order < b.order end)
    if built then CU.Rebuild() end
end

function CU.Refresh()
    for _, w in ipairs(widgets) do if w.Refresh then pcall(w.Refresh, w) end end
end

local GAP, PAD, ROW, COL2 = 12, 16, 30, 340
local OPACITY = { 1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2 }
local function near(v)          -- the closest choice to a saved value
    local best, gap = 1, 2
    for _, o in ipairs(OPACITY) do if math.abs(o - (v or 1)) < gap then best, gap = o, math.abs(o - (v or 1)) end end
    return best
end

-- The kit a section builds with: the page's spacing, a faint divider, a look
-- row (name, Style, Background), and keep(widget) to refresh it on show.
local kit = { GAP = GAP, PAD = PAD, ROW = ROW, COL2 = COL2, OPACITY = OPACITY }
function kit.keep(w) widgets[#widgets + 1] = w; return w end
function kit.divider(c, at)
    local d = c:CreateTexture(nil, "ARTWORK")
    d:SetColorTexture(1, 1, 1, 0.06)
    d:SetHeight(1)
    d:SetPoint("TOPLEFT", PAD, at)
    d:SetPoint("TOPRIGHT", -PAD, at)
    return d
end
function kit.lookRow(c, at, name, keys, getStyle, setStyle, getAlpha, setAlpha, tipStyle, tipBack)
    local n = W.Label(c, name, "GameFontHighlight")
    n:SetPoint("TOPLEFT", PAD, at)
    n:SetWidth(170)
    local sl = W.Label(c, C.dim .. "Style|r", "GameFontHighlightSmall")
    sl:SetPoint("TOPLEFT", PAD + 180, at - 1)
    local st = W.Dropdown(c, 170, keys, getStyle, function(v) setStyle(v); CU.Refresh() end)
    st.format = function(v) return v == "mixed" and "Mixed" or (L.LABEL[v] or v) end
    st:SetPoint("LEFT", sl, "RIGHT", 10, 0)
    st.tipTitle = tipStyle
    st:Refresh()
    kit.keep(st)
    local bd
    if getAlpha then
        local bl = W.Label(c, C.dim .. "Background|r", "GameFontHighlightSmall")
        bl:SetPoint("LEFT", st, "RIGHT", 28, 0)
        bd = W.Dropdown(c, 84, OPACITY, function()
            local v = getAlpha()
            if v == "mixed" then return v end
            return near(v)
        end, function(v) setAlpha(v); CU.Refresh() end)
        bd.format = function(v) return v == "mixed" and "Mixed" or ("%d%%"):format(math.floor(v * 100 + 0.5)) end
        bd:SetPoint("LEFT", bl, "RIGHT", 10, 0)
        bd.tipTitle = tipBack
        bd:Refresh()
        kit.keep(bd)
    end
    return st, bd
end
CU.Kit = kit

-- The game's frames: every look at once, then each frame
local function buildFrames(g)
    local mm, ot, wm = ns.Minimap, ns.Objectives, ns.WorldMap
    CU.allStyles, CU.allAlpha = kit.lookRow(g, -40, C.white .. "All styles|r", L.KEYS,
        function() return L.AllStyles() end, function(v) L.SetAllStyles(v) end,
        function() return L.AllAlpha() end, function(v) L.SetAllAlpha(v) end,
        "One look for the minimap, the objective tracker, the world map, and what modules add here (Pathfinder's tracker and waypoint). Blizzard gives them all the game's own look.",
        "One opacity for the minimap's, the objective tracker's and the world map's backgrounds, and what modules add here")
    kit.divider(g, -70)
    if mm then
        CU.mmStyle, CU.mmAlpha = kit.lookRow(g, -84, "Minimap", mm.STYLES,
            function() return mm.Style() end, function(v) mm.SetStyle(v) end,
            function() return mm.Alpha() end, function(v) mm.SetAlpha(v) end,
            "The game's own look, or the suite's modern one: a square frame around the map, a slim ring, an N where north is, mouse-wheel zoom, and the tracking button, zone, calendar, addon list, mail, coordinates and clock in its corners",
            "How see-through the frame around the minimap is")
    end
    if ot then
        CU.otStyle, CU.otAlpha = kit.lookRow(g, -84 - 40, "Objective Tracker", ot.STYLES,
            function() return ot.Style() end, function(v) ot.SetStyle(v) end,
            function() return ot.Alpha() end, function(v) ot.SetAlpha(v) end,
            "The game's own look, or the suite's modern one: a panel behind the tracker, headers in the look's color, quest titles and objectives in the suite's text colors",
            "How see-through the panel behind the objective tracker is")
    end
    if wm then
        CU.wmStyle, CU.wmAlpha = kit.lookRow(g, -84 - 80, "World Map & Quest Log", wm.STYLES,
            function() return wm.Style() end, function(v) wm.SetStyle(v) end,
            function() return wm.Alpha() end, function(v) wm.SetAlpha(v) end,
            "The game's own look, or the suite's modern one: the map window and quest log in the suite's look, with flat quest markers and buttons",
            "How see-through the map window's background is")
    end
    -- where addons' minimap buttons sit with a modern minimap
    if mm and mm.ICON_SPOTS then
        local il = W.Label(g, "Minimap addon buttons", "GameFontHighlight")
        il:SetPoint("TOPLEFT", PAD, -84 - 120)
        il:SetWidth(170)
        local sl = W.Label(g, C.dim .. "Place|r", "GameFontHighlightSmall")
        sl:SetPoint("TOPLEFT", PAD + 180, -84 - 121)
        CU.mmIcons = W.Dropdown(g, 170, mm.ICON_SPOTS, function() return mm.IconSpot() end, function(v) mm.SetIconSpot(v) end)
        CU.mmIcons.format = function(v) return mm.ICON_LABEL[v] or v end
        CU.mmIcons:SetPoint("LEFT", sl, "RIGHT", 10, 0)
        CU.mmIcons.tipTitle = "With a modern minimap: addons' minimap buttons around the round map, or on the square frame around it. The game's own minimap keeps them around the map."
        CU.mmIcons:Refresh()
        kit.keep(CU.mmIcons)
    end
end

local function fill()
    built = true
    for i = #widgets, 1, -1 do widgets[i] = nil end
    local y = 0
    local function card(title, height)
        local c = W.Card(body)
        c:SetPoint("TOPLEFT", 0, -y)
        c:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        c:SetHeight(height)
        local h = W.Header(c, title)
        h:SetPoint("TOPLEFT", PAD - 2, -10)
        y = y + height + GAP
        return c
    end
    local list = { { order = 0, title = "Game Frames", height = 254, build = buildFrames } }
    for _, s in ipairs(sections) do list[#list + 1] = s end
    table.sort(list, function(a, b) return a.order < b.order end)
    body.cards, CU.titles = {}, {}
    for _, s in ipairs(list) do
        CU.titles[#CU.titles + 1] = s.title
        local c = card(s.title, s.height)
        body.cards[#body.cards + 1] = c
        local ok, err = pcall(s.build, c, kit)
        if not ok and ns.ReportError then ns.ReportError(err) end
    end
    body:SetHeight(math.max(y, 10))
    if W.FitScrollBar and page.sf then W.FitScrollBar(page.sf) end
end

function CU.Rebuild()
    if not body then return end
    for _, c in ipairs(body.cards or {}) do c:Hide(); c:SetParent(nil) end
    fill()
end

-- Settings builds the tab's page with this; it fills in on first show, by
-- when every module has added its sections.
function CU.Build(p)
    page = p
    local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -24, 0)
    body = CreateFrame("Frame", nil, sf)
    body:SetSize(math.max(400, (p:GetWidth() or 900) - 24), 10)
    sf:SetScrollChild(body)
    sf:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then body:SetWidth(w) end end)
    if W.SmoothScroll then W.SmoothScroll(sf, 72) end
    p.sf = sf
    local function show()
        if not built then fill() end
        CU.Refresh()
    end
    p:HookScript("OnShow", show)
    if p:IsVisible() then show() end
end

R.Customize = CU
R.Looks, R.Minimap, R.Objectives, R.WorldMap = ns.Looks, ns.Minimap, ns.Objectives, ns.WorldMap
