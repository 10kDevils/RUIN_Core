-- RUIN Core: shared widget kit and toast alerts
-- Modules build their pages from these so every RUIN addon looks and
-- behaves the same (and couch mode / scaling applies everywhere).
local ADDON, ns = ...

local W = {}
ns.Widgets = W

-- The RUIN look (from the RUIN Companion brief): dark navy panels with thin
-- steel-blue edges, teal for focus and selection, gold for the RUIN mark.
W.PALETTE = {
    bg      = { 0.027, 0.043, 0.075 },   -- window body
    panel   = { 0.047, 0.071, 0.114 },   -- cards and rows
    panelHi = { 0.075, 0.110, 0.169 },   -- buttons, raised rows
    border  = { 0.165, 0.267, 0.400 },   -- steel-blue edges
    glow    = { 0.329, 0.718, 0.851 },   -- teal: selected tab, hover, links
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

W.CORE_SCHEME = { accent = P.glow, edge = P.border, panel = P.panel, panelHi = P.panelHi, bg = P.bg,
                  mark = P.gold, core = true }
local schemes = {}

function W.SchemeFor(theme)
    if not theme or theme.core or not theme.color then return W.CORE_SCHEME end
    local s = schemes[theme]
    if s then return s end
    local c = theme.color
    s = {
        color   = c,
        accent  = mix(c, { 1, 1, 1 }, 0.15),     -- a touch lighter so it reads on navy
        edge    = mix(P.border, c, 0.55),
        panel   = mix(P.panel, c, 0.07),
        panelHi = mix(P.panelHi, c, 0.14),
        bg      = mix(P.bg, c, 0.04),
        mark    = c,
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
    fs:SetTextColor(rgb("text"))
    local rule = parent:CreateTexture(nil, "ARTWORK")
    local a = W.SchemeOf(parent).accent
    rule:SetColorTexture(a[1], a[2], a[3], 0.85)
    rule:SetSize(40, 2)
    rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
    fs.rule = rule
    return fs
end

-- Navy button with a steel edge that lights teal on hover. LockHighlight
-- marks a button as selected (used by list-of-buttons pickers).
local function paintButton(b)
    if not b.skinBg then return end
    if not b:IsEnabled() then
        W.Skin(b, "panel", 0.85, "border")
        b.label:SetTextColor(0.45, 0.50, 0.58)
    elseif b.locked then
        W.Skin(b, "panelHi", 1, "glow")
        b.label:SetTextColor(1, 1, 1)
    elseif b.hover then
        W.Skin(b, "panelHi", 1, "glow")
        b.label:SetTextColor(1, 1, 1)
    else
        W.Skin(b, "panelHi", 1, "border")
        b.label:SetTextColor(rgb("text"))
    end
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
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    local ac = W.SchemeOf(b).accent
    hl:SetColorTexture(ac[1], ac[2], ac[3], 0.10)
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

-- Check box with its own label (the label is clickable too); call
-- :Refresh() to sync from getter. A navy box that fills with the page color.
function W.Check(parent, label, getter, setter)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(24, 24)
    c.box = CreateFrame("Frame", nil, c)
    c.box:SetSize(16, 16)
    c.box:SetPoint("LEFT", 3, 0)
    W.Skin(c.box, "bg", 1, "border")
    c.mark = c.box:CreateTexture(nil, "OVERLAY")
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    local ac = W.SchemeOf(c).accent
    c.mark:SetColorTexture(ac[1], ac[2], ac[3], 1)
    c.label = W.Label(c, label)          -- a child, so it hides with the box
    c.label:SetPoint("LEFT", c, "RIGHT", -1, 0)
    if c.SetHitRectInsets then c:SetHitRectInsets(0, -((c.label:GetStringWidth() or 60) + 6), 0, 0) end
    local function sync() c.mark:SetShown(c:GetChecked() and true or false) end
    c:SetScript("OnClick", function(self)
        sync()
        setter(self:GetChecked() and true or false)
    end)
    -- c.tip = "One line saying what it does" shows on hover.
    c:SetScript("OnEnter", function(self)
        W.SetBorder(self.box, "glow")
        if self.tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    c:SetScript("OnLeave", function(self)
        W.SetBorder(self.box, "border")
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
    for i, angle in ipairs({ -45, 45 }) do      -- a small down chevron
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(ac[1], ac[2], ac[3], 0.9)
        t:SetSize(5, 2)
        t:SetPoint("RIGHT", b, "RIGHT", i == 1 and -10 or -7, 0)
        t:SetRotation(math.rad(angle))
    end
    b:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if self.tipTitle then GameTooltip:AddLine(self.tipTitle, 1, 1, 1) end
        GameTooltip:AddLine(hint or "Click for the next choice, right-click to go back.", 0.7, 0.75, 0.8)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

-- Button that cycles through options: left-click next, right-click previous.
-- A small chevron marks it as a choice, and hovering says how it works.
function W.Cycle(parent, width, options, getter, setter, prefix)
    local b = W.Button(parent, "", width)
    W.MarkChoice(b)
    -- b.format = function(value) return "Shown text" end  (then b:Refresh())
    local function show()
        local v = getter() or options[1]
        b:SetText((prefix or "") .. tostring(b.format and b.format(v) or v))
    end
    b:SetScript("OnClick", function(_, mouse)
        local cur, idx = getter(), 1
        for i, v in ipairs(options) do if v == cur then idx = i end end
        idx = (mouse == "RightButton") and (idx - 2) % #options + 1 or idx % #options + 1
        setter(options[idx])
        show()
    end)
    b.Refresh = show
    show()
    return b
end

-- Scrolling list. setupRow(row) creates the row's regions once;
-- updateRow(row, item, index) fills them. list:SetItems(items).
-- A row with row.link set shows that item's tooltip on hover; row.tip
-- (a function(tooltip)) adds any other tooltip. list:SetEmptyText(text)
-- shows a line when there is nothing to list.
local function rowEnter(r)
    local ac = W.SchemeOf(r).accent
    r.zebra:SetColorTexture(ac[1], ac[2], ac[3], 0.14)
    if (r.link or r.tip) and GameTooltip then
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        if r.link then pcall(GameTooltip.SetHyperlink, GameTooltip, r.link) end
        if r.tip then pcall(r.tip, GameTooltip) end
        GameTooltip:Show()
    end
end

local function rowLeave(r)
    local c = W.SchemeOf(r).panelHi
    r.zebra:SetColorTexture(c[1], c[2], c[3], r.zebraAlpha or 0)
    if (r.link or r.tip) and GameTooltip then GameTooltip:Hide() end
end

-- Show a scroll frame's scroll bar only when there is something to scroll.
-- Call after the content changes; it also rechecks when the frame is shown
-- or resized.
function W.FitScrollBar(sf)
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

function W.List(parent, rowHeight, setupRow, updateRow)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
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
                -- Navy zebra rows (tinted on module pages); the page color on hover.
                row.zebra = row:CreateTexture(nil, "BACKGROUND")
                row.zebra:SetAllPoints()
                row:EnableMouse(true)
                row:SetScript("OnEnter", rowEnter)
                row:SetScript("OnLeave", rowLeave)
                setupRow(row)
                self.rows[i] = row
            end
            row.zebraAlpha = (i % 2 == 0) and 0.85 or 0.35
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
    local base = bar:CreateTexture(nil, "BACKGROUND")
    local edge = W.SchemeOf(bar).edge
    base:SetColorTexture(edge[1], edge[2], edge[3], 0.8)
    base:SetHeight(1)
    base:SetPoint("BOTTOMLEFT", 0, -3)
    base:SetPoint("BOTTOMRIGHT", 0, -3)

    local obj = { bar = bar, buttons = {}, pages = {}, names = names }
    local function paint(i)
        local b = obj.buttons[i]
        local on = obj.selected == i
        if on then
            W.Skin(b, "panelHi", 1, "glow")
            b.text:SetTextColor(1, 1, 1)
        elseif b.hover then
            W.Skin(b, "panelHi", 0.9, "border")
            b.text:SetTextColor(rgb("text"))
        else
            W.Skin(b, "panel", 0.9, "border")
            b.text:SetTextColor(rgb("sub"))
        end
        b.line:SetShown(on)
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
        W.Skin(b, "panel", 0.9, "border")
        b.line = b:CreateTexture(nil, "ARTWORK")
        local ac = W.SchemeOf(b).accent
        b.line:SetColorTexture(ac[1], ac[2], ac[3], 1)
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 1, 1)
        b.line:SetPoint("BOTTOMRIGHT", -1, 1)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("CENTER", 0, 1)
        b.text:SetText(name)
        b:SetWidth(math.max(78, (b.text:GetStringWidth() or 60) + 28))
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0) end
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
                if last then btn:SetPoint("LEFT", last, "RIGHT", 4, 0) else btn:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0) end
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
    W.Skin(f, "panel", 0.92, "border")
    if t and t.color then
        local c = t.color
        local accent = f:CreateTexture(nil, "ARTWORK")
        accent:SetColorTexture(c[1], c[2], c[3], 0.9)
        accent:SetSize(48, 2)
        accent:SetPoint("TOPLEFT", 1, -1)
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
            it = W.Button(m, "", 170)
            it:SetHeight(20)
            it.label:SetJustifyH("LEFT")
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
-- Dropdown: a button showing the current choice; clicking it opens the list
-- of choices underneath (click one, or the button again to close).
--   local d = W.Dropdown(parent, 130, options, getter, setter, prefix)
-- options: a list of values, or a function returning one. d.format(value)
-- gives the shown text; d:Refresh() after the value changes elsewhere.
---------------------------------------------------------------------------
function W.Dropdown(parent, width, options, getter, setter, prefix)
    local b = W.Button(parent, "", width)
    W.MarkChoice(b, "Click to pick from a list.")
    local menu = W.Card(b)
    W.Skin(menu, "panel", 1, "glow")
    menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    if menu.SetFrameStrata then menu:SetFrameStrata("DIALOG") end
    menu:EnableMouse(true)
    menu:Hide()
    b.menu, b.items = menu, {}
    local function opts() return (type(options) == "function" and options()) or options or {} end
    local function label(v) return tostring(b.format and b.format(v) or v) end
    function b:Refresh()
        local v = getter()
        if v == nil then v = opts()[1] end
        self:SetText((prefix or "") .. (v ~= nil and label(v) or ""))
    end
    function b:Open()
        local list = opts()
        local cur = getter()
        for i, v in ipairs(list) do
            local it = b.items[i]
            if not it then
                it = W.Button(menu, "", width - 8)
                it:SetHeight(20)
                it.label:SetJustifyH("LEFT")
                b.items[i] = it
            end
            it:ClearAllPoints()
            it:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 21)
            it:SetWidth(width - 8)
            it:SetText(label(v))
            if v == cur then it:LockHighlight() else it:UnlockHighlight() end
            it:SetScript("OnClick", function()
                menu:Hide()
                setter(v)
                b:Refresh()
            end)
            it:Show()
        end
        for i = #list + 1, #b.items do b.items[i]:Hide() end
        menu:SetSize(width, 8 + #list * 21)
        menu:Show()
    end
    b:SetScript("OnClick", function() if menu:IsShown() then menu:Hide() else b:Open() end end)
    b:HookScript("OnHide", function() menu:Hide() end)
    b:Refresh()
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

function W.HudFrame(name, themeKey, store, key, point)
    local theme = ns.ThemeFor and ns.ThemeFor(themeKey) or nil
    local c = theme and theme.color or W.PALETTE.glow
    local f = CreateFrame("Frame", name, UIParent)
    f.ruinTheme = theme
    W.Skin(f, "bg", 0.90, "border")
    -- Modules written for Blizzard backdrops can still tint the frame.
    f.SetBackdropBorderColor = function(self, r, g, b, a) W.SetBorder(self, { r, g, b }, a) end
    f.SetBackdropColor = function(self, r, g, b, a) self.skinBg:SetColorTexture(r, g, b, a or 0.9) end
    -- A thin band in the module color along the top edge.
    local band = f:CreateTexture(nil, "ARTWORK")
    band:SetColorTexture(c[1], c[2], c[3], 0.85)
    band:SetHeight(2)
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
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
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if store then
            local pt, _, rel, x, y = self:GetPoint()
            store[key] = { point = pt, rel = rel, x = x, y = y }
        end
    end)
    f:SetScale(hudScale())
    hudFrames[#hudFrames + 1] = f
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
function W.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g = math.floor(copper / 10000)
    local s = math.floor(copper / 100) % 100
    local c = copper % 100
    if g > 0 then return ("%dg %02ds"):format(g, s) end
    if s > 0 then return ("%ds %02dc"):format(s, c) end
    return ("%dc"):format(c)
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
