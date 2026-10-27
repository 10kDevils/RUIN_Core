-- RUIN Core: guild bank snapshots
-- Whoever of the guild opens the guild bank with RUIN on takes a snapshot of
-- what it holds (each tab they may view: items and counts) and its gold, and
-- shares it with the guild, so every member can see on the Guild page's Bank
-- tab what's there and how old the picture is. Only what that member's rank
-- can see is in it. Clients without a guild bank show nothing.
local ADDON, ns = ...

local Wd = ns.Widgets
local C = Wd.COLORS
local GREY, GREEN = C.dim, C.good

local Bank = {}
ns.Bank = Bank

local SLOTS = 98
local function now() return GetServerTime and GetServerTime() or time() end
local function norm(n) return ns.NormalizeName(n or "") end

function Bank:Available() return type(GetNumGuildBankTabs) == "function" and type(GetGuildBankItemInfo) == "function" end

local function store()
    if not ns.db then return {} end
    ns.db.bank = type(ns.db.bank) == "table" and ns.db.bank or {}
    return ns.db.bank
end

-- The latest snapshot of your guild's bank, or nil.
function Bank:Snapshot() return ns.guildName and store()[ns.guildName] or nil end

local function take()
    if not (Bank:Available() and ns.guildName) then return end
    local snap = { t = now(), by = ns.playerName, money = GetGuildBankMoney and (tonumber(GetGuildBankMoney()) or 0) or 0, tabs = {} }
    for tab = 1, GetNumGuildBankTabs() or 0 do
        local name, _, viewable = GetGuildBankTabInfo(tab)
        if viewable then
            local items, order = {}, {}
            for slot = 1, SLOTS do
                local _, count = GetGuildBankItemInfo(tab, slot)
                local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
                local id = link and tonumber(link:match("item:(%d+)"))
                if id then
                    if not items[id] then items[id] = 0; order[#order + 1] = id end
                    items[id] = items[id] + (tonumber(count) or 1)
                    if ns.Items then ns.Items.RememberLinks(link) end
                end
            end
            local list = {}
            for _, id in ipairs(order) do list[#list + 1] = { id, items[id] } end
            snap.tabs[#snap.tabs + 1] = { n = tostring(name or ("Tab " .. tab)):sub(1, 24), i = list }
        end
    end
    store()[ns.guildName] = snap
    ns.Comms:Send("BANKSNAP", snap, "GUILD", nil, ns.Comms.PRIORITY.BULK)
    ns:Fire("BANK_CHANGED")
end

local pending = false
local function scheduleTake()
    if pending then return end
    pending = true
    C_Timer.After(2, function() pending = false; take() end)
end

local function opened()
    if not Bank:Available() then return end
    for tab = 1, GetNumGuildBankTabs() or 0 do
        local _, _, viewable = GetGuildBankTabInfo(tab)
        if viewable and QueryGuildBankTab then pcall(QueryGuildBankTab, tab) end
    end
    scheduleTake()
end

ns:RegisterEvent("GUILDBANKFRAME_OPENED", opened)
ns:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", function() scheduleTake() end)
ns:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
    local banker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
    if banker and kind == banker then opened() end
end)

ns.Comms:Register("BANKSNAP", function(d, sender, scope)
    if scope ~= "GUILD" or not ns.guildName or type(d.tabs) ~= "table" then return end
    if not (ns.roster and ns.roster[norm(sender)]) then return end
    local cur = store()[ns.guildName]
    local t = tonumber(d.t)
    if not t or (cur and (cur.t or 0) >= t) then return end
    local snap = { t = t, by = sender, money = tonumber(d.money) or 0, tabs = {} }
    for i, tab in ipairs(d.tabs) do
        if i > 12 or type(tab) ~= "table" then break end
        local list = {}
        for j, it in ipairs(type(tab.i) == "table" and tab.i or {}) do
            if j > SLOTS then break end
            if type(it) == "table" and tonumber(it[1]) then list[#list + 1] = { tonumber(it[1]), tonumber(it[2]) or 1 } end
        end
        snap.tabs[#snap.tabs + 1] = { n = tostring(tab.n or ("Tab " .. i)):sub(1, 24), i = list }
    end
    store()[ns.guildName] = snap
    ns:Fire("BANK_CHANGED")
end)

---------------------------------------------------------------------------
-- The Bank tab
---------------------------------------------------------------------------
local ui = { tab = 0, query = "" }

function ns.GuildUI.BuildBank(page)
    ui.page = page
    ui.info = Wd.Label(page, "", "GameFontHighlightSmall")
    ui.info:SetPoint("TOPLEFT", 2, -4)
    ui.info:SetPoint("RIGHT", page, "RIGHT", -330, 0)
    ui.info:SetWordWrap(false)
    ui.tabBtn = Wd.Dropdown(page, 150, function()
        local out = { 0 }
        local s = Bank:Snapshot()
        for i in ipairs(s and s.tabs or {}) do out[#out + 1] = i end
        return out
    end, function() return ui.tab end, function(v) ui.tab = v; Bank:Refresh() end)
    ui.tabBtn.format = function(v)
        if v == 0 then return "All tabs" end
        local s = Bank:Snapshot()
        return s and s.tabs[v] and s.tabs[v].n or ("Tab " .. v)
    end
    ui.tabBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -170, 0)
    ui.search = Wd.EditBox(page, 160, function(t) ui.query = t or ""; Bank:Refresh() end, "Search items")
    ui.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -2)
    ui.search:SetScript("OnTextChanged", function(self, user) if user then ui.query = self:GetText() or ""; Bank:Refresh() end end)
    ui.list = Wd.List(page, 22, function(row)
        row.text = Wd.Label(row, "")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -200, 0)
        row.text:SetWordWrap(false)
        row.count = Wd.Label(row, "", "GameFontHighlightSmall")
        row.count:SetPoint("RIGHT", -120, 0)
        row.tabName = Wd.Label(row, "", "GameFontHighlightSmall")
        row.tabName:SetPoint("RIGHT", -6, 0)
        row.tabName:SetWidth(110)
        row.tabName:SetJustifyH("RIGHT")
    end, function(row, e)
        row.text:SetText(ns.Items.Text(e.id))
        row.count:SetText(C.white .. "x" .. e.count .. "|r")
        row.tabName:SetText(GREY .. ns.Escape(e.tab) .. "|r")
        row.link = select(2, ns.Items.Info(e.id))
    end)
    ui.list.frame:SetPoint("TOPLEFT", 0, -32)
    ui.list.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
    page:SetScript("OnShow", function() Bank:Refresh() end)
end

function Bank:Rows()
    local s, out, q = Bank:Snapshot(), {}, (ui.query or ""):lower()
    for i, tab in ipairs(s and s.tabs or {}) do
        if ui.tab == 0 or ui.tab == i then
            for _, it in ipairs(tab.i) do
                local name = ns.Items.Info(it[1])
                if q == "" or (name and name:lower():find(q, 1, true)) then
                    out[#out + 1] = { id = it[1], count = it[2], tab = tab.n, name = name or "" }
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.tab < b.tab end)
    return out
end

function Bank:Refresh()
    if not (ui.page and ui.page:IsVisible()) then return end
    local s = Bank:Snapshot()
    if not Bank:Available() and not s then
        ui.info:SetText(GREY .. "This game client has no guild bank.|r")
    elseif not s then
        ui.info:SetText(GREY .. "No snapshot yet. It appears when someone of your guild opens the guild bank with RUIN on.|r")
    else
        ui.info:SetText(("%s  ·  %sseen by %s %s ago|r"):format(Wd.Money(s.money or 0), GREY, ns.Escape(ns.ShortName(s.by or "?")),
            Wd.Duration(math.max(60, now() - (s.t or now())))))
    end
    ui.tabBtn:Refresh()
    ui.list:SetEmptyText(s and "Nothing matches." or "")
    ui.list:SetItems(Bank:Rows())
end

ns:Subscribe("BANK_CHANGED", function() Bank:Refresh() end)
ns:Subscribe("ITEMS_LOADED", function() Bank:Refresh() end)
