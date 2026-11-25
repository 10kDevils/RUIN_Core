-- RUIN Core: the world map and quest log, in the game's own look or in
-- Pathfinder's, the same design language as its minimap and objective
-- tracker: the game's gold frame, portrait, parchment and header bars give
-- way to a panel in the suite's HUD look (its edges, the accent band, a
-- slight green to black gradient at the opacity you pick); the title, the
-- breadcrumb bar and the quest log's zone headers take Pathfinder's color;
-- quest markers, collapse buttons and the window's buttons are drawn flat.
-- The game still lays out and runs the map and the log.
local ADDON, ns = ...
local R = RUIN_API
if not R then return end
local W = R.Widgets
local MM = ns.Minimap
local OT = ns.Objectives

local WM = {}
ns.WorldMap = WM

local L = ns.Looks
WM.STYLES = L.KEYS
WM.STYLE_LABEL = L.LABEL

local OWNER = "worldmap"
local LINE = { 0.60, 0.64, 0.70 }
local TEXT = { 0.92, 0.94, 0.96 }

local db
local panel            -- the panel behind the window
local colored = {}     -- fontstring -> its own color, to give back

local function map() return rawget(_G, "WorldMapFrame") end
local function questMap() return rawget(_G, "QuestMapFrame") end

function WM.Style()
    local s = db and db.wmStyle
    return (s and L.Valid(s)) and s or "blizzard"
end
function WM.Scheme() local s = WM.Style(); return L.Scheme(s ~= "blizzard" and s or "pathfinder") end
function WM.Theme() local s = WM.Style(); return L.Theme(s ~= "blizzard" and s or "pathfinder") end
function WM.Alpha() return (db and db.wmAlpha) or 0.95 end
local function on() return WM.Style() ~= "blizzard" end

local function accent() return WM.Scheme().accent end

local function color(fs, c)
    if type(fs) ~= "table" or not fs.SetTextColor then return end
    if colored[fs] == nil and fs.GetTextColor then colored[fs] = { fs:GetTextColor() } end
    fs:SetTextColor(c[1], c[2], c[3])
end

local function visible(x)
    if type(x) ~= "table" then return false end
    if x.IsVisible then return x:IsVisible() end
    return x.IsShown == nil or x:IsShown()
end

local function isTexture(r) return type(r) == "table" and r.GetObjectType and r:GetObjectType() == "Texture" end

-- The game's art on a frame: every picture it holds (not its children's).
local function dimArt(frame, test)
    if type(frame) ~= "table" or not frame.GetRegions then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if isTexture(r) and not r.ruinOwn and (not test or test(r)) then MM.Dim(r, true) end
    end
end

-- Large pictures (backgrounds, parchment) and anything named or drawn as a
-- border, background or inset: frame art, not icons.
local function frameArt(r)
    local w, h = (r.GetWidth and r:GetWidth()) or 0, (r.GetHeight and r:GetHeight()) or 0
    if w > 60 and h > 60 then return true end
    local id = (tostring((r.GetName and r:GetName()) or "") .. " " .. tostring((r.GetAtlas and r:GetAtlas()) or "")):lower()
    return id:find("border") or id:find("background") or id:find("inset") or id:find("frame") or id:find("bg") or id:find("divider")
        or id:find("parchment") or id:find("tile") or id:find("streak") or id:find("header") or false
end

-- Walk a part of the window and hide its frame art, sparing buttons' icons
-- and the map itself.
local function dimTree(frame, depth, skip)
    if type(frame) ~= "table" or depth > 4 or (skip and skip[frame]) then return end
    dimArt(frame, frameArt)
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do
            local t = c.GetObjectType and c:GetObjectType()
            if t ~= "Button" and t ~= "CheckButton" and t ~= "EditBox" then dimTree(c, depth + 1, skip) end
        end
    end
end

-- The quest log side: its backgrounds may sit on any frame at any depth, even
-- inside its buttons (header bars), and may be plain color: hide every big
-- picture there, and every picture on the log's own frames.
local function bigArt(r)
    local w, h = (r.GetWidth and r:GetWidth()) or 0, (r.GetHeight and r:GetHeight()) or 0
    return (w >= 100 and h >= 40) or (h >= 100 and w >= 40) or frameArt(r)
end
local function dimLog(frame, depth)
    if type(frame) ~= "table" or depth > 8 then return end
    if frame.ruinEdge then return end
    local t = frame.GetObjectType and frame:GetObjectType()
    if t == "EditBox" then return end
    dimArt(frame, depth <= 2 and nil or bigArt)
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do dimLog(c, depth + 1) end
    end
end

-- What's still drawn over the quest log: big pictures, for finding art the
-- style misses (/path worldmap debug).
function WM.Debug(print)
    local q = questMap()
    if type(q) ~= "table" or not q.GetRect or not q:GetRect() then return print("Open the map with the quest log first.") end
    -- the middle of the quest log, on screen
    local es = q:GetEffectiveScale()
    local l, b, w, h = q:GetRect()
    local px, py = (l + w / 2) * es, (b + h * 0.35) * es
    local function covers(r)
        local rl, rb, rw, rh = r:GetRect()
        if not rl then return false end
        local s = (r.GetEffectiveScale and r:GetEffectiveScale()) or es
        rl, rb, rw, rh = rl * s, rb * s, rw * s, rh * s
        return px >= rl and px <= rl + rw and py >= rb and py <= rb + rh, rw, rh
    end
    local function path(f)
        local parts, x = {}, f
        while x and #parts < 6 do
            local n = x.GetName and x:GetName()
            table.insert(parts, 1, n or ("(" .. x:GetObjectType() .. ")"))
            if n then break end
            x = x.GetParent and x:GetParent()
        end
        return table.concat(parts, ".")
    end
    local n = 0
    local f = EnumerateFrames()
    while f do
        pcall(function()
            if (f.IsForbidden and f:IsForbidden()) or not f:IsVisible() then return end
            for _, r in ipairs({ f:GetRegions() }) do
                if isTexture(r) and r:IsVisible() and (r:GetAlpha() or 0) > 0.05 then
                    local hit, rw, rh = covers(r)
                    if hit and n < 20 then
                        n = n + 1
                        local cr, cg, cb, ca = r:GetVertexColor()
                        print(("%s: %s %dx%d tex=%s atlas=%s color=%.2f,%.2f,%.2f,%.2f layer=%s"):format(path(f), tostring(r:GetName()), rw, rh,
                            tostring(r:GetTexture()), tostring(r.GetAtlas and r:GetAtlas()), cr or 0, cg or 0, cb or 0, ca or 0, tostring(r:GetDrawLayer())))
                    end
                end
            end
        end)
        f = EnumerateFrames(f)
    end
    print(n .. " pictures drawn at the middle of the quest log.")
end

local function buildPanel(f)
    panel = CreateFrame("Frame", "RUIN_PathfinderWorldMapBack", f)
    panel:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1)))
    if panel.EnableMouse then panel:EnableMouse(false) end
    panel.ruinTheme = WM.Theme()
    if W.Skin then W.Skin(panel, "bg", 0.95, "border") end
    if W.Sheen then panel.sheen = W.Sheen(panel, 0.04) end
    panel.band = panel:CreateTexture(nil, "ARTWORK")
    panel.band:SetHeight(2)
    panel.band:SetPoint("TOPLEFT", 0, 0)
    panel.band:SetPoint("TOPRIGHT", 0, 0)
    -- a hairline between the map and the quest log
    panel.split = panel:CreateTexture(nil, "ARTWORK")
    panel.split:SetWidth(1)
end

local function layoutPanel(f)
    local border = f.BorderFrame or f
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    local c = accent()
    panel.band:SetColorTexture(c[1], c[2], c[3], 0.9)
    MM.Paint(panel, WM.Alpha(), 0.12, -0.55, WM.Scheme())
    local q = questMap()
    if visible(q) then
        local e = W.BTN_EDGE or { 0.3, 0.34, 0.38 }
        panel.split:SetColorTexture(e[1], e[2], e[3], 0.9)
        panel.split:ClearAllPoints()
        panel.split:SetPoint("TOPLEFT", q, "TOPLEFT", -1, 0)
        panel.split:SetPoint("BOTTOMLEFT", q, "BOTTOMLEFT", -1, 0)
        panel.split:Show()
    else
        panel.split:Hide()
    end
    panel:Show()
end

-- The window's own buttons: close, maximize / minimize.
local function styleButtons(f)
    local b = f.BorderFrame
    if type(b) ~= "table" then return end
    OT.SkinButton(b.CloseButton or rawget(_G, "WorldMapFrameCloseButton"), "close", OWNER, on, WM.Scheme)
    local mm = b.MaximizeMinimizeFrame or f.MaximizeMinimizeFrame
    if type(mm) == "table" then
        OT.SkinButton(mm.MaximizeButton, "expand", OWNER, on, WM.Scheme)
        OT.SkinButton(mm.MinimizeButton, "shrink", OWNER, on, WM.Scheme)
        dimArt(mm)
    end
end

-- The breadcrumb bar: plain words, the place you're on in Pathfinder's color,
-- the game's arrows drawn as small chevrons.
local function styleNav(f)
    local nav = f.NavBar
    if type(nav) ~= "table" then return end
    dimTree(nav, 1)
    local list = {}
    if type(nav.homeButton) == "table" then list[#list + 1] = nav.homeButton end
    if type(nav.navList) == "table" then for _, b in ipairs(nav.navList) do list[#list + 1] = b end end
    for i, b in ipairs(list) do
        dimArt(b)
        local text = b.text or b.Text or (b.GetFontString and b:GetFontString())
        color(text, i == #list and accent() or TEXT)
        local arrow = b.MenuArrowButton
        if type(arrow) == "table" then OT.SkinButton(arrow, "menu", OWNER, on, WM.Scheme) end
    end
end

-- Zone headers stand out in every look: a band of color fading across each,
-- an edge down its left and a line under it, and larger text that keeps its
-- color (the game repaints it on hover). Blizzard's look uses WoW Forever's
-- gold and bronze.
local heads = {}
local BLIZZ_TEXT, BLIZZ_BAND = { 1, 0.82, 0 }, { 0.80, 0.58, 0.30 }
local function headColors()
    if on() then local a = accent(); return a, a end
    return BLIZZ_TEXT, BLIZZ_BAND
end
local function paintBand(tex, c, a1, a2)
    local ok = false
    if tex.SetGradient and CreateColor then
        tex:SetColorTexture(1, 1, 1, 1)
        ok = pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(c[1], c[2], c[3], a1), CreateColor(c[1], c[2], c[3], a2))
    end
    if not ok then tex:SetColorTexture(c[1], c[2], c[3], (a1 + a2) / 2) end
end
local function styleHeader(frame, text)
    if type(text) ~= "table" or not text.SetTextColor then return end
    local h = heads[frame]
    if not h then
        if not frame.CreateTexture then return end
        h = {}
        h.band = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        h.band:SetPoint("TOPLEFT", 0, -1)
        h.band:SetPoint("BOTTOMRIGHT", 0, 1)
        h.edge = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        h.edge:SetPoint("TOPLEFT", 0, -1)
        h.edge:SetPoint("BOTTOMLEFT", 0, 1)
        h.edge:SetWidth(3)
        h.line = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        h.line:SetPoint("BOTTOMLEFT", 0, 1)
        h.line:SetPoint("BOTTOMRIGHT", 0, 1)
        h.line:SetHeight(1)
        h.band.ruinOwn, h.edge.ruinOwn, h.line.ruinOwn = true, true, true
        heads[frame] = h
    end
    if h.text ~= text then
        h.text = text
        h.font = text.GetFont and { text:GetFont() } or nil
    end
    local tc, bc = headColors()
    paintBand(h.band, bc, on() and 0.24 or 0.30, 0.02)
    h.edge:SetColorTexture(bc[1], bc[2], bc[3], 0.95)
    paintBand(h.line, bc, 0.6, 0)
    h.band:Show(); h.edge:Show(); h.line:Show()
    if h.font and h.font[1] and h.font[2] and not h.bigger then
        pcall(text.SetFont, text, h.font[1], h.font[2] + 2, h.font[3] or "")
        h.bigger = true
    end
    if text.SetShadowOffset then text:SetShadowOffset(1, -1) end
    text.ruinHeadColor = tc
    if not text.ruinHeadHooked and hooksecurefunc then
        text.ruinHeadHooked = true
        hooksecurefunc(text, "SetTextColor", function(fs)
            local c = fs.ruinHeadColor
            if c and not fs.ruinHeadPainting then
                fs.ruinHeadPainting = true
                fs:SetTextColor(c[1], c[2], c[3])
                fs.ruinHeadPainting = false
            end
        end)
    end
    if colored[text] == nil and text.GetTextColor then colored[text] = { text:GetTextColor() } end
    text.ruinHeadPainting = true
    text:SetTextColor(tc[1], tc[2], tc[3])
    text.ruinHeadPainting = false
end
WM.Heads = heads

local function unstyleHeaders()
    for _, h in pairs(heads) do
        h.band:Hide(); h.edge:Hide(); h.line:Hide()
        if h.text then
            h.text.ruinHeadColor = nil
            if h.bigger and h.font and h.font[1] then pcall(h.text.SetFont, h.text, h.font[1], h.font[2], h.font[3] or "") end
            h.bigger = nil
        end
    end
end

local function headerOf(frame)
    local cb = frame.CollapseButton
    return type(cb) == "table" and (frame.ButtonText or frame.Text or frame.text) or nil
end

-- Blizzard's look: only the headers
local function styleHeaders(frame, depth)
    if type(frame) ~= "table" or depth > 6 or not visible(frame) then return end
    local t = headerOf(frame)
    if t then styleHeader(frame, t) end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do styleHeaders(c, depth + 1) end
    end
end

-- The quest log: zone headers in Pathfinder's color with flat collapse
-- buttons, quest markers drawn flat, objectives in the suite's grey. Quest
-- titles keep the game's difficulty colors.
local function styleLog(frame, depth)
    if type(frame) ~= "table" or depth > 6 or not visible(frame) then return end
    local kind = OT.KindOf(frame, false)
    if kind == "poi" then OT.SkinButton(frame, "poi", OWNER, on, WM.Scheme); return end
    local cb = frame.CollapseButton
    local headText = frame.ButtonText or (cb and (frame.Text or frame.text))
    if headText and type(cb) == "table" then
        dimArt(frame)
        styleHeader(frame, headText)
        OT.SkinButton(cb, "collapse", OWNER, on, WM.Scheme)
    elseif frame.Text and (frame.Dash or frame.dash) then
        color(frame.Text, LINE)
        color(frame.Dash or frame.dash, accent())
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do styleLog(c, depth + 1) end
    end
end

-- The quest's details (its text, objectives and rewards) are written in the
-- game's dark ink for parchment, unreadable on the suite's dark panel: any
-- text drawn dark is lightened, headings in the look's color. Colored text
-- (item names, money) is left alone.
local BODY = { 0.86, 0.87, 0.90 }
local function readable(frame, depth)
    if type(frame) ~= "table" or depth > 8 then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if type(r) == "table" and r.GetObjectType and r:GetObjectType() == "FontString" and r.GetTextColor then
                local cr, cg, cb = r:GetTextColor()
                if type(cr) == "number" and not (issecretvalue and issecretvalue(cr)) then
                    local lum = 0.3 * cr + 0.59 * (cg or 0) + 0.11 * (cb or 0)
                    if lum < 0.45 or r.ruinLit then
                        local n = tostring((r.GetName and r:GetName()) or ""):lower()
                        local head = n:find("header") or n:find("title")
                        local c = head and accent() or BODY
                        if colored[r] == nil then colored[r] = { cr, cg, cb } end
                        r.ruinLit = true
                        r:SetTextColor(c[1], c[2], c[3])
                    end
                end
            end
        end
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do readable(c, depth + 1) end
    end
end
local function readableDetails()
    if not on() then return end
    local q = questMap()
    for _, f in ipairs({ q and q.DetailsFrame or false, rawget(_G, "QuestInfoFrame") or false,
                         rawget(_G, "QuestMapDetailsScrollFrame") or false }) do
        if f and visible(f) then pcall(readable, f, 1) end
    end
end
WM.ReadableDetails = readableDetails

local function styleSearch(box)
    if type(box) ~= "table" then return end
    dimArt(box, function(r)
        local n = tostring((r.GetName and r:GetName()) or ""):lower()
        return n:find("left") or n:find("right") or n:find("middle") or n:find("mid") or frameArt(r)
    end)
    if not box.ruinEdge and W.Skin then
        local e = CreateFrame("Frame", nil, box)
        e:SetPoint("TOPLEFT", -4, 2)
        e:SetPoint("BOTTOMRIGHT", 2, -2)
        if e.SetFrameLevel then e:SetFrameLevel(math.max(0, (box:GetFrameLevel() or 1) - 1)) end
        e.ruinTheme = panel and panel.ruinTheme
        W.Skin(e, "bg", 0.9, "border")
        box.ruinEdge = e
    end
    box.ruinEdge:Show()
end

function WM.Refresh()
    local f = map()
    if not (db and f) or not on() or not visible(f) then return end
    if not panel then buildPanel(f) end
    layoutPanel(f)
    local skip = { [f.ScrollContainer or 0] = true }
    -- the window's own background (WorldMapFrameBg: the grey behind the log)
    dimArt(f, frameArt)
    if type(rawget(_G, "WorldMapFrameBg")) == "table" then MM.Dim(WorldMapFrameBg, true) end
    if type(f.BorderFrame) == "table" then
        dimTree(f.BorderFrame, 1, skip)
        local title = f.BorderFrame.TitleContainer and f.BorderFrame.TitleContainer.TitleText or f.BorderFrame.TitleText
        color(title, accent())
        local portrait = f.BorderFrame.PortraitContainer or f.BorderFrame.portrait or f.BorderFrame.Portrait
        if type(portrait) == "table" then MM.Dim(portrait, true) end
    end
    styleButtons(f)
    styleNav(f)
    local q = questMap()
    if type(q) == "table" and visible(q) then
        dimLog(q, 1)
        local scroll = rawget(_G, "QuestScrollFrame") or (q.QuestsFrame and q.QuestsFrame.ScrollFrame)
        if type(scroll) == "table" then
            dimLog(scroll, 1)
            styleLog(scroll.Contents or scroll, 1)
            styleSearch(scroll.SearchBox or (q.QuestsFrame and q.QuestsFrame.SearchBox))
        end
        readableDetails()
    end
end

local function restore()
    if panel then panel:Hide() end
    unstyleHeaders()
    OT.UnskinOwner(OWNER)
    for fs, c in pairs(colored) do
        fs.ruinLit = nil
        if fs.SetTextColor and c[1] then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    end
    colored = {}
    MM.UndimOwner(OWNER)
    local box = rawget(_G, "QuestScrollFrame") and QuestScrollFrame.SearchBox
    if type(box) == "table" and box.ruinEdge then box.ruinEdge:Hide() end
    -- the game repaints the log's own colors on its next update: ask for one
    if QuestMapFrame_UpdateAll then pcall(QuestMapFrame_UpdateAll) end
end

function WM.Apply()
    if not db then return end
    if on() then
        MM.DimOwner(OWNER)            -- what's dimmed from here on is the map's, to give back
        WM.Refresh()
        MM.DimOwner(nil)
    else
        restore()
    end
end

function WM.SetStyle(style)
    if not L.Valid(style) then return false end
    db.wmStyle = style
    if style ~= "blizzard" then
        local qs = rawget(_G, "QuestScrollFrame")
        local box = type(qs) == "table" and type(qs.SearchBox) == "table" and qs.SearchBox or nil
        for _, x in ipairs({ panel or false, (box and type(box.ruinEdge) == "table" and box.ruinEdge) or false }) do
            if x then
                x.ruinTheme, x.ruinThemeFound = WM.Theme(), nil
                if W.Skin then W.Skin(x, "bg", 0.95, "border") end
            end
        end
    end
    WM.Apply()
    return true
end

function WM.SetAlpha(a)
    if type(a) ~= "number" then return false end
    db.wmAlpha = math.max(0, math.min(1, a))
    if panel and panel:IsShown() then MM.Paint(panel, db.wmAlpha, 0.12, -0.55, WM.Scheme()) end
    return true
end

-- Keep it styled while the map is open: the log rebuilds as quests change.
local since = 0
local function tick(self, elapsed)
    since = since + (elapsed or 0)
    if since < 0.3 then return end
    since = 0
    if on() then
        WM.Apply()
    elseif db then
        local scroll = rawget(_G, "QuestScrollFrame")
        if type(scroll) == "table" and visible(scroll) then styleHeaders(scroll.Contents or scroll, 1) end
    end
end

WM.Tick = tick

function WM.Init(cdb)
    db = cdb
    if db.wmStyle == nil then db.wmStyle = "blizzard" end
    if type(db.wmAlpha) ~= "number" then db.wmAlpha = 0.95 end
    local f = map()
    if type(f) ~= "table" or not f.HookScript then return end
    local ticker = CreateFrame("Frame", nil, f)
    ticker:SetScript("OnUpdate", tick)
    f:HookScript("OnShow", function() if on() then WM.Apply() end end)
    -- the game repaints the details when a quest is opened: light them again at once
    for _, fn in ipairs({ "QuestInfo_Display", "QuestMapFrame_ShowQuestDetails" }) do
        if type(rawget(_G, fn)) == "function" then
            hooksecurefunc(fn, function() if on() then readableDetails() end end)
        end
    end
end
