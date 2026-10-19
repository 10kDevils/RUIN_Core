-- RUIN Core: window shell, Org tab and text dialogs
-- Modules add their own tabs through RUIN_API (Module:AddTab).
local ADDON, ns = ...

local UI = {}
ns.UI = UI

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local GREEN, RED, YELLOW, GREY = "|cff40ff40", "|cffff6060", "|cffffd100", "|cff888888"

local tabs = {}         -- { title, builder, module, button, panel }
local main, content, dialog
local selectedTab
local org = {}          -- Org tab widgets

local function styleBox(f)
    if f.SetBackdrop then
        f:SetBackdrop(BACKDROP)
        f:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
        f:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
    end
end

local function makeButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 130, 26)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function makeCheck(parent, label, getter, setter)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(26, 26)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
    fs:SetText(label)
    c:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    c.Refresh = function(self) self:SetChecked(getter() and true or false) end
    return c
end

---------------------------------------------------------------------------
-- Generic text dialog (import, export, prompts)
---------------------------------------------------------------------------
local function getDialog()
    if dialog then return dialog end
    local d = CreateFrame("Frame", "RUIN_TextDialog", UIParent, BACKDROP_TEMPLATE)
    d:SetSize(480, 230)
    d:SetPoint("CENTER", 0, 80)
    d:SetFrameStrata("DIALOG")
    d:SetClampedToScreen(true)
    styleBox(d)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:Hide()

    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.title:SetPoint("TOP", 0, -14)
    d.hint = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.hint:SetPoint("TOPLEFT", 18, -40)
    d.hint:SetPoint("TOPRIGHT", -18, -40)
    d.hint:SetJustifyH("LEFT")

    local sf = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 18, -72)
    sf:SetPoint("BOTTOMRIGHT", -38, 50)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(410)
    eb:SetHeight(100)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function() d:Hide() end)
    sf:SetScrollChild(eb)
    sf:EnableMouse(true)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
    d.edit = eb

    local ok = makeButton(d, OKAY or "OK", 110, function()
        local cb, text = d.onAccept, eb:GetText()
        d:Hide()
        if cb then cb(text) end
    end)
    ok:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 16)
    local cancel = makeButton(d, CANCEL or "Cancel", 110, function() d:Hide() end)
    cancel:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 16)

    tinsert(UISpecialFrames, "RUIN_TextDialog")
    dialog = d
    UI:ApplyScale()
    return d
end

function UI:ShowText(title, hint, text, onAccept, selectAll)
    local d = getDialog()
    d.title:SetText(title)
    d.hint:SetText(hint or "")
    d.edit:SetText(text or "")
    d.onAccept = onAccept
    d:Show()
    d.edit:SetFocus()
    if selectAll then d.edit:HighlightText() end
end

---------------------------------------------------------------------------
-- Yes/no dialog (RUIN's own, instead of Blizzard's StaticPopup)
---------------------------------------------------------------------------
local confirm
local function getConfirm()
    if confirm then return confirm end
    local d = CreateFrame("Frame", "RUIN_ConfirmDialog", UIParent, BACKDROP_TEMPLATE)
    d:SetSize(420, 170)
    d:SetPoint("TOP", 0, -160)
    d:SetFrameStrata("DIALOG")
    d:SetClampedToScreen(true)
    styleBox(d)
    d:EnableMouse(true)
    d:Hide()
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.title:SetPoint("TOP", 0, -14)
    d.text = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.text:SetPoint("TOPLEFT", 18, -42)
    d.text:SetPoint("TOPRIGHT", -18, -42)
    d.text:SetJustifyH("LEFT")
    local yes = makeButton(d, ACCEPT or "Accept", 120, function()
        local cb = d.onAccept
        d:Hide()
        if cb then cb() end
    end)
    yes:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 16)
    local no = makeButton(d, DECLINE or "Decline", 120, function() d:Hide() end)
    no:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 16)
    tinsert(UISpecialFrames, "RUIN_ConfirmDialog")
    confirm = d
    UI:ApplyScale()
    return d
end

function UI:ShowConfirm(title, text, onAccept)
    local d = getConfirm()
    d.title:SetText(title)
    d.text:SetText(text)
    d.onAccept = onAccept
    d:Show()
end

---------------------------------------------------------------------------
-- Key actions
---------------------------------------------------------------------------
function UI:PromptImport()
    UI:ShowText("Import org key", "Paste the RUIN key below, then press OK.", "", function(text)
        local k, err = ns.Org.Decode(text)
        if not k then
            ns:Print("Import failed: " .. err .. ".")
            return
        end
        local ok, why = ns.Org:Apply(k, "import")
        if ok then
            ns:Print(("Imported the %s org key (rev %d)."):format(k.org, k.rev))
            if not ns.Org:MyGuildInOrg() then
                ns:Print("Your guild is not listed in this key yet. Ask the org admin to add it.")
            end
        else
            ns:Print("Did not import: " .. tostring(why) .. ".")
        end
    end)
end

function UI:ShowExport()
    local k = ns.Org:Get()
    if not k then
        ns:Print("No org key to export.")
        return
    end
    local hint = k.oc
        and "Copy with Ctrl+C. This key includes the officer channel: give it only to guild leaders."
        or "Copy with Ctrl+C. This is a member key (no officer channel)."
    UI:ShowText("Export org key", hint, ns.Org.Encode(k), nil, true)
end

function UI:SendKeyToTarget()
    local name = UnitExists("target") and UnitIsPlayer("target") and GetUnitName("target", true)
    if name then
        local ok, err = ns.Org:SendFullKey(name)
        ns:Print(ok and ("Offered the org key to " .. ns.ShortName(name) .. ".") or err)
        return
    end
    UI:ShowText("Send org key", "Target the player and press the button again, or type their full character name.", "", function(text)
        text = ns.Trim(text)
        if text == "" then return end
        local ok, err = ns.Org:SendFullKey(text)
        ns:Print(ok and ("Offered the org key to " .. text .. ".") or err)
    end)
end

function UI:PromptCreate()
    UI:ShowText("Create org key", "Name of the organization. You become the org admin; your guild is added with rank 1 as officer.", "RUIN", function(text)
        local ok, err = ns.Org:Create(text)
        ns:Print(ok and "Org key created. Add the other guilds next." or err)
    end, true)
end

function UI:PromptAddGuild()
    UI:ShowText("Add guild", "Guild name, lowest officer rank, short tag. Example:  Ashen Order, 1, Ashen\nRank 0 is the guild master, 1 the next rank down, and so on.", "", function(text)
        local name, rank, tag = ns.ParseGuildSpec(text)
        local ok, err = ns.Org:AddGuild(name, rank, tag)
        ns:Print(ok and ("Added " .. name .. ".") or err)
    end)
end

function UI:PromptRotate()
    UI:ShowText("Rotate org key", "New channel names and passwords for everyone. Officers online get the new key automatically; offline guild leaders need it sent again.\nType ROTATE and press OK.", "", function(text)
        if ns.Trim(text):upper() ~= "ROTATE" then return end
        local ok, err = ns.Org:Rotate()
        ns:Print(ok and "Org key rotated." or err)
    end)
end

---------------------------------------------------------------------------
-- Org tab
---------------------------------------------------------------------------
local function buildOrgPanel(p)
    org.status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    org.status:SetPoint("TOPLEFT", 4, -2)
    org.status:SetWidth(540)
    org.status:SetJustifyH("LEFT")
    org.status:SetJustifyV("TOP")
    if org.status.SetSpacing then org.status:SetSpacing(3) end

    org.import = makeButton(p, "Import key", 130, function() UI:PromptImport() end)
    org.import:SetPoint("TOPLEFT", 0, -130)
    org.export = makeButton(p, "Export key", 130, function() UI:ShowExport() end)
    org.export:SetPoint("LEFT", org.import, "RIGHT", 6, 0)
    org.send = makeButton(p, "Send key to target", 170, function() UI:SendKeyToTarget() end)
    org.send:SetPoint("LEFT", org.export, "RIGHT", 6, 0)

    org.create = makeButton(p, "Create org key", 130, function() UI:PromptCreate() end)
    org.create:SetPoint("TOPLEFT", org.import, "BOTTOMLEFT", 0, -6)
    org.addGuild = makeButton(p, "Add guild", 130, function() UI:PromptAddGuild() end)
    org.addGuild:SetPoint("LEFT", org.create, "RIGHT", 6, 0)
    org.rotate = makeButton(p, "Rotate key", 170, function() UI:PromptRotate() end)
    org.rotate:SetPoint("LEFT", org.addGuild, "RIGHT", 6, 0)

    local s = function() return ns.db.settings end
    org.checks = {
        makeCheck(p, "Show other guilds' chat", function() return s().showOrgChat end,
            function(v) s().showOrgChat = v end),
        makeCheck(p, "Show other guilds' officer chat", function() return s().showOfficerChat end,
            function(v) s().showOfficerChat = v end),
        makeCheck(p, "Relay for guildmates without RUIN", function() return s().allowBridge end,
            function(v) s().allowBridge = v; ns:Fire("SETTINGS_CHANGED") end),
        makeCheck(p, "Couch mode (larger window)", function() return s().couchMode end,
            function(v) s().couchMode = v; UI:ApplyScale() end),
        makeCheck(p, "Animated page headers", function() return s().animations end,
            function(v) s().animations = v end),
    }
    org.checks[1]:SetPoint("TOPLEFT", org.create, "BOTTOMLEFT", -4, -10)
    org.checks[2]:SetPoint("TOPLEFT", org.checks[1], "BOTTOMLEFT", 0, -2)
    org.checks[3]:SetPoint("TOPLEFT", org.checks[1], "TOPLEFT", 280, 0)
    org.checks[4]:SetPoint("TOPLEFT", org.checks[3], "BOTTOMLEFT", 0, -2)
    org.checks[5]:SetPoint("TOPLEFT", org.checks[2], "BOTTOMLEFT", 0, -2)

    local header = ns.Widgets.Header(p, "Online with RUIN")
    header:SetPoint("TOPLEFT", org.checks[5], "BOTTOMLEFT", 4, -12)

    local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    sf:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -26, 0)
    org.listChild = CreateFrame("Frame", nil, sf)
    org.listChild:SetSize(500, 10)
    sf:SetScrollChild(org.listChild)
    org.list = org.listChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    org.list:SetPoint("TOPLEFT")
    org.list:SetWidth(500)
    org.list:SetJustifyH("LEFT")
    org.list:SetJustifyV("TOP")

    UI:Refresh()
end

local function classColored(name, class)
    local color = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    local short = ns.ShortName(name)
    if color and color.WrapTextInColorCode then return color:WrapTextInColorCode(short) end
    return short
end

local function channelState(scope)
    if ns.Comms:IsJoined(scope) then return GREEN .. "connected|r" end
    if ns.Comms:HasChannel(scope) then return YELLOW .. "joining|r" end
    return GREY .. "off|r"
end

local function setEnabled(button, on)
    if on then button:Enable() else button:Disable() end
end

function UI:Refresh()
    if not main or not main:IsShown() then return end
    local k = ns.Org:Get()

    if org.status then
        local lines = {}
        if k then
            lines[#lines + 1] = ("Org: |cffffffff%s|r   key rev %d%s"):format(k.org, k.rev,
                ns.Org:IsAdmin() and "   (you are the org admin)" or "")
        else
            lines[#lines + 1] = RED .. "No org key yet.|r An officer shares it automatically, or use Import key."
        end
        if ns.guildName then
            lines[#lines + 1] = ("Guild: |cffffffff%s|r   %s%s"):format(ns.guildName,
                ns.Org:MyGuildInOrg() and (GREEN .. "in org|r") or (RED .. "not in org key|r"),
                ns.Org:AmOfficer() and "   (officer)" or "")
        else
            lines[#lines + 1] = RED .. "You are not in a guild.|r"
        end
        lines[#lines + 1] = ("Org channel: %s     Officer channel: %s"):format(channelState("ORG"), channelState("OFFICERS"))
        local bridge = ns.Presence:BridgeGUID()
        lines[#lines + 1] = "Guild bridge: " .. (bridge and (bridge == ns.playerGUID and "you"
            or ns.ShortName(ns.Presence:NameForGUID(bridge) or "?")) or GREY .. "none|r")
        local members, guilds = ns.Presence:CountOnline()
        lines[#lines + 1] = ("Online with RUIN: %d in %d guild(s)     Version %s"):format(members, guilds, ns.VERSION)
        local mods = {}
        for _, m in ipairs(RUIN_API:GetModules()) do mods[#mods + 1] = m.name .. " " .. tostring(m.version or "") end
        lines[#lines + 1] = "Modules: " .. (#mods > 0 and table.concat(mods, ", ") or (GREY .. "none installed|r"))
        org.status:SetText(table.concat(lines, "\n"))

        local admin = ns.Org:IsAdmin()
        setEnabled(org.export, k ~= nil)
        setEnabled(org.send, k ~= nil and (admin or (k.oc ~= nil and ns.Org:AmOfficer())))
        setEnabled(org.create, k == nil)
        setEnabled(org.addGuild, admin)
        setEnabled(org.rotate, admin)
        for _, c in ipairs(org.checks) do c:Refresh() end

        -- Online list grouped by guild
        local byGuild, order = {}, {}
        for _, r in ipairs(ns.Presence:GetOnlineList()) do
            local g = r.guild or "?"
            if not byGuild[g] then byGuild[g] = {}; order[#order + 1] = g end
            table.insert(byGuild[g], r)
        end
        table.sort(order)
        local out = {}
        for _, g in ipairs(order) do
            out[#out + 1] = YELLOW .. g .. "|r"
            table.sort(byGuild[g], function(a, b) return tostring(a.name) < tostring(b.name) end)
            for _, r in ipairs(byGuild[g]) do
                out[#out + 1] = ("    %s   %s%s  v%s|r"):format(classColored(r.name, r.class), GREY,
                    r.level and ("level " .. r.level) or "", r.version or "?")
            end
        end
        org.list:SetText(#out > 0 and table.concat(out, "\n") or (GREY .. "Nobody online yet.|r"))
        org.listChild:SetHeight(math.max(10, (org.list:GetStringHeight() or 0) + 4))
    end
end

---------------------------------------------------------------------------
-- The window: Blizzard's own portrait window (ButtonFrameTemplate) with tabs
-- along the bottom, like the Character and Collections windows. If this
-- client lacks the template, a plain RUIN frame is used instead.
---------------------------------------------------------------------------
local Wd = ns.Widgets
local WINDOW_W, WINDOW_H = 724, 640

local function sound(kit)
    if PlaySound and SOUNDKIT and SOUNDKIT[kit] then pcall(PlaySound, SOUNDKIT[kit]) end
end

local function themeForTab(t)
    if t.module then return ns.ThemeFor(t.module.name, t.module) end
    return ns.ThemeFor(t.title)
end

-- Window title and portrait follow the open page.
local function setWindowChrome(t)
    local theme = themeForTab(t)
    -- "RUIN - Finder" for modules; the Org page's own title already says RUIN.
    local name = theme.title or t.title
    local title = name:find("^RUIN") and name or ("RUIN  -  " .. name)
    if main.SetTitle then
        main:SetTitle(title)
    elseif main.TitleText then
        main.TitleText:SetText(title)
    elseif main.title then
        main.title:SetText(title)
    end
    if main.SetPortraitToAsset then
        pcall(main.SetPortraitToAsset, main, theme.icon)
    elseif main.portrait and SetPortraitToTexture then
        pcall(SetPortraitToTexture, main.portrait, theme.icon)
    end
end

function UI:SelectTab(index)
    local changed = selectedTab ~= index
    selectedTab = index
    for i, t in ipairs(tabs) do
        if i == index then
            if not t.panel then
                local theme = themeForTab(t)
                t.panel = CreateFrame("Frame", nil, content)
                t.panel:SetAllPoints(content)
                local headerHeight = Wd.PageHeader(t.panel, theme)
                t.body = CreateFrame("Frame", nil, t.panel)
                t.body:SetPoint("TOPLEFT", 8, -(headerHeight + 10))
                t.body:SetPoint("BOTTOMRIGHT", -8, 8)
                Wd.currentTheme = theme
                local ok, err = pcall(t.builder, t.body, t.module)
                Wd.currentTheme = nil
                if not ok then ns.ReportError(err) end
            end
            t.panel:Show()
            setWindowChrome(t)
        elseif t.panel then
            t.panel:Hide()
        end
    end
    if main.usesBlizzardTabs and PanelTemplates_SetTab then
        pcall(PanelTemplates_SetTab, main, index)
    else
        for i, t in ipairs(tabs) do
            if t.button then
                if i == index then t.button:LockHighlight() else t.button:UnlockHighlight() end
            end
        end
    end
    if changed and main:IsShown() then sound("IG_CHARACTER_INFO_TAB") end
end

function UI:LayoutTabs()
    if not main then return end
    local prev, rowStart, rowWidth = nil, nil, 0
    for i, t in ipairs(tabs) do
        if not t.button then
            local b
            if main.usesBlizzardTabs then
                local ok, tab = pcall(CreateFrame, "Button", "RUIN_MainFrameTab" .. i, main, "PanelTabButtonTemplate")
                if ok and tab then b = tab else main.usesBlizzardTabs = false end
            end
            if not b then b = makeButton(main, t.title, 92, nil) end
            if b.SetID then b:SetID(i) end
            b:SetText(t.title)
            b:SetScript("OnClick", function() UI:SelectTab(i) end)
            if main.usesBlizzardTabs and PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
            t.button = b
        end
        -- Tabs run along the bottom edge; extras wrap onto a second row.
        local w = (t.button.GetWidth and t.button:GetWidth()) or 90
        t.button:ClearAllPoints()
        if not prev then
            t.button:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 12, main.usesBlizzardTabs and 2 or -2)
            rowStart, rowWidth = t.button, w
        elseif rowWidth + 2 + w > WINDOW_W - 24 then
            t.button:SetPoint("TOPLEFT", rowStart, "BOTTOMLEFT", 0, 0)
            rowStart, rowWidth = t.button, w
        else
            t.button:SetPoint("LEFT", prev, "RIGHT", 2, 0)
            rowWidth = rowWidth + 2 + w
        end
        prev = t.button
    end
    if main.usesBlizzardTabs and PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, main, #tabs) end
    if not selectedTab and tabs[1] then UI:SelectTab(1) end
end

function UI:AddTab(title, builder, module)
    tabs[#tabs + 1] = { title = title, builder = builder, module = module }
    if main then UI:LayoutTabs() end
    return #tabs
end

-- Open the window on a page, by title or index.
function UI:OpenTab(which)
    if not ns.db then return end
    if not main then UI:CreateMain() end
    for i, t in ipairs(tabs) do
        if i == which or t.title == which then
            main:Show()
            UI:SelectTab(i)
            return true
        end
    end
    return false
end

function UI:CreateMain()
    local ok, f = pcall(CreateFrame, "Frame", "RUIN_MainFrame", UIParent, "ButtonFrameTemplate")
    if ok and f then
        main = f
        main.usesBlizzardTabs = true
        if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, main) end
        content = CreateFrame("Frame", nil, main.Inset or main)
        if main.Inset then
            content:SetPoint("TOPLEFT", main.Inset, "TOPLEFT", 3, -3)
            content:SetPoint("BOTTOMRIGHT", main.Inset, "BOTTOMRIGHT", -3, 3)
        else
            content:SetPoint("TOPLEFT", 10, -62)
            content:SetPoint("BOTTOMRIGHT", -10, 10)
        end
    else
        main = CreateFrame("Frame", "RUIN_MainFrame", UIParent, BACKDROP_TEMPLATE)
        styleBox(main)
        main.usesBlizzardTabs = false
        main.title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        main.title:SetPoint("TOP", 0, -12)
        local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        content = CreateFrame("Frame", nil, main)
        content:SetPoint("TOPLEFT", 10, -40)
        content:SetPoint("BOTTOMRIGHT", -10, 10)
    end
    main:SetSize(WINDOW_W, WINDOW_H)
    main:SetFrameStrata("HIGH")
    if main.SetToplevel then main:SetToplevel(true) end
    main:SetClampedToScreen(true)
    local pos = ns.db.window
    main:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        main:SetPoint(pos.point, UIParent, pos.rel or pos.point, pos.x or 0, pos.y or 0)
    else
        main:SetPoint("CENTER")
    end
    main:EnableMouse(true)
    main:SetMovable(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.db.window = { point = point, rel = rel, x = x, y = y }
    end)
    main:Hide()
    tinsert(UISpecialFrames, "RUIN_MainFrame")
    main:SetScript("OnShow", function()
        sound("IG_CHARACTER_INFO_OPEN")
        UI:Refresh()
    end)
    main:SetScript("OnHide", function() sound("IG_CHARACTER_INFO_CLOSE") end)
    UI:ApplyScale()
    UI:LayoutTabs()
end

function UI:ApplyScale()
    local scale = (ns.db and ns.db.settings.couchMode) and 1.15 or 1
    if main then main:SetScale(scale) end
    if dialog then dialog:SetScale(scale) end
    if confirm then confirm:SetScale(scale) end
    if ns.Widgets.ApplyHudScale then ns.Widgets.ApplyHudScale() end
end

function RUIN_ToggleWindow()
    if not ns.db then return end
    if not main then UI:CreateMain() end
    if main:IsShown() then main:Hide() else main:Show() end
end

function RUIN_OnAddonCompartmentClick()
    RUIN_ToggleWindow()
end

BINDING_HEADER_RUIN = "RUIN"
BINDING_NAME_RUIN_TOGGLE = "Toggle RUIN window"

UI:AddTab("Org", buildOrgPanel)

for _, ev in ipairs({ "KEY_CHANGED", "PEERS_CHANGED", "ROSTER_UPDATED", "CHANNELS_CHANGED", "GUILD_CHANGED" }) do
    ns:Subscribe(ev, function() UI:Refresh() end)
end
