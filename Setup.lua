-- RUIN Core: first-run setup for guild leaders
-- A guild leader with no org key gets a short guide a moment after logging
-- in (once; /ruin setup opens it any time). It asks one thing first: are you
-- starting an org, or joining one?
--   Starting: name the org (you become its admin), add each guild with its
--   officer rank and tag, then send the key to each guild's leader.
--   Joining: ask the org's admin to send you the key (you get an Accept
--   prompt), or type the key phrase they gave you.
-- Each step does what the /ruin key commands do, with the same checks.
local ADDON, ns = ...
local Wd = ns.Widgets
local C = Wd.COLORS

local Setup = {}
ns.Setup = Setup

local W_, H_ = 520, 360
local f            -- the window
local pages = {}
local cur

local function Org() return ns.Org end
local function say(msg) if f and f.status then f.status:SetText(msg or "") end end

local function show(name)
    for n, p in pairs(pages) do p:SetShown(n == name) end
    cur = name
    say("")
    if pages[name] and pages[name].onShow then pages[name].onShow() end
end
Setup.Page = function() return cur end

-- what each step's button does (the same checks as /ruin key); tests call these too
Setup.Actions = {
    create = function(orgName)
        local ok, err = Org():Create(ns.Trim(orgName or "") ~= "" and ns.Trim(orgName) or "RUIN")
        if ok then show("guilds") else say(C.bad .. tostring(err) .. "|r") end
        return ok, err
    end,
    addGuild = function(name, rank, tag)
        name = ns.Trim(name or "")
        local ok, err = Org():AddGuild(name, tonumber(rank) or 1, ns.Trim(tag or ""))
        if ok then say(C.good .. "Added " .. name .. ".|r"); if pages.guilds and pages.guilds.onShow then pages.guilds.onShow() end
        else say(C.bad .. tostring(err) .. "|r") end
        return ok, err
    end,
    send = function(who)
        who = ns.Trim(who or "")
        if who == "" then say(C.bad .. "Type a character name.|r"); return false, "no name" end
        local ok, err = Org():SendFullKey(who)
        if ok then say(C.good .. "Offered the key to " .. who .. ".|r") else say(C.bad .. tostring(err) .. "|r") end
        return ok, err
    end,
    join = function(phrase)
        local ok, err = Org():JoinWithPhrase(ns.Trim(phrase or ""))
        if ok then say(C.good .. "Joining: a RUIN member online will send the key.|r") else say(C.bad .. tostring(err) .. "|r") end
        return ok, err
    end,
}
Setup.Show = function(name) show(name) end
Setup.Status = function() return f and f.status and f.status:GetText() or "" end

local function page(name, title, text)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 24, -78)
    p:SetPoint("BOTTOMRIGHT", -24, 56)
    p.title = Wd.Label(p, C.gold .. title .. "|r", "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", 0, 0)
    p.text = Wd.Label(p, text or "", "GameFontHighlight")
    p.text:SetPoint("TOPLEFT", 0, -26)
    p.text:SetWidth(W_ - 48)
    p.text:SetJustifyH("LEFT")
    p.text:SetJustifyV("TOP")
    p:Hide()
    pages[name] = p
    return p
end

local function build()
    f = CreateFrame("Frame", "RUIN_Setup", UIParent)
    f:SetSize(W_, H_)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    Wd.Skin(f, "panel", 0.97, "glow")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.emblem = ns.Brand and ns.Brand.Draw(f, 34, "wide", "ARTWORK")
    if f.emblem then f.emblem:SetPoint("TOP", 0, -10) end
    f.head = Wd.Label(f, C.gold .. "Set up RUIN for your guild|r", "GameFontNormal")
    f.head:SetPoint("TOP", 0, -50)
    f.close = Wd.Button(f, "Close", 80, function() f:Hide() end)
    f.close:SetPoint("BOTTOMRIGHT", -16, 14)
    f.never = Wd.Button(f, "Don't show again", 130, function()
        if ns.db then ns.db.setupDismissed = true end
        f:Hide()
        ns:Print("Setup guide hidden. /ruin setup opens it again.")
    end)
    f.never:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
    f.status = Wd.Label(f, "", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 20, 22)
    f.status:SetPoint("RIGHT", f.never, "LEFT", -10, 0)
    f.status:SetWordWrap(false)
    if UISpecialFrames then tinsert(UISpecialFrames, "RUIN_Setup") end

    -- 1. start or join
    local p = page("choose", "Starting an org, or joining one?",
        "An org is the RUIN guilds that share chat, events and everything else. One guild leader starts it and is its admin; "
        .. "every other guild joins with the org's key.")
    local start = Wd.Button(p, "Start a new org", 200, function() show("create") end)
    start:SetPoint("TOPLEFT", 0, -96)
    local join = Wd.Button(p, "Join an org", 200, function() show("join") end)
    join:SetPoint("LEFT", start, "RIGHT", 16, 0)

    -- 2a. create
    p = page("create", "Name your org", "You'll be its admin: you add the guilds and send them the key. You can hand the admin to someone else later.")
    local name = Wd.EditBox(p, 260)
    name:SetPoint("TOPLEFT", 0, -80)
    name:SetText("RUIN")
    local go = Wd.Button(p, "Create the org", 140, function() Setup.Actions.create(name:GetText()) end)
    go:SetPoint("LEFT", name, "RIGHT", 10, 0)
    local back = Wd.Button(p, "Back", 80, function() show("choose") end)
    back:SetPoint("TOPLEFT", 0, -120)

    -- 3. add guilds
    p = page("guilds", "Add the org's guilds",
        "Each guild with the rank number of its officers (0 is the guild master, 1 the next rank down) and a short tag shown in org chat. "
        .. "Your own guild is in already.")
    local gname = Wd.EditBox(p, 180)
    gname:SetPoint("TOPLEFT", 0, -84)
    gname.tip = "The guild's name, exactly as in game."
    local grank = Wd.EditBox(p, 40)
    grank:SetPoint("LEFT", gname, "RIGHT", 8, 0)
    grank:SetText("1")
    grank.tip = "Officer rank: this rank and above are officers."
    local gtag = Wd.EditBox(p, 70)
    gtag:SetPoint("LEFT", grank, "RIGHT", 8, 0)
    gtag.tip = "A short tag for org chat (optional)."
    local add = Wd.Button(p, "Add", 70, function()
        if Setup.Actions.addGuild(gname:GetText(), grank:GetText(), gtag:GetText()) then gname:SetText(""); gtag:SetText("") end
    end)
    add:SetPoint("LEFT", gtag, "RIGHT", 8, 0)
    p.list = Wd.Label(p, "", "GameFontHighlightSmall")
    p.list:SetPoint("TOPLEFT", 0, -118)
    p.list:SetWidth(W_ - 48)
    p.list:SetJustifyH("LEFT")
    p.onShow = function()
        local names = Org():GuildNames() or {}
        pages.guilds.list:SetText(C.dim .. "In the org: |r" .. (#names > 0 and table.concat(names, ", ") or "none yet"))
    end
    local nextB = Wd.Button(p, "Next: send the key", 160, function() show("send") end)
    nextB:SetPoint("TOPLEFT", 0, -150)

    -- 4. send the key
    p = page("send", "Send the key to each guild's leader",
        "Type the guild leader's character name. They need RUIN installed and to be online; they get a prompt to accept. "
        .. "Inside each guild, officers pass the key to members as they log in.")
    local who = Wd.EditBox(p, 220)
    who:SetPoint("TOPLEFT", 0, -84)
    local send = Wd.Button(p, "Send the key", 130, function() if Setup.Actions.send(who:GetText()) then who:SetText("") end end)
    send:SetPoint("LEFT", who, "RIGHT", 10, 0)
    local done = Wd.Button(p, "Done", 100, function() show("done") end)
    done:SetPoint("TOPLEFT", 0, -124)

    -- 2b. join
    p = page("join", "Join an org",
        "Ask the org's admin, or an officer of any RUIN guild, to send you the key: you'll get a prompt to accept it. "
        .. "Or, if they gave you the key phrase, type it here and a RUIN member online sends the key.")
    local phrase = Wd.EditBox(p, 260)
    phrase:SetPoint("TOPLEFT", 0, -96)
    phrase.tip = "The org's key phrase."
    local joinB = Wd.Button(p, "Join with the phrase", 160, function() Setup.Actions.join(phrase:GetText()) end)
    joinB:SetPoint("LEFT", phrase, "RIGHT", 10, 0)
    local back2 = Wd.Button(p, "Back", 80, function() show("choose") end)
    back2:SetPoint("TOPLEFT", 0, -136)
    p.onShow = function() if Org():Get() then show("done") end end

    -- 5. done
    p = page("done", "You're set", "")
    p.onShow = function()
        local k = Org():Get()
        local lines = {}
        if k then
            lines[#lines + 1] = ("Your guild is in %s%s|r."):format(C.gold, tostring(k.org or "the org"))
            if Org():IsAdmin() then
                lines[#lines + 1] = "As the admin: Settings > Org adds and edits guilds, sets links for the org page, and makes a new key when someone leaves."
            end
            lines[#lines + 1] = "Your officers pass the key on to members as they log in. Members without RUIN still see org chat through a member who has it."
        else
            lines[#lines + 1] = "When the key arrives, accept the prompt and you're in. /ruin setup brings this guide back."
        end
        lines[#lines + 1] = "/ruin opens the RUIN window; /ruin status shows the connection."
        pages.done.text:SetText(table.concat(lines, "\n\n"))
    end
    f:Hide()
end

function Setup.Open(which)
    if not f then build() end
    show(which or (Org():Get() and "done" or "choose"))
    f:Show()
    return f
end

-- Should a guild leader see it now? (no org key, in a guild you lead, not dismissed)
function Setup.Due()
    if not ns.db or ns.db.setupDismissed or ns.db.setupShown then return false end
    if Org():Get() then return false end
    if not (IsInGuild and IsInGuild()) then return false end
    return IsGuildLeader and IsGuildLeader() and true or false
end

ns:Subscribe("LOGIN", function()
    C_Timer.After(15, function()
        if not Setup.Due() then return end
        local function open()
            if InCombatLockdown and InCombatLockdown() then return C_Timer.After(10, open) end
            ns.db.setupShown = true
            Setup.Open()
        end
        open()
    end)
end)
