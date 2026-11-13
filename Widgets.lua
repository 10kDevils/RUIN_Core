-- RUIN Core: shared widget kit and toast alerts
-- Modules build their pages from these so every RUIN addon looks and
-- behaves the same (and couch mode / scaling applies everywhere).
local ADDON, ns = ...

local W = {}
ns.Widgets = W

-- The RUIN look: deep navy surfaces in three steps (window, panel, raised),
-- quiet steel edges, gold for the RUIN mark and headings, and each page's
-- own color for whatever is selected, hovered or switched on.
W.PALETTE = {
    bg      = { 0.027, 0.039, 0.063 },   -- window body
    panel   = { 0.047, 0.067, 0.102 },   -- cards and rows
    panelHi = { 0.082, 0.114, 0.165 },   -- buttons, raised rows
    border  = { 0.149, 0.212, 0.306 },   -- steel edges
    line    = { 0.098, 0.141, 0.204 },   -- hairlines and dividers inside panels
    glow    = { 0.329, 0.718, 0.851 },   -- teal: links and RUIN's own focus color
    gold    = { 0.902, 0.722, 0.384 },   -- the RUIN mark and headline accents
    text    = { 0.925, 0.941, 0.965 },
    sub     = { 0.584, 0.651, 0.749 },
    good    = { 0.361, 0.851, 0.451 },
    warn    = { 0.949, 0.749, 0.247 },
    bad     = { 0.949, 0.400, 0.349 },
}

W.COLORS = {
    accent = "|cff54b7d9", good = "|cff5cd973", bad = "|cfff26659",
    gold = "|cffe6b862", dim = "|cff95a6bf", white = "|cffffffff", warn = "|cfff2bf3f",
}

-- Priority and evidence tags, drawn as small pills (W.Pill) or as colored
-- text (W.TagText). Quick/Medium/Long follow the brief's Gear Path.
W.TAGS = {
    Quick      = { bg = { 0.09, 0.33, 0.16 }, fg = { 0.62, 1.00, 0.62 } },
    Medium     = { bg = { 0.40, 0.30, 0.05 }, fg = { 1.00, 0.86, 0.38 } },
    Long       = { bg = { 0.38, 0.17, 0.07 }, fg = { 1.00, 0.64, 0.40 } },
    Verified   = { bg = { 0.09, 0.30, 0.26 }, fg = { 0.55, 0.95, 0.85 } },
    Unverified = { bg = { 0.33, 0.24, 0.08 }, fg = { 1.00, 0.80, 0.45 } },
    Sample     = { bg = { 0.20, 0.22, 0.28 }, fg = { 0.80, 0.83, 0.90 } },
    Group      = { bg = { 0.12, 0.22, 0.40 }, fg = { 0.60, 0.80, 1.00 } },
    Solo       = { bg = { 0.20, 0.16, 0.32 }, fg = { 0.82, 0.72, 1.00 } },
}

-- Map and tracker markers share one color code across every module, matching
-- the brief's legend: quest, turn-in, dungeon, class quest, flight path,
-- waypoint, group event (plus RUIN's enemy and objective marks).
W.MARKERS = {
    quest    = { 1.00, 0.82, 0.10 },
    turnin   = { 0.30, 0.62, 1.00 },
    dungeon  = { 0.90, 0.22, 0.22 },
    class    = { 0.66, 0.42, 0.98 },
    trainer  = { 0.66, 0.42, 0.98 },
    flight   = { 0.45, 0.78, 1.00 },
    waypoint = { 0.30, 0.62, 1.00 },
    event    = { 1.00, 0.55, 0.15 },
    enemy    = { 0.95, 0.30, 0.25 },
    objective= { 0.90, 0.72, 0.38 },
}

local function rgb(key)
    if type(key) == "table" then return key[1], key[2], key[3] end
    local c = W.PALETTE[key] or W.PALETTE.panel
    return c[1], c[2], c[3]
end
W.RGB = rgb

---------------------------------------------------------------------------
-- Page colors. Guild and Options keep RUIN's own navy, steel blue, teal and
-- gold. A module's page takes on that addon's color throughout: selected
-- tabs, edges, hover, section rules, check marks and a faint tint in the
-- panels. Widgets find their page by walking up their parents to the frame
-- Core marked with .ruinTheme, so rows and buttons made later match too.
---------------------------------------------------------------------------
local P = W.PALETTE
local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end
W.Mix = mix

-- Controls are quiet until you touch them: a raised navy button with a
-- steel edge, which takes the page's color on hover and fills with it when
-- picked. Check marks, the open tab's underline and focus rings use the same
-- color, so each page reads in its own hue. Gold stays RUIN's: the mark,
-- section titles, and the accent wherever there is no page (dialogs, menus).
local GOLD = P.gold
local WHITE = { 1, 1, 1 }
local BTN_EDGE = mix(P.border, P.text, 0.14)         -- a resting control's edge
local BTN_TEXT = mix(P.text, P.sub, 0.10)
-- kept for modules that still ask for them: a resting control's edge and a picked fill
local GOLD_EDGE = BTN_EDGE
local GOLD_FILL = mix(P.panelHi, P.gold, 0.26)
W.GOLD_EDGE, W.GOLD_FILL, W.BTN_EDGE = GOLD_EDGE, GOLD_FILL, BTN_EDGE

W.CORE_SCHEME = { accent = P.gold, edge = P.border, panel = P.panel, panelHi = P.panelHi, bg = P.bg,
                  mark = P.gold, color = P.gold, core = true }
local schemes = {}

-- A page's colors from its theme. Core pages (Guild, Settings) keep the
-- plain navy panels and take only the accent; a module's page is also
-- tinted, faintly, in its color.
function W.SchemeFor(theme)
    if not theme or not theme.color then return W.CORE_SCHEME end
    local s = schemes[theme]
    if s then return s end
    local c = theme.color
    local core = theme.core and true or false
    s = {
        color   = c,
        accent  = mix(c, WHITE, 0.24),           -- lighter, so lines and marks read on navy
        edge    = mix(P.border, c, core and 0.16 or 0.40),
        panel   = core and P.panel or mix(P.panel, c, 0.055),
        panelHi = core and P.panelHi or mix(P.panelHi, c, 0.11),
        bg      = core and P.bg or mix(P.bg, c, 0.03),
        mark    = c,
        core    = core,
    }
    schemes[theme] = s
    return s
end

-- The theme of the page a frame sits on (nil outside module pages).
function W.ThemeOf(f)
    if not f then return nil end
    if f.ruinThemeFound ~= nil then return f.ruinThemeFound or nil end
    local o, depth, found = f, 0, false
    while o and depth < 40 do
        if o.ruinTheme then found = o.ruinTheme; break end
        if o ~= f and o.ruinThemeFound ~= nil then found = o.ruinThemeFound; break end
        o = o.GetParent and o:GetParent() or nil
        depth = depth + 1
    end
    if f.GetParent then f.ruinThemeFound = found end
    return found or nil
end

function W.SchemeOf(f) return W.SchemeFor(W.ThemeOf(f)) end

-- Palette names resolved for the frame's page: panel, panelHi, bg, border
-- (the page's edge color) and glow/accent (the page's highlight color).
local SCHEME_KEYS = { panel = "panel", panelHi = "panelHi", bg = "bg", border = "edge", glow = "accent", accent = "accent" }
local function rgbFor(f, key)
    if type(key) == "table" then return key[1], key[2], key[3] end
    local sk = SCHEME_KEYS[key]
    if sk and f then
        local c = W.SchemeOf(f)[sk]
        return c[1], c[2], c[3]
    end
    return rgb(key)
end
W.RGBFor = rgbFor

function W.Hex(key)
    local r, g, b = rgb(key)
    return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- Give any frame RUIN's panel look: a filled background and 1-pixel edges.
-- bgKey/borderKey are palette names (or {r,g,b}); returns the frame.
function W.Skin(f, bgKey, alpha, borderKey)
    if not f.skinBg then
        f.skinBg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
        f.skinBg:SetAllPoints()
        f.skinEdges = {}
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local e = f:CreateTexture(nil, "BORDER", nil, 7)
            if side == "TOP" or side == "BOTTOM" then
                e:SetHeight(1)
                e:SetPoint(side .. "LEFT", 0, 0)
                e:SetPoint(side .. "RIGHT", 0, 0)
            else
                e:SetWidth(1)
                e:SetPoint("TOP" .. side, 0, 0)
                e:SetPoint("BOTTOM" .. side, 0, 0)
            end
            f.skinEdges[side] = e
        end
    end
    local r, g, b = rgbFor(f, bgKey or "panel")
    f.skinBg:SetColorTexture(r, g, b, alpha or 0.96)
    W.SetBorder(f, borderKey or "border")
    return f
end

function W.SetBorder(f, key, alpha)
    if not f.skinEdges then return end
    local r, g, b = rgbFor(f, key or "border")
    for side, e in pairs(f.skinEdges) do
        -- the top edge catches a little more light
        local a = (alpha or 1) * (side == "TOP" and 1 or 0.8)
        e:SetColorTexture(r, g, b, a)
    end
end

function W.Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

-- While a module page is being built, Core sets W.currentTheme so headers
-- and lists pick up that module's colors without the module doing anything.
W.currentTheme = nil

-- Section heading: light title with a short rule beneath in the page's color.
function W.Header(parent, text)
    local fs = W.Label(parent, text, "GameFontNormal")
    fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local rule = parent:CreateTexture(nil, "ARTWORK")
    local a = W.SchemeOf(parent).accent
    rule:SetColorTexture(a[1], a[2], a[3], 0.9)
    rule:SetSize(28, 2)
    rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
    fs.rule = rule
    return fs
end

-- A faint light across the top half of a raised control.
local function sheen(f, strength)
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    t:SetPoint("TOPLEFT", 1, -1)
    t:SetPoint("TOPRIGHT", -1, -1)
    t:SetHeight(10)
    t:SetColorTexture(1, 1, 1, 1)
    local a = strength or 0.055
    local ok = CreateColor and t.SetGradient and pcall(t.SetGradient, t, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, a))
    if not ok then t:SetColorTexture(1, 1, 1, a * 0.4) end
    return t
end
W.Sheen = sheen

-- Raised navy button with a steel edge; the page's color on hover, and a fill
-- of it when picked. LockHighlight marks a button as selected (pickers made
-- of buttons). b.flat = true makes it a menu row: no edge, a fill on hover.
local function paintButton(b)
    if not b.skinBg then return end
    local sc = W.SchemeOf(b)
    local ac = sc.accent
    local link = b.linkColor      -- a button that opens another addon wears that addon's color
    if link and b:IsEnabled() then
        if b.locked or b.hover then
            W.Skin(b, mix(P.panelHi, link, 0.40), 1, mix(link, WHITE, 0.30))
            b.label:SetTextColor(1, 1, 1)
        else
            W.Skin(b, mix(P.panelHi, link, 0.22), 1, mix(P.border, link, 0.80))
            local t = mix(link, WHITE, 0.66)
            b.label:SetTextColor(t[1], t[2], t[3])
        end
        return
    end
    if b.flat then
        if not b:IsEnabled() then
            W.Skin(b, "panel", 0, "panel"); W.SetBorder(b, "panel", 0)
            b.label:SetTextColor(0.45, 0.50, 0.58)
        elseif b.locked then
            W.Skin(b, mix(sc.panelHi, ac, 0.30), 1, ac); W.SetBorder(b, ac, 0)
            b.label:SetTextColor(1, 1, 1)
        elseif b.hover then
            W.Skin(b, mix(sc.panelHi, ac, 0.16), 1, ac); W.SetBorder(b, ac, 0)
            b.label:SetTextColor(1, 1, 1)
        else
            W.Skin(b, "panel", 0, "panel"); W.SetBorder(b, "panel", 0)
            b.label:SetTextColor(BTN_TEXT[1], BTN_TEXT[2], BTN_TEXT[3])
        end
        if b.pickBar then b.pickBar:SetShown(b.locked and b:IsEnabled() and true or false) end
        return
    end
    if not b:IsEnabled() then
        W.Skin(b, "panel", 0.80, "line")
        b.label:SetTextColor(0.42, 0.47, 0.55)
    elseif b.locked then
        W.Skin(b, mix(sc.panelHi, ac, 0.32), 1, ac)
        b.label:SetTextColor(1, 1, 1)
    elseif b.hover then
        W.Skin(b, mix(sc.panelHi, ac, 0.15), 1, mix(P.border, ac, 0.85))
        b.label:SetTextColor(1, 1, 1)
    else
        W.Skin(b, "panelHi", 1, BTN_EDGE)
        b.label:SetTextColor(BTN_TEXT[1], BTN_TEXT[2], BTN_TEXT[3])
    end
    if b.sheen then b.sheen:SetShown(b:IsEnabled() and true or false) end
end
W.PaintButton = paintButton

function W.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, 24)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.label:SetWordWrap(false)
    b:SetFontString(b.label)
    b:SetPushedTextOffset(1, -1)
    W.Skin(b, "panelHi", 1, "border")
    b.sheen = sheen(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    local hc = W.SchemeOf(b).accent
    hl:SetColorTexture(hc[1], hc[2], hc[3], 0.06)
    b.hl = hl
    b:SetText(text or "")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- b.tip = "what it does" shows on hover
    b:HookScript("OnEnter", function(self)
        self.hover = true; paintButton(self)
        if type(self.tip) == "string" and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:HookScript("OnLeave", function(self)
        self.hover = false; paintButton(self)
        if type(self.tip) == "string" and GameTooltip then GameTooltip:Hide() end
    end)
    b:HookScript("OnEnable", paintButton)
    b:HookScript("OnDisable", paintButton)
    local lock, unlock = b.LockHighlight, b.UnlockHighlight
    b.LockHighlight = function(self) self.locked = true; if lock then lock(self) end; paintButton(self) end
    b.UnlockHighlight = function(self) self.locked = false; if unlock then unlock(self) end; paintButton(self) end
    if onClick then b:SetScript("OnClick", onClick) end
    paintButton(b)
    return b
end

-- A menu row: W.Button without its edge, a bar on the left when it's the
-- current choice. Used by the lists under dropdowns and the context menu.
function W.MenuRow(parent, width)
    local it = W.Button(parent, "", width)
    it:SetHeight(20)
    it.flat = true
    it.sheen:Hide(); it.sheen = nil
    it.label:SetJustifyH("LEFT")
    it.label:SetPoint("LEFT", 8, 0)
    local ac = W.SchemeOf(it).accent
    it.pickBar = it:CreateTexture(nil, "OVERLAY")
    it.pickBar:SetColorTexture(ac[1], ac[2], ac[3], 1)
    it.pickBar:SetWidth(2)
    it.pickBar:SetPoint("TOPLEFT", 0, 0)
    it.pickBar:SetPoint("BOTTOMLEFT", 0, 0)
    it.pickBar:Hide()
    paintButton(it)
    return it
end

-- Check box with its own label (the label is clickable too); call
-- :Refresh() to sync from getter. A navy box that fills with the page's
-- color and shows a check when it's on.
local MEDIA = "Interface\\AddOns\\RUIN_Core\\Media\\"
function W.Check(parent, label, getter, setter)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(24, 24)
    c.box = CreateFrame("Frame", nil, c)
    c.box:SetSize(16, 16)
    c.box:SetPoint("LEFT", 3, 0)
    W.Skin(c.box, "bg", 1, BTN_EDGE)
    local ac = W.SchemeOf(c).accent
    c.fill = c.box:CreateTexture(nil, "ARTWORK")
    c.fill:SetPoint("TOPLEFT", 1, -1)
    c.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    c.fill:SetColorTexture(ac[1], ac[2], ac[3], 1)
    c.mark = c.box:CreateTexture(nil, "OVERLAY")
    c.mark:SetPoint("TOPLEFT", 1, -1)
    c.mark:SetPoint("BOTTOMRIGHT", -1, 1)
    c.mark:SetTexture(MEDIA .. "Check")
    c.mark:SetVertexColor(P.bg[1], P.bg[2], P.bg[3], 1)
    c.label = W.Label(c, label)          -- a child, so it hides with the box
    c.label:SetPoint("LEFT", c, "RIGHT", 0, 0)
    if c.SetHitRectInsets then c:SetHitRectInsets(0, -((c.label:GetStringWidth() or 60) + 8), 0, 0) end
    local function sync()
        local on = c:GetChecked() and true or false
        c.mark:SetShown(on)
        c.fill:SetShown(on)
        W.SetBorder(c.box, (on or c.hover) and ac or BTN_EDGE)
    end
    c:SetScript("OnClick", function(self)
        sync()
        setter(self:GetChecked() and true or false)
    end)
    -- c.tip = "One line saying what it does" shows on hover.
    c:SetScript("OnEnter", function(self)
        self.hover = true
        W.SetBorder(self.box, ac)
        if self.tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    c:SetScript("OnLeave", function(self)
        self.hover = false
        sync()
        if self.tip and GameTooltip then GameTooltip:Hide() end
    end)
    c.Refresh = function(self) self:SetChecked(getter() and true or false); sync() end
    c:Refresh()
    return c
end

-- Single-line input; onCommit(text) on Enter or when focus leaves.
-- placeholder: grey hint shown while the box is empty (also :SetPlaceholder).
function W.EditBox(parent, width, onCommit, placeholder)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width or 160, 22)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    if e.SetTextInsets then e:SetTextInsets(6, 6, 0, 0) end
    W.Skin(e, "bg", 1, "border")
    e.hint = e:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    e.hint:SetPoint("LEFT", 7, 0)
    e.hint:SetPoint("RIGHT", -6, 0)
    e.hint:SetJustifyH("LEFT")
    e.hint:SetWordWrap(false)
    local function updateHint(self)
        local empty = (self:GetText() or "") == ""
        self.hint:SetShown(empty and not (self.HasFocus and self:HasFocus()))
    end
    function e:SetPlaceholder(text) self.hint:SetText(text or ""); updateHint(self) end
    local function commit(self)
        self:ClearFocus()
        if onCommit then onCommit(self:GetText() or "") end
    end
    -- Core's own handlers run even when a module sets its own script.
    local internal = {
        OnEditFocusGained = function(self) W.SetBorder(self, "glow"); self.hint:Hide() end,
        OnEditFocusLost = function(self)
            W.SetBorder(self, "border")
            updateHint(self)
            if onCommit then onCommit(self:GetText() or "") end
        end,
        OnTextChanged = function(self) updateHint(self) end,
    }
    local setScript = e.SetScript
    e.SetScript = function(self, k, fn)
        local mine = internal[k]
        if mine then
            setScript(self, k, function(...) mine(...); if fn then fn(...) end end)
        else
            setScript(self, k, fn)
        end
    end
    e:SetScript("OnEnterPressed", commit)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    for k in pairs(internal) do e:SetScript(k, nil) end
    e:SetPlaceholder(placeholder)
    return e
end

-- Marks a button that steps through choices: a small down chevron in the
-- page color and a hover line saying how it works (b.tipTitle adds a title).
-- hint replaces that line ("Click to pick from a list.").
function W.MarkChoice(b, hint)
    b.label:SetPoint("RIGHT", -16, 0)
    local ac = W.SchemeOf(b).accent
    local chev = b:CreateTexture(nil, "OVERLAY")       -- a small down chevron
    chev:SetTexture(MEDIA .. "Chevron")
    chev:SetSize(12, 12)
    chev:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    chev:SetVertexColor(ac[1], ac[2], ac[3], 0.95)
    b.chevron = chev
    b:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        -- to the left of the button, beside the list that opens under it
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -6, 0)
        if self.tipTitle then GameTooltip:AddLine(self.tipTitle, 1, 1, 1) end
        GameTooltip:AddLine(hint or "Click to pick from a list.", 0.7, 0.75, 0.8)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

-- Button that cycles through options: left-click next, right-click previous.
-- A small chevron marks it as a choice, and hovering says how it works.
-- A button with the down arrow is a dropdown: W.Cycle is kept for the
-- modules that ask for it and opens the same list as W.Dropdown.
function W.Cycle(parent, width, options, getter, setter, prefix)
    return W.Dropdown(parent, width, options, getter, setter, prefix)
end

-- Scrolling list. setupRow(row) creates the row's regions once;
-- updateRow(row, item, index) fills them. list:SetItems(items).
-- A row with row.link set shows that item's tooltip on hover; row.tip
-- (a function(tooltip)) adds any other tooltip. list:SetEmptyText(text)
-- shows a line when there is nothing to list.
local tipRow     -- the list row whose tooltip is showing
local function rowEnter(r)
    local ac = W.SchemeOf(r).accent
    r.zebra:SetColorTexture(ac[1], ac[2], ac[3], 0.13)
    if r.hoverBar then r.hoverBar:Show() end
    tipRow = r
    if (r.link or r.tip) and GameTooltip then
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        if r.link then pcall(GameTooltip.SetHyperlink, GameTooltip, r.link) end
        if r.tip then pcall(r.tip, GameTooltip) end
        GameTooltip:Show()
    end
end

local function rowLeave(r)
    if tipRow == r then tipRow = nil end
    local c = W.SchemeOf(r).panelHi
    r.zebra:SetColorTexture(c[1], c[2], c[3], r.zebraAlpha or 0)
    if r.hoverBar then r.hoverBar:Hide() end
    if (r.link or r.tip) and GameTooltip then GameTooltip:Hide() end
end

-- Item names that arrive while a row's tooltip is open fill it in at once
-- ("Loading item..." turns into the name), after the pages have redrawn.
if ns.Subscribe then
    ns:Subscribe("ITEMS_LOADED", function()
        if not (tipRow and C_Timer) then return end
        C_Timer.After(0, function()
            local r = tipRow
            if r and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(r) and r:IsShown() then rowEnter(r) end
        end)
    end)
end

-- The game's scroll bar, slimmed down: no arrow buttons, a thin track and a
-- thumb in the page's color whose length follows how much there is to
-- scroll. Safe to call more than once, and on a frame with no bar.
local function styleScrollBar(sf)
    local bar = sf.ScrollBar or (sf.GetName and sf:GetName() and _G[sf:GetName() .. "ScrollBar"])
    local ac = W.SchemeOf(sf).accent
    sf.ruinBarColor = ac
    if type(bar) ~= "table" or bar.ruinStyled then return end
    bar.ruinStyled = true
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local btn = bar[key]
        if type(btn) == "table" then
            if btn.SetAlpha then btn:SetAlpha(0) end
            if btn.EnableMouse then btn:EnableMouse(false) end
        end
    end
    if bar.ClearAllPoints and bar.SetPoint then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 9, -1)
        bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 9, 1)
    end
    if bar.SetWidth then bar:SetWidth(7) end
    if bar.CreateTexture then
        local track = bar:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(P.panelHi[1], P.panelHi[2], P.panelHi[3], 0.55)
        bar.ruinTrack = track
    end
    local thumb = bar.ThumbTexture or (bar.GetThumbTexture and bar:GetThumbTexture())
    if type(thumb) == "table" and thumb.SetColorTexture then
        thumb:SetColorTexture(ac[1], ac[2], ac[3], 0.70)
        if thumb.SetTexCoord then thumb:SetTexCoord(0, 1, 0, 1) end
        thumb:SetSize(7, 40)
        local function fit(self)
            local view = self:GetHeight() or 0
            local range = (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
            if view <= 0 then return end
            thumb:SetHeight(math.max(24, math.min(view, view * view / (view + math.max(0, range)))))
        end
        if sf.HookScript then
            sf:HookScript("OnScrollRangeChanged", fit)
            sf:HookScript("OnSizeChanged", fit)
        end
        fit(sf)
    end
    sf.ruinSlimBar = true
end
function W.StyleScrollBar(sf)
    if type(sf) == "table" then pcall(styleScrollBar, sf) end
    return sf
end

-- Show a scroll frame's scroll bar only when there is something to scroll.
-- Call after the content changes; it also rechecks when the frame is shown
-- or resized.
function W.FitScrollBar(sf)
    W.StyleScrollBar(sf)
    local bar = sf.ScrollBar or (sf.GetName and sf:GetName() and _G[sf:GetName() .. "ScrollBar"])
    local child = sf.GetScrollChild and sf:GetScrollChild()
    if type(bar) ~= "table" or type(child) ~= "table" then return end
    local view = sf:GetHeight() or 0
    local need = (child:GetHeight() or 0) > view + 1 and view > 0
    if bar.SetShown then bar:SetShown(need) elseif need then bar:Show() else bar:Hide() end
    if not need and sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
    if not sf.fitHooked and sf.HookScript then
        sf.fitHooked = true
        sf:HookScript("OnShow", function(self) W.FitScrollBar(self) end)
        sf:HookScript("OnSizeChanged", function(self) W.FitScrollBar(self) end)
    end
end

-- Scrolling that's easy to follow: the mouse wheel glides instead of
-- jumping, a faint weave on the content moves with it (so you can see it
-- move), and soft fades at the top and bottom edges say there's more.
function W.SmoothScroll(sf, step)
    if not sf or sf.smoothScroll then return sf end
    sf.smoothScroll = true
    step = step or 64
    local target
    local function maxScroll(self) return (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0 end
    local function glide(self, elapsed)
        local cur = self:GetVerticalScroll() or 0
        local diff = (target or cur) - cur
        if math.abs(diff) < 0.5 then
            self:SetVerticalScroll(target or cur)
            self:SetScript("OnUpdate", nil)
            return
        end
        self:SetVerticalScroll(cur + diff * math.min(1, (elapsed or 0.016) * 14))
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = maxScroll(self)
        if range <= 0 then return end
        target = math.max(0, math.min(range, (target or self:GetVerticalScroll() or 0) - delta * step))
        self:SetScript("OnUpdate", glide)
    end)
    -- the scroll bar or a jump elsewhere resets where the glide aims
    sf:HookScript("OnVerticalScroll", function(self, offset)
        if not self:GetScript("OnUpdate") then target = offset end
    end)
    return sf
end

function W.ScrollDressing(sf, child, color)
    if not sf or sf.dressed then return sf end
    sf.dressed = true
    local c = color or W.SchemeOf(sf).accent
    if child then
        local weave = child:CreateTexture(nil, "BACKGROUND", nil, -8)
        weave:SetAllPoints(child)
        weave:SetTexture(MEDIA .. "Weave", "REPEAT", "REPEAT")
        if weave.SetHorizTile then weave:SetHorizTile(true); weave:SetVertTile(true) end
        weave:SetVertexColor(c[1], c[2], c[3], 0.55)
        sf.weave = weave
    end
    local over = CreateFrame("Frame", nil, sf)
    over:SetAllPoints(sf)
    over:SetFrameLevel((child and child:GetFrameLevel() or sf:GetFrameLevel()) + 6)
    local bg = W.SchemeOf(sf).panel
    local top = over:CreateTexture(nil, "OVERLAY")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(22)
    top:SetTexture(MEDIA .. "Fade")
    top:SetVertexColor(bg[1], bg[2], bg[3], 1)
    local bottom = over:CreateTexture(nil, "OVERLAY")
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(22)
    bottom:SetTexture(MEDIA .. "Fade")
    bottom:SetTexCoord(0, 1, 1, 0)
    bottom:SetVertexColor(bg[1], bg[2], bg[3], 1)
    sf.fadeTop, sf.fadeBottom = top, bottom
    local function update(self)
        local range = (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
        local at = self:GetVerticalScroll() or 0
        top:SetShown(at > 2)
        bottom:SetShown(range > 0 and at < range - 2)
    end
    sf:HookScript("OnVerticalScroll", update)
    sf:HookScript("OnScrollRangeChanged", update)
    sf:HookScript("OnShow", update)
    sf.UpdateFades = update
    update(sf)
    return sf
end

function W.List(parent, rowHeight, setupRow, updateRow)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
    W.StyleScrollBar(sf)
    local list = { frame = sf, rows = {}, items = {}, theme = W.currentTheme }
    local empty = W.Label(child, "", "GameFontDisable")
    empty:SetPoint("TOPLEFT", 6, -8)
    empty:SetPoint("RIGHT", child, "RIGHT", -6, 0)
    empty:Hide()

    function list:SetEmptyText(text) self.emptyText = text end

    function list:SetItems(items)
        self.items = items or {}
        local width = math.max(100, (sf:GetWidth() or 400) - 4)
        child:SetWidth(width)
        for i, item in ipairs(self.items) do
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, child)
                row:SetHeight(rowHeight)
                -- Quiet zebra rows (tinted on module pages); under the mouse a row
                -- takes the page's color, with a bar of it on the left.
                row.zebra = row:CreateTexture(nil, "BACKGROUND")
                row.zebra:SetAllPoints()
                local hc = W.SchemeOf(row).accent
                row.hoverBar = row:CreateTexture(nil, "BORDER")
                row.hoverBar:SetColorTexture(hc[1], hc[2], hc[3], 1)
                row.hoverBar:SetWidth(2)
                row.hoverBar:SetPoint("TOPLEFT", 0, 0)
                row.hoverBar:SetPoint("BOTTOMLEFT", 0, 0)
                row.hoverBar:Hide()
                row:EnableMouse(true)
                row:SetScript("OnEnter", rowEnter)
                row:SetScript("OnLeave", rowLeave)
                setupRow(row)
                self.rows[i] = row
            end
            row.zebraAlpha = (i % 2 == 0) and 0.62 or 0.24
            local zc = W.SchemeOf(row).panelHi
            row.zebra:SetColorTexture(zc[1], zc[2], zc[3], row.zebraAlpha)
            row.link, row.tip = nil, nil
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            updateRow(row, item, i)
            row:Show()
        end
        for i = #self.items + 1, #self.rows do self.rows[i]:Hide() end
        child:SetHeight(math.max(10, #self.items * rowHeight))
        W.FitScrollBar(sf)
        if #self.items == 0 and self.emptyText then
            empty:SetText(self.emptyText)
            empty:Show()
        else
            empty:Hide()
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Sub-pages inside a module page: a row of tabs in the page's colors.
--   local tabs = W.SubTabs(panel, { "Board", "Groups" }, function(i, name) ... end)
--   build into tabs.pages[1], tabs.pages[2]; tabs:Select(1)
-- Each page frame sits below the tab row and fills the rest of the panel.
---------------------------------------------------------------------------
W.SUBTAB_HEIGHT = 32

function W.SubTabs(parent, names, onSelect)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(24)
    -- flat tabs standing on a hairline: the open one is bright and underlined
    -- in the page's color, the rest are quiet until the mouse is on them
    local base = bar:CreateTexture(nil, "BACKGROUND")
    base:SetColorTexture(P.line[1], P.line[2], P.line[3], 1)
    base:SetHeight(1)
    base:SetPoint("BOTTOMLEFT", 0, -3)
    base:SetPoint("BOTTOMRIGHT", 0, -3)
    local ac = W.SchemeOf(bar).accent

    local obj = { bar = bar, buttons = {}, pages = {}, names = names }
    local function paint(i)
        local b = obj.buttons[i]
        local on = obj.selected == i
        if on then
            b.text:SetTextColor(1, 1, 1)
        elseif b.hover then
            b.text:SetTextColor(rgb("text"))
        else
            b.text:SetTextColor(rgb("sub"))
        end
        b.wash:SetShown(on)
        b.line:SetShown((on or b.hover) and true or false)
        b.line:SetColorTexture(ac[1], ac[2], ac[3], on and 1 or 0.40)
    end
    function obj:Select(i)
        if not self.buttons[i] then return end
        local changed = self.selected ~= i
        self.selected = i
        for j, page in ipairs(self.pages) do
            if j == i then page:Show() else page:Hide() end
            paint(j)
        end
        if changed and PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
            pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_TAB)
        end
        if onSelect then onSelect(i, names[i]) end
    end
    -- Show a count or marker after a tab's name, e.g. "Groups (3)".
    function obj:SetLabel(i, text)
        local b = self.buttons[i]
        if not b then return end
        b.text:SetText(text)
        b:SetWidth(math.max(78, (b.text:GetStringWidth() or 60) + 28))
    end

    local prev
    for i, name in ipairs(names) do
        local b = CreateFrame("Button", nil, bar)
        b:SetHeight(24)
        -- a wash of the page's color rising from the underline, on the open tab
        b.wash = b:CreateTexture(nil, "BACKGROUND")
        b.wash:SetPoint("TOPLEFT", 0, -2)
        b.wash:SetPoint("BOTTOMRIGHT", 0, -3)
        b.wash:SetColorTexture(ac[1], ac[2], ac[3], 0.10)
        if CreateColor and b.wash.SetGradient then
            b.wash:SetColorTexture(1, 1, 1, 1)
            if not pcall(b.wash.SetGradient, b.wash, "VERTICAL", CreateColor(ac[1], ac[2], ac[3], 0.20), CreateColor(ac[1], ac[2], ac[3], 0)) then
                b.wash:SetColorTexture(ac[1], ac[2], ac[3], 0.10)
            end
        end
        b.wash:Hide()
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetColorTexture(ac[1], ac[2], ac[3], 1)
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 0, -3)
        b.line:SetPoint("BOTTOMRIGHT", 0, -3)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("CENTER", 0, 1)
        b.text:SetText(name)
        b:SetWidth(math.max(78, (b.text:GetStringWidth() or 60) + 28))
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0) end
        b:SetScript("OnEnter", function(self) self.hover = true; paint(i) end)
        b:SetScript("OnLeave", function(self) self.hover = false; paint(i) end)
        b:SetScript("OnClick", function() obj:Select(i) end)
        obj.buttons[i] = b

        local page = CreateFrame("Frame", nil, parent)
        page:SetPoint("TOPLEFT", 0, -W.SUBTAB_HEIGHT)
        page:SetPoint("BOTTOMRIGHT", 0, 0)
        page:Hide()
        obj.pages[i] = page
        prev = b
    end
    -- Show or hide a tab; the others close up. Hiding the open tab opens the first.
    function obj:SetTabShown(i, shown)
        local b = self.buttons[i]
        if not b then return end
        self.hidden = self.hidden or {}
        if (not self.hidden[i]) == (shown and true or false) then return end
        self.hidden[i] = not shown or nil
        b:SetShown(shown)
        local last
        for j, btn in ipairs(self.buttons) do
            if not self.hidden[j] then
                btn:ClearAllPoints()
                if last then btn:SetPoint("LEFT", last, "RIGHT", 2, 0) else btn:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0) end
                last = btn
            end
        end
        if not shown and self.selected == i then self:Select(1) end
    end
    for i = 1, #names do paint(i) end
    return obj
end

---------------------------------------------------------------------------
-- Card: a navy panel with edges in the page's color, for grouping controls.
-- The page's own color also shows as a short accent along the top edge.
---------------------------------------------------------------------------
function W.Card(parent)
    local f = CreateFrame("Frame", nil, parent)
    local t = W.ThemeOf(f) or W.currentTheme
    W.Skin(f, "panel", 0.94, "border")
    if t and t.color then
        local c = W.SchemeFor(t).accent
        local accent = f:CreateTexture(nil, "ARTWORK")
        accent:SetColorTexture(c[1], c[2], c[3], 0.95)
        accent:SetSize(40, 2)
        accent:SetPoint("TOPLEFT", 0, 0)
        f.accent = accent
    end
    f.edges = f.skinEdges
    return f
end

---------------------------------------------------------------------------
-- Context menu at the cursor: W.ContextMenu({ { text, fn }, { title = "..." }, ... })
-- Click an entry, or anywhere else (or Escape), to close it.
---------------------------------------------------------------------------
local ctxMenu
function W.ContextMenu(entries)
    if not ctxMenu then
        ctxMenu = CreateFrame("Frame", "RUIN_ContextMenu", UIParent)
        W.Skin(ctxMenu, "panel", 1, "glow")
        ctxMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        ctxMenu:EnableMouse(true)
        ctxMenu:SetClampedToScreen(true)
        ctxMenu.items = {}
        ctxMenu:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver(8, -8, -8, 8) then
                self.away = (self.away or 0) + 1
                if self.away > 90 then self:Hide() end
            else
                self.away = 0
            end
        end)
        if UISpecialFrames then tinsert(UISpecialFrames, "RUIN_ContextMenu") end
    end
    local m = ctxMenu
    local y = -6
    for i, e in ipairs(entries) do
        local it = m.items[i]
        if not it then
            it = W.MenuRow(m, 170)
            m.items[i] = it
        end
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", 4, y)
        it:SetText(e.title and (W.COLORS.gold .. e.title .. "|r") or e[1])
        it:SetEnabled(not e.title)
        it:SetScript("OnClick", function() m:Hide(); if e[2] then e[2]() end end)
        it:Show()
        y = y - 21
    end
    for i = #entries + 1, #m.items do m.items[i]:Hide() end
    m:SetSize(178, -y + 6)
    local x, cy = 0, 0
    if GetCursorPosition then
        x, cy = GetCursorPosition()
        local sc = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        x, cy = x / sc, cy / sc
    end
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 6, cy + 6)
    m.away = 0
    m:Show()
    return m
end

---------------------------------------------------------------------------
-- Popover: a small card that opens under a button (for settings that would
-- otherwise crowd a page). The button toggles it; it closes with its page.
--   local pop = W.Popover(button, 260, 120, "Alert me for")
---------------------------------------------------------------------------
function W.Popover(button, width, height, title)
    local page = (button.GetParent and button:GetParent()) or button
    local card = W.Card(page)
    W.Skin(card, "panel", 1, "glow")
    card:SetSize(width, height)
    card:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
    if card.SetFrameLevel then card:SetFrameLevel(((page.GetFrameLevel and page:GetFrameLevel()) or 1) + 30) end
    card:EnableMouse(true)
    card:Hide()
    if title then
        local h = W.Header(card, title)
        h:SetPoint("TOPLEFT", 8, -6)
    end
    button:SetScript("OnClick", function() if card:IsShown() then card:Hide() else card:Show() end end)
    if page.HookScript then page:HookScript("OnHide", function() card:Hide() end) end
    return card
end

---------------------------------------------------------------------------
-- A list that opens under a button (anything with the down arrow):
--   W.AttachMenu(button, { items = function() return list end,
--       label = function(v) return text end, current = function() return v end,
--       pick = function(v) ... end, width = n })
-- Click the button to open or close it; click a choice to pick it. Long
-- lists show 14 at a time and scroll with the mouse wheel, starting with the
-- current choice in view. It closes a moment after the mouse leaves it.
---------------------------------------------------------------------------
local MENU_ROWS = 14
function W.AttachMenu(b, spec)
    local width = spec.width or (b.GetWidth and b:GetWidth()) or 160
    local menu = W.Card(b)
    W.Skin(menu, "panel", 1, "glow")
    menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    if menu.SetFrameStrata then menu:SetFrameStrata("DIALOG") end
    menu:EnableMouse(true)
    menu:Hide()
    menu.offset = 0
    menu.more = W.Label(menu, "", "GameFontDisableSmall")
    menu.more:SetPoint("BOTTOMLEFT", 8, 4)
    b.menu, b.items = menu, {}
    local function list() return (spec.items and spec.items()) or {} end
    local function label(v) return spec.label and spec.label(v) or tostring(v) end
    local function draw()
        local all = list()
        local cur = spec.current and spec.current()
        local n = math.min(#all, MENU_ROWS)
        menu.offset = math.max(0, math.min(menu.offset, #all - n))
        for i = 1, n do
            local v = all[menu.offset + i]
            local it = b.items[i]
            if not it then
                it = W.MenuRow(menu, width - 8)
                b.items[i] = it
            end
            it:ClearAllPoints()
            it:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 21)
            it:SetWidth(width - 8)
            it:SetText(label(v))
            if v == cur then it:LockHighlight() else it:UnlockHighlight() end
            it:SetScript("OnClick", function()
                menu:Hide()
                spec.pick(v)
            end)
            it:Show()
        end
        for i = n + 1, #b.items do b.items[i]:Hide() end
        local extra = #all > n
        menu.more:SetText(extra and ("%d-%d of %d  ·  scroll for more"):format(menu.offset + 1, menu.offset + n, #all) or "")
        menu:SetSize(width, 8 + n * 21 + (extra and 14 or 0))
    end
    if menu.EnableMouseWheel then menu:EnableMouseWheel(true) end
    menu:SetScript("OnMouseWheel", function(_, delta) menu.offset = menu.offset - delta * 3; draw() end)
    menu:SetScript("OnUpdate", function(self)
        if self.IsMouseOver and not self:IsMouseOver(10, -10, -10, 10) and not b:IsMouseOver() then
            self.away = (self.away or 0) + 1
            if self.away > 75 then self:Hide() end
        else
            self.away = 0
        end
    end)
    function b:Open()
        local all, cur = list(), spec.current and spec.current()
        menu.offset = 0
        for i, v in ipairs(all) do
            if v == cur and i > MENU_ROWS then menu.offset = i - math.floor(MENU_ROWS / 2) end
        end
        menu.away = 0
        draw()
        menu:Show()
    end
    function b:CloseMenu() menu:Hide() end
    b:SetScript("OnClick", function() if menu:IsShown() then menu:Hide() else b:Open() end end)
    b:HookScript("OnHide", function() menu:Hide() end)
    return b
end

---------------------------------------------------------------------------
-- Dropdown: a button showing the current choice; clicking it opens the list
-- of choices underneath (click one, or the button again to close).
--   local d = W.Dropdown(parent, 130, options, getter, setter, prefix)
-- options: a list of values, or a function returning one. d.format(value)
-- gives the shown text; d:Refresh() (or d.Refresh()) after the value changes elsewhere.
---------------------------------------------------------------------------
function W.Dropdown(parent, width, options, getter, setter, prefix)
    local b = W.Button(parent, "", width)
    W.MarkChoice(b, "Click to pick from a list.")
    local function opts() return (type(options) == "function" and options()) or options or {} end
    local function label(v) return tostring(b.format and b.format(v) or v) end
    b.Refresh = function()
        local v = getter()
        if v == nil then v = opts()[1] end
        b:SetText((prefix or "") .. (v ~= nil and label(v) or ""))
    end
    W.AttachMenu(b, { width = width, items = opts, label = label, current = getter,
                      pick = function(v) setter(v); b.Refresh() end })
    b.Refresh()
    return b
end

-- "Wed 10/21 8:00 PM": how RUIN writes an event's time (local time).
function W.WhenText(at)
    local d = date("*t", at)
    local h = d.hour % 12
    if h == 0 then h = 12 end
    return ("%s %d/%d %d:%02d %s"):format(date("%a", at), d.month, d.day, h, d.min, d.hour >= 12 and "PM" or "AM")
end

---------------------------------------------------------------------------
-- When picker: a day dropdown (today and the next days, as "Wed 10/21"),
-- an hour box, a minute box and AM / PM. Times are your local time.
--   local p = W.WhenPicker(parent)        p:SetTime(t)
--   p:GetTime() -> epoch seconds, or nil and why
--   p:GetText() -> "2026-10-21 20:00" (what RUIN's event times are written as)
---------------------------------------------------------------------------
function W.WhenPicker(parent, days)
    days = days or 14
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(276, 24)
    local st = { day = 1, hour = 8, min = 0, ampm = "PM" }
    -- noon of the day `offset` days from today (noon keeps clear of daylight-saving edges)
    local function noon(offset)
        local t = date("*t")
        t.hour, t.min, t.sec = 12, 0, 0
        return time(t) + offset * 86400
    end
    local offsets = {}
    for i = 0, days - 1 do offsets[#offsets + 1] = i end
    f.day = W.Dropdown(f, 124, offsets, function() return st.day end, function(v) st.day = v end)
    f.day.format = function(off)
        local t = noon(off)
        local d = date("*t", t)
        return ("%s %d/%d"):format(off == 0 and "Today" or date("%a", t), d.month, d.day)
    end
    f.day.tipTitle = "Day"
    f.day:Refresh()
    f.day:SetPoint("LEFT", 0, 0)
    local function box(w, max, read)
        local e = W.EditBox(f, w, function(text) read(text) end)
        if e.SetNumeric then e:SetNumeric(true) end
        if e.SetMaxLetters then e:SetMaxLetters(max) end
        if e.SetJustifyH then e:SetJustifyH("CENTER") end
        return e
    end
    local function clampHour(text)
        local h = tonumber(text)
        if h and h >= 1 and h <= 12 then st.hour = h end
        f.hour:SetText(tostring(st.hour))
    end
    local function clampMin(text)
        local m = tonumber(text)
        if m and m >= 0 and m <= 59 then st.min = m end
        f.min:SetText(("%02d"):format(st.min))
    end
    f.hour = box(34, 2, clampHour)
    f.hour:SetPoint("LEFT", f.day, "RIGHT", 6, 0)
    f.colon = W.Label(f, ":")
    f.colon:SetPoint("LEFT", f.hour, "RIGHT", 3, 0)
    f.min = box(34, 2, clampMin)
    f.min:SetPoint("LEFT", f.hour, "RIGHT", 10, 0)
    f.ampm = W.Dropdown(f, 62, { "AM", "PM" }, function() return st.ampm end, function(v) st.ampm = v end)
    f.ampm.tipTitle = "AM or PM"
    f.ampm:SetPoint("LEFT", f.min, "RIGHT", 6, 0)

    function f:GetTime()
        local h, m = tonumber(self.hour:GetText()), tonumber(self.min:GetText())
        if not h or h < 1 or h > 12 then return nil, "the hour must be 1 to 12" end
        if not m or m < 0 or m > 59 then return nil, "the minutes must be 0 to 59" end
        local t = date("*t", noon(st.day))
        local h24 = h % 12 + (st.ampm == "PM" and 12 or 0)
        t.hour, t.min, t.sec = h24, m, 0
        return time(t)
    end
    function f:GetText()
        local t, err = self:GetTime()
        if not t then return nil, err end
        return date("%Y-%m-%d %H:%M", t)
    end
    function f:SetTime(when)
        local d = date("*t", when)
        local today = date("*t", noon(0))
        local a = time({ year = d.year, month = d.month, day = d.day, hour = 12 })
        local b = time({ year = today.year, month = today.month, day = today.day, hour = 12 })
        st.day = math.max(0, math.min(days - 1, math.floor((a - b) / 86400 + 0.5)))
        st.ampm = d.hour >= 12 and "PM" or "AM"
        st.hour = d.hour % 12
        if st.hour == 0 then st.hour = 12 end
        st.min = d.min
        self.hour:SetText(tostring(st.hour))
        self.min:SetText(("%02d"):format(st.min))
        self.day:Refresh()
        self.ampm:Refresh()
    end
    -- default: tomorrow, 8:00 PM
    f:SetTime(noon(1) + 8 * 3600)
    return f
end

---------------------------------------------------------------------------
-- Pills: small colored tags such as Quick / Medium / Long.
--   local p = W.Pill(row, 58); p:SetTag("Quick")  or  p:SetTag("Sample", "Classic sample")
-- W.TagText("Quick") gives the same tag as colored text for list lines.
---------------------------------------------------------------------------
function W.Pill(parent, width, height)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(width or 58, height or 16)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.edge = p:CreateTexture(nil, "BORDER")
    p.edge:SetPoint("TOPLEFT", 0, 0)
    p.edge:SetPoint("TOPRIGHT", 0, 0)
    p.edge:SetHeight(1)
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.text:SetPoint("CENTER", 0, 0)
    function p:SetTag(tag, label)
        local t = W.TAGS[tag] or W.TAGS.Sample
        self.bg:SetColorTexture(t.bg[1], t.bg[2], t.bg[3], 0.95)
        self.edge:SetColorTexture(t.fg[1], t.fg[2], t.fg[3], 0.35)
        self.text:SetTextColor(t.fg[1], t.fg[2], t.fg[3])
        self.text:SetText(label or tag)
        self:Show()
    end
    return p
end

function W.TagText(tag, label)
    local t = W.TAGS[tag] or W.TAGS.Sample
    return ("|cff%02x%02x%02x%s|r"):format(t.fg[1] * 255, t.fg[2] * 255, t.fg[3] * 255, label or tag)
end

---------------------------------------------------------------------------
-- Progress bar ("4/6 collected"). bar:SetValue(0..1), bar:SetColor(key).
---------------------------------------------------------------------------
function W.Progress(parent, width, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 200, height or 8)
    W.Skin(f, "bg", 1, "border")
    f.fill = f:CreateTexture(nil, "ARTWORK")
    f.fill:SetPoint("TOPLEFT", 1, -1)
    f.fill:SetPoint("BOTTOMLEFT", 1, 1)
    f.fill:SetWidth(1)
    function f:SetColor(key)
        local r, g, b = rgb(key or "good")
        self.fill:SetColorTexture(r, g, b, 1)
    end
    function f:SetValue(v)
        v = math.max(0, math.min(1, tonumber(v) or 0))
        self.value = v
        local w = (self:GetWidth() or 0) - 2
        self.fill:SetWidth(math.max(1, w * v))
        self.fill:SetShown(v > 0)
    end
    f:SetScript("OnSizeChanged", function(self) self:SetValue(self.value or 0) end)
    f:SetColor("good")
    f:SetValue(0)
    return f
end

---------------------------------------------------------------------------
-- On-screen frames (HUDs, trackers, badges) in a module's colors.
-- Draggable; the position is saved in store[key]. Couch mode scales them.
---------------------------------------------------------------------------
local hudFrames = {}

local function hudScale()
    return (ns.db and ns.db.settings and ns.db.settings.couchMode) and 1.15 or 1
end

-- A flat close button: a quiet x that turns red under the mouse. size is
-- the square's side (22 in the main window, 18 on small windows).
function W.CloseButton(parent, onClick, size)
    size = size or 22
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    W.Skin(b, "panel", 0, "panel")
    W.SetBorder(b, "border", 0)
    local bars = {}
    for i, angle in ipairs({ 45, -45 }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(P.sub[1], P.sub[2], P.sub[3], 1)
        t:SetSize(math.floor(size * 0.55 + 0.5), 2)
        t:SetPoint("CENTER")
        t:SetRotation(math.rad(angle))
        bars[i] = t
    end
    b.bars = bars
    b:SetScript("OnEnter", function(self)
        W.Skin(self, { 0.62, 0.20, 0.18 }, 0.85, { 0.85, 0.35, 0.30 })
        for _, t in ipairs(bars) do t:SetColorTexture(1, 1, 1, 1) end
        if type(self.tip) == "string" and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(self.tip, 1, 1, 1, true); GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        W.Skin(self, "panel", 0, "panel")
        W.SetBorder(self, "border", 0)
        for _, t in ipairs(bars) do t:SetColorTexture(P.sub[1], P.sub[2], P.sub[3], 1) end
        if type(self.tip) == "string" and GameTooltip then GameTooltip:Hide() end
    end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- The head of a small window (an alert, a HUD panel): the module's glyph in
-- its color, a title in small capitals, and a hairline under them. Returns
-- the height it takes, so the content can start below it.
function W.HudHeader(f, title)
    local theme = W.ThemeOf(f)
    local ac = W.SchemeOf(f).accent
    local x = 12
    if theme and theme.glyph then
        local g = f:CreateTexture(nil, "ARTWORK")
        g:SetTexture(theme.glyph)
        g:SetVertexColor(ac[1], ac[2], ac[3], 1)
        g:SetSize(14, 14)
        g:SetPoint("TOPLEFT", 11, -10)
        f.headGlyph = g
        x = 31
    end
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetText((title or ""):upper())
    t:SetTextColor(ac[1], ac[2], ac[3], 1)
    t:SetPoint("TOPLEFT", x, -12)
    f.headTitle = t
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(P.line[1], P.line[2], P.line[3], 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 1, -32)
    line:SetPoint("TOPRIGHT", -1, -32)
    f.headLine = line
    return 33
end

function W.HudFrame(name, themeKey, store, key, point)
    local theme = ns.ThemeFor and ns.ThemeFor(themeKey) or nil
    local c = theme and W.SchemeFor(theme).accent or W.PALETTE.glow
    local f = CreateFrame("Frame", name, UIParent)
    f.ruinTheme = theme
    W.Skin(f, "bg", 0.94, "border")
    f.sheen = W.Sheen(f, 0.04)
    -- Modules written for Blizzard backdrops can still tint the frame.
    f.SetBackdropBorderColor = function(self, r, g, b, a) W.SetBorder(self, { r, g, b }, a) end
    f.SetBackdropColor = function(self, r, g, b, a) self.skinBg:SetColorTexture(r, g, b, a or 0.9) end
    -- A thin band in the module color along the top edge.
    local band = f:CreateTexture(nil, "ARTWORK")
    band:SetColorTexture(c[1], c[2], c[3], 0.9)
    band:SetHeight(2)
    band:SetPoint("TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", 0, 0)
    f.band = band
    f.themeColor = c
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    local p = store and store[key]
    if type(p) == "table" and p.point then
        f:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
    else
        f:SetPoint(unpack(point or { "CENTER" }))
    end
    -- Moving: it follows the mouse the moment the left button goes down (no
    -- drag threshold to wait out), from anywhere on it; children that take the
    -- mouse (rows with tooltips) pass the press on with f:DragBy(child).
    f:EnableMouse(true)
    f:SetMovable(true)
    -- the move ends when the button comes up, even if the module set its own
    -- OnMouseUp (a click badge); f.justMoved says the press was a drag, not a click
    local watcher = CreateFrame("Frame")
    local startX, startY
    local stopMove
    local function startMove(self)
        if self.moving then return end
        self.moving, self.justMoved = true, false
        startX, startY = self:GetLeft(), self:GetTop()
        if GameTooltip then GameTooltip:Hide() end
        self:StartMoving()
        local down = rawget(_G, "IsMouseButtonDown")
        if down then
            watcher:SetScript("OnUpdate", function()
                if not down("LeftButton") then stopMove(self) end
            end)
        end
    end
    function stopMove(self)
        if not self.moving then return end
        self.moving = false
        watcher:SetScript("OnUpdate", nil)
        self:StopMovingOrSizing()
        local x, y = self:GetLeft(), self:GetTop()
        self.justMoved = startX ~= nil and x ~= nil and (math.abs(x - startX) + math.abs((y or 0) - (startY or 0))) > 3
        if store then
            local pt, _, rel, px, py = self:GetPoint()
            store[key] = { point = pt, rel = rel, x = px, y = py }
        end
    end
    f.StartMove, f.StopMove = startMove, stopMove
    f:SetScript("OnMouseDown", function(self, button) if button == "LeftButton" then startMove(self) end end)
    f:SetScript("OnMouseUp", function(self, button) if button == "LeftButton" then stopMove(self) end end)
    f:HookScript("OnHide", stopMove)
    function f:DragBy(child)
        child:EnableMouse(true)
        child:HookScript("OnMouseDown", function(_, button) if button == "LeftButton" then startMove(f) end end)
        child:HookScript("OnMouseUp", function(_, button) if button == "LeftButton" then stopMove(f) end end)
        return child
    end
    f:SetScale(hudScale())
    hudFrames[#hudFrames + 1] = f
    return f
end

-- A module's own window (an editor, a prompt) in that module's colors: the
-- controls built on it afterwards pick up its accent, and it wears a thin
-- band of the color along the top. Call it before adding the controls.
--   W.Themed(frame, "Pathfinder")
function W.Themed(f, themeKey)
    local theme = ns.ThemeFor and ns.ThemeFor(themeKey) or nil
    if not (f and theme) then return f end
    f.ruinTheme, f.ruinThemeFound = theme, nil
    if not f.band and f.CreateTexture then
        local c = W.SchemeFor(theme).accent
        f.band = f:CreateTexture(nil, "ARTWORK")
        f.band:SetColorTexture(c[1], c[2], c[3], 0.9)
        f.band:SetHeight(2)
        f.band:SetPoint("TOPLEFT", 0, 0)
        f.band:SetPoint("TOPRIGHT", 0, 0)
    end
    return f
end

function W.ApplyHudScale()
    local s = hudScale()
    for _, f in ipairs(hudFrames) do f:SetScale(s) end
end

---------------------------------------------------------------------------
-- Inline icons for text: roles and classes.
---------------------------------------------------------------------------
local ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = { T = "0:19:22:41", H = "20:39:1:20", D = "20:39:22:41" }
function W.RoleIcon(role, size)
    local k = (role == "TANK" or role == "T") and "T" or ((role == "HEALER" or role == "H") and "H" or "D")
    size = size or 14
    return ("|T%s:%d:%d:0:0:64:64:%s|t"):format(ROLE_TEX, size, size, ROLE_COORDS[k])
end

function W.ClassIcon(class, size)
    local tc = CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class]
    if not tc then return "" end
    size = size or 14
    return ("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:%d:%d:0:0:256:256:%d:%d:%d:%d|t")
        :format(size, size, tc[1] * 256, tc[2] * 256, tc[3] * 256, tc[4] * 256)
end

---------------------------------------------------------------------------
-- Formatting helpers
---------------------------------------------------------------------------
-- Money with the game's own coin icons: 1[g] 5[s], 1[s] 44[c], 36[c].
local COIN = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
W.COIN = COIN

function W.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g = math.floor(copper / 10000)
    local s = math.floor(copper / 100) % 100
    local c = copper % 100
    if g > 0 then return s > 0 and (g .. COIN.g .. " " .. s .. COIN.s) or (g .. COIN.g) end
    if s > 0 then return c > 0 and (s .. COIN.s .. " " .. c .. COIN.c) or (s .. COIN.s) end
    return c .. COIN.c
end

-- The same text with the coin icons as letters (1g 5s), for plain text.
function W.PlainMoney(text)
    return (tostring(text or ""):gsub("|TInterface\\MoneyFrame\\UI%-(%a)%a+Icon[^|]*|t", function(k) return k:lower() end))
end

function W.Ago(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
    return math.floor(seconds / 86400) .. "d ago"
end

-- "3d 4h", "2h 05m", "14m", "45s"
function W.Duration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds >= 86400 then return ("%dd %dh"):format(seconds / 86400, (seconds % 86400) / 3600) end
    if seconds >= 3600 then return ("%dh %02dm"):format(seconds / 3600, (seconds % 3600) / 60) end
    if seconds >= 60 then return ("%dm"):format(seconds / 60) end
    return ("%ds"):format(seconds)
end

function W.ClassName(name, class)
    local short = ns.ShortName(name)
    local color = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if color and color.WrapTextInColorCode then return color:WrapTextInColorCode(short) end
    return short
end

---------------------------------------------------------------------------
-- Toasts: short alerts stacked near the top of the screen
---------------------------------------------------------------------------
local toastFrame
local toastLines = {}
local MAX_TOASTS, TOAST_SECONDS = 4, 8

local function toastHost()
    if toastFrame then return toastFrame end
    toastFrame = CreateFrame("Frame", "RUIN_ToastFrame", UIParent)
    toastFrame:SetSize(520, 20)
    toastFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    toastFrame:SetFrameStrata("HIGH")
    for i = 1, MAX_TOASTS do
        local fs = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetPoint("TOP", toastFrame, "TOP", 0, -(i - 1) * 24)
        fs:SetWidth(520)
        toastLines[i] = { fs = fs, expires = 0 }
    end
    return toastFrame
end

local function redrawToasts()
    local now = GetTime()
    for _, line in ipairs(toastLines) do
        if line.expires <= now then line.fs:SetText("") end
    end
end

-- opts: { sound = true }
function W.Toast(text, opts)
    toastHost()
    -- shift older toasts down
    for i = MAX_TOASTS, 2, -1 do
        toastLines[i].fs:SetText(toastLines[i - 1].fs:GetText() or "")
        toastLines[i].expires = toastLines[i - 1].expires
    end
    toastLines[1].fs:SetText(text)
    toastLines[1].expires = GetTime() + TOAST_SECONDS
    C_Timer.After(TOAST_SECONDS + 0.1, redrawToasts)
    if opts and opts.sound and PlaySound then
        local kit = SOUNDKIT and (SOUNDKIT.RAID_WARNING or SOUNDKIT.READY_CHECK)
        if kit then pcall(PlaySound, kit, "Master") end
    end
    -- Also leave a copy in chat so nothing is missed.
    ns:Print(text)
end
