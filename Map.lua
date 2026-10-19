-- RUIN Core: map pins and positions
-- Modules put markers on the world map and the minimap through RUIN_API.Map:
--
--   RUIN_API.Map:SetPin("Muster", id, { map = uiMapID, x = 0.41, y = 0.33,
--       icon = "Interface\\Icons\\INV_BannerPVP_01", color = { 0.77, 0.12, 0.23 },
--       title = "Crossroads", text = "Held by Briar Fang", alpha = 1,
--       minimap = true, worldmap = true })
--   RUIN_API.Map:RemovePin("Muster", id)    RUIN_API.Map:ClearPins("Muster")
--
-- Positions are a uiMapID plus 0-1 coordinates, the same as
-- C_Map.GetPlayerMapPosition. Pins show on that map and on maps that contain
-- it (a zone pin also shows on its continent). Pins are plain frames on the
-- map canvas and the minimap; nothing Blizzard-owned is replaced.
local ADDON, ns = ...

local Map = { owners = {} }
ns.Map = Map

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
function Map:PlayerPos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    return map, x, y
end

-- A point on one map expressed on another (parent or child), or nil.
function Map:Translate(fromMap, x, y, toMap)
    if fromMap == toMap then return x, y end
    if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, fromMap, toMap)
    if ok and minX and maxX and maxX > minX and maxY > minY then
        return minX + x * (maxX - minX), minY + y * (maxY - minY)
    end
    ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, toMap, fromMap)
    if ok and minX and maxX and maxX > minX and maxY > minY then
        local nx, ny = (x - minX) / (maxX - minX), (y - minY) / (maxY - minY)
        if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then return nx, ny end
    end
    return nil
end

-- Yards east and north from you to a point, and the straight distance.
-- nil when the point is on a map that can't be related to yours. Callers
-- drawing many pins can pass your position (pm, px, py) to save lookups.
function Map:Offset(map, x, y, pm, px, py)
    if not pm then pm, px, py = self:PlayerPos() end
    if not pm then return nil end
    local tx, ty = x, y
    if pm ~= map then
        tx, ty = self:Translate(map, x, y, pm)
        if not tx then return nil end
    end
    if not C_Map.GetMapWorldSize then return nil end
    local w, h = C_Map.GetMapWorldSize(pm)
    if not w or w <= 0 or not h or h <= 0 then return nil end
    local east, north = (tx - px) * w, -(ty - py) * h
    return east, north, math.sqrt(east * east + north * north)
end

local DIRS = { "N", "NW", "W", "SW", "S", "SE", "E", "NE" }
-- "120 yd NE", or nil.
function Map:DistanceText(map, x, y)
    local east, north, dist = self:Offset(map, x, y)
    if not dist then return nil end
    local angle = math.atan2(-east, north)          -- counter-clockwise from north
    local dir = DIRS[math.floor(angle / (2 * math.pi) * 8 + 0.5) % 8 + 1]
    return ("%d yd %s"):format(dist, dir), dist
end

---------------------------------------------------------------------------
-- Pin store
---------------------------------------------------------------------------
local redrawPending = false
local drawWorld, drawMinimap

local function scheduleRedraw()
    if redrawPending then return end
    redrawPending = true
    C_Timer.After(0.1, function()
        redrawPending = false
        drawWorld()
    end)
end

function Map:SetPin(owner, id, data)
    if type(data) ~= "table" or type(data.map) ~= "number" or type(data.x) ~= "number" or type(data.y) ~= "number" then
        return
    end
    self.owners[owner] = self.owners[owner] or {}
    self.owners[owner][id] = data
    scheduleRedraw()
end

function Map:RemovePin(owner, id)
    if self.owners[owner] and self.owners[owner][id] then
        self.owners[owner][id] = nil
        scheduleRedraw()
    end
end

function Map:ClearPins(owner)
    if self.owners[owner] and next(self.owners[owner]) then
        self.owners[owner] = {}
        scheduleRedraw()
    end
end

function Map:GetPins(owner) return self.owners[owner] or {} end

local function eachPin(fn)
    for owner, pins in pairs(Map.owners) do
        for id, p in pairs(pins) do fn(owner, id, p) end
    end
end

---------------------------------------------------------------------------
-- Pin frames: a round icon with a ring in the pin's color
---------------------------------------------------------------------------
local function makePin(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(16, 16)
    f.ring = f:CreateTexture(nil, "BACKGROUND")
    f.ring:SetPoint("TOPLEFT", -2, 2)
    f.ring:SetPoint("BOTTOMRIGHT", 2, -2)
    f.ring:SetColorTexture(1, 1, 1, 1)
    pcall(f.ring.SetMask, f.ring, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    pcall(f.icon.SetMask, f.icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local p = self.pin
        if not p or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local c = p.color or { 1, 0.82, 0 }
        GameTooltip:AddLine(p.title or "RUIN", c[1], c[2], c[3])
        if p.text and p.text ~= "" then GameTooltip:AddLine(p.text, 1, 1, 1, true) end
        local dist = Map:DistanceText(p.map, p.x, p.y)
        if dist then GameTooltip:AddLine(dist, 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return f
end

local function dressPin(f, p, size)
    f.pin = p
    f:SetSize(size, size)
    local c = p.color or { 1, 0.82, 0 }
    f.ring:SetVertexColor(c[1], c[2], c[3], 1)
    f.icon:SetTexture(p.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    f:SetAlpha(p.alpha or 1)
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
local worldPins = {}

local function worldCanvas()
    if not WorldMapFrame then return nil end
    if WorldMapFrame.GetCanvas then
        local ok, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
        if ok and canvas then return canvas end
    end
    return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

drawWorld = function()
    local canvas = worldCanvas()
    if not canvas or not WorldMapFrame:IsShown() then
        for _, f in ipairs(worldPins) do f:Hide() end
        return
    end
    local shown = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local cw, ch = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if not shown or cw <= 0 then return end
    local size = math.max(14, math.min(28, cw / 45))
    local used = 0
    eachPin(function(_, _, p)
        if p.worldmap == false then return end
        local x, y = Map:Translate(p.map, p.x, p.y, shown)
        if not x or x < 0 or x > 1 or y < 0 or y > 1 then return end
        used = used + 1
        local f = worldPins[used]
        if not f then
            f = makePin(canvas)
            worldPins[used] = f
        end
        f:SetParent(canvas)
        f:SetFrameLevel((canvas:GetFrameLevel() or 1) + 2000)
        dressPin(f, p, size)
        f:ClearAllPoints()
        f:SetPoint("CENTER", canvas, "TOPLEFT", x * cw, -y * ch)
        f:Show()
    end)
    for i = used + 1, #worldPins do worldPins[i]:Hide() end
end

local hooked = false
local function hookWorldMap()
    if hooked or not WorldMapFrame then return end
    hooked = true
    WorldMapFrame:HookScript("OnShow", function() drawWorld() end)
    WorldMapFrame:HookScript("OnHide", function() for _, f in ipairs(worldPins) do f:Hide() end end)
    if WorldMapFrame.OnMapChanged then
        pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", function() drawWorld() end)
    end
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local miniPins = {}
local OUTDOOR_RADIUS = { [0] = 233, 200, 167, 133, 100, 67 }     -- yards by zoom, fallback only

local function minimapRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, r = pcall(C_Minimap.GetViewRadius)
        if ok and r and r > 0 then return r end
    end
    local zoom = Minimap.GetZoom and Minimap:GetZoom() or 0
    return OUTDOOR_RADIUS[zoom] or 233
end

local function rotating()
    return GetCVar and GetCVar("rotateMinimap") == "1"
end

drawMinimap = function()
    if not Minimap then return end
    local any = false
    eachPin(function(_, _, p) if p.minimap ~= false then any = true end end)
    if not any then
        for _, f in ipairs(miniPins) do f:Hide() end
        return
    end
    local pm, px, py = Map:PlayerPos()
    if not pm then
        for _, f in ipairs(miniPins) do f:Hide() end
        return
    end
    local radius = minimapRadius()
    local half = (Minimap:GetWidth() or 140) / 2
    local facing = rotating() and GetPlayerFacing and GetPlayerFacing() or 0
    local cf, sf = math.cos(facing), math.sin(facing)
    local used = 0
    eachPin(function(_, _, p)
        if p.minimap == false then return end
        local east, north, dist = Map:Offset(p.map, p.x, p.y, pm, px, py)
        if not dist then return end
        local right, up = east, north
        if facing ~= 0 then
            right = east * cf + north * sf
            up = -east * sf + north * cf
        end
        local px, py = right / radius * half, up / radius * half
        local edge = dist > radius
        if edge then
            local k = (half - 6) / math.sqrt(px * px + py * py)
            px, py = px * k, py * k
        end
        used = used + 1
        local f = miniPins[used]
        if not f then
            f = makePin(Minimap)
            miniPins[used] = f
        end
        dressPin(f, p, edge and 10 or 14)
        if edge then f:SetAlpha((p.alpha or 1) * 0.6) end
        f:ClearAllPoints()
        f:SetPoint("CENTER", Minimap, "CENTER", px, py)
        f:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
        f:Show()
    end)
    for i = used + 1, #miniPins do miniPins[i]:Hide() end
end

-- Minimap pins move with you, so they redraw ten times a second while any exist.
local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.1 then return end
    acc = 0
    local ok, err = pcall(drawMinimap)
    if not ok then ns:Debug("minimap pins: " .. tostring(err)) end
end)

ns:Subscribe("LOGIN", function()
    hookWorldMap()
    -- Alpha and text of pins change with age; keep an open world map current.
    C_Timer.NewTicker(1, function()
        hookWorldMap()
        if WorldMapFrame and WorldMapFrame:IsShown() then drawWorld() end
    end)
end)

Map.Redraw = function() drawWorld(); drawMinimap() end
