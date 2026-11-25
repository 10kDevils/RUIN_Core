-- RUIN Core: the game's objective tracker, in the game's own look or
-- in Pathfinder's, the minimap's design language: a panel behind it in the
-- suite's HUD look (its edges, the accent band along the top, a slight green
-- to black gradient at the opacity you pick), headers in Pathfinder's color
-- with a short rule beneath, quest titles in the suite's white, objectives in
-- its quieter grey with an accent dash, finished ones in green.
-- Only colors and the panel change: the game still lays the tracker out,
-- sizes its text and handles its buttons.
local ADDON, ns = ...
local R = RUIN_API
if not R then return end
local W = R.Widgets
local MM = ns.Minimap

local OT = {}
ns.Objectives = OT

local L = ns.Looks
OT.STYLES = L.KEYS
OT.STYLE_LABEL = L.LABEL

local PAD = 8
local TITLE = { 1, 1, 1 }           -- quest names: bright, with a firm shadow
local LINE = { 0.60, 0.64, 0.70 }   -- objectives: quieter, so the names lead
local DONE = { 0.52, 0.84, 0.48 }

local db
local back             -- the panel behind the tracker
local styled = {}      -- fontstring -> true: colored by Pathfinder
local rules = {}       -- module header -> its accent rule

local function tracker() return rawget(_G, "ObjectiveTrackerFrame") end

function OT.Style()
    local s = db and db.otStyle
    return (s and L.Valid(s)) and s or "blizzard"
end
local function modern() return OT.Style() ~= "blizzard" end
OT.Modern = modern
function OT.Scheme() local s = OT.Style(); return L.Scheme(s ~= "blizzard" and s or "pathfinder") end
function OT.Theme() local s = OT.Style(); return L.Theme(s ~= "blizzard" and s or "pathfinder") end
-- the colors the icon being drawn takes (its owner's look)
local CUR
local function sch() return CUR or OT.Scheme() end
function OT.Alpha() return (db and db.otAlpha) or 0.85 end

local function accent() return OT.Scheme().accent end

local function color(fs, c)
    if type(fs) ~= "table" or not fs.SetTextColor then return end
    styled[fs] = true
    fs:SetTextColor(c[1], c[2], c[3])
end

local function shown(f) return type(f) == "table" and (f.IsShown == nil or f:IsShown()) end
local function visible(x)
    if type(x) ~= "table" then return false end
    if x.IsVisible then return x:IsVisible() end
    return x.IsShown == nil or x:IsShown()
end

---------------------------------------------------------------------------
-- Icons: the game's quest markers, collapse buttons, item buttons and
-- check marks drawn in Pathfinder's flat style (Media\Modern*.tga). The
-- game's buttons stay where they are, unseen, and still take the clicks.
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\RUIN_Core\\Media\\Modern"
local GOLD = { 1, 0.82, 0.32 }
local GREY = { 0.80, 0.83, 0.88 }
local skins = {}        -- game button -> { kind, overlay }
local checks = {}       -- check-mark texture -> its own art, to give back

local function tex(f, name, layer, sub)
    local t = f:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    t:SetTexture(MEDIA .. name)
    return t
end

local function overlay(btn, owner)
    local o = CreateFrame("Frame", nil, (owner == "tracker" and tracker()) or btn:GetParent() or UIParent)
    if o.SetFrameStrata and btn.GetFrameStrata then o:SetFrameStrata(btn:GetFrameStrata() or "MEDIUM") end
    if o.SetFrameLevel then o:SetFrameLevel(((btn.GetFrameLevel and btn:GetFrameLevel()) or 1) + 3) end
    if o.EnableMouse then o:EnableMouse(false) end
    o:SetAllPoints(btn)
    return o
end

local function hovered(btn) return btn.IsMouseOver and btn:IsMouseOver() or false end

-- What a quest marker says: ? to hand in, ... under way, ! not started.
local function questState(btn)
    local q = btn.questID or (btn.GetQuestID and btn:GetQuestID())
    local style = btn.GetStyle and btn:GetStyle()
    local S = rawget(_G, "POIButtonUtil") and POIButtonUtil.Style
    local done = (q and C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(q))
        or (S and style ~= nil and style == S.QuestComplete)
    local picked = (btn.GetSelected and btn:GetSelected())
        or (q and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() == q)
    local off = S and style ~= nil and style == S.QuestDisabled
    return done and "done" or (off and "off" or "busy"), picked
end

local PAINT = {}
function PAINT.poi(btn, o)
    if not o.disc then
        o.disc = tex(o, "Disc", "ARTWORK", 0); o.disc:SetAllPoints()
        o.ring = tex(o, "Ring", "ARTWORK", 1); o.ring:SetAllPoints()
        o.glyph = tex(o, "Dots", "ARTWORK", 2)
        o.glyph:SetPoint("TOPLEFT", o, "TOPLEFT", 4, -4)
        o.glyph:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -4, 4)
    end
    local sc, state, picked = sch(), questState(btn)
    local a = sc.accent
    o.glyph:SetTexture(MEDIA .. (state == "done" and "Question" or "Dots"))
    local glyph = state == "done" and GOLD or GREY
    if picked then
        o.disc:SetVertexColor(a[1], a[2], a[3], 1)
        o.ring:SetVertexColor(1, 1, 1, hovered(btn) and 0.9 or 0.5)
        o.glyph:SetVertexColor(0.05, 0.07, 0.06, 1)
    else
        o.disc:SetVertexColor(sc.bg[1], sc.bg[2], sc.bg[3], 0.95)
        if hovered(btn) then o.ring:SetVertexColor(1, 1, 1, 1) elseif state == "off" then o.ring:SetVertexColor(0.45, 0.48, 0.52, 1) else o.ring:SetVertexColor(a[1], a[2], a[3], 1) end
        o.glyph:SetVertexColor(glyph[1], glyph[2], glyph[3], 1)
    end
end
function PAINT.collapse(btn, o)
    if not o.glyph then
        o.glyph = tex(o, "Minus")
        o.glyph:SetPoint("CENTER")
        o.glyph:SetSize(12, 12)
    end
    local owner = btn:GetParent() and btn:GetParent():GetParent()
    local shut = owner and ((owner.IsCollapsed and owner:IsCollapsed()) or owner.collapsed or owner.isCollapsed)
    -- the game's own art says it best: a plus (or "expand") when shut
    local art = btn.Icon or btn.icon or (btn.GetNormalTexture and btn:GetNormalTexture())
    local atlas = type(art) == "table" and art.GetAtlas and art:GetAtlas()
    if type(atlas) == "string" then
        atlas = atlas:lower()
        if atlas:find("plus") or atlas:find("expand") then shut = true
        elseif atlas:find("minus") or atlas:find("collapse") then shut = false end
    end
    o.glyph:SetTexture(MEDIA .. (shut and "Plus" or "Minus"))
    local c = hovered(btn) and { 1, 1, 1 } or sch().accent
    o.glyph:SetVertexColor(c[1], c[2], c[3], 1)
end
function PAINT.item(btn, o)
    if not o.slot then
        o.slot = tex(o, "Slot")
        o.slot:SetPoint("TOPLEFT", -2, 2)
        o.slot:SetPoint("BOTTOMRIGHT", 2, -2)
    end
    local c = hovered(btn) and sch().accent or (W.BTN_EDGE or { 0.3, 0.34, 0.38 })
    o.slot:SetVertexColor(c[1], c[2], c[3], 1)
end
function PAINT.arrow(btn, o)
    if not o.glyph then
        o.glyph = tex(o, "Chevron")
        o.glyph:SetPoint("CENTER")
        o.glyph:SetSize(12, 12)
    end
    local c = hovered(btn) and { 1, 1, 1 } or sch().accent
    o.glyph:SetVertexColor(c[1], c[2], c[3], 1)
end

local function paint(btn)
    local s = skins[btn]
    if not s then return end
    s.overlay:SetShown(visible(btn) and s.on())
    if s.overlay:IsShown() then
        CUR = s.scheme()
        PAINT[s.kind](btn, s.overlay)
        CUR = nil
    end
end

local function itemArt(btn) return btn.icon or btn.Icon or btn.IconTexture end

-- Take a game button into Pathfinder's look.
local function skin(btn, kind, owner, on, schemeFn)
    owner = owner or "tracker"
    local s = skins[btn]
    if not s then
        s = { kind = kind, owner = owner, overlay = overlay(btn, owner), on = on or modern, scheme = schemeFn or OT.Scheme }
        skins[btn] = s
        if btn.HookScript and not btn.ruinOTHook then
            btn.ruinOTHook = true
            btn:HookScript("OnEnter", function(b) paint(b) end)
            btn:HookScript("OnLeave", function(b) paint(b) end)
            btn:HookScript("OnShow", function(b) paint(b) end)
            btn:HookScript("OnHide", function(b) paint(b) end)
        end
    end
    if kind == "item" then
        local n = btn.GetNormalTexture and btn:GetNormalTexture()
        if n then MM.Dim(n, true) end
        local art = itemArt(btn)
        if art and art.SetTexCoord then art:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    else
        MM.Dim(btn, true, true)          -- unseen, but still takes the clicks
    end
    paint(btn)
end

local function unskin(btn, s)
    s.overlay:Hide()
    if s.kind == "item" then
        local n = btn.GetNormalTexture and btn:GetNormalTexture()
        if n then MM.Dim(n, false) end
        local art = itemArt(btn)
        if art and art.SetTexCoord then art:SetTexCoord(0, 1, 0, 1) end
    else
        MM.Dim(btn, false)
    end
end

-- A finished objective's check mark, in Pathfinder's.
local function skinCheck(t)
    if type(t) ~= "table" or not t.SetTexture then return end
    if not checks[t] then
        checks[t] = { atlas = t.GetAtlas and t:GetAtlas(), file = t.GetTexture and t:GetTexture() }
    end
    t:SetTexture(MEDIA .. "Check")
    t:SetVertexColor(DONE[1], DONE[2], DONE[3], 1)
end

local function unskinCheck(t, was)
    t:SetVertexColor(1, 1, 1, 1)
    if was.atlas and t.SetAtlas then t:SetAtlas(was.atlas) elseif was.file then t:SetTexture(was.file) end
end

-- Which kind of game button this is, if one Pathfinder redraws.
local function kindOf(x, inBlock)
    local t = x.GetObjectType and x:GetObjectType()
    if t ~= "Button" and t ~= "CheckButton" then return nil end
    local w = x.GetWidth and x:GetWidth() or 0
    if (x.questID ~= nil or (x.GetStyle and x.Display)) and w <= 40 then return "poi" end
    if itemArt(x) and (x.itemLink ~= nil or x.charges ~= nil or x.questLogIndex ~= nil or x.SetItem or x.UpdateItem) then return "item" end
    local name = tostring((x.GetName and x:GetName()) or ""):lower()
    if name:find("minimize") or name:find("collapse") then return "collapse" end
    if inBlock then
        if w > 0 and w <= 26 and not (x.GetText and x:GetText() and x:GetText() ~= "") then return "arrow" end
    end
end
OT.KindOf = kindOf
OT.PAINT = PAINT
OT.MEDIA = MEDIA

-- For Pathfinder's other skins (the world map): redraw a game button in
-- this style under an owner's name, and give an owner's buttons back.
function OT.SkinButton(btn, kind, owner, on, schemeFn) if type(btn) == "table" and btn.GetObjectType then skin(btn, kind, owner, on, schemeFn) end end
function OT.Repaint(btn) paint(btn) end
function OT.UnskinOwner(owner)
    for btn, sk in pairs(skins) do if sk.owner == owner then unskin(btn, sk) end end
end
function OT.SkinCheck(t) skinCheck(t) end

-- plain glyphs in Pathfinder's green, white under the mouse
local function glyph(name, size, rot)
    return function(btn, o)
        if not o.glyph then
            o.glyph = tex(o, name)
            o.glyph:SetPoint("CENTER")
            o.glyph:SetSize(size, size)
            if rot and o.glyph.SetRotation then o.glyph:SetRotation(rot) end
        end
        local c = hovered(btn) and { 1, 1, 1 } or sch().accent
        o.glyph:SetVertexColor(c[1], c[2], c[3], 1)
    end
end
PAINT.close = glyph("Close", 12)
PAINT.expand = glyph("Expand", 13)
PAINT.shrink = glyph("Shrink", 13)
PAINT.menu = glyph("Chevron", 10, -math.pi / 2)

-- A header (the tracker's or a section's): accent text, the game's backdrop
-- hidden, a short accent rule under the text.
local function styleHeader(h)
    if type(h) ~= "table" then return end
    color(h.Text, accent())
    if h.Background then MM.Dim(h.Background, true) end
    local rule = rules[h]
    if not rule and h.CreateTexture then
        rule = h:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rules[h] = rule
        if h.Text and h.Text.GetObjectType then
            rule:SetPoint("TOPLEFT", h.Text, "BOTTOMLEFT", 0, -3)
        else
            rule:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
        end
        rule:SetWidth(28)
    end
    if rule then
        local c = accent()
        rule:SetColorTexture(c[1], c[2], c[3], 0.8)
        rule:Show()
    end
    local mb = h.MinimizeButton or h.CollapseButton
    if type(mb) == "table" and mb.GetObjectType then skin(mb, "collapse") end
end

-- A quest line: its finished check (or color) decides.
local function finished(line)
    local icon = line.Icon or line.Check
    return type(icon) == "table" and icon.IsShown and icon:IsShown() or line.state == "COMPLETED" or line.completed == true
end


-- Walk a section: quest blocks (HeaderText) and their lines (Text + Dash).
local function styleTree(f, depth, inBlock)
    if type(f) ~= "table" or depth > 6 or not shown(f) then return end
    local kind = skins[f] and skins[f].kind or kindOf(f, inBlock)
    if kind then skin(f, kind); return end
    if f.HeaderText and not (f.IsMouseOver and f:IsMouseOver()) then
        color(f.HeaderText, TITLE)
        if type(f.HeaderText) == "table" and f.HeaderText.SetShadowOffset then
            f.HeaderText:SetShadowColor(0, 0, 0, 1)
            f.HeaderText:SetShadowOffset(1, -1)
        end
    end
    if f.Text and f.Dash then
        local fin = finished(f)
        color(f.Text, fin and DONE or LINE)
        color(f.Dash, accent())
        if fin then skinCheck(f.Icon or f.Check) end
    end
    if f.Header and f ~= tracker() then styleHeader(f.Header) end
    if f.GetChildren then
        local block = inBlock or f.HeaderText ~= nil
        for _, c in ipairs({ f:GetChildren() }) do styleTree(c, depth + 1, block) end
    end
end

-- The box around everything the tracker shows: its text and its buttons
-- (the quest markers on the left, item buttons on the right, the collapse
-- buttons), in the tracker's own units. Container frames don't count: the
-- tracker itself is as tall as its Edit Mode box, not its contents.

local function contentBounds(f)
    local fes = (f.GetEffectiveScale and f:GetEffectiveScale()) or 1
    local l, r, t, b
    local function add(x)
        if not (x.GetLeft and x:GetLeft()) then return end
        local es = (x.GetEffectiveScale and x:GetEffectiveScale()) or fes
        local k = es / fes
        local xl, xr, xt, xb = x:GetLeft() * k, x:GetRight() * k, x:GetTop() * k, x:GetBottom() * k
        if xr - xl < 1 or xt - xb < 1 then return end
        l = (l and math.min(l, xl)) or xl
        r = (r and math.max(r, xr)) or xr
        t = (t and math.max(t, xt)) or xt
        b = (b and math.min(b, xb)) or xb
    end
    local function walk(x, depth)
        if depth > 7 or not visible(x) or x == back then return end
        local kind = x.GetObjectType and x:GetObjectType()
        if x ~= f and (kind == "Button" or kind == "CheckButton") then add(x) end
        if x.GetRegions then
            for _, reg in ipairs({ x:GetRegions() }) do
                if reg.GetObjectType and reg:GetObjectType() == "FontString" and visible(reg) then
                    local text = reg.GetText and reg:GetText()
                    if type(text) == "string" and text ~= "" then add(reg) end
                end
            end
        end
        if x.GetChildren then
            for _, c in ipairs({ x:GetChildren() }) do walk(c, depth + 1) end
        end
    end
    walk(f, 1)
    return l, r, t, b
end

local function buildBack(f)
    back = CreateFrame("Frame", "RUIN_PathfinderObjectivesBack", f)
    if back.SetFrameStrata then back:SetFrameStrata("BACKGROUND") end
    if back.EnableMouse then back:EnableMouse(false) end
    back.ruinTheme = OT.Theme()
    if W.Skin then W.Skin(back, "bg", 0.9, "border") end
    if W.Sheen then back.sheen = W.Sheen(back, 0.04) end
    back.band = back:CreateTexture(nil, "ARTWORK")
    back.band:SetHeight(2)
    back.band:SetPoint("TOPLEFT", 0, 0)
    back.band:SetPoint("TOPRIGHT", 0, 0)
end

local function layoutBack(f)
    local l, r, t, b = contentBounds(f)
    back:ClearAllPoints()
    if l and f.GetLeft and f:GetLeft() then
        -- room around it all: a little more at the top for the accent band
        local fl, fb = f:GetLeft(), f:GetBottom()
        back:SetPoint("TOPLEFT", f, "BOTTOMLEFT", l - fl - PAD, t - fb + PAD + 2)
        back:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", r - fl + PAD, b - fb - PAD)
    else
        back:SetPoint("TOPLEFT", f, "TOPLEFT", -PAD, PAD)
        back:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", PAD, -PAD)
    end
    local c = accent()
    back.band:SetColorTexture(c[1], c[2], c[3], 0.9)
    MM.Paint(back, OT.Alpha(), 0.14, -0.6, OT.Scheme())
    back:SetShown(shown(f))
end

-- One pass over the tracker: the panel's size, the colors.
function OT.Refresh()
    local f = tracker()
    if not (db and f) or not modern() then return end
    if not back then buildBack(f) end
    layoutBack(f)
    styleHeader(f.Header)
    if type(f.modules) == "table" then
        for _, mod in ipairs(f.modules) do styleTree(mod, 1) end
    else
        styleTree(f, 1)
    end
end

-- Hand the tracker back to the game: its colors, its header backdrops.
local function restore()
    local f = tracker()
    if back then back:Hide() end
    for h, rule in pairs(rules) do
        rule:Hide()
        if h.Background then MM.Dim(h.Background, false) end
    end
    styled = {}
    for btn, sk in pairs(skins) do if sk.owner == "tracker" then unskin(btn, sk) end end
    for t, was in pairs(checks) do unskinCheck(t, was) end
    checks = {}
    -- the game repaints its own colors on its next update: ask for one now
    local mgr = rawget(_G, "ObjectiveTrackerManager")
    if type(mgr) == "table" and mgr.UpdateAll then pcall(mgr.UpdateAll, mgr)
    elseif type(f) == "table" and f.Update then pcall(f.Update, f)
    elseif ObjectiveTracker_Update then pcall(ObjectiveTracker_Update) end
end

function OT.Apply()
    if not db then return end
    if modern() then OT.Refresh() else restore() end
end

function OT.SetStyle(style)
    if not L.Valid(style) then return false end
    local was = db.otStyle
    db.otStyle = style
    if back and style ~= "blizzard" then
        back.ruinTheme, back.ruinThemeFound = OT.Theme(), nil
        if W.Skin then W.Skin(back, "bg", 0.9, "border") end
    end
    if was ~= style or style ~= "blizzard" then OT.Apply() end
    return true
end

function OT.SetAlpha(a)
    if type(a) ~= "number" then return false end
    db.otAlpha = math.max(0, math.min(1, a))
    if back and back:IsShown() then MM.Paint(back, db.otAlpha, 0.14, -0.6, OT.Scheme()) end
    return true
end

-- The game rebuilds the tracker as quests change: keep it styled.
local ticker, since = nil, 0
local function tick(_, elapsed)
    since = since + (elapsed or 0)
    if since < 1 then return end            -- the game's Update hook restyles at once; this is a backstop
    since = 0
    if modern() then OT.Refresh() end
end

function OT.Init(cdb)
    db = cdb
    if db.otStyle == nil then db.otStyle = "blizzard" end
    if type(db.otAlpha) ~= "number" then db.otAlpha = 0.85 end
    ticker = ticker or CreateFrame("Frame")
    ticker:SetScript("OnUpdate", tick)
    local f = tracker()
    if type(f) == "table" and hooksecurefunc and type(f.Update) == "function" then
        hooksecurefunc(f, "Update", function() if modern() then OT.Refresh() end end)
    end
    if db.otStyle ~= "blizzard" and C_Timer then C_Timer.After(1, OT.Apply) end
end
