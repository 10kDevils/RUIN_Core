-- RUIN Core: page themes
-- Each page gets a header in its module's colors: the module's badge, the
-- page title and tagline, and a line drawing on the right that says what the
-- module is about (banners for Guild, a route for Pathfinder, a price chart
-- for Exchange...). The badges, tab glyphs and drawings are RUIN's own art
-- in Media/ (drawn by tools/art/make_art.py); a module that brings its own
-- theme with a game icon still gets a header from that.
local ADDON, ns = ...
local W = ns.Widgets

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"

-- Pages are named after their module (Codex, Pathfinder, ...), with the app's
-- name above the title. tab/order: the label and place of the page's tab
-- along the top of the window (Options always last).
local APP = "RUIN Gaming Companion App"
ns.APP_NAME = APP
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
-- icon:  the module's badge (its glyph on a dark tile edged in its color)
-- glyph: the glyph alone, white, tinted wherever it's drawn (tabs)
-- art:   the header's line drawing; motif names the motion drawn over it
ns.THEMES = {
    Codex      = { color = { 0.54, 0.32, 0.84 }, icon = MEDIA .. "BadgeCodex", glyph = MEDIA .. "IconCodex", art = MEDIA .. "ArtCodex",
                   motif = "tome", order = 50, tab = "Codex",
                   title = "Codex", kicker = APP, tagline = "Class macros, macro commands, and a dungeon and raid journal with boss loot" },
    Pathfinder = { color = { 0.31, 0.60, 0.23 }, icon = MEDIA .. "BadgePathfinder", glyph = MEDIA .. "IconPathfinder", art = MEDIA .. "ArtPathfinder",
                   motif = "trail", order = 40, tab = "Pathfinder",
                   title = "Pathfinder", kicker = APP, tagline = "Leveling routes and your quests, with the rest of RUIN" },
    Guild      = { color = { 0.90, 0.72, 0.38 }, icon = MEDIA .. "BadgeGuild", tabIcon = ns.Brand.ICON, art = MEDIA .. "ArtGuild",
                   motif = "banners", order = 10, tab = "Guild",
                   title = "Guild & Community", kicker = APP, tagline = "Who's online, guild news and RUIN's links", core = true },
    Finder     = { color = { 0.82, 0.31, 0.54 }, icon = MEDIA .. "BadgeFinder", glyph = MEDIA .. "IconFinder", art = MEDIA .. "ArtFinder",
                   motif = "board", order = 20, tab = "Finder",
                   title = "Finder", kicker = APP, tagline = "Find people in RUIN to group with, right now" },
    Muster     = { color = { 0.85, 0.38, 0.17 }, icon = MEDIA .. "BadgeMuster", glyph = MEDIA .. "IconMuster", art = MEDIA .. "ArtMuster",
                   motif = "torches", order = 30, tab = "Muster",
                   title = "Muster", kicker = APP, tagline = "Events, rallies, bounties and world sightings" },
    Warfront   = { color = { 0.77, 0.12, 0.23 }, icon = "Interface\\Icons\\INV_BannerPVP_01",      motif = "war",     order = 70, tab = "Warfront",
                   title = "Warfront (retired)", kicker = APP, tagline = "Retired: use Overlord Forever and RUIN Muster" },
    Intel      = { color = { 0.22, 0.71, 0.91 }, icon = "Interface\\Icons\\INV_Misc_Spyglass_03",  motif = "radar",   order = 75, tab = "Intel",
                   title = "Intel (retired)", kicker = APP, tagline = "Retired: sightings and timers moved to RUIN Muster" },
    Planner    = { color = { 0.36, 0.62, 0.78 }, icon = MEDIA .. "BadgePlanner", glyph = MEDIA .. "IconPlanner", art = MEDIA .. "ArtPathfinder",
                   motif = "trail", order = 45, tab = "Planner",
                   title = "Planner", kicker = APP, tagline = "Ruinous Forever Planner: your next steps, gear and goals, shared with RUIN" },
    Exchange   = { color = { 0.84, 0.60, 0.16 }, icon = MEDIA .. "BadgeExchange", glyph = MEDIA .. "IconExchange", art = MEDIA .. "ArtExchange",
                   motif = "ledger", order = 60, tab = "Exchange",
                   title = "Exchange", kicker = APP, tagline = "Auction prices, crafters and craft requests across RUIN" },
    Settings   = { color = { 0.33, 0.72, 0.85 }, icon = MEDIA .. "BadgeSettings", glyph = MEDIA .. "IconSettings", art = MEDIA .. "ArtSettings",
                   motif = "gears", order = 99, tab = "Settings",
                   title = "Settings", kicker = APP, tagline = "Your org key, options and feedback", core = true },
}
ns.THEMES.Org = ns.THEMES.Guild

-- Color a button that opens another addon (Codex's "Post in Muster", "Quest
-- route" to Pathfinder) with that addon's color; pass nil to make it plain again.
function W.LinkTo(b, addon)
    if not b then return b end
    local t = addon and ns.THEMES[addon]
    b.linkColor = t and t.color or nil
    if b.hl then
        local c = b.linkColor or W.SchemeOf(b).accent
        b.hl:SetColorTexture(c[1], c[2], c[3], 0.08)
    end
    if W.PaintButton then W.PaintButton(b) end
    return b
end

-- "|cffRRGGBB" in an addon's color, for text that leads into that addon.
function W.AddonHex(addon)
    local t = ns.THEMES[addon]
    local c = t and t.color or { 1, 1, 1 }
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

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
-- Motifs. A page with art (theme.art) shows that drawing, 256 x 64, on the
-- right of its header; its motif may add a little motion over it and returns
-- an OnUpdate function. The box's top left is the drawing's top left, so
-- positions here match tools/art/make_art.py. Pages without art (retired
-- ones, a module's own theme) draw their whole scene from plain textures.
---------------------------------------------------------------------------
local MOTIFS = {}
local ART_W, ART_H = 256, 64

-- a small bright dot that travels along a list of points, there and back never: it loops
local function runner(box, pts, color, speed, size)
    local dot = tex(box, "OVERLAY", color[1], color[2], color[3], 1)
    dot:SetSize(size or 5, size or 5)
    dot:SetRotation(math.pi / 4)
    local halo = tex(box, "ARTWORK", color[1], color[2], color[3], 0.25)
    halo:SetSize((size or 5) + 6, (size or 5) + 6)
    halo:SetRotation(math.pi / 4)
    local function place(p)
        local f = p * (#pts - 1) + 1
        local i = math.floor(f)
        local a, b = pts[i], pts[math.min(i + 1, #pts)]
        local k = f - i
        local x, y = a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k
        dot:ClearAllPoints(); dot:SetPoint("CENTER", box, "TOPLEFT", x, -y)
        halo:ClearAllPoints(); halo:SetPoint("CENTER", box, "TOPLEFT", x, -y)
    end
    place(0.35)
    return function(_, time) place((time * speed) % 1) end
end

-- small lights that brighten and dim in turn
local function twinkles(box, spots, color, size)
    local lights = {}
    for i, sp in ipairs(spots) do
        local t = tex(box, "OVERLAY", color[1], color[2], color[3], 1)
        t:SetSize(size or 4, size or 4)
        t:SetRotation(math.pi / 4)
        t:SetPoint("CENTER", box, "TOPLEFT", sp[1], -sp[2])
        t:SetAlpha(0.55)
        lights[i] = { tex = t, phase = i * 1.7 }
    end
    return function(_, time)
        for _, l in ipairs(lights) do l.tex:SetAlpha(0.25 + 0.75 * (0.5 + 0.5 * math.sin(time * 1.6 + l.phase))) end
    end
end

local function bright(t) return W.Mix(t.color, { 1, 1, 1 }, 0.55) end

-- Pathfinder (and the Planner): a traveler on the dotted route.
function MOTIFS.trail(box, t)
    local pts = {}
    for i = 0, 22 do pts[#pts + 1] = { 98 + i * 6.6, 32 - math.sin(i * 0.45) * 15 } end
    return runner(box, pts, { 1, 0.95, 0.62 }, 0.10, 5)
end

-- Exchange: the latest price moving along the trend line.
function MOTIFS.ledger(box, t)
    local pts = {}
    for i = 0, 13 do pts[#pts + 1] = { 70 + 13 * i, 46 - i * 1.9 + 5.5 * math.sin(i * 0.9) - 9 } end
    return runner(box, pts, bright(t), 0.07, 5)
end

-- Finder: the players you found light up in turn.
function MOTIFS.board(box, t)
    return twinkles(box, { { 206, 31 }, { 150, 20 }, { 176, 48 }, { 232, 14 } }, bright(t), 5)
end

-- Codex: the circle's heart and the points of its star glow in turn.
function MOTIFS.tome(box, t)
    local spots = { { 208, 32 } }
    for k = 0, 5 do
        local a = math.rad(-90 + k * 60)
        spots[#spots + 1] = { 208 + 21.5 * math.cos(a), 32 + 21.5 * math.sin(a) }
    end
    return twinkles(box, spots, bright(t), 4)
end

-- Muster: lanterns on the two poles.
function MOTIFS.torches(box, t)
    local flames = {}
    for i, x in ipairs({ 96, 250 }) do
        local glow = tex(box, "ARTWORK", 1, 0.62, 0.22, 0.30)
        glow:SetSize(16, 16)
        glow:SetRotation(math.pi / 4)
        glow:SetPoint("CENTER", box, "TOPLEFT", x, -4)
        local flame = tex(box, "OVERLAY", 1, 0.82, 0.40, 1)
        flame:SetSize(5, 5)
        flame:SetRotation(math.pi / 4)
        flame:SetPoint("CENTER", box, "TOPLEFT", x, -4)
        flames[i] = { glow = glow, flame = flame, phase = i * 2.3 }
    end
    return function(_, time)
        for _, f in ipairs(flames) do
            local k = 0.5 + 0.25 * math.sin(time * 11 + f.phase) + 0.25 * math.sin(time * 17.3 + f.phase * 2)
            f.glow:SetAlpha(0.15 + 0.30 * k)
            f.flame:SetAlpha(0.70 + 0.30 * k)
        end
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
-- Builds the themed header at the top of `page` and returns its height: a
-- band washed in the page's color, the module's badge, a small kicker naming
-- the app, the page title and tagline, and the page's drawing on the right.
function W.PageHeader(page, theme)
    local HEIGHT = 66
    local c = theme.color
    local P = W.PALETTE
    local scheme = W.SchemeFor(theme)
    local ac = scheme.accent
    local h = CreateFrame("Frame", nil, page)
    h:SetPoint("TOPLEFT")
    h:SetPoint("TOPRIGHT")
    h:SetHeight(HEIGHT)

    -- the band: the page's color on the left, falling away to the window's navy
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 1)
    local left = W.Mix(P.panelHi, c, 0.16)
    local ok = CreateColor and bg.SetGradient and pcall(bg.SetGradient, bg, "HORIZONTAL",
        CreateColor(left[1], left[2], left[3], 1), CreateColor(P.bg[1], P.bg[2], P.bg[3], 1))
    if not ok then bg:SetColorTexture(P.panelHi[1], P.panelHi[2], P.panelHi[3], 1) end
    -- a soft light along the top edge
    local lift = h:CreateTexture(nil, "BACKGROUND", nil, 1)
    lift:SetPoint("TOPLEFT"); lift:SetPoint("TOPRIGHT")
    lift:SetHeight(22)
    lift:SetColorTexture(1, 1, 1, 1)
    if not (CreateColor and lift.SetGradient and pcall(lift.SetGradient, lift, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.045))) then
        lift:SetColorTexture(1, 1, 1, 0.02)
    end

    -- the badge: RUIN's own art is drawn as it is; a game icon gets a ring in the page's color
    local badge
    local own = type(theme.icon) == "string" and theme.icon:find("RUIN_Core", 1, true)
    if own then
        badge = icon(h, theme.icon, 46, "ARTWORK")
        badge:SetPoint("LEFT", 12, 0)
    else
        badge = h:CreateTexture(nil, "ARTWORK")
        badge:SetSize(46, 46)
        badge:SetPoint("LEFT", 12, 0)
        badge:SetColorTexture(c[1], c[2], c[3], 1)
        pcall(badge.SetMask, badge, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
        local ico = icon(h, theme.icon, 42, "OVERLAY")
        ico:SetPoint("CENTER", badge, "CENTER", 0, 0)
        pcall(ico.SetMask, ico, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    end

    local kicker = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    kicker:SetText((theme.kicker or "RUIN"):upper())
    kicker:SetTextColor(P.gold[1], P.gold[2], P.gold[3], 0.9)
    kicker:SetPoint("TOPLEFT", badge, "TOPRIGHT", 12, 1)

    local title = h:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(GameFontNormalHuge)        -- fallback if the font file can't load
    title:SetFont(BODY_FONT, 20, "")
    title:SetTextColor(1, 1, 1)
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

    local edge = scheme.edge
    local rule = tex(h, "ARTWORK", edge[1], edge[2], edge[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    local accent = tex(h, "OVERLAY", ac[1], ac[2], ac[3], 1)
    accent:SetSize(120, 2)
    accent:SetPoint("BOTTOMLEFT", 0, 0)

    -- the drawing, in the page's color, with whatever moves on top of it
    local draw = theme.motif and MOTIFS[theme.motif]
    if theme.art or draw then
        local box = CreateFrame("Frame", nil, h)
        box:SetSize(ART_W, ART_H)
        box:SetPoint("RIGHT", -2, 0)
        if box.SetClipsChildren then box:SetClipsChildren(true) end
        if theme.art then
            local art = box:CreateTexture(nil, "BACKGROUND")
            art:SetAllPoints()
            art:SetTexture(theme.art)
            art:SetVertexColor(ac[1], ac[2], ac[3], 0.70)
            h.art = art
        else
            box:SetAlpha(0.75)
        end
        if draw then
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
    end
    return HEIGHT
end
