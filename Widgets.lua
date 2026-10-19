-- RUIN Core: shared widget kit and toast alerts
-- Modules build their pages from these so every RUIN addon looks and
-- behaves the same (and couch mode / scaling applies everywhere).
local ADDON, ns = ...

local W = {}
ns.Widgets = W

W.COLORS = {
    accent = "|cffc41e3a", good = "|cff40ff40", bad = "|cffff6060",
    gold = "|cffffd100", dim = "|cff888888", white = "|cffffffff",
}

function W.Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

-- While a module page is being built, Core sets W.currentTheme so headers
-- and lists pick up that module's colors without the module doing anything.
W.currentTheme = nil

-- Section heading: gold title with a short underline in the page's color.
function W.Header(parent, text)
    local fs = W.Label(parent, text, "GameFontNormal")
    local t = W.currentTheme
    if t then
        local c = t.color
        local rule = parent:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(c[1], c[2], c[3], 0.9)
        rule:SetSize(48, 2)
        rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
    end
    return fs
end

function W.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 120, 24)
    b:SetText(text)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Check box with its own label; call :Refresh() to sync from getter.
function W.Check(parent, label, getter, setter)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c.label = W.Label(parent, label)
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    c.Refresh = function(self) self:SetChecked(getter() and true or false) end
    c:Refresh()
    return c
end

-- Single-line input; onCommit(text) on Enter or when focus leaves.
function W.EditBox(parent, width, onCommit)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width or 160, 22)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    local function commit(self)
        self:ClearFocus()
        if onCommit then onCommit(self:GetText() or "") end
    end
    e:SetScript("OnEnterPressed", commit)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(self) if onCommit then onCommit(self:GetText() or "") end end)
    return e
end

-- Button that cycles through options: left-click next, right-click previous.
function W.Cycle(parent, width, options, getter, setter, prefix)
    local b = W.Button(parent, "", width)
    local function show()
        b:SetText((prefix or "") .. tostring(getter() or options[1]))
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
    r.zebra:SetAlpha(0.22)
    if (r.link or r.tip) and GameTooltip then
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        if r.link then pcall(GameTooltip.SetHyperlink, GameTooltip, r.link) end
        if r.tip then pcall(r.tip, GameTooltip) end
        GameTooltip:Show()
    end
end

local function rowLeave(r)
    r.zebra:SetAlpha(r.zebraAlpha or 0)
    if (r.link or r.tip) and GameTooltip then GameTooltip:Hide() end
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
                -- Zebra rows tinted with the page color; brighter on hover.
                row.zebra = row:CreateTexture(nil, "BACKGROUND")
                row.zebra:SetAllPoints()
                local c = self.theme and self.theme.color or { 1, 1, 1 }
                row.zebra:SetColorTexture(c[1], c[2], c[3], 1)
                row:EnableMouse(true)
                row:SetScript("OnEnter", rowEnter)
                row:SetScript("OnLeave", rowLeave)
                setupRow(row)
                self.rows[i] = row
            end
            row.zebraAlpha = (i % 2 == 0) and 0.10 or 0.04
            row.zebra:SetAlpha(row.zebraAlpha)
            row.link, row.tip = nil, nil
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            updateRow(row, item, i)
            row:Show()
        end
        for i = #self.items + 1, #self.rows do self.rows[i]:Hide() end
        child:SetHeight(math.max(10, #self.items * rowHeight))
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
W.SUBTAB_HEIGHT = 30

function W.SubTabs(parent, names, onSelect)
    local t = W.currentTheme
    local c = t and t.color or { 0.77, 0.12, 0.23 }
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(24)
    local base = bar:CreateTexture(nil, "BACKGROUND")
    base:SetColorTexture(c[1], c[2], c[3], 0.45)
    base:SetHeight(1)
    base:SetPoint("BOTTOMLEFT", 0, 0)
    base:SetPoint("BOTTOMRIGHT", 0, 0)

    local obj = { bar = bar, buttons = {}, pages = {}, names = names }
    local function paint(i)
        local b = obj.buttons[i]
        local on = obj.selected == i
        b.bg:SetAlpha(on and 0.38 or 0.08)
        b.line:SetShown(on)
        if on then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(1, 0.82, 0) end
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
        b:SetWidth(math.max(72, (b.text:GetStringWidth() or 60) + 26))
    end

    local prev
    for i, name in ipairs(names) do
        local b = CreateFrame("Button", nil, bar)
        b:SetHeight(24)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(c[1], c[2], c[3], 1)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetColorTexture(1, 0.82, 0, 1)
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 0, 0)
        b.line:SetPoint("BOTTOMRIGHT", 0, 0)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER", 0, 1)
        b.text:SetText(name)
        b:SetWidth(math.max(72, (b.text:GetStringWidth() or 60) + 26))
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0) end
        b:SetScript("OnEnter", function(self) if obj.selected ~= i then self.bg:SetAlpha(0.22) end end)
        b:SetScript("OnLeave", function() paint(i) end)
        b:SetScript("OnClick", function() obj:Select(i) end)
        obj.buttons[i] = b

        local page = CreateFrame("Frame", nil, parent)
        page:SetPoint("TOPLEFT", 0, -W.SUBTAB_HEIGHT)
        page:SetPoint("BOTTOMRIGHT", 0, 0)
        page:Hide()
        obj.pages[i] = page
        prev = b
    end
    return obj
end

---------------------------------------------------------------------------
-- Card: a faintly tinted box in the page's color, for grouping controls.
---------------------------------------------------------------------------
function W.Card(parent)
    local t = W.currentTheme
    local c = t and t.color or { 0.5, 0.5, 0.55 }
    local f = CreateFrame("Frame", nil, parent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(c[1], c[2], c[3], 0.07)
    local edges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local e = f:CreateTexture(nil, "BORDER")
        e:SetColorTexture(c[1], c[2], c[3], i == 1 and 0.7 or 0.3)
        if side == "TOP" or side == "BOTTOM" then
            e:SetHeight(1)
            e:SetPoint(side .. "LEFT", 0, 0)
            e:SetPoint(side .. "RIGHT", 0, 0)
        else
            e:SetWidth(1)
            e:SetPoint("TOP" .. side, 0, 0)
            e:SetPoint("BOTTOM" .. side, 0, 0)
        end
        edges[side] = e
    end
    f.edges = edges
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
    local c = theme and theme.color or { 0.77, 0.12, 0.23 }
    local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
                        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.03, 0.03, 0.05, 0.88)
        f:SetBackdropBorderColor(c[1] * 0.9 + 0.1, c[2] * 0.9 + 0.1, c[3] * 0.9 + 0.1, 1)
    end
    -- A thin band in the module color along the top edge.
    local band = f:CreateTexture(nil, "ARTWORK")
    band:SetColorTexture(c[1], c[2], c[3], 0.85)
    band:SetHeight(2)
    band:SetPoint("TOPLEFT", 4, -4)
    band:SetPoint("TOPRIGHT", -4, -4)
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
