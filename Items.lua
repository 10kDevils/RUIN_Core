-- RUIN Core: item names
-- The game only knows an item's name once its data has reached your client,
-- so lists of item IDs (loot tables, prices, recipes) would show bare
-- numbers. RUIN asks the game to load each item it shows, remembers every
-- name and quality it has seen (account-wide, in RUIN_DB), and tells pages
-- to redraw when names arrive (the ITEMS_LOADED callback, a moment later).
local ADDON, ns = ...

local Items = {}
ns.Items = Items

local MAX_CACHE = 4000
local pendingFire = false
local failed = {}            -- itemID -> true when the game says it doesn't exist

local function cache()
    if not ns.db then return nil end
    ns.db.items = type(ns.db.items) == "table" and ns.db.items or {}
    return ns.db.items
end

local function remember(id, name, quality)
    local c = cache()
    if not (c and id and type(name) == "string" and name ~= "") then return end
    local cur = c[id]
    if cur and cur.n == name and cur.q == quality then return end
    if not cur then
        c._n = (c._n or 0) + 1
        if c._n > MAX_CACHE then                  -- start over rather than grow forever
            ns.db.items = { _n = 0 }
            c = ns.db.items
        end
    end
    c[id] = { n = name, q = quality }
end
Items.Remember = remember

local function request(id)
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
    elseif GetItemInfo then
        pcall(GetItemInfo, id)
    end
end

-- "|cff0070dd" for a quality (1 = white, 2 = green, 3 = blue, 4 = purple ...).
function Items.QualityHex(q)
    q = tonumber(q)
    if not q then return "|cffffffff" end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.hex then return c.hex end
    local fixed = { [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00", [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000" }
    return fixed[q] or "|cffffffff"
end

local QUALITY_NAMES = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary", [6] = "Artifact" }
function Items.QualityName(q)
    q = tonumber(q)
    local global = q and _G["ITEM_QUALITY" .. q .. "_DESC"]
    return (type(global) == "string" and global) or QUALITY_NAMES[q or -1] or "Unknown"
end

-- name, link, quality for an item ID (or link). Missing data is requested;
-- the remembered name and quality stand in until it arrives.
function Items.Info(id)
    if type(id) == "string" then id = tonumber(id:match("item:(%d+)") or id) end
    id = tonumber(id)
    if not id then return nil end
    local name, link, quality
    if GetItemInfo then name, link, quality = GetItemInfo(id) end
    if name then
        remember(id, name, quality)
        return name, link, quality
    end
    request(id)
    local c = cache()
    local e = c and c[id]
    if e then return e.n, nil, e.q end
    return nil
end

-- What to show for an item: its link, else its name in quality color, else
-- the fallback name a data file gave, else "Loading item..." (or "Unknown
-- item" once the game says there is no such item).
function Items.Text(id, fallback, fallbackQuality)
    local name, link, quality = Items.Info(id)
    if link then return link end
    if name then return Items.QualityHex(quality) .. "[" .. name .. "]|r" end
    if type(fallback) == "string" and fallback ~= "" then
        return Items.QualityHex(fallbackQuality) .. "[" .. fallback .. "]|r"
    end
    if failed[tonumber(id) or 0] then return "|cff888888Unknown item|r" end
    return "|cff888888Loading item...|r"
end

-- Names arrive one by one; pages redraw once, shortly after the last.
local function onReceived(_, itemID, success)
    itemID = tonumber(itemID)
    if itemID then
        if success == false then
            failed[itemID] = true
        elseif GetItemInfo then
            local name, _, quality = GetItemInfo(itemID)
            if name then remember(itemID, name, quality) end
        end
    end
    if pendingFire then return end
    pendingFire = true
    C_Timer.After(0.4, function()
        pendingFire = false
        ns:Fire("ITEMS_LOADED")
    end)
end
ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", onReceived)
ns:RegisterEvent("ITEM_DATA_LOAD_RESULT", onReceived)

-- Items in a chat line or link text: remember their names as they go by.
function Items.RememberLinks(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
    for color, id, name in text:gmatch("|c(%x%x%x%x%x%x%x%x)|Hitem:(%d+)[^|]*|h%[(.-)%]|h") do
        local q
        for qq = 0, 5 do
            if Items.QualityHex(qq):lower() == ("|c" .. color):lower() then q = qq; break end
        end
        remember(tonumber(id), name, q)
    end
end
