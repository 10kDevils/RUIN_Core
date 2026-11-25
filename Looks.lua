-- RUIN Core: the looks Pathfinder can give the game's own frames (the
-- minimap, the objective tracker, the world map and quest log) and its
-- waypoint: the game's own (Blizzard), or the suite's modern style in one of
-- its colors. RUIN wears the core app's navy and gold; Ink gold on ink, as
-- the waypoint always has; the others their module's color, as the
-- module's pages do.
local ADDON, ns = ...
local R = RUIN_API
if not R then return end
local W = R.Widgets

local L = {}
ns.Looks = L

L.KEYS = { "blizzard", "core", "ruin", "pathfinder", "finder", "muster", "codex", "exchange" }
L.MODERN = { "core", "ruin", "pathfinder", "finder", "muster", "codex", "exchange" }
-- (the keys stay as saved: "core" is the RUIN look, "ruin" is Ink)
L.LABEL = { blizzard = "Blizzard", ruin = "Ink", core = "RUIN", pathfinder = "Pathfinder", finder = "Finder",
            muster = "Muster", codex = "Codex", exchange = "Exchange" }

local GOLD = { 0.90, 0.72, 0.38 }
local INK = { 0.035, 0.045, 0.075 }
local INK_BLACK = { 0.010, 0.010, 0.013 }     -- the Ink look's background
L.GOLD, L.INK = GOLD, INK
local COLOR = {
    ruin = GOLD,
    core = GOLD,
    pathfinder = { 0.31, 0.60, 0.23 },
    finder = { 0.82, 0.31, 0.54 },
    muster = { 0.85, 0.38, 0.17 },
    codex = { 0.54, 0.32, 0.84 },
    exchange = { 0.84, 0.60, 0.16 },
}

-- Edge a frame like the game's tooltips (the Blizzard look), or take the
-- edge off again.
local TIP_EDGE = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } }
function L.GameEdge(f, on)
    if not f then return end
    local e = f.ruinGameEdge
    if on and not e then
        local ok, made = pcall(CreateFrame, "Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
        if not ok or not made then return end
        e = made
        e:SetAllPoints(f)
        if e.EnableMouse then e:EnableMouse(false) end
        if e.SetFrameLevel and f.GetFrameLevel then e:SetFrameLevel(f:GetFrameLevel() or 1) end
        if e.SetBackdrop then
            pcall(e.SetBackdrop, e, TIP_EDGE)
            -- WoW Forever's bronze, as on its minimap ring and unit frames
            if e.SetBackdropBorderColor then pcall(e.SetBackdropBorderColor, e, 0.80, 0.58, 0.30, 1) end
        end
        f.ruinGameEdge = e
    end
    if e then e:SetShown(on and true or false) end
end

-- A background that sits inside the game's rounded edge (so its square
-- corners don't poke out past it), or fills the frame again.
function L.FitInside(bg, frame, on)
    if not (bg and frame and bg.ClearAllPoints) then return end
    bg:ClearAllPoints()
    if on then
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
        bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    else
        bg:SetAllPoints(frame)
    end
end

local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
L.Mix = mix

function L.Valid(key) return COLOR[key] ~= nil or key == "blizzard" end
function L.Modern(key) return COLOR[key] ~= nil end

-- A look's theme (what a frame's ruinTheme is set to, so the suite's skins
-- color it) and its scheme (accent, edge, bg...).
local themes, schemes = {}, {}
-- The game's own look, for Pathfinder's own frames (the tracker, the
-- waypoint): a warm near-black edged in WoW Forever's bronze, in the game's gold.
local BLIZZ = { 1, 0.82, 0 }
function L.Theme(key)
    if key == "blizzard" then
        themes.blizzard = themes.blizzard or { color = BLIZZ, core = true, look = true }
        return themes.blizzard
    end
    key = COLOR[key] and key or "pathfinder"
    themes[key] = themes[key] or { color = COLOR[key], core = (key == "ruin" or key == "core") or nil, look = true }
    return themes[key]
end

function L.Scheme(key)
    if key == "blizzard" then
        -- WoW Forever's own: bronze edges and gold on a warm near-black
        schemes.blizzard = schemes.blizzard or { accent = BLIZZ, color = { 0.22, 0.15, 0.07 }, bg = { 0.035, 0.026, 0.016 },
            edge = { 0.80, 0.58, 0.30 }, ink = { 0.05, 0.036, 0.022 }, panel = { 0.05, 0.036, 0.022 }, panelHi = { 0.10, 0.075, 0.045 },
            mark = BLIZZ, core = true, blizzard = true }
        return schemes.blizzard
    end
    key = COLOR[key] and key or "pathfinder"
    if schemes[key] then return schemes[key] end
    local base = W.SchemeFor and W.SchemeFor(L.Theme(key)) or { accent = COLOR[key], edge = { 0.2, 0.25, 0.3 }, bg = INK }
    local s = {}
    for k, v in pairs(base) do s[k] = v end
    s.color = COLOR[key]
    if key == "ruin" then
        -- Ink: plain gold on a near-black, with only a breath of gold in its gradient
        s.accent = GOLD
        s.bg = INK_BLACK
        s.color = mix(INK_BLACK, GOLD, 0.35)
        s.edge = mix(base.edge or { 0.2, 0.25, 0.3 }, GOLD, 0.35)
    end
    if key == "core" then
        -- the core app's own: gold on its navy panels, a blue cast to the gradient
        local P = W.RUIN_PALETTE or W.PALETTE or {}
        s.accent = P.gold or GOLD
        s.bg = P.bg or { 0.04, 0.06, 0.11 }
        s.edge = P.border or { 0.2, 0.26, 0.38 }
        s.color = { 0.20, 0.34, 0.62 }
        s.ink = { 0.05, 0.08, 0.16 }
        schemes[key] = s
        return s
    end
    -- the waypoint's card: ink, tinted faintly in the look's color
    s.ink = key == "ruin" and INK_BLACK or mix(INK, COLOR[key], 0.10)
    schemes[key] = s
    return s
end
