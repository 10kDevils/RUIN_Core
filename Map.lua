-- RUIN Core: map pins and positions
-- Modules put markers on the world map and the minimap through RUIN_API.Map:
--
--   RUIN_API.Map:SetPin("Muster", id, { map = uiMapID, x = 0.41, y = 0.33,
--       icon = "Interface\\Icons\\INV_BannerPVP_01", color = { 0.77, 0.12, 0.23 },
--       title = "Crossroads", text = "Held by Briar Fang", alpha = 1,
--       minimap = true, worldmap = true })
--
-- Optional: plain = true draws the icon as it is (no colored ring, no round
-- mask), with iconCoords = { l, r, t, b } and aspect = width / height;
-- corner = true puts the pin in the bottom-right corner of the map when that
-- zone's own map is open (a reference, not a place), with label beside it.
-- On a continent or the world map it still sits on the zone.
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
    -- Retail 12 can hide these (instances, combat): a hidden value can't be used
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return nil end
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

-- A map point in world yards: continent, north, west (the game's own world
-- coordinates). nil when the client can't place it.
function Map:WorldPos(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok or not cont or not pos then return nil end
    local wx, wy = pos.x, pos.y
    if pos.GetXY then wx, wy = pos:GetXY() end
    if type(wx) ~= "number" or type(wy) ~= "number" then return nil end
    return cont, wx, wy
end

-- Yards between two points on one map (or nil).
function Map:Yards(map, x1, y1, x2, y2)
    local c1, n1, w1 = self:WorldPos(map, x1, y1)
    local c2, n2, w2 = self:WorldPos(map, x2, y2)
    if c1 and c1 == c2 then
        local dn, dw = n2 - n1, w2 - w1
        return math.sqrt(dn * dn + dw * dw)
    end
    if not (C_Map and C_Map.GetMapWorldSize) then return nil end
    local w, h = C_Map.GetMapWorldSize(map)
    if not w or w <= 0 or not h or h <= 0 then return nil end
    local dx, dy = (x2 - x1) * w, (y2 - y1) * h
    return math.sqrt(dx * dx + dy * dy)
end

-- Yards east and north from you to a point, and the straight distance.
-- nil when the point is on a map that can't be related to yours. Callers
-- drawing many pins can pass your position (pm, px, py) to save lookups.
function Map:Offset(map, x, y, pm, px, py)
    if not pm then pm, px, py = self:PlayerPos() end
    if not pm then return nil end
    -- world positions: works across zones on the same continent
    local tc, tn, tw = self:WorldPos(map, x, y)
    local pc, pn, pw = self:WorldPos(pm, px, py)
    if tc and pc then
        if tc ~= pc then return nil end
        local east, north = -(tw - pw), tn - pn
        return east, north, math.sqrt(east * east + north * north)
    end
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

-- A zone's uiMapID from its name as the roster gives it (localized text),
-- or nil. Built once from the world map's own tree.
local zoneIDs
function Map:ZoneMapID(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not zoneIDs then
        zoneIDs = {}
        if C_Map and C_Map.GetMapChildrenInfo then
            for _, root in ipairs({ 947, 946, 1, 0 }) do
                local ok, list = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
                if ok and type(list) == "table" and #list > 0 then
                    for _, info in ipairs(list) do
                        if info.name and info.mapID and (info.mapType == 3 or not zoneIDs[info.name]) then
                            zoneIDs[info.name] = info.mapID
                        end
                    end
                    break
                end
            end
        end
        -- asked before the map data was ready: try again next time
        if next(zoneIDs) == nil then zoneIDs = nil; return nil end
    end
    return zoneIDs[name]
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
    data.owner, data.id = owner, id
    self.owners[owner][id] = data
    scheduleRedraw()
end

-- Clear one mark you can clear (clearable = true): it goes, and its owner
-- hears of it (onClear) so it doesn't put it straight back.
function Map:ClearMark(p)
    if not (p and p.clearable and p.owner and p.id) then return false end
    local pins = self.owners[p.owner]
    if not pins or pins[p.id] ~= p then return false end
    pins[p.id] = nil
    if type(p.onClear) == "function" then pcall(p.onClear, p) end
    scheduleRedraw()
    if drawMinimap then pcall(drawMinimap) end
    return true
end

-- Clear every mark you can clear. Returns how many went.
function Map:ClearMarks()
    local list = {}
    for _, pins in pairs(self.owners) do
        for _, p in pairs(pins) do if p.clearable then list[#list + 1] = p end end
    end
    local n = 0
    for _, p in ipairs(list) do if self:ClearMark(p) then n = n + 1 end end
    return n
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
    -- plain pins: the art alone, no ring and no round mask
    f.art = f:CreateTexture(nil, "ARTWORK")
    f.art:SetAllPoints()
    f.art:Hide()
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.label:SetPoint("LEFT", f, "RIGHT", 4, 0)
    f.label:Hide()
    -- a soft round shadow under the pin, and a round colored ring (the round
    -- mask file itself, tinted, so it stays round where masks don't apply)
    f.shade = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.shade:SetPoint("TOPLEFT", -3, 2)
    f.shade:SetPoint("BOTTOMRIGHT", 3, -4)
    f.shade:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    f.shade:SetVertexColor(0, 0, 0, 0.5)
    f.ring = f:CreateTexture(nil, "BACKGROUND")
    f.ring:SetPoint("TOPLEFT", -2, 2)
    f.ring:SetPoint("BOTTOMRIGHT", 2, -2)
    f.ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    pcall(f.icon.SetMask, f.icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local p = self.pin
        if not p or not GameTooltip then return end
        ns.Widgets.TipOwner(self)
        local c = p.color or { 1, 0.82, 0 }
        GameTooltip:AddLine(p.title or "RUIN", c[1], c[2], c[3])
        if p.text and p.text ~= "" then GameTooltip:AddLine(p.text, 1, 1, 1, true) end
        local dist = Map:DistanceText(p.map, p.x, p.y)
        if dist then GameTooltip:AddLine(dist, 0.7, 0.7, 0.7) end
        if self.zoomTo then
            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(self.zoomTo)
            GameTooltip:AddLine("Click to open " .. ((info and info.name) or "the zone") .. "'s map.", 0.6, 0.8, 1)
        end
        if p.clearable then GameTooltip:AddLine("Right-click to clear this mark.  /ruin clearmap clears them all.", 0.6, 0.8, 1, true) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- a zone mark on a continent or world map clicks through into the zone;
    -- right-click zooms out, as it does anywhere on the map
    f:SetScript("OnMouseUp", function(self, button)
        -- right-click a mark you can clear: it goes
        if button == "RightButton" and self.pin and self.pin.clearable then
            if GameTooltip then GameTooltip:Hide() end
            Map:ClearMark(self.pin)
            self:Hide()
            return
        end
        local wmf = rawget(_G, "WorldMapFrame")
        if not wmf or not self.zoomTo and button ~= "RightButton" then return end
        if button == "RightButton" then
            if wmf.NavigateToParentMap then pcall(wmf.NavigateToParentMap, wmf)
            else
                local cur = wmf.GetMapID and wmf:GetMapID()
                local info = cur and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(cur)
                if info and info.parentMapID and info.parentMapID > 0 and wmf.SetMapID then pcall(wmf.SetMapID, wmf, info.parentMapID) end
            end
        elseif wmf.SetMapID then
            if GameTooltip then GameTooltip:Hide() end
            pcall(wmf.SetMapID, wmf, self.zoomTo)
        end
    end)
    return f
end

local function dressPin(f, p, size, withLabel)
    f.pin = p
    local c = p.color or { 1, 0.82, 0 }
    -- the shadow and ring sit a little outside the pin: a share of its size, so
    -- they stay in step on a canvas zoomed far in (where a pin is a few units across)
    local k = size / 24
    f.shade:ClearAllPoints()
    f.shade:SetPoint("TOPLEFT", -3 * k, 2 * k)
    f.shade:SetPoint("BOTTOMRIGHT", 3 * k, -4 * k)
    f.ring:ClearAllPoints()
    f.ring:SetPoint("TOPLEFT", -2 * k, 2 * k)
    f.ring:SetPoint("BOTTOMRIGHT", 2 * k, -2 * k)
    if p.plain then
        f:SetSize(size * (p.aspect or 1), size)
        f.ring:Hide(); f.icon:Hide()
        f.art:SetTexture(p.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local tc = p.iconCoords
        if tc then f.art:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) else f.art:SetTexCoord(0, 1, 0, 1) end
        f.art:Show()
        if p.shadow then f.shade:Show() else f.shade:Hide() end
    else
        f.shade:Show()
        f:SetSize(size, size)
        f.art:Hide()
        f.ring:Show(); f.icon:Show()
        f.ring:SetVertexColor(c[1], c[2], c[3], 1)
        f.icon:SetTexture(p.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    if withLabel and p.label and p.label ~= "" then
        f.label:SetText(p.label)
        f.label:Show()
    else
        f.label:Hide()
    end
    f:SetAlpha(p.alpha or 1)
end
Map.DressPin = dressPin

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
local worldPins = {}
local cornerPins = {}       -- on the visible map, not the zoomable canvas
Map.worldPins, Map.cornerPins = worldPins, cornerPins

local function worldCanvas()
    if not WorldMapFrame then return nil end
    if WorldMapFrame.GetCanvas then
        local ok, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
        if ok and canvas then return canvas end
    end
    return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

-- OpenMap (an addon) stitches every zone into one world map on the game's own
-- map. While it does, the map underneath follows the view, a pin can be off
-- that map's edges and still in view, and its art covers the canvas up to a
-- frame level it tells: its API places pins and lifts them over the art.
local function openMap()
    local OM = rawget(_G, "OpenMapAPI")
    if type(OM) == "table" and type(OM.IsStitched) == "function" then
        local ok, on = pcall(OM.IsStitched)
        if ok and on then return OM end
    end
end

-- Where a pin sits on the canvas of the map shown (0..1 is that map's own
-- rectangle), or nil when it isn't on it.
function Map.CanvasSpot(p, shown)
    local OM = openMap()
    if OM and OM.WorldFromMap and OM.MapFromWorld then
        local ok, u, v = pcall(OM.WorldFromMap, p.map, p.x, p.y)
        if ok and u then
            local ok2, x, y = pcall(OM.MapFromWorld, shown, u, v)
            -- the stitched view shows well past the map underneath
            if ok2 and x and x > -4 and x < 5 and y > -4 and y < 5 then return x, y end
        end
    end
    local x, y = Map:Translate(p.map, p.x, p.y, shown)
    if not x or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

-- The frame level for pins on the canvas: over the map, and over OpenMap's art.
function Map.PinLevel(canvas)
    local level = (canvas:GetFrameLevel() or 1) + 2000
    local OM = openMap()
    if OM and OM.ArtTopLevel then
        local ok, top = pcall(OM.ArtTopLevel)
        if ok and type(top) == "number" and top + 20 > level then level = top + 20 end
    end
    return math.min(level, 9000)
end

drawWorld = function()
    local canvas = worldCanvas()
    if not canvas or not WorldMapFrame:IsShown() then
        for _, f in ipairs(worldPins) do f:Hide() end
        for _, f in ipairs(cornerPins) do f:Hide() end
        return
    end
    local shown = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local cw, ch = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if not shown or cw <= 0 then return end
    -- pins keep their size on screen however far the map is zoomed: the
    -- canvas can be thousands of units wide and scaled right down
    local size = 24
    local ces = canvas.GetEffectiveScale and canvas:GetEffectiveScale()
    local wes = WorldMapFrame.GetEffectiveScale and WorldMapFrame:GetEffectiveScale()
    if type(ces) == "number" and type(wes) == "number" and ces > 0 and wes > 0 then
        size = 24 * wes / ces
    else
        size = math.max(14, math.min(28, cw / 45))
    end
    local used, corners = 0, 0
    -- OpenMap's stitched map shows every zone at once, and the map under it
    -- turns into the zone you zoom into: a zone's mark stays on its zone
    -- there instead of jumping to the corner
    local stitched = openMap() ~= nil
    Map.drawnScale = ces
    local view = WorldMapFrame.ScrollContainer
    if type(view) ~= "table" then view = canvas end
    -- marks go on the window above the canvas where there is one; k turns
    -- canvas units into the window's
    local ves = view.GetEffectiveScale and view:GetEffectiveScale()
    local onView = view ~= canvas and type(ves) == "number" and ves > 0 and type(ces) == "number" and ces > 0 and type(wes) == "number"
    local k = onView and ces / ves or 1
    local onViewSize = onView and 24 * wes / ves or size
    eachPin(function(_, _, p)
        if p.worldmap == false then return end
        if p.corner and p.map == shown and not stitched then
            -- the zone's own map: a reference in the corner of what you see
            corners = corners + 1
            local f = cornerPins[corners]
            if not f then
                f = makePin(view)
                cornerPins[corners] = f
            end
            f:SetParent(view)
            f:SetFrameLevel(math.max((view:GetFrameLevel() or 1) + 2100, Map.PinLevel(canvas) + 10))
            f.zoomTo = nil
            dressPin(f, p, 28, true)
            -- bottom-right corner, the count to its left; more marks stack upward
            f.label:ClearAllPoints()
            f.label:SetPoint("RIGHT", f, "LEFT", -4, 0)
            f:ClearAllPoints()
            f:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -14, 12 + (corners - 1) * 34)
            f:Show()
            return
        end
        local x, y = Map.CanvasSpot(p, shown)
        if not x then return end
        used = used + 1
        local f = worldPins[used]
        if not f then
            f = makePin(onView and view or canvas)
            worldPins[used] = f
        end
        -- a zone mark seen from a continent or the world: smaller, and a way into the zone
        local zoneMark = p.corner and p.map ~= shown
        f.zoomTo = zoneMark and p.map or nil
        f:ClearAllPoints()
        f.onView = onView
        if onView then
            -- on the map's window, not its canvas: the canvas's zoom (and
            -- OpenMap swapping the map under it) never touches its size; it's
            -- placed at its spot on the canvas, in the window's units
            f:SetParent(view)
            pcall(f.SetFrameLevel, f, math.max((view:GetFrameLevel() or 1) + 2000, Map.PinLevel(canvas)))
            dressPin(f, p, (zoneMark and p.plain) and onViewSize * 0.7 or onViewSize)
            f:SetPoint("CENTER", canvas, "TOPLEFT", x * cw * k, -y * ch * k)
        else
            f:SetParent(canvas)
            pcall(f.SetFrameLevel, f, Map.PinLevel(canvas))
            dressPin(f, p, (zoneMark and p.plain) and size * 0.7 or size)
            f:SetPoint("CENTER", canvas, "TOPLEFT", x * cw, -y * ch)
        end
        f:Show()
    end)
    for i = used + 1, #worldPins do worldPins[i]:Hide() end
    Map.drawnWidth = cw
    Map.CullWorldPins()
    for i = corners + 1, #cornerPins do cornerPins[i]:Hide() end
end

-- Marks on the map's window: only those inside it show (the canvas under it
-- is clipped to the window; the window's own children aren't)
function Map.CullWorldPins()
    local view = rawget(_G, "WorldMapFrame") and WorldMapFrame.ScrollContainer
    if type(view) ~= "table" or not view.GetLeft then return end
    local l, r, t, b = view:GetLeft(), view:GetRight(), view:GetTop(), view:GetBottom()
    if not (l and r and t and b) then return end
    for _, f in ipairs(worldPins) do
        if f.pin and f.onView then
            local cx, cy = f:GetCenter()
            local inside = cx and cy and cx >= l and cx <= r and cy >= b and cy <= t
            f:SetAlpha(inside and (f.pin.alpha or 1) or 0)
            if f.EnableMouse then f:EnableMouse(inside and true or false) end
        end
    end
end

-- While the map is open: redrawn as soon as its zoom moves (the marks' spots
-- are in canvas units, scaled), or OpenMap changes the map under it; and
-- every frame, marks panned out of the window are hidden
local scaleWatch = CreateFrame("Frame")
scaleWatch:Hide()
scaleWatch:SetScript("OnUpdate", function()
    local canvas = worldCanvas()
    if not canvas or not WorldMapFrame:IsShown() then return end
    local ces = canvas.GetEffectiveScale and canvas:GetEffectiveScale()
    local last = Map.drawnScale
    local cw = canvas.GetWidth and canvas:GetWidth()
    if (type(ces) == "number" and type(last) == "number" and last > 0 and math.abs(ces - last) > last * 0.004)
        or (type(cw) == "number" and Map.drawnWidth and math.abs(cw - Map.drawnWidth) > 0.5) then
        drawWorld()
    else
        Map.CullWorldPins()
    end
end)
Map.scaleWatch = scaleWatch

local hooked = false
local function hookWorldMap()
    if hooked or not WorldMapFrame then return end
    hooked = true
    WorldMapFrame:HookScript("OnShow", function() drawWorld(); scaleWatch:Show() end)
    WorldMapFrame:HookScript("OnHide", function()
        scaleWatch:Hide()
        for _, f in ipairs(worldPins) do f:Hide() end
        for _, f in ipairs(cornerPins) do f:Hide() end
    end)
    if WorldMapFrame.OnMapChanged then
        pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", function() drawWorld() end)
    end
    -- OpenMap: redraw when its stitched map comes or goes, and as its view moves
    local OM = rawget(_G, "OpenMapAPI")
    if type(OM) == "table" and type(OM.RegisterCallback) == "function" then
        local me = {}
        pcall(OM.RegisterCallback, me, "OpenMap_StitchedChanged", function() scheduleRedraw() end)
        pcall(OM.RegisterCallback, me, "OpenMap_ViewChanged", function() scheduleRedraw() end)
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
    if not Minimap or (Minimap.IsVisible and not Minimap:IsVisible()) then return end
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
    if type(facing) ~= "number" or (issecretvalue and issecretvalue(facing)) then facing = 0 end
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
        f.zoomTo = nil
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
