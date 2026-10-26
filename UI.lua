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

    -- the text box sits under the hint, however many lines the hint takes
    local inset = CreateFrame("Frame", nil, d)
    inset:SetPoint("TOPLEFT", d.hint, "BOTTOMLEFT", -4, -10)
    inset:SetPoint("BOTTOMRIGHT", -14, 50)
    Wd.Skin(inset, "panel", 1, "border")

    local sf = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -6)
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

-- The dialog's height follows the hint: title, hint, a text box of at
-- least BOX_H, and the buttons.
local DIALOG_TOP, BOX_H, DIALOG_BOTTOM = 40, 120, 50
function UI:ShowText(title, hint, text, onAccept, selectAll)
    local d = getDialog()
    d.title:SetText(title)
    d.hint:SetText(hint or "")
    local hintH = (hint and hint ~= "") and math.ceil(d.hint:GetStringHeight() or 14) or 0
    d:SetHeight(DIALOG_TOP + hintH + 10 + BOX_H + DIALOG_BOTTOM)
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
    UI:ShowText("Import org key", "Paste the RUIN key, or type the org's key phrase, then press OK.", "", function(text)
        text = text or ""
        -- not a full key: treat it as a key phrase
        if not ns.Trim(text):upper():find("^RUIN1:") then
            local ok, err = ns.Org:JoinWithPhrase(text)
            ns:Print(ok and "Joining with the key phrase; a RUIN member online will send the key (this takes a few seconds)." or ("Import failed: " .. err))
            return
        end
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

-- Only the org admin exports the key: a pasted key is how a new guild joins.
function UI:ShowExport()
    local k = ns.Org:Get()
    if not k then
        ns:Print("No org key to export.")
        return
    end
    if not ns.Org:IsAdmin() then
        ns:Print("Only the org admin can export the org key. Inside your guild, officers share it automatically.")
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
    UI:ShowText("Create org key", "Name of the organization. You become the org admin; your guild is added with rank 1 as officer.", "RUIN", function(name)
        UI:ShowText("Key phrase (optional)", "A word or phrase members type under Import key to join (6 to 40 characters), like  dragons eat at dawn.\nLeave it empty for a random key (safer; shared with Export key or Send key to target).", "", function(phrase)
            local ok, err = ns.Org:Create(name, phrase)
            ns:Print(ok and "Org key created. Add the other guilds next." or err)
        end)
    end, true)
end

function UI:PromptAddGuild()
    UI:ShowText("Add guild", "Guild name, lowest officer rank, short tag. Example:  Ashen Order, 1, Ashen\nRank 0 is the guild master, 1 the next rank down, and so on.", "", function(text)
        local name, rank, tag = ns.ParseGuildSpec(text)
        local ok, err = ns.Org:AddGuild(name, rank, tag)
        ns:Print(ok and ("Added " .. name .. ".") or err)
    end)
end

-- The admin's "Choose new key": a new key phrase, or a random key.
function UI:PromptNewKey()
    if not ns.Org:IsAdmin() then return ns:Print("Only the org admin can choose a new key.") end
    UI:ShowText("Choose new key", "Type a new key phrase (6 to 40 characters) that members type under Import key to join, or leave it empty for a new random key.\nEveryone gets new channels: officers online get the new key at once and pass it on; members offline right now need the new phrase or key.",
        ns.Org:Phrase() or "", function(text)
        local ph, err
        if ns.Trim(text or "") ~= "" then
            ph, err = ns.Org.CheckPhrase(text)
            if not ph then return ns:Print(err) end
        end
        UI:ShowConfirm("Choose new key", ph and ("Change the org's key to the phrase\n\n%s\n\nThe old key and phrase stop working."):format(ns.Escape(ph))
            or "Change the org's key to a new random key?\n\nThe old key and phrase stop working.", function()
            local ok, e = ns.Org:ChooseNewKey(ph)
            ns:Print(ok and (ph and ("New key phrase set: " .. ph .. ".") or "New random org key set.") or e)
            UI:Refresh()
        end)
    end, true)
end
UI.PromptRotate = UI.PromptNewKey

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

-- Everyone online with RUIN across the org (you, your guildmates and the
-- other guilds' members), for the Overview. The full rosters are on Roster.
function UI:GuildRows()
    local rows, guilds = {}, {}
    local k = ns.Org:Get()
    for _, p in ipairs(ns.Presence:GetOnlineList()) do
        local gi = k and p.guild and k.guilds[p.guild]
        rows[#rows + 1] = { name = p.name, class = p.class, level = p.level, zone = p.zone, status = tonumber(p.status) or 0,
                            guild = p.guild, own = p.guild == ns.guildName, tag = (gi and gi.tag) or p.guild,
                            version = p.version, self = p.self }
        if p.guild then guilds[p.guild] = true end
    end
    table.sort(rows, function(a, b)
        if a.own ~= b.own then return a.own == true end
        if (a.guild or "") ~= (b.guild or "") then return (a.guild or "") < (b.guild or "") end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return tostring(a.name) < tostring(b.name)
    end)
    local ng = 0
    for _ in pairs(guilds) do ng = ng + 1 end
    return rows, { ruin = #rows, guilds = ng }
end

local function channelDot(scope)
    if ns.Comms:IsJoined(scope) then return GREEN .. "connected|r" end
    if ns.Comms:HasChannel(scope) then return YELLOW .. "joining|r" end
    return GREY .. "off|r"
end

local buildGuildOverview

-- Guild page: Overview (who's online, MOTD, links, Overlord), Roster (the
-- full guild window roster with moderation) and Chat (guild or org chat,
-- with a pop-out window). Roster and Chat live in Guild.lua.
local function buildGuildPanel(p)
    guild.tabs = Wd.SubTabs(p, { "Overview", "Roster", "Chat" }, function(i)
        if i == 2 then ns.GuildUI.RefreshRoster() elseif i == 3 then ns.GuildUI.RefreshChat() else UI:Refresh() end
    end)
    buildGuildOverview(guild.tabs.pages[1])
    ns.GuildUI.BuildRoster(guild.tabs.pages[2])
    guild.chat = ns.GuildUI.BuildChatView(guild.tabs.pages[3], false)
    guild.tabs:Select(1)
end

function UI:SelectGuildTab(i) if guild.tabs then guild.tabs:Select(i) end end

buildGuildOverview = function(p)
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
    guild.rosterHeader = Wd.Header(left, "Online with RUIN")
    guild.rosterHeader:SetPoint("TOPLEFT", 10, -8)
    guild.rosterCount = Wd.Label(left, "", "GameFontHighlightSmall")
    guild.rosterCount:SetPoint("LEFT", guild.rosterHeader, "RIGHT", 8, 0)
    guild.rosterCount:SetTextColor(P.sub[1], P.sub[2], P.sub[3])
    guild.roster = Wd.List(left, 24, function(row)
        row.icon = Wd.Label(row, "")
        row.icon:SetPoint("LEFT", 4, 0)
        row.name = Wd.Label(row, "")
        row.name:SetPoint("LEFT", 26, 0)
        row.name:SetWidth(112)
        row.name:SetWordWrap(false)
        row.level = Wd.Label(row, "", "GameFontHighlightSmall")
        row.level:SetPoint("LEFT", 140, 0)
        row.level:SetWidth(22)
        row.zone = Wd.Label(row, "", "GameFontHighlightSmall")
        row.zone:SetPoint("LEFT", 166, 0)
        row.zone:SetWidth(120)
        row.zone:SetWordWrap(false)
        row.badge = Wd.Label(row, "", "GameFontHighlightSmall")
        row.badge:SetPoint("RIGHT", -6, 0)
        row.badge:SetWidth(70)
        row.badge:SetJustifyH("RIGHT")
        row.badge:SetWordWrap(false)
    end, function(row, r)
        row.icon:SetText(Wd.ClassIcon(r.class, 16))
        local st = STATUS[r.status or 0]
        row.name:SetText(Wd.ClassName(r.name, r.class) .. ((r.status or 0) > 0 and st and (" " .. Wd.Hex(st[2]) .. "(" .. st[1] .. ")|r") or ""))
        row.level:SetText(r.level and tostring(r.level) or "")
        row.zone:SetText(GREY .. ns.Escape(r.zone or "") .. "|r")
        row.badge:SetText((r.own and GREEN or C.gold) .. "[" .. ns.Escape(r.tag or "?") .. "]|r")
        row.tip = function(tt)
            tt:AddLine(ns.Escape(ns.ShortName(r.name)) .. (r.self and "  (you)" or ""))
            tt:AddLine(("Level %s %s"):format(tostring(r.level or "?"), className(r.class)), 0.8, 0.8, 0.8)
            if r.zone and r.zone ~= "" then tt:AddLine(r.zone, 0.8, 0.8, 0.8) end
            tt:AddLine(ns.Escape(r.guild or "?") .. (r.version and ("  ·  RUIN " .. r.version) or ""), 0.6, 0.7, 0.8)
        end
    end)
    guild.roster:SetEmptyText("Nobody is connected with RUIN yet.")
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
    guild.editMotd = Wd.Button(motd, "Edit", 56, function()
        local cur = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
        UI:ShowText("Guild message of the day", "Everyone in the guild sees it when they log in (up to 128 characters).", cur, function(text)
            ns.Guild:SetMOTD(text)
        end)
    end)
    guild.editMotd:SetPoint("TOPRIGHT", -8, -6)
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

    -- Overlord Forever: one short line of state; the button sits on the header line.
    local ov = Wd.Card(p)
    ov:SetPoint("TOPLEFT", links, "BOTTOMLEFT", 0, -10)
    ov:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    ov:SetHeight(78)
    local oh = Wd.Header(ov, "Overlord Forever")
    oh:SetPoint("TOPLEFT", 10, -8)
    guild.ovButton = Wd.Button(ov, "Open Overlord", 112, function() UI:OpenOverlord() end)
    guild.ovButton:SetPoint("TOPRIGHT", -8, -6)
    guild.ovText = Wd.Label(ov, "", "GameFontHighlightSmall")
    guild.ovText:SetPoint("TOPLEFT", 12, -32)
    guild.ovText:SetPoint("RIGHT", ov, "RIGHT", -12, 0)
    guild.ovText:SetJustifyV("TOP")
    if guild.ovText.SetSpacing then guild.ovText:SetSpacing(2) end

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
        parts[#parts + 1] = RED .. "No org key yet.|r An officer shares it automatically, or import it under Settings."
    end
    guild.orgLine:SetText(table.concat(parts, GREY .. "   ·   |r"))

    local rows, counts = UI:GuildRows()
    guild.rosterCount:SetText(("%d in %d guild%s  ·  everyone: Roster tab"):format(counts.ruin, counts.guilds, counts.guilds == 1 and "" or "s"))
    guild.roster:SetItems(rows)

    local text = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
    guild.motd:SetText((text and text ~= "") and ns.Escape(text) or (GREY .. "No message of the day.|r"))
    guild.editMotd:SetShown(ns.Guild:Can("motd"))

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
        guild.ovText:SetText("Installed. RUIN's world PvP (campaign, keeps, Most Wanted) runs on Overlord; Muster adds org rallies and bounties.")
        guild.ovButton:Show()
    elseif ovState == "off" then
        guild.ovText:SetText(GREY .. "Installed but switched off. Turn it on in the AddOns list and reload; RUIN uses it for world PvP.|r")
        guild.ovButton:Hide()
    else
        guild.ovText:SetText(GREY .. "Not installed. RUIN uses it for world PvP (campaign, keeps, Most Wanted); get it on CurseForge.|r")
        guild.ovButton:Hide()
    end
end

---------------------------------------------------------------------------
-- Settings page: the org key, display options, about
---------------------------------------------------------------------------
local refreshSettings

-- Rank names of your own guild ("0  Guild Master"); numbers for other guilds.
local function rankLabel(guildName, rank)
    rank = tonumber(rank) or 0
    local name
    if guildName == ns.guildName and GuildControlGetRankName then
        local ok, n = pcall(GuildControlGetRankName, rank + 1)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    return name and (rank .. "  " .. name) or ("Rank " .. rank)
end

-- The org admin's list of guilds: pick one to rename it, change which ranks
-- count as officers, change its tag, or remove it from the org.
local function buildGuildAdmin(parent, anchor)
    local card = Wd.Card(parent)
    card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    settings.guildCardAnchor = anchor
    card:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    local h = Wd.Header(card, "Guilds in the org")
    h:SetPoint("TOPLEFT", 10, -8)
    local hint = Wd.Label(card, GREY .. "Org admin only. Pick a guild to change it.|r", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", h, "RIGHT", 10, 0)
    settings.guildList = Wd.List(card, 26, function(row)
        row.name = Wd.Label(row, "")
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetWidth(170)
        row.name:SetWordWrap(false)
        row.info = Wd.Label(row, "", "GameFontHighlightSmall")
        row.info:SetPoint("LEFT", 182, 0)
        row.info:SetWidth(120)
        row.info:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function(self)
            if self.g then settings.gSel = self.g.name; settings.gEdit = nil; refreshSettings() end
        end)
    end, function(row, g)
        row.g = g
        local on = settings.gSel == g.name
        row.name:SetText((on and C.gold or C.white) .. ns.Escape(g.name) .. "|r" .. (g.name == ns.guildName and (GREY .. "  (yours)|r") or ""))
        row.info:SetText(GREY .. "[" .. ns.Escape(g.tag or "") .. "]  officers 0-" .. tostring(g.o) .. "|r")
    end)
    settings.guildList.frame:SetPoint("TOPLEFT", 6, -30)
    settings.guildList.frame:SetPoint("BOTTOMLEFT", 6, 8)
    settings.guildList.frame:SetWidth(320)

    local ed = CreateFrame("Frame", nil, card)
    ed:SetPoint("TOPLEFT", 352, -30)
    ed:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
    local function label(text, y)
        local l = Wd.Label(ed, GREY .. text .. "|r", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 0, y)
        return l
    end
    label("Guild name (exactly as in game)", 0)
    settings.gName = Wd.EditBox(ed, 220)
    settings.gName:SetPoint("TOPLEFT", 0, -14)
    label("Short tag shown in chat", -44)
    settings.gTag = Wd.EditBox(ed, 120)
    settings.gTag:SetPoint("TOPLEFT", 0, -58)
    label("Officers are ranks 0 to", -88)
    settings.gRank = Wd.Dropdown(ed, 200, { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        function() return settings.gRankValue end, function(v) settings.gRankValue = v end)
    settings.gRank.format = function(v) return rankLabel(settings.gSel, v) end
    settings.gRank.tipTitle = "The lowest guild rank that counts as officer (0 is the guild master)"
    settings.gRank:SetPoint("TOPLEFT", 0, -102)
    settings.gSave = Wd.Button(ed, "Save changes", 116, function()
        local old = settings.gSel
        if not old then return end
        local new = ns.Trim(settings.gName:GetText() or "")
        local function save()
            local ok, err = ns.Org:EditGuild(old, new, settings.gRankValue, settings.gTag:GetText())
            if ok then
                settings.gSel = new
                ns:Print(("Saved %s. Every RUIN member gets the change with the org key."):format(new))
            else
                ns:Print(err)
            end
            refreshSettings()
        end
        if new ~= old then
            UI:ShowConfirm("Rename guild", ("Rename %s to %s in the org key?\n\nThe name must match the in-game guild name exactly, or that guild's members lose the org connection.")
                :format(ns.Escape(old), ns.Escape(new)), save)
        else
            save()
        end
    end)
    settings.gSave:SetPoint("TOPLEFT", 0, -140)
    settings.gRemove = Wd.Button(ed, "Remove guild", 116, function()
        local name = settings.gSel
        if not name then return end
        UI:ShowConfirm("Remove guild from the org", (ns.Org:Phrase()
            and "Remove %s from the RUIN org?\n\nIts members lose the org chat and modules' sharing. The officer channel gets a new password. They still know the key phrase: choose a new key phrase if they shouldn't be able to listen in."
            or "Remove %s from the RUIN org?\n\nIts members lose the org chat and modules' sharing. The org's channels get new passwords; officers online get the new key automatically, offline guild leaders need it sent again.")
            :format(ns.Escape(name)), function()
            local ok, err = ns.Org:RemoveGuild(name)
            ns:Print(ok and ("Removed " .. name .. " from the org.") or err)
            settings.gSel = nil
            refreshSettings()
        end)
    end)
    settings.gRemove:SetPoint("LEFT", settings.gSave, "RIGHT", 6, 0)
    settings.gEditor = ed
    settings.guildCard = card
end

-- Feedback: a box to write in, and a link that opens a new GitHub issue
-- with the text filled in (addons can't reach the internet themselves).
local function buildFeedback(page)
    local FB = ns.Feedback
    local card = Wd.Card(page)
    card:SetPoint("TOPLEFT", 0, 0)
    card:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    card:SetHeight(264)
    local h = Wd.Header(card, "Send feedback")
    h:SetPoint("TOPLEFT", 10, -8)
    local hint = Wd.Label(card, GREY .. "Bugs, ideas, questions: they go to the Companion App's GitHub as an issue.|r", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", h, "RIGHT", 10, 0)
    settings.fbCat = "Bug"
    local cat = Wd.Dropdown(card, 140, FB.CATEGORIES, function() return settings.fbCat end, function(v) settings.fbCat = v end, "Type: ")
    cat:SetPoint("TOPLEFT", 10, -32)
    cat.tipTitle = "What kind of feedback this is"

    -- a multi-line box
    local box = CreateFrame("Frame", nil, card)
    box:SetPoint("TOPLEFT", 10, -62)
    box:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    box:SetHeight(124)
    Wd.Skin(box, "panel", 1, "border")
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(600)
    eb:SetHeight(110)
    eb:SetMaxLetters(FB.MAX)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eb)
    sf:EnableMouse(true)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    local ph = Wd.Label(box, GREY .. "Type your feedback here: what happened, what you expected, or your idea.|r", "GameFontHighlightSmall")
    ph:SetPoint("TOPLEFT", 10, -10)
    settings.fbCount = Wd.Label(box, "", "GameFontDisableSmall")
    settings.fbCount:SetPoint("BOTTOMRIGHT", -30, 6)
    eb:SetScript("OnTextChanged", function(self)
        local n = #(self:GetText() or "")
        ph:SetShown(n == 0)
        settings.fbCount:SetText(n .. " / " .. FB.MAX)
        if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
    end)
    settings.fbEdit = eb

    settings.fbLink = Wd.Button(card, "Copy GitHub link", 140, function()
        local text = eb:GetText() or ""
        if #ns.Trim(text) < FB.MIN then return ns:Print("Write your feedback first; the link fills it in.") end
        UI:ShowText("Open on GitHub", "Copy this link (Ctrl+C) and open it in your browser. GitHub opens a new issue with your feedback filled in; press Submit there (you need a free GitHub account).",
            FB.IssueLink(settings.fbCat, text), nil, true)
    end)
    settings.fbLink.tip = "A link that opens a new GitHub issue with your feedback filled in"
    settings.fbLink:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
    local how = Wd.Label(card, GREY .. "The game can't open web pages, so copy the link into your browser. Issues on GitHub are public: keep anything private for Discord.|r", "GameFontHighlightSmall")
    how:SetPoint("TOPLEFT", settings.fbLink, "BOTTOMLEFT", 2, -10)
    how:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    how:SetJustifyH("LEFT")
end

local function buildSettingsPanel(p)
    settings.page = p
    -- Org (key and, for the admin, the guild list), Display (chat, window and
    -- tab order) and About.
    settings.tabs = Wd.SubTabs(p, { "Org", "Options", "Feedback" }, function() refreshSettings() end)
    local orgPage, dispPage, fbPage = settings.tabs.pages[1], settings.tabs.pages[2], settings.tabs.pages[3]
    local keyCard = Wd.Card(orgPage)
    keyCard:SetPoint("TOPLEFT", 0, 0)
    keyCard:SetPoint("RIGHT", orgPage, "RIGHT", 0, 0)
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
    settings.rotate = Wd.Button(keyCard, "Choose new key", 130, function() UI:PromptNewKey() end)
    settings.rotate.tip = "Set a new key phrase members type to join, or a new random key"
    settings.links = Wd.Button(keyCard, "Community links", 140, function() UI:PromptLinks() end)
    settings.keyCard = keyCard

    -- Your guild's settings (officers change them): who can create events.
    local gs = Wd.Card(orgPage)
    gs:SetPoint("TOPLEFT", keyCard, "BOTTOMLEFT", 0, -10)
    gs:SetPoint("RIGHT", orgPage, "RIGHT", 0, 0)
    gs:SetHeight(58)
    local gsh = Wd.Header(gs, "Guild settings")
    gsh:SetPoint("TOPLEFT", 10, -8)
    settings.gsHint = Wd.Label(gs, "", "GameFontHighlightSmall")
    settings.gsHint:SetPoint("LEFT", gsh, "RIGHT", 10, 0)
    local evl = Wd.Label(gs, "Can create events (RUIN Muster): ranks 0 to", "GameFontHighlightSmall")
    evl:SetPoint("TOPLEFT", 12, -34)
    settings.eventRank = Wd.Dropdown(gs, 200, { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        function() return ns.Guild:EventRank() end, function(v)
            local ok, err = ns.Guild:SetEventRank(v)
            ns:Print(ok and ("Ranks 0 to %d of %s can now create events."):format(v, ns.guildName or "your guild") or err)
            refreshSettings()
        end)
    settings.eventRank.format = function(v) return rankLabel(ns.guildName, v) end
    settings.eventRank.tipTitle = "The lowest guild rank that can create events, rallies included (officers always can)"
    settings.eventRank:SetPoint("LEFT", evl, "RIGHT", 10, 0)
    settings.eventRankText = Wd.Label(gs, "", "GameFontHighlightSmall")
    settings.eventRankText:SetPoint("LEFT", evl, "RIGHT", 10, 0)
    settings.gsCard = gs
    buildGuildAdmin(orgPage, gs)

    local disp = Wd.Card(dispPage)
    disp:SetPoint("TOPLEFT", 0, 0)
    disp:SetPoint("RIGHT", dispPage, "RIGHT", 0, 0)
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

    -- Tab order: pick a tab, then move it left or right. Saved for you in
    -- RUIN Core; Options always stays last.
    local order = Wd.Card(dispPage)
    order:SetPoint("TOPLEFT", disp, "BOTTOMLEFT", 0, -10)
    order:SetPoint("RIGHT", dispPage, "RIGHT", 0, 0)
    order:SetHeight(64)
    local oh = Wd.Header(order, "Tab order")
    oh:SetPoint("TOPLEFT", 10, -8)
    local ohint = Wd.Label(order, GREY .. "Pick a tab, then move it.|r", "GameFontHighlightSmall")
    ohint:SetPoint("LEFT", oh, "RIGHT", 10, 0)
    settings.orderReset = Wd.Button(order, "Reset", 64, function() settings.orderPick = nil; UI:ResetTabOrder() end)
    settings.orderReset:SetPoint("TOPRIGHT", -8, -6)
    settings.orderRight = Wd.Button(order, "Move right", 92, function()
        if settings.orderPick then UI:MoveTab(settings.orderPick, 1) end
    end)
    settings.orderRight:SetPoint("RIGHT", settings.orderReset, "LEFT", -6, 0)
    settings.orderLeft = Wd.Button(order, "Move left", 92, function()
        if settings.orderPick then UI:MoveTab(settings.orderPick, -1) end
    end)
    settings.orderLeft:SetPoint("RIGHT", settings.orderRight, "LEFT", -4, 0)
    settings.orderChips = {}
    for i = 1, 12 do
        local b = Wd.Button(order, "", 80)
        b:SetHeight(22)
        b:Hide()
        settings.orderChips[i] = b
    end

    -- About, at the bottom of Options
    local about = Wd.Card(dispPage)
    about:SetPoint("TOPLEFT", order, "BOTTOMLEFT", 0, -10)
    about:SetPoint("BOTTOMRIGHT", dispPage, "BOTTOMRIGHT", 0, 0)
    local ah = Wd.Header(about, "About RUIN")
    ah:SetPoint("TOPLEFT", 10, -8)
    settings.about = Wd.Label(about, "", "GameFontHighlightSmall")
    settings.about:SetPoint("TOPLEFT", 12, -30)
    settings.about:SetPoint("RIGHT", about, "RIGHT", -12, 0)
    settings.about:SetJustifyV("TOP")
    if settings.about.SetSpacing then settings.about:SetSpacing(3) end

    buildFeedback(fbPage)

    p:SetScript("OnShow", function() UI:Refresh() end)
    settings.tabs:Select(1)
    UI:Refresh()
end

function UI:SelectSettingsTab(i) if settings.tabs then settings.tabs:Select(i) end end

local function setEnabled(button, on)
    if on then button:Enable() else button:Disable() end
end

refreshSettings = function()
    if not (settings.page and settings.page:IsVisible()) then return end
    local k = ns.Org:Get()
    local lines = {}
    if k then
        lines[#lines + 1] = ("Org: |cffffffff%s|r   key rev %d%s%s"):format(ns.Escape(k.org), k.rev,
            ns.Org:IsAdmin() and ("   " .. C.gold .. "you are the org admin|r") or "",
            k.ph and ("   key phrase: " .. C.gold .. ns.Escape(k.ph) .. "|r") or "")
    else
        lines[#lines + 1] = ns.Org:IsJoining() and (YELLOW .. "Joining with the key phrase...|r waiting for a RUIN member online to send the key.")
            or (RED .. "No org key yet.|r An officer shares it automatically, or use Import key (the key or the org's key phrase).")
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
    if k and admin then row1[#row1 + 1] = settings.export end
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
    -- your guild's settings (only with RUIN Muster installed, and in a guild)
    local muster = RUIN_API and RUIN_API.GetModule and RUIN_API:GetModule("Muster")
    local showGS = ns.guildName ~= nil and muster ~= nil
    settings.gsCard:SetShown(showGS)
    if showGS then
        local officer = ns.Org:AmOfficer()
        settings.eventRank:SetShown(officer)
        settings.eventRank:Refresh()
        settings.eventRankText:SetShown(not officer)
        settings.eventRankText:SetText(C.white .. rankLabel(ns.guildName, ns.Guild:EventRank()) .. "|r")
        settings.gsHint:SetText(GREY .. (officer and ("For %s. Officers and up can change this."):format(ns.Escape(ns.guildName))
            or ("For %s. Your guild's officers set this."):format(ns.Escape(ns.guildName))) .. "|r")
    end
    settings.guildCard:ClearAllPoints()
    settings.guildCard:SetPoint("TOPLEFT", showGS and settings.gsCard or settings.keyCard, "BOTTOMLEFT", 0, -10)
    settings.guildCard:SetPoint("BOTTOMRIGHT", settings.guildCard:GetParent(), "BOTTOMRIGHT", 0, 0)
    -- the admin's guild list
    settings.guildCard:SetShown(admin)
    if admin then
        local list = {}
        for _, name in ipairs(ns.Org:GuildNames()) do
            local g = k.guilds[name]
            list[#list + 1] = { name = name, tag = g.tag, o = tonumber(g.o) or 1 }
        end
        local found
        for _, g in ipairs(list) do if g.name == settings.gSel then found = g end end
        if not found then settings.gSel = list[1] and list[1].name; found = list[1] end
        settings.guildList:SetItems(list)
        settings.gEditor:SetShown(found ~= nil)
        if found and settings.gEdit ~= found.name then        -- fill the editor once per pick
            settings.gEdit = found.name
            settings.gName:SetText(found.name)
            settings.gTag:SetText(found.tag or "")
            settings.gRankValue = found.o
        end
        settings.gRank:Refresh()
        setEnabled(settings.gRemove, #list > 1)
    end
    for _, c in ipairs(settings.checks) do c:Refresh() end
    -- Officer chat only matters to officers.
    local officer = ns.Org:AmOfficer()
    settings.checks[2]:SetShown(officer)
    settings.checks[5]:ClearAllPoints()
    settings.checks[5]:SetPoint("TOPLEFT", officer and settings.checks[2] or settings.checks[1], "BOTTOMLEFT", 0, -2)

    -- tab order chips, in the order the tabs are now
    local movable = UI:MovableTabs()
    local prevChip
    for i, chip in ipairs(settings.orderChips) do
        local e = movable[i]
        if e then
            chip:SetText(e.label)
            chip:SetWidth(math.max(56, (chip.label:GetStringWidth() or 40) + 20))
            chip:ClearAllPoints()
            if prevChip then chip:SetPoint("LEFT", prevChip, "RIGHT", 4, 0)
            else chip:SetPoint("TOPLEFT", settings.orderLeft:GetParent(), "TOPLEFT", 10, -34) end
            chip:SetScript("OnClick", function() settings.orderPick = e.title; refreshSettings() end)
            if settings.orderPick == e.title then chip:LockHighlight() else chip:UnlockHighlight() end
            chip:Show()
            prevChip = chip
        else
            chip:Hide()
        end
    end
    local picked = false
    for _, e in ipairs(movable) do if e.title == settings.orderPick then picked = true end end
    if not picked then settings.orderPick = nil end
    setEnabled(settings.orderLeft, picked and movable[1].title ~= settings.orderPick)
    setEnabled(settings.orderRight, picked and movable[#movable].title ~= settings.orderPick)
    setEnabled(settings.orderReset, UI:HasCustomTabOrder())

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

-- Your own order (Settings > Options > Tab order) wins; Settings always stays last. Pages
-- that aren't in your saved order yet (a newly installed module) come after
-- the ones that are, in their usual order.
local function savedOrder()
    local s = ns.db and ns.db.settings
    local list = s and s.tabOrder
    return type(list) == "table" and #list > 0 and list or nil
end

local function tabOrder(t)
    local theme = themeForTab(t)
    local base = t.order or theme.order or 50
    if t.title == "Settings" then return 10000 end
    local list = savedOrder()
    if list then
        for i, title in ipairs(list) do if title == t.title then return i end end
        return 1000 + base
    end
    return base
end

local function sortedTabs()
    local sorted = {}
    for i, t in ipairs(tabs) do sorted[#sorted + 1] = { t = t, i = i } end
    table.sort(sorted, function(a, b)
        local oa, ob = tabOrder(a.t), tabOrder(b.t)
        if oa ~= ob then return oa < ob end
        return a.i < b.i
    end)
    return sorted
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
    local sorted = sortedTabs()
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
    local sorted = sortedTabs()
    local out = {}
    for _, e in ipairs(sorted) do out[#out + 1] = tabLabel(e.t) end
    return out
end

-- Tabs you can move (everything but Options), in their current order.
function UI:MovableTabs()
    local out = {}
    for _, e in ipairs(sortedTabs()) do
        if e.t.title ~= "Settings" then out[#out + 1] = { title = e.t.title, label = tabLabel(e.t) } end
    end
    return out
end

-- Move a page's tab left (-1) or right (+1); saved in RUIN_CoreDB.
function UI:MoveTab(title, delta)
    local list = UI:MovableTabs()
    local idx
    for i, e in ipairs(list) do if e.title == title then idx = i end end
    if not idx then return false end
    local to = idx + delta
    if to < 1 or to > #list then return false end
    list[idx], list[to] = list[to], list[idx]
    local order = {}
    for i, e in ipairs(list) do order[i] = e.title end
    ns.db.settings.tabOrder = order
    UI:LayoutTabs()
    UI:Refresh()
    return true
end

function UI:HasCustomTabOrder() return savedOrder() ~= nil end

function UI:ResetTabOrder()
    ns.db.settings.tabOrder = nil
    UI:LayoutTabs()
    UI:Refresh()
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
UI:AddTab("Settings", buildSettingsPanel, nil, { alias = "Options" })

for _, ev in ipairs({ "KEY_CHANGED", "PEERS_CHANGED", "ROSTER_UPDATED", "CHANNELS_CHANGED", "GUILD_CHANGED", "KEY_JOIN_CHANGED", "GUILD_SETTINGS_CHANGED" }) do
    ns:Subscribe(ev, function() UI:Refresh() end)
end
