-- RUIN Core: the RUIN window, the Guild and Settings pages, and text dialogs
-- Modules add their own pages through RUIN_API (Module:AddTab).
--
-- The RUIN Gaming Companion App. The look follows the RUIN Companion brief:
-- a dark navy window with thin steel-blue edges, the gold RUIN mark top left,
-- page tabs across the top named after each module (Guild, Finder, ...
-- Options). Guild and Options use RUIN's teal and gold; each module's page
-- and tab use that addon's own color. Everything is drawn from plain
-- textures, so no art can go missing.
local ADDON, ns = ...

local UI = {}
ns.UI = UI

local Wd = ns.Widgets
local P = Wd.PALETTE
local C = Wd.COLORS

local GREEN, RED, YELLOW, GREY = C.good, C.bad, C.warn, C.dim

local tabs = {}         -- { title, label, order, builder, module, button, panel }
local main, content, dialog, tabStrip
local selectedTab
local guild, settings = {}, {}   -- page widgets

local MARK_ICON = "Interface\\Icons\\INV_Sword_39"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"

local function styleBox(f)
    Wd.Skin(f, "bg", 0.97, "border")
end

local function sound(kit)
    if PlaySound and SOUNDKIT and SOUNDKIT[kit] then pcall(PlaySound, SOUNDKIT[kit]) end
end

-- A small X drawn from two bars, for close buttons.
local function closeButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    Wd.Skin(b, "panel", 0.9, "border")
    local bars = {}
    for i, angle in ipairs({ 45, -45 }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(P.sub[1], P.sub[2], P.sub[3], 1)
        t:SetSize(12, 2)
        t:SetPoint("CENTER")
        t:SetRotation(math.rad(angle))
        bars[i] = t
    end
    b:SetScript("OnEnter", function(self)
        Wd.SetBorder(self, "glow")
        for _, t in ipairs(bars) do t:SetColorTexture(1, 1, 1, 1) end
    end)
    b:SetScript("OnLeave", function(self)
        Wd.SetBorder(self, "border")
        for _, t in ipairs(bars) do t:SetColorTexture(P.sub[1], P.sub[2], P.sub[3], 1) end
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- The RUIN mark: a gold ring around a sword, then the wordmark.
local function drawMark(parent, size)
    local ring = parent:CreateTexture(nil, "ARTWORK")
    ring:SetSize(size, size)
    ring:SetColorTexture(P.gold[1], P.gold[2], P.gold[3], 1)
    pcall(ring.SetMask, ring, ROUND_MASK)
    local icon = parent:CreateTexture(nil, "OVERLAY")
    icon:SetSize(size - 4, size - 4)
    icon:SetPoint("CENTER", ring, "CENTER", 0, 0)
    icon:SetTexture(MARK_ICON)
    pcall(icon.SetMask, icon, ROUND_MASK)
    return ring
end

---------------------------------------------------------------------------
-- Generic text dialog (import, export, prompts)
---------------------------------------------------------------------------
local function dialogTitle(d)
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.title:SetPoint("TOP", 0, -14)
    d.title:SetTextColor(P.gold[1], P.gold[2], P.gold[3])
end

local function getDialog()
    if dialog then return dialog end
    local d = CreateFrame("Frame", "RUIN_TextDialog", UIParent)
    d:SetSize(500, 250)
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

    dialogTitle(d)
    d.hint = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.hint:SetPoint("TOPLEFT", 18, -40)
    d.hint:SetPoint("TOPRIGHT", -18, -40)
    d.hint:SetJustifyH("LEFT")
    d.hint:SetTextColor(P.sub[1], P.sub[2], P.sub[3])

    local inset = CreateFrame("Frame", nil, d)
    inset:SetPoint("TOPLEFT", 14, -76)
    inset:SetPoint("BOTTOMRIGHT", -14, 50)
    Wd.Skin(inset, "panel", 1, "border")

    local sf = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 20, -82)
    sf:SetPoint("BOTTOMRIGHT", -38, 56)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(420)
    eb:SetHeight(100)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function() d:Hide() end)
    sf:SetScrollChild(eb)
    sf:EnableMouse(true)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
    d.edit = eb

    local ok = Wd.Button(d, OKAY or "OK", 110, function()
        local cb, text = d.onAccept, eb:GetText()
        d:Hide()
        if cb then cb(text) end
    end)
    ok:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 16)
    local cancel = Wd.Button(d, CANCEL or "Cancel", 110, function() d:Hide() end)
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
    local d = CreateFrame("Frame", "RUIN_ConfirmDialog", UIParent)
    d:SetSize(430, 170)
    d:SetPoint("TOP", 0, -160)
    d:SetFrameStrata("DIALOG")
    d:SetClampedToScreen(true)
    styleBox(d)
    d:EnableMouse(true)
    d:Hide()
    dialogTitle(d)
    d.text = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.text:SetPoint("TOPLEFT", 18, -42)
    d.text:SetPoint("TOPRIGHT", -18, -42)
    d.text:SetJustifyH("LEFT")
    local yes = Wd.Button(d, ACCEPT or "Accept", 120, function()
        local cb = d.onAccept
        d:Hide()
        if cb then cb() end
    end)
    yes:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 16)
    local no = Wd.Button(d, DECLINE or "Decline", 120, function() d:Hide() end)
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

function UI:PromptLinks()
    if not ns.Org:IsAdmin() then
        ns:Print("Only the org admin sets the community links. They reach everyone with the org key.")
        return
    end
    UI:ShowText("RUIN community links", "One link per line as  Name = address  (up to 8). Example:\nDiscord = https://discord.gg/yourcode     Keep donation links (Patreon) on the website: Blizzard's add-on rules forbid them in game.",
        ns.Org.LinksText(), function(text)
            local ok, err = ns.Org:SetLinks(ns.Org.ParseLinks(text))
            ns:Print(ok and "Community links updated for the whole org." or err)
        end)
end

function UI:CopyLink(label, url)
    UI:ShowText(label, "Press Ctrl+C to copy, then paste it into your browser or Discord.", url, nil, true)
end

---------------------------------------------------------------------------
-- Overlord Forever: RUIN works beside it rather than duplicating its
-- campaign. It is found in the game's AddOns list (any addon whose folder
-- or title says "Overlord"), so it counts as installed however and whenever
-- it registers its chat command. /ov is only needed to open it.
---------------------------------------------------------------------------
local ovIndex, ovListAt -- where it sits in the AddOns list; when the list was last read
local ovSlash           -- its /ov handler, once found

local function plainTitle(t)
    t = tostring(t or "")
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return t
end

local function addonApi()
    local C = C_AddOns
    return (C and C.GetNumAddOns) or GetNumAddOns, (C and C.GetAddOnInfo) or GetAddOnInfo,
        (C and C.IsAddOnLoaded) or IsAddOnLoaded
end

-- Returns the AddOns-list entry for Overlord: { index, name, title, loaded, reason } or nil.
local function overlordEntry()
    local num, info, loaded = addonApi()
    if not (num and info) then return nil end
    local function entry(i)
        local ok, name, title, _, _, reason = pcall(info, i)
        if not ok or type(name) ~= "string" then return nil end
        local t = plainTitle(title)
        if not (name:lower():find("overlord", 1, true) or t:lower():find("overlord", 1, true)) then return nil end
        local isLoaded = false
        if loaded then
            local ok2, l = pcall(loaded, i)
            isLoaded = ok2 and l and true or false
        end
        return { index = i, name = name, title = t, loaded = isLoaded, reason = reason }
    end
    if ovIndex then
        local e = entry(ovIndex)
        if e then return e end
        ovIndex = nil
    end
    -- not found yet: read the list at most every 5 seconds (and straight after any addon loads)
    if ovListAt and GetTime() - ovListAt < 5 then return nil end
    ovListAt = GetTime()
    local ok, n = pcall(num)
    if not ok or type(n) ~= "number" then return nil end
    for i = 1, n do
        local e = entry(i)
        if e then
            ovIndex = i
            return e
        end
    end
    return nil
end
ns:RegisterEvent("ADDON_LOADED", function() ovListAt = nil end)

-- Overlord's chat-command handler (/ov or /overlord), or nil.
local function overlordSlash()
    if ovSlash then return ovSlash end
    if type(SlashCmdList) ~= "table" then return nil end
    -- the game remembers commands it has already run
    if type(hash_SlashCmdList) == "table" then
        local fn = hash_SlashCmdList["/OV"] or hash_SlashCmdList["/OVERLORD"]
        if type(fn) == "function" then ovSlash = fn; return fn end
    end
    for key, fn in pairs(SlashCmdList) do
        local i = 1
        while type(key) == "string" do
            local cmd = _G["SLASH_" .. key .. i]
            if type(cmd) ~= "string" then break end
            local c = cmd:lower()
            if c == "/ov" or c == "/overlord" then
                if type(fn) == "function" then ovSlash = fn; return fn end
                break
            end
            i = i + 1
        end
    end
    return nil
end

-- "loaded", "off" (in the AddOns list but not running: switched off, or waiting to load) or nil.
function UI:OverlordState()
    local e = overlordEntry()
    if e and e.loaded then return "loaded", e end
    if overlordSlash() then return "loaded", e end
    if e then return "off", e end
    return nil
end

-- Kept for modules and tests: something non-nil when Overlord is running.
function UI:FindOverlord()
    local state = UI:OverlordState()
    if state == "loaded" then return overlordSlash() or true end
    return nil
end

-- Runs "/ov show": through Overlord's handler when it can be found, otherwise
-- by sending the command through the chat box like a typed command.
local function sendTyped(text)
    local eb = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
        or (ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend())
        or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
    local send = ChatEdit_SendText or (ChatFrameUtil and ChatFrameUtil.SendText)
    if not (eb and eb.SetText and send) then return false end
    local ok = pcall(function()
        eb:SetText(text)
        send(eb, 0)
    end)
    return ok
end

function UI:OpenOverlord()
    local state, e = UI:OverlordState()
    if state == "off" then
        return ns:Print("Overlord Forever is in your AddOns list but not loaded" ..
            (e and e.reason and e.reason ~= "" and (" (" .. tostring(e.reason):lower():gsub("_", " ") .. ")") or "") ..
            ". Turn it on in the AddOns list and reload.")
    elseif not state then
        return ns:Print("Overlord Forever isn't installed.")
    end
    if InCombatLockdown and InCombatLockdown() then return ns:Print("Open Overlord after combat.") end
    local fn = overlordSlash()
    if fn then
        local ok, err = pcall(fn, "show")
        if ok then return end
        ns:Debug("Overlord /ov show failed: " .. tostring(err))
    end
    if not sendTyped("/ov show") then ns:Print("Type /ov show to open Overlord.") end
end

-- /ruin overlord: what RUIN can see of it.
function UI:PrintOverlord()
    ovListAt = nil
    local state, e = UI:OverlordState()
    if e then
        ns:Print(("Overlord: AddOns list entry %q (%s), %s%s."):format(e.name, e.title ~= "" and e.title or "no title",
            e.loaded and "loaded" or "not loaded", (not e.loaded and e.reason) and (", " .. tostring(e.reason)) or ""))
    else
        ns:Print("Overlord: no addon with \"Overlord\" in its folder name or title is in the AddOns list.")
    end
    ns:Print("Overlord /ov command: " .. (overlordSlash() and "found." or "not found."))
    ns:Print("RUIN treats it as: " .. (state == "loaded" and "installed and running." or state == "off" and "installed, not loaded." or "not installed."))
end

---------------------------------------------------------------------------
-- Guild page: who's online, the message of the day, community links
---------------------------------------------------------------------------
local STATUS = { [0] = { "Online", "good" }, [1] = { "Away", "warn" }, [2] = { "Busy", "bad" } }

local function className(class, fallback)
    if fallback and fallback ~= "" then return fallback end
    local names = LOCALIZED_CLASS_NAMES_MALE
    if names and class and names[class] then return names[class] end
    return class and (class:sub(1, 1) .. class:sub(2):lower()) or ""
end

-- Online guildmates (with or without RUIN) plus RUIN members of the other guilds.
function UI:GuildRows()
    local rows, ruin = {}, {}
    for _, p in ipairs(ns.Presence:GetOnlineList()) do
        if p.guid then ruin[p.guid] = p end
    end
    local inGuild, total = 0, 0
    for _, e in pairs(ns.roster or {}) do
        total = total + 1
        if e.online then
            inGuild = inGuild + 1
            rows[#rows + 1] = { name = e.name, class = e.class, className = e.className, level = e.level,
                                zone = e.zone, status = tonumber(e.status) or 0, own = true,
                                ruin = e.guid and ruin[e.guid] ~= nil }
        end
    end
    local tags = {}
    local k = ns.Org:Get()
    for name, g in pairs(k and k.guilds or {}) do tags[name] = g.tag end
    local others = 0
    for _, p in pairs(ruin) do
        if p.guild and p.guild ~= ns.guildName then
            others = others + 1
            rows[#rows + 1] = { name = p.name, class = p.class, level = p.level, status = 0, ruin = true,
                                guild = p.guild, tag = tags[p.guild] or p.guild }
        end
    end
    table.sort(rows, function(a, b)
        if a.own ~= b.own then return a.own == true end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return tostring(a.name) < tostring(b.name)
    end)
    local ruinCount = 0
    for _ in pairs(ruin) do ruinCount = ruinCount + 1 end
    return rows, { online = inGuild, total = total, others = others, ruin = ruinCount }
end

local function channelDot(scope)
    if ns.Comms:IsJoined(scope) then return GREEN .. "connected|r" end
    if ns.Comms:HasChannel(scope) then return YELLOW .. "joining|r" end
    return GREY .. "off|r"
end

local function buildGuildPanel(p)
    guild.page = p
    guild.orgLine = Wd.Label(p, "", "GameFontHighlightSmall")
    guild.orgLine:SetPoint("TOPLEFT", 2, 0)
    guild.orgLine:SetPoint("RIGHT", p, "RIGHT", -2, 0)
    guild.orgLine:SetWordWrap(false)

    -- Left: who's online
    local left = Wd.Card(p)
    left:SetPoint("TOPLEFT", 0, -20)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(392)
    guild.rosterHeader = Wd.Header(left, "Guild online")
    guild.rosterHeader:SetPoint("TOPLEFT", 10, -8)
    guild.rosterCount = Wd.Label(left, "", "GameFontHighlightSmall")
    guild.rosterCount:SetPoint("LEFT", guild.rosterHeader, "RIGHT", 8, 0)
    guild.rosterCount:SetTextColor(P.sub[1], P.sub[2], P.sub[3])
    guild.roster = Wd.List(left, 24, function(row)
        row.icon = Wd.Label(row, "")
        row.icon:SetPoint("LEFT", 4, 0)
        row.name = Wd.Label(row, "")
        row.name:SetPoint("LEFT", 26, 0)
        row.name:SetWidth(118)
        row.name:SetWordWrap(false)
        row.level = Wd.Label(row, "", "GameFontHighlightSmall")
        row.level:SetPoint("LEFT", 146, 0)
        row.level:SetWidth(24)
        row.class = Wd.Label(row, "", "GameFontHighlightSmall")
        row.class:SetPoint("LEFT", 172, 0)
        row.class:SetWidth(66)
        row.class:SetWordWrap(false)
        row.state = Wd.Label(row, "", "GameFontHighlightSmall")
        row.state:SetPoint("LEFT", 240, 0)
        row.state:SetWidth(54)
        row.badge = Wd.Label(row, "", "GameFontHighlightSmall")
        row.badge:SetPoint("RIGHT", -6, 0)
    end, function(row, r)
        row.icon:SetText(Wd.ClassIcon(r.class, 16))
        row.name:SetText(Wd.ClassName(r.name, r.class))
        row.level:SetText(r.level and tostring(r.level) or "")
        row.class:SetText(GREY .. className(r.class, r.className) .. "|r")
        local st = STATUS[r.status or 0] or STATUS[0]
        row.state:SetText(Wd.Hex(st[2]) .. st[1] .. "|r")
        if r.tag then
            row.badge:SetText(C.gold .. "[" .. ns.Escape(r.tag) .. "]|r")
        else
            row.badge:SetText(r.ruin and (C.accent .. "RUIN|r") or "")
        end
        row.tip = function(tt)
            tt:AddLine(ns.Escape(ns.ShortName(r.name)))
            if r.zone and r.zone ~= "" then tt:AddLine(r.zone, 0.8, 0.8, 0.8) end
            tt:AddLine(r.guild and ("RUIN · " .. ns.Escape(r.guild)) or (r.ruin and "Runs RUIN" or "Not running RUIN yet"), 0.6, 0.7, 0.8)
        end
    end)
    guild.roster:SetEmptyText("Nobody online yet.")
    guild.roster.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -30)
    guild.roster.frame:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -26, 24)
    local together = Wd.Label(left, "Because great games are better together.", "GameFontHighlightSmall")
    together:SetPoint("BOTTOM", left, "BOTTOM", 0, 7)
    together:SetTextColor(P.glow[1], P.glow[2], P.glow[3])

    -- Right column
    local motd = Wd.Card(p)
    motd:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    motd:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    motd:SetHeight(112)
    local mh = Wd.Header(motd, "Guild message of the day")
    mh:SetPoint("TOPLEFT", 10, -8)
    guild.motd = Wd.Label(motd, "", "GameFontHighlightSmall")
    guild.motd:SetPoint("TOPLEFT", 12, -30)
    guild.motd:SetPoint("RIGHT", motd, "RIGHT", -12, 0)
    guild.motd:SetJustifyV("TOP")
    guild.motd:SetHeight(58)
    if guild.motd.SetSpacing then guild.motd:SetSpacing(2) end
    local sig = Wd.Label(motd, "- Leadership", "GameFontHighlightSmall")
    sig:SetPoint("BOTTOMRIGHT", -12, 8)
    sig:SetTextColor(P.sub[1], P.sub[2], P.sub[3])

    local links = Wd.Card(p)
    links:SetPoint("TOPLEFT", motd, "BOTTOMLEFT", 0, -10)
    links:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    links:SetHeight(196)
    local lh = Wd.Header(links, "RUIN community links")
    lh:SetPoint("TOPLEFT", 10, -8)
    guild.editLinks = Wd.Button(links, "Edit", 56, function() UI:PromptLinks() end)
    guild.editLinks:SetPoint("TOPRIGHT", -8, -6)
    guild.linkRows = {}
    for i = 1, 6 do
        local row = CreateFrame("Frame", nil, links)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 26)
        row:SetPoint("RIGHT", links, "RIGHT", -10, 0)
        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(8, 8)
        row.dot:SetPoint("LEFT", 2, 0)
        row.dot:SetColorTexture(P.glow[1], P.glow[2], P.glow[3], 1)
        row.dot:SetRotation(math.pi / 4)
        row.label = Wd.Label(row, "")
        row.label:SetPoint("LEFT", 18, 0)
        row.label:SetWidth(110)
        row.label:SetWordWrap(false)
        row.url = Wd.Label(row, "", "GameFontHighlightSmall")
        row.url:SetPoint("LEFT", 130, 0)
        row.url:SetPoint("RIGHT", row, "RIGHT", -60, 0)
        row.url:SetWordWrap(false)
        row.url:SetTextColor(P.sub[1], P.sub[2], P.sub[3])
        row.copy = Wd.Button(row, "Copy", 52)
        row.copy:SetPoint("RIGHT", 0, 0)
        row:Hide()
        guild.linkRows[i] = row
    end
    guild.linksEmpty = Wd.Label(links, "", "GameFontDisableSmall")
    guild.linksEmpty:SetPoint("TOPLEFT", 12, -34)
    guild.linksEmpty:SetPoint("RIGHT", links, "RIGHT", -12, 0)

    local ov = Wd.Card(p)
    ov:SetPoint("TOPLEFT", links, "BOTTOMLEFT", 0, -10)
    ov:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    ov:SetHeight(70)
    local oh = Wd.Header(ov, "Overlord Forever")
    oh:SetPoint("TOPLEFT", 10, -8)
    guild.ovText = Wd.Label(ov, "", "GameFontHighlightSmall")
    guild.ovText:SetPoint("TOPLEFT", 12, -30)
    guild.ovText:SetPoint("RIGHT", ov, "RIGHT", -110, 0)
    guild.ovText:SetJustifyV("TOP")
    guild.ovButton = Wd.Button(ov, "Open  /ov show", 96, function() UI:OpenOverlord() end)
    guild.ovButton:SetPoint("TOPRIGHT", -8, -28)

    local unites = p:CreateFontString(nil, "OVERLAY")
    unites:SetFontObject(GameFontNormal)
    unites:SetFont(TITLE_FONT, 16, "")
    unites:SetTextColor(P.gold[1], P.gold[2], P.gold[3])
    unites:SetText("RUIN unites us")
    unites:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -4, 2)

    p:SetScript("OnShow", function() UI:Refresh() end)
    UI:Refresh()
end

local function refreshGuild()
    if not (guild.page and guild.page:IsVisible()) then return end
    local k = ns.Org:Get()
    local parts = {}
    if k then
        local n = 0
        for _ in pairs(k.guilds) do n = n + 1 end
        parts[#parts + 1] = C.gold .. ns.Escape(k.org) .. "|r"
        parts[#parts + 1] = ("%d guild%s"):format(n, n == 1 and "" or "s")
        parts[#parts + 1] = "Org chat " .. channelDot("ORG")
        if ns.Org:AmOfficer() then parts[#parts + 1] = "Officer chat " .. channelDot("OFFICERS") end
    else
        parts[#parts + 1] = RED .. "No org key yet.|r An officer shares it automatically, or import it under Options."
    end
    guild.orgLine:SetText(table.concat(parts, GREY .. "   ·   |r"))

    local rows, counts = UI:GuildRows()
    guild.rosterCount:SetText(ns.guildName and ("%d/%d in %s  ·  %d with RUIN"):format(counts.online, counts.total,
        ns.Escape(ns.guildName), counts.ruin) or "")
    guild.roster:SetItems(rows)

    local text = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
    guild.motd:SetText((text and text ~= "") and ns.Escape(text) or (GREY .. "No message of the day.|r"))

    local list = ns.Org:GetLinks()
    for i, row in ipairs(guild.linkRows) do
        local l = list[i]
        if l then
            row.label:SetText(ns.Escape(l.label))
            row.url:SetText(ns.Escape(l.url))
            row.copy:SetScript("OnClick", function() UI:CopyLink(l.label, l.url) end)
            row:Show()
        else
            row:Hide()
        end
    end
    guild.linksEmpty:SetText(#list == 0 and "No links yet. The org admin adds Discord, the website and streams with Edit (or /ruin key links)." or "")
    guild.editLinks:SetShown(ns.Org:IsAdmin())

    local ovState = UI:OverlordState()
    if ovState == "loaded" then
        guild.ovText:SetText("Installed. RUIN's world PvP runs on Overlord: its campaign, keeps, captures and Most Wanted. RUIN Muster adds org rallies and bounties.")
        guild.ovButton:Show()
    elseif ovState == "off" then
        guild.ovText:SetText(GREY .. "Installed but not loaded. Turn Overlord Forever on in the AddOns list and reload; RUIN uses it for world PvP.|r")
        guild.ovButton:Hide()
    else
        guild.ovText:SetText(GREY .. "Not installed. RUIN uses Overlord Forever for world PvP (campaign, keeps, Most Wanted); get it on CurseForge.|r")
        guild.ovButton:Hide()
    end
end

---------------------------------------------------------------------------
-- Settings page: the org key, display options, about
---------------------------------------------------------------------------
local function buildSettingsPanel(p)
    settings.page = p
    local keyCard = Wd.Card(p)
    keyCard:SetPoint("TOPLEFT", 0, 0)
    keyCard:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    keyCard:SetHeight(176)
    local kh = Wd.Header(keyCard, "Org key")
    kh:SetPoint("TOPLEFT", 10, -8)
    settings.status = Wd.Label(keyCard, "", "GameFontHighlightSmall")
    settings.status:SetPoint("TOPLEFT", 12, -30)
    settings.status:SetPoint("RIGHT", keyCard, "RIGHT", -12, 0)
    settings.status:SetJustifyV("TOP")
    if settings.status.SetSpacing then settings.status:SetSpacing(3) end

    -- Everyone's key actions, then the org admin's (shown only to the admin).
    settings.import = Wd.Button(keyCard, "Import key", 120, function() UI:PromptImport() end)
    settings.export = Wd.Button(keyCard, "Export key", 120, function() UI:ShowExport() end)
    settings.send = Wd.Button(keyCard, "Send key to target", 160, function() UI:SendKeyToTarget() end)
    settings.create = Wd.Button(keyCard, "Create org key", 130, function() UI:PromptCreate() end)
    settings.adminLabel = Wd.Label(keyCard, C.gold .. "Org admin|r", "GameFontNormalSmall")
    settings.addGuild = Wd.Button(keyCard, "Add guild", 110, function() UI:PromptAddGuild() end)
    settings.rotate = Wd.Button(keyCard, "Rotate key", 110, function() UI:PromptRotate() end)
    settings.links = Wd.Button(keyCard, "Community links", 140, function() UI:PromptLinks() end)
    settings.keyCard = keyCard

    local disp = Wd.Card(p)
    disp:SetPoint("TOPLEFT", keyCard, "BOTTOMLEFT", 0, -10)
    disp:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    disp:SetHeight(108)
    local dh = Wd.Header(disp, "Chat and display")
    dh:SetPoint("TOPLEFT", 10, -8)
    local s = function() return ns.db.settings end
    settings.checks = {
        Wd.Check(disp, "Show other guilds' chat", function() return s().showOrgChat end,
            function(v) s().showOrgChat = v end),
        Wd.Check(disp, "Show other guilds' officer chat", function() return s().showOfficerChat end,
            function(v) s().showOfficerChat = v end),
        Wd.Check(disp, "Share chat from guildmates without RUIN", function() return s().allowBridge end,
            function(v) s().allowBridge = v; ns:Fire("SETTINGS_CHANGED") end),
        Wd.Check(disp, "Couch mode (larger window, for Steam Deck and TV)", function() return s().couchMode end,
            function(v) s().couchMode = v; UI:ApplyScale() end),
        Wd.Check(disp, "Animated page headers", function() return s().animations end,
            function(v) s().animations = v end),
    }
    settings.checks[1].tip = "Show guild chat from the other RUIN guilds in your guild chat."
    settings.checks[2].tip = "Show officer chat from the other RUIN guilds in your officer chat."
    settings.checks[3].tip = "Guildmates who don't run RUIN can't send to the other guilds. When this is on, one RUIN member online passes their guild chat along."
    settings.checks[4].tip = "Bigger window and on-screen frames, easier to read on a Steam Deck or a TV."
    settings.checks[5].tip = "The small moving scene in each page's header."
    settings.checks[1]:SetPoint("TOPLEFT", 8, -28)
    settings.checks[2]:SetPoint("TOPLEFT", settings.checks[1], "BOTTOMLEFT", 0, -2)
    settings.checks[5]:SetPoint("TOPLEFT", settings.checks[2], "BOTTOMLEFT", 0, -2)
    settings.checks[3]:SetPoint("TOPLEFT", settings.checks[1], "TOPLEFT", 330, 0)
    settings.checks[4]:SetPoint("TOPLEFT", settings.checks[3], "BOTTOMLEFT", 0, -2)

    local about = Wd.Card(p)
    about:SetPoint("TOPLEFT", disp, "BOTTOMLEFT", 0, -10)
    about:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    local ah = Wd.Header(about, "About RUIN")
    ah:SetPoint("TOPLEFT", 10, -8)
    settings.about = Wd.Label(about, "", "GameFontHighlightSmall")
    settings.about:SetPoint("TOPLEFT", 12, -30)
    settings.about:SetPoint("RIGHT", about, "RIGHT", -12, 0)
    settings.about:SetJustifyV("TOP")
    if settings.about.SetSpacing then settings.about:SetSpacing(3) end

    p:SetScript("OnShow", function() UI:Refresh() end)
    UI:Refresh()
end

local function setEnabled(button, on)
    if on then button:Enable() else button:Disable() end
end

local function refreshSettings()
    if not (settings.page and settings.page:IsVisible()) then return end
    local k = ns.Org:Get()
    local lines = {}
    if k then
        lines[#lines + 1] = ("Org: |cffffffff%s|r   key rev %d%s"):format(ns.Escape(k.org), k.rev,
            ns.Org:IsAdmin() and ("   " .. C.gold .. "you are the org admin|r") or "")
    else
        lines[#lines + 1] = RED .. "No org key yet.|r An officer shares it automatically, or use Import key."
    end
    if ns.guildName then
        lines[#lines + 1] = ("Guild: |cffffffff%s|r   %s%s"):format(ns.Escape(ns.guildName),
            ns.Org:MyGuildInOrg() and (GREEN .. "in org|r") or (RED .. "not in org key|r"),
            ns.Org:AmOfficer() and "   (officer)" or "")
    else
        lines[#lines + 1] = RED .. "You are not in a guild.|r"
    end
    lines[#lines + 1] = ("Org channel: %s     Officer channel: %s"):format(channelDot("ORG"), channelDot("OFFICERS"))
    local bridge = ns.Presence:BridgeGUID()
    lines[#lines + 1] = "Guild bridge: " .. (bridge and (bridge == ns.playerGUID and "you"
        or ns.ShortName(ns.Presence:NameForGUID(bridge) or "?")) or GREY .. "none|r")
    settings.status:SetText(table.concat(lines, "\n"))

    -- Only the buttons that do something for you, in one or two rows.
    local admin = ns.Org:IsAdmin()
    local row1 = { settings.import }
    if k then row1[#row1 + 1] = settings.export end
    if k and (admin or (k.oc ~= nil and ns.Org:AmOfficer())) then row1[#row1 + 1] = settings.send end
    if not k then row1[#row1 + 1] = settings.create end
    local row2 = admin and { settings.addGuild, settings.rotate, settings.links } or {}
    local all = { settings.import, settings.export, settings.send, settings.create, settings.addGuild, settings.rotate, settings.links }
    for _, b in ipairs(all) do b:Hide() end
    local function place(list, y, x0)
        local prev
        for _, b in ipairs(list) do
            b:ClearAllPoints()
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", settings.keyCard, "TOPLEFT", x0, y) end
            b:Show()
            prev = b
        end
    end
    place(row1, -98, 10)
    settings.adminLabel:ClearAllPoints()
    settings.adminLabel:SetPoint("TOPLEFT", settings.keyCard, "TOPLEFT", 12, -136)
    settings.adminLabel:SetShown(#row2 > 0)
    place(row2, -130, 82)
    settings.keyCard:SetHeight(#row2 > 0 and 164 or 132)
    for _, c in ipairs(settings.checks) do c:Refresh() end
    -- Officer chat only matters to officers.
    local officer = ns.Org:AmOfficer()
    settings.checks[2]:SetShown(officer)
    settings.checks[5]:ClearAllPoints()
    settings.checks[5]:SetPoint("TOPLEFT", officer and settings.checks[2] or settings.checks[1], "BOTTOMLEFT", 0, -2)

    local mods = {}
    for _, m in ipairs(RUIN_API:GetModules()) do mods[#mods + 1] = m.name .. " " .. tostring(m.version or "") end
    local members, guilds = ns.Presence:CountOnline()
    settings.about:SetText(table.concat({
        ("%s, RUIN Core %s, on %s.   Online with RUIN: %d in %d guild(s)."):format(ns.APP_NAME or "RUIN Gaming Companion App", ns.VERSION, ns.CLIENT_NAME, members, guilds),
        "Modules: " .. (#mods > 0 and table.concat(mods, ", ") or (GREY .. "none installed|r")),
        GREY .. "RUIN shares only with RUIN members of your org, never outside the game. No ads.|r",
        GREY .. "Commands: /ruin help.  Key binding: Key Bindings > AddOns > RUIN.|r",
    }, "\n"))
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local WINDOW_W, WINDOW_H = 780, 660
local TITLE_H, TAB_H, TAB_GAP = 50, 26, 4

local function themeForTab(t)
    if t.module then return ns.ThemeFor(t.module.name, t.module) end
    return ns.ThemeFor(t.title)
end

-- Tabs show the job ("Gear Path", "Leveling") and sort the way the brief
-- lays them out; Settings is always last.
local function tabLabel(t)
    local theme = themeForTab(t)
    return t.label or theme.tab or t.title
end

local function tabOrder(t)
    local theme = themeForTab(t)
    return t.order or theme.order or 50
end

-- Each tab wears its page's colors: RUIN's teal for Guild and Options, the
-- addon's own color for module pages (a thin strip shows it even unselected).
local function paintTab(t)
    local b = t.button
    if not b then return end
    local on = selectedTab ~= nil and tabs[selectedTab] == t
    if on then
        Wd.Skin(b, "panelHi", 1, "glow")
        b.text:SetTextColor(1, 1, 1)
    elseif b.hover then
        Wd.Skin(b, "panelHi", 0.95, "border")
        b.text:SetTextColor(P.text[1], P.text[2], P.text[3])
    else
        Wd.Skin(b, "panel", 0.92, "border")
        b.text:SetTextColor(P.sub[1], P.sub[2], P.sub[3])
    end
    b.line:SetShown(on)
    b.strip:SetShown(not on)
end

-- The content area takes the selected page's edge color and tint.
local function paintContent(theme)
    local s = Wd.SchemeFor(theme)
    Wd.Skin(content, s.panel, 0.55, s.edge)
end

local function updateChrome()
    if not main then return end
    local connected = ns.Comms:IsJoined("ORG")
    main.state:SetText((connected and (GREEN .. "connected to RUIN|r") or (GREY .. "not connected|r"))
        .. GREY .. "   ·   " .. ns.CLIENT_NAME .. "|r")
    local c = connected and P.good or P.sub
    main.stateDot:SetColorTexture(c[1], c[2], c[3], 1)
end

function UI:SelectTab(index)
    local changed = selectedTab ~= index
    selectedTab = index
    for i, t in ipairs(tabs) do
        if i == index then
            local theme = themeForTab(t)
            paintContent(theme)
            if not t.panel then
                t.panel = CreateFrame("Frame", nil, content)
                t.panel.ruinTheme = theme
                t.panel:SetAllPoints(content)
                local headerHeight = Wd.PageHeader(t.panel, theme)
                t.body = CreateFrame("Frame", nil, t.panel)
                t.body:SetPoint("TOPLEFT", 10, -(headerHeight + 10))
                t.body:SetPoint("BOTTOMRIGHT", -10, 10)
                Wd.currentTheme = theme
                local ok, err = pcall(t.builder, t.body, t.module)
                Wd.currentTheme = nil
                if not ok then ns.ReportError(err) end
            end
            t.panel:Show()
        elseif t.panel then
            t.panel:Hide()
        end
    end
    for _, t in ipairs(tabs) do paintTab(t) end
    if changed and main:IsShown() then sound("IG_CHARACTER_INFO_TAB") end
end

function UI:LayoutTabs()
    if not main then return end
    for i, t in ipairs(tabs) do
        if not t.button then
            local theme = themeForTab(t)
            local b = CreateFrame("Button", nil, tabStrip)
            b.ruinTheme = theme
            b:SetHeight(TAB_H)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(14, 14)
            b.icon:SetPoint("LEFT", 7, 0)
            b.icon:SetTexture(theme.icon)
            pcall(b.icon.SetMask, b.icon, ROUND_MASK)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
            b.text:SetText(tabLabel(t))
            local ac = Wd.SchemeFor(theme).accent
            b.line = b:CreateTexture(nil, "OVERLAY")
            b.line:SetColorTexture(ac[1], ac[2], ac[3], 1)
            b.line:SetHeight(2)
            b.line:SetPoint("BOTTOMLEFT", 1, 1)
            b.line:SetPoint("BOTTOMRIGHT", -1, 1)
            local tc = theme.color or P.glow
            b.strip = b:CreateTexture(nil, "OVERLAY")
            b.strip:SetColorTexture(tc[1], tc[2], tc[3], 0.55)
            b.strip:SetHeight(1)
            b.strip:SetPoint("BOTTOMLEFT", 6, 1)
            b.strip:SetPoint("BOTTOMRIGHT", -6, 1)
            b:SetWidth(math.max(60, (b.text:GetStringWidth() or 50) + 36))
            b:SetScript("OnClick", function() UI:SelectTab(i) end)
            b:SetScript("OnEnter", function(self) self.hover = true; paintTab(t) end)
            b:SetScript("OnLeave", function(self) self.hover = false; paintTab(t) end)
            t.button = b
        end
    end
    -- Sorted by order; extras wrap onto a second row.
    local sorted = {}
    for i, t in ipairs(tabs) do sorted[#sorted + 1] = { t = t, i = i } end
    table.sort(sorted, function(a, b)
        local oa, ob = tabOrder(a.t), tabOrder(b.t)
        if oa ~= ob then return oa < ob end
        return a.i < b.i
    end)
    local x, row = 0, 0
    local width = WINDOW_W - 24
    for _, e in ipairs(sorted) do
        local b = e.t.button
        local w = b:GetWidth() or 90
        if x > 0 and x + w > width then x, row = 0, row + 1 end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", tabStrip, "TOPLEFT", x, -row * (TAB_H + TAB_GAP))
        x = x + w + TAB_GAP
        paintTab(e.t)
    end
    local rows = row + 1
    tabStrip:SetHeight(rows * (TAB_H + TAB_GAP))
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", main, "TOPLEFT", 10, -(TITLE_H + 8 + rows * (TAB_H + TAB_GAP) + 2))
    content:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -10, 10)
    if not selectedTab and sorted[1] then UI:SelectTab(sorted[1].i) end
end

-- Tab labels in the order they appear along the top.
function UI:TabLabels()
    local sorted = {}
    for i, t in ipairs(tabs) do sorted[#sorted + 1] = { t = t, i = i } end
    table.sort(sorted, function(a, b)
        local oa, ob = tabOrder(a.t), tabOrder(b.t)
        if oa ~= ob then return oa < ob end
        return a.i < b.i
    end)
    local out = {}
    for _, e in ipairs(sorted) do out[#out + 1] = tabLabel(e.t) end
    return out
end

-- opts: { order = n, label = "Tab text", alias = "Other name" }
function UI:AddTab(title, builder, module, opts)
    opts = opts or {}
    tabs[#tabs + 1] = { title = title, builder = builder, module = module,
                        order = opts.order, label = opts.label, alias = opts.alias }
    if main then UI:LayoutTabs() end
    return #tabs
end

-- Open the window on a page, by title, tab label, module name or index.
function UI:OpenTab(which)
    if not ns.db then return end
    if not main then UI:CreateMain() end
    for i, t in ipairs(tabs) do
        if i == which or t.title == which or t.alias == which or tabLabel(t) == which
            or (t.module and t.module.name == which) then
            main:Show()
            UI:SelectTab(i)
            return true
        end
    end
    return false
end

function UI:CreateMain()
    main = CreateFrame("Frame", "RUIN_MainFrame", UIParent)
    main:SetSize(WINDOW_W, WINDOW_H)
    Wd.Skin(main, "bg", 0.97, "border")
    local shade = main:CreateTexture(nil, "BACKGROUND", nil, -8)
    shade:SetPoint("TOPLEFT", -4, 4)
    shade:SetPoint("BOTTOMRIGHT", 4, -4)
    shade:SetColorTexture(0, 0, 0, 0.55)

    -- Title bar: the RUIN mark, the brief's tagline, connection state, close.
    local bar = CreateFrame("Frame", nil, main)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TITLE_H)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and barBg.SetGradient and pcall(barBg.SetGradient, barBg, "VERTICAL",
        CreateColor(P.bg[1], P.bg[2], P.bg[3], 1), CreateColor(P.panelHi[1], P.panelHi[2], P.panelHi[3], 1))
    if not ok then barBg:SetColorTexture(P.panel[1], P.panel[2], P.panel[3], 1) end
    local rule = bar:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(P.border[1], P.border[2], P.border[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)

    local ring = drawMark(bar, 32)
    ring:SetPoint("LEFT", 12, 0)
    local word = bar:CreateFontString(nil, "OVERLAY")
    word:SetFontObject(GameFontNormalHuge)
    word:SetFont(TITLE_FONT, 28, "")
    word:SetTextColor(P.gold[1], P.gold[2], P.gold[3])
    word:SetShadowOffset(1, -1)
    word:SetShadowColor(0, 0, 0, 1)
    word:SetText("RUIN")
    word:SetPoint("LEFT", ring, "RIGHT", 8, 1)
    local divider = bar:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(P.border[1], P.border[2], P.border[3], 1)
    divider:SetSize(1, 28)
    divider:SetPoint("LEFT", word, "RIGHT", 14, -1)
    local tagline = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagline:SetText("GAMING COMPANION APP")
    tagline:SetTextColor(P.gold[1] * 0.9, P.gold[2] * 0.9, P.gold[3] * 0.9)
    tagline:SetPoint("BOTTOMLEFT", divider, "RIGHT", 14, 1)
    local motto = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    motto:SetText("Guide  ·  Gear  ·  Quests  ·  Guild")
    motto:SetTextColor(P.sub[1], P.sub[2], P.sub[3])
    motto:SetPoint("TOPLEFT", divider, "RIGHT", 14, -2)

    local close = closeButton(bar, function() main:Hide() end)
    close:SetPoint("RIGHT", -10, 0)
    main.state = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    main.state:SetPoint("RIGHT", close, "LEFT", -12, 0)
    main.stateDot = bar:CreateTexture(nil, "OVERLAY")
    main.stateDot:SetSize(7, 7)
    main.stateDot:SetRotation(math.pi / 4)
    main.stateDot:SetPoint("RIGHT", main.state, "LEFT", -6, 0)

    tabStrip = CreateFrame("Frame", nil, main)
    tabStrip:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -(TITLE_H + 8))
    tabStrip:SetPoint("RIGHT", main, "RIGHT", -12, 0)
    tabStrip:SetHeight(TAB_H)
    content = CreateFrame("Frame", nil, main)
    content:SetPoint("TOPLEFT", main, "TOPLEFT", 10, -(TITLE_H + 8 + TAB_H + TAB_GAP + 2))
    content:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -10, 10)
    Wd.Skin(content, "panel", 0.55, "border")

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
    updateChrome()
end

function UI:Refresh()
    if not main or not main:IsShown() then return end
    updateChrome()
    refreshGuild()
    refreshSettings()
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

UI:AddTab("Guild", buildGuildPanel, nil, { alias = "Org" })
UI:AddTab("Settings", buildSettingsPanel)

for _, ev in ipairs({ "KEY_CHANGED", "PEERS_CHANGED", "ROSTER_UPDATED", "CHANNELS_CHANGED", "GUILD_CHANGED" }) do
    ns:Subscribe(ev, function() UI:Refresh() end)
end
