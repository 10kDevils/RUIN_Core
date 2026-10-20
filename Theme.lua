-- RUIN Core: page themes
-- Each page gets a header in its module's colors: the module icon, a gold
-- title in WoW's Morpheus face, a tagline, and a small animated scene on the
-- right that says what the module is about. Everything is drawn from plain
-- textures and item icons, so nothing depends on art that may be missing.
local ADDON, ns = ...
local W = ns.Widgets

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"

-- Pages are named after their module (Codex, Pathfinder, ...), with the app's
-- name above the title. tab/order: the label and place of the page's tab
-- along the top of the window (Options always last).
local APP = "RUIN Gaming Companion App"
ns.APP_NAME = APP
ns.THEMES = {
    Codex      = { color = { 0.54, 0.32, 0.84 }, icon = "Interface\\Icons\\INV_Chest_Cloth_17",     motif = "tome",    order = 50, tab = "Gear",
                   title = "Gear & Dungeons", kicker = APP, tagline = "Gear Path, journal, best-in-slot and macros" },
    Pathfinder = { color = { 0.31, 0.60, 0.23 }, icon = "Interface\\Icons\\INV_Misc_Map_01",       motif = "trail",   order = 40, tab = "Leveling",
                   title = "Leveling & Quest Guide", kicker = APP, tagline = "Leveling and quest guide" },
    Guild      = { color = { 0.90, 0.72, 0.38 }, icon = "Interface\\Icons\\INV_Banner_03",        motif = "banners", order = 10, tab = "Guild",
                   title = "Guild & Community", kicker = APP, tagline = "One banner for every RUIN guild" },
    Finder     = { color = { 0.82, 0.31, 0.54 }, icon = "Interface\\Icons\\INV_Misc_GroupLooking", motif = "board",   order = 20, tab = "Groups",
                   title = "Group Finder", kicker = APP, tagline = "Who in RUIN wants to group, right now" },
    Muster     = { color = { 0.85, 0.38, 0.17 }, icon = "Interface\\Icons\\INV_Misc_Note_02",      motif = "torches", order = 30, tab = "Events",
                   title = "Events & Rallies", kicker = APP, tagline = "Events, rallies, bounties and world sightings" },
    Warfront   = { color = { 0.77, 0.12, 0.23 }, icon = "Interface\\Icons\\INV_BannerPVP_01",      motif = "war",     order = 70, tab = "Warfront",
                   title = "Warfront (retired)", kicker = APP, tagline = "Retired: use Overlord Forever and the Events page" },
    Intel      = { color = { 0.22, 0.71, 0.91 }, icon = "Interface\\Icons\\INV_Misc_Spyglass_03",  motif = "radar",   order = 75, tab = "Intel",
                   title = "Intel (retired)", kicker = APP, tagline = "Retired: sightings and timers moved to the Events page" },
    Exchange   = { color = { 0.84, 0.60, 0.16 }, icon = "Interface\\Icons\\INV_Misc_Coin_02",      motif = "ledger",  order = 60, tab = "Market",
                   title = "Market", kicker = APP, tagline = "Every member's market knowledge, pooled" },
    Settings   = { color = { 0.33, 0.72, 0.85 }, icon = "Interface\\Icons\\Trade_Engineering",    motif = nil,       order = 99, tab = "Options",
                   title = "Options", kicker = APP, tagline = "Org key, chat and display" },
}
ns.THEMES.Org = ns.THEMES.Guild

local DEFAULT_THEME = { color = { 0.55, 0.58, 0.66 }, icon = "Interface\\Icons\\INV_Misc_QuestionMark", motif = nil, tagline = "" }

-- A module may pass its own theme in RegisterModule's info table.
function ns.ThemeFor(key, module)
    local t = (module and module.info and module.info.theme) or ns.THEMES[key]
    if t then return t end
    local copy = {}
    for k, v in pairs(DEFAULT_THEME) do copy[k] = v end
    copy.title = key
    return copy
end

local function animationsOn()
    return not ns.db or ns.db.settings.animations ~= false
end

local function tex(parent, layer, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function icon(parent, path, size, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(path)
    t:SetSize(size, size)
    return t
end

---------------------------------------------------------------------------
-- Motifs: each draws into a clipped box (about 250 x 60) on the header's
-- right and may return an OnUpdate function for ambient motion.
---------------------------------------------------------------------------
local MOTIFS = {}

-- Core: three hanging Alliance banners on a gold rod.
function MOTIFS.banners(box, t)
    local fields = { { 0.18, 0.36, 0.83 }, { 0.77, 0.12, 0.23 }, { 0.18, 0.36, 0.83 } }
    for i = 1, 3 do
        local x = 70 + (i - 1) * 50
        local rod = tex(box, "ARTWORK", 0.95, 0.78, 0.35, 1)
        rod:SetSize(36, 3)
        rod:SetPoint("TOPLEFT", x - 6, -5)
        local trim = tex(box, "ARTWORK", 0.85, 0.66, 0.28, 1)
        trim:SetSize(24, 46)
        trim:SetPoint("TOP", rod, "BOTTOM", 0, 0)
        local c = fields[i]
        local field = tex(box, "ARTWORK", c[1], c[2], c[3], 1, 1)
        field:SetSize(20, 44)
        field:SetPoint("TOP", trim, "TOP", 0, 0)
        local notch = tex(box, "ARTWORK", 0.03, 0.03, 0.05, 1, 2)
        notch:SetSize(15, 15)
        notch:SetRotation(math.pi / 4)
        notch:SetPoint("CENTER", trim, "BOTTOM", 0, -1)
        local crest = tex(box, "ARTWORK", 0.95, 0.78, 0.35, 1, 3)
        crest:SetSize(7, 7)
        crest:SetRotation(math.pi / 4)
        crest:SetPoint("CENTER", field, "CENTER", 0, 6)
    end
end

-- Finder: notes pinned to a tavern board.
function MOTIFS.board(box, t)
    local notes = { { 40, -8, -7 }, { 92, -5, 5 }, { 144, -10, -3 }, { 194, -6, 8 } }
    local c = t.color
    for _, n in ipairs(notes) do
        local paper = tex(box, "ARTWORK", 0.86, 0.79, 0.62, 0.95)
        paper:SetSize(40, 46)
        paper:SetPoint("TOPLEFT", n[1], n[2])
        paper:SetRotation(math.rad(n[3]))
        for l = 1, 3 do
            local line = tex(box, "ARTWORK", 0.38, 0.30, 0.22, 0.75, 1)
            line:SetSize(26 - l * 3, 2)
            line:SetPoint("TOPLEFT", paper, "TOPLEFT", 7, -12 - l * 8)
            line:SetRotation(math.rad(n[3]))
        end
        local pin = tex(box, "ARTWORK", c[1] + 0.15, c[2] + 0.1, c[3] + 0.1, 1, 2)
        pin:SetSize(7, 7)
        pin:SetRotation(math.pi / 4)
        pin:SetPoint("CENTER", paper, "TOP", 0, -4)
    end
end

-- Warfront: war stripes, crossed swords and rising embers.
function MOTIFS.war(box, t)
    local c = t.color
    for i = -2, 14 do
        local s = tex(box, "BACKGROUND", c[1], c[2], c[3], 0.28)
        s:SetSize(10, 150)
        s:SetPoint("CENTER", box, "LEFT", i * 22, 0)
        s:SetRotation(math.rad(32))
    end
    local swords = icon(box, "Interface\\Icons\\Ability_DualWield", 40)
    swords:SetPoint("RIGHT", -14, 0)
    local embers = {}
    for i = 1, 16 do
        local e = tex(box, "OVERLAY", 1, 0.55 + (i % 3) * 0.12, 0.15, 1)
        e:SetSize(2 + i % 2, 2 + i % 2)
        embers[i] = { tex = e, x = (i * 37) % 240, speed = 10 + (i * 7) % 18, phase = i * 0.37 }
    end
    return function(elapsed, time)
        for _, e in ipairs(embers) do
            local p = ((time * e.speed / 60) + e.phase) % 1
            e.tex:ClearAllPoints()
            e.tex:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", e.x + math.sin(time + e.phase * 9) * 4, p * 64)
            e.tex:SetAlpha((1 - p) * 0.9)
        end
    end
end

-- Pathfinder: a dotted trail from a start mark to an X, with a traveler.
function MOTIFS.trail(box, t)
    local pts = {}
    for i = 0, 22 do
        local x, y = 24 + i * 9.5, -32 + math.sin(i * 0.45) * 15
        local d = tex(box, "ARTWORK", 0.90, 0.84, 0.64, 0.8)
        d:SetSize(3, 3)
        d:SetPoint("CENTER", box, "TOPLEFT", x, y)
        pts[#pts + 1] = { x, y }
    end
    local start = tex(box, "ARTWORK", t.color[1] + 0.2, t.color[2] + 0.2, t.color[3] + 0.1, 1, 1)
    start:SetSize(9, 9)
    start:SetRotation(math.pi / 4)
    start:SetPoint("CENTER", box, "TOPLEFT", pts[1][1], pts[1][2])
    local last = pts[#pts]
    for _, a in ipairs({ 45, -45 }) do
        local bar = tex(box, "ARTWORK", 0.85, 0.15, 0.15, 1, 1)
        bar:SetSize(14, 3)
        bar:SetRotation(math.rad(a))
        bar:SetPoint("CENTER", box, "TOPLEFT", last[1] + 8, last[2])
    end
    local n = W.Label(box, "N", "GameFontNormalSmall")
    n:SetPoint("TOPRIGHT", -6, -4)
    local walker = tex(box, "OVERLAY", 1, 0.95, 0.6, 1)
    walker:SetSize(6, 6)
    return function(elapsed, time)
        local p = (time * 0.12) % 1
        local f = p * (#pts - 1) + 1
        local i = math.floor(f)
        local a, b = pts[i], pts[math.min(i + 1, #pts)]
        local k = f - i
        walker:ClearAllPoints()
        walker:SetPoint("CENTER", box, "TOPLEFT", a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k)
    end
end

-- Codex: a faint tome with a row of runes along each edge that pulse.
function MOTIFS.tome(box, t)
    local book = icon(box, "Interface\\Icons\\INV_Misc_Book_11", 52, "BACKGROUND")
    book:SetPoint("CENTER", 20, 0)
    book:SetAlpha(0.35)
    local runes = {}
    local c = t.color
    for i = 1, 12 do
        for _, y in ipairs({ -6, -54 }) do
            local r = tex(box, "ARTWORK", c[1] + 0.25, c[2] + 0.2, c[3] + 0.1, 1)
            r:SetSize(6, 6)
            r:SetRotation(math.pi / 4)
            r:SetPoint("CENTER", box, "TOPLEFT", 20 + i * 18, y)
            runes[#runes + 1] = { tex = r, phase = i * 0.5 + (y < -30 and 1.6 or 0) }
        end
    end
    return function(elapsed, time)
        for _, r in ipairs(runes) do
            r.tex:SetAlpha(0.35 + 0.65 * (0.5 + 0.5 * math.sin(time * 2 + r.phase)))
        end
    end
end

-- Exchange: a ledger page with a red margin and stacked coins.
function MOTIFS.ledger(box, t)
    local page = tex(box, "BACKGROUND", 0.86, 0.76, 0.52, 0.12)
    page:SetAllPoints()
    for i = 1, 6 do
        local line = tex(box, "ARTWORK", 0.75, 0.62, 0.35, 0.35)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", 0, -i * 9)
        line:SetPoint("TOPRIGHT", 0, -i * 9)
    end
    local margin = tex(box, "ARTWORK", 0.75, 0.18, 0.18, 0.6)
    margin:SetWidth(1)
    margin:SetPoint("TOPLEFT", 40, 0)
    margin:SetPoint("BOTTOMLEFT", 40, 0)
    local coins = { "INV_Misc_Coin_05", "INV_Misc_Coin_03", "INV_Misc_Coin_01" }
    for i, c in ipairs(coins) do
        local coin = icon(box, "Interface\\Icons\\" .. c, 26)
        coin:SetPoint("BOTTOMRIGHT", -14 - (i - 1) * 22, 8 + (i - 1) * 6)
    end
end

-- Muster: two flickering torches and a string of rally pennants.
function MOTIFS.torches(box, t)
    local c = t.color
    local rope = tex(box, "ARTWORK", 0.55, 0.42, 0.28, 0.9)
    rope:SetHeight(2)
    rope:SetPoint("TOPLEFT", 40, -12)
    rope:SetPoint("TOPRIGHT", -40, -12)
    for i = 1, 7 do
        local p = tex(box, "ARTWORK", c[1], c[2], c[3], 1, 1)
        p:SetSize(12, 12)
        p:SetRotation(math.pi / 4)
        p:SetPoint("CENTER", box, "TOPLEFT", 48 + i * 22, -20)
    end
    local flames = {}
    for _, side in ipairs({ { "BOTTOMLEFT", 16 }, { "BOTTOMRIGHT", -16 } }) do
        local stick = tex(box, "ARTWORK", 0.40, 0.26, 0.14, 1)
        stick:SetSize(4, 26)
        stick:SetPoint(side[1], side[2], 4)
        local glow = tex(box, "BACKGROUND", 1, 0.55, 0.15, 0.35)
        glow:SetSize(40, 40)
        glow:SetPoint("BOTTOM", stick, "TOP", 0, -14)
        local flame = tex(box, "ARTWORK", 1, 0.75, 0.25, 1, 1)
        flame:SetSize(8, 12)
        flame:SetRotation(math.pi / 4)
        flame:SetPoint("BOTTOM", stick, "TOP", 0, -2)
        flames[#flames + 1] = { glow = glow, flame = flame, phase = side[2] }
    end
    return function(elapsed, time)
        for _, f in ipairs(flames) do
            local k = 0.5 + 0.25 * math.sin(time * 11 + f.phase) + 0.25 * math.sin(time * 17.3 + f.phase * 2)
            f.glow:SetAlpha(0.2 + 0.25 * k)
            f.flame:SetAlpha(0.7 + 0.3 * k)
        end
    end
end

-- Intel: a radar with rings, a sweeping beam and blips that flare as it passes.
function MOTIFS.radar(box, t)
    local c = t.color
    local cx, cy = 180, -30
    for _, r in ipairs({ 10, 19, 28 }) do
        for i = 1, 20 do
            local a = i / 20 * 2 * math.pi
            local d = tex(box, "ARTWORK", c[1], c[2], c[3], 0.45)
            d:SetSize(2, 2)
            d:SetPoint("CENTER", box, "TOPLEFT", cx + r * math.cos(a), cy + r * math.sin(a))
        end
    end
    local beam = tex(box, "OVERLAY", c[1] + 0.2, c[2] + 0.2, c[3], 0.9)
    beam:SetSize(28, 2)
    local blips = {}
    for i, b in ipairs({ { 0.9, 16 }, { 2.6, 24 }, { 4.4, 11 } }) do
        local d = tex(box, "OVERLAY", 1, 0.3, 0.3, 1)
        d:SetSize(4, 4)
        d:SetPoint("CENTER", box, "TOPLEFT", cx + b[2] * math.cos(b[1]), cy + b[2] * math.sin(b[1]))
        blips[i] = { tex = d, angle = b[1] }
    end
    local scan = W.Label(box, "SCANNING", "GameFontDisableSmall")
    scan:SetPoint("LEFT", 20, -4)
    return function(elapsed, time)
        local a = (time * 1.6) % (2 * math.pi)
        beam:ClearAllPoints()
        beam:SetPoint("CENTER", box, "TOPLEFT", cx + 14 * math.cos(a), cy + 14 * math.sin(a))
        beam:SetRotation(-a)
        for _, b in ipairs(blips) do
            local behind = (a - b.angle) % (2 * math.pi)
            b.tex:SetAlpha(math.max(0.1, 1 - behind / 2.5))
        end
        scan:SetAlpha(0.5 + 0.5 * math.sin(time * 3))
    end
end

---------------------------------------------------------------------------
-- Page header
---------------------------------------------------------------------------
-- Builds the themed header at the top of `page` and returns its height:
-- a navy band, the page icon in a ring of its color, a small kicker naming
-- the addon, the page title and tagline, and the page's animated scene.
function W.PageHeader(page, theme)
    local HEIGHT = 66
    local c = theme.color
    local P = W.PALETTE
    local h = CreateFrame("Frame", nil, page)
    h:SetPoint("TOPLEFT")
    h:SetPoint("TOPRIGHT")
    h:SetHeight(HEIGHT)

    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and bg.SetGradient and pcall(bg.SetGradient, bg, "HORIZONTAL",
        CreateColor(P.panelHi[1] + c[1] * 0.10, P.panelHi[2] + c[2] * 0.10, P.panelHi[3] + c[3] * 0.10, 1),
        CreateColor(P.bg[1], P.bg[2], P.bg[3], 1))
    if not ok then bg:SetColorTexture(P.panelHi[1], P.panelHi[2], P.panelHi[3], 1) end

    local ring = h:CreateTexture(nil, "ARTWORK")
    ring:SetSize(48, 48)
    ring:SetPoint("LEFT", 12, 0)
    ring:SetColorTexture(c[1], c[2], c[3], 1)
    pcall(ring.SetMask, ring, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    local ico = icon(h, theme.icon, 44, "OVERLAY")
    ico:SetPoint("CENTER", ring, "CENTER", 0, 0)
    pcall(ico.SetMask, ico, "Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local kicker = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    kicker:SetText((theme.kicker or "RUIN"):upper())
    kicker:SetTextColor(P.gold[1], P.gold[2], P.gold[3])
    kicker:SetPoint("TOPLEFT", ring, "TOPRIGHT", 12, 2)

    local title = h:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(GameFontNormalHuge)        -- fallback if the font file can't load
    title:SetFont(BODY_FONT, 20, "")
    title:SetTextColor(P.text[1], P.text[2], P.text[3])
    title:SetShadowOffset(1, -1)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetText(theme.title or "")
    title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -2)

    local tag = h:CreateFontString(nil, "OVERLAY")
    tag:SetFontObject(GameFontHighlightSmall)
    tag:SetFont(BODY_FONT, 11, "")
    tag:SetTextColor(P.sub[1], P.sub[2], P.sub[3])
    tag:SetText(theme.tagline or "")
    tag:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -3)

    local rule = tex(h, "ARTWORK", P.border[1], P.border[2], P.border[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    local accent = tex(h, "OVERLAY", c[1], c[2], c[3], 1)
    accent:SetSize(72, 2)
    accent:SetPoint("BOTTOMLEFT", 0, 0)

    local draw = theme.motif and MOTIFS[theme.motif]
    if draw then
        local box = CreateFrame("Frame", nil, h)
        box:SetSize(250, HEIGHT - 6)
        box:SetPoint("TOPRIGHT", -4, -2)
        box:SetAlpha(0.75)
        if box.SetClipsChildren then box:SetClipsChildren(true) end
        local ok2, animate = pcall(draw, box, theme)
        if ok2 and type(animate) == "function" then
            local clock = 0
            box:SetScript("OnUpdate", function(_, elapsed)
                if not animationsOn() then return end
                clock = clock + (elapsed or 0)
                animate(elapsed, clock)
            end)
        elseif not ok2 then
            ns:Debug("header scene failed: " .. tostring(animate))
        end
    end
    return HEIGHT
end
