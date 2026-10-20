-- RUIN Core: public API for suite modules
--
-- A module (RUIN_Codex, RUIN_Muster, ...) declares
--   ## Dependencies: RUIN_Core
-- and then:
--
--   local M = RUIN_API:RegisterModule("Codex", { version = "0.1.0" })
--   function M:OnEnable()
--       self:Listen("DROP", "OnDrop")                -- handler by method name
--       self:AddTab("Codex", function(panel) ... end)
--   end
--   function M:OnDrop(data, sender, scope) ... end
--   M:Send("DROP", { item = 12345 }, "ORG")
--
-- Scopes: "GUILD", "ORG", "OFFICERS", "PEER" (pass a character name as target).
-- Message kinds are namespaced automatically ("Codex:DROP").
local ADDON, ns = ...

local API = {}
RUIN_API = API
API.version = ns.VERSION
API.protocol = ns.PROTOCOL
API.apiLevel = 6              -- modules check this to know which API they can use
API.PRIORITY = ns.Comms.PRIORITY
API.Widgets = ns.Widgets      -- shared widget kit (Button, Check, EditBox, Cycle, List, SubTabs, HudFrame, Toast,
                              -- from level 4 Pill, TagText, Progress, Skin, PALETTE, MARKERS, and from
                              -- level 6 page colors (SchemeOf), MarkChoice, Popover and EditBox placeholders)
API.client = ns.CLIENT        -- "forever" or "retail" (level 4)
API.Map = ns.Map              -- positions, distances, and pins on the world map and minimap (level 3)

local modules, ordered = {}, {}

local Module = {}
Module.__index = Module

function Module:Send(kind, data, scope, target, priority)
    return ns.Comms:Send(self.name .. ":" .. kind, data, scope, target, priority)
end

function Module:Listen(kind, handler)
    local mod = self
    ns.Comms:Register(self.name .. ":" .. kind, function(data, sender, scope)
        local fn = type(handler) == "string" and mod[handler] or handler
        if fn then fn(mod, data, sender, scope) end
    end)
end

-- Listen for a message kind under its full name, e.g. "Intel:SPOT" (level 5).
-- Lets a module keep understanding messages from a retired addon's old versions.
function Module:ListenRaw(fullKind, handler)
    local mod = self
    ns.Comms:Register(fullKind, function(data, sender, scope)
        local fn = type(handler) == "string" and mod[handler] or handler
        if fn then fn(mod, data, sender, scope) end
    end)
end

-- opts (level 4): { order = n, label = "Tab text" }; by default the tab's
-- label and place come from the module's theme.
function Module:AddTab(title, builder, opts)
    self.tabTitle = title
    return ns.UI:AddTab(title, builder, self, opts)
end

-- Open the RUIN window on this module's page.
function Module:OpenTab()
    return ns.UI:OpenTab(self.tabTitle or self.name)
end

-- Module events, for other modules to react to (level 3). Another module
-- listens with RUIN_API:Subscribe("Muster:SPOT", fn); nothing is sent over
-- the network, so modules work alone and integrate when both are installed.
function Module:Publish(event, ...)
    ns:Fire(self.name .. ":" .. event, ...)
end

-- The module's name in its page color, for chat lines and alerts.
local function tag(mod)
    if not mod.tagText then
        local t = ns.ThemeFor and ns.ThemeFor(mod.name, mod)
        local c = t and t.color or { 0.67, 0.67, 0.67 }
        -- lift dark colors a little so they stay readable on chat backgrounds
        local r, g, b = math.min(1, c[1] + 0.15), math.min(1, c[2] + 0.15), math.min(1, c[3] + 0.15)
        mod.tagText = ("|cff%02x%02x%02x%s:|r "):format(r * 255, g * 255, b * 255, (t and t.tab) or mod.name)
    end
    return mod.tagText
end

function Module:Print(msg)
    ns:Print(tag(self) .. tostring(msg))
end

function Module:Toast(msg, opts)
    ns.Widgets.Toast(tag(self) .. tostring(msg), opts)
end

-- Core callbacks (KEY_CHANGED, PEERS_CHANGED, ...)
function Module:On(eventName, fn)
    ns:Subscribe(eventName, fn)
end

-- Game events, with errors reported instead of breaking other handlers.
function Module:RegisterEvent(event, fn)
    local mod = self
    ns:RegisterEvent(event, function(_, ...) fn(mod, ...) end)
end

local function enable(m)
    if m.enabled then return end
    m.enabled = true
    if m.OnEnable then
        local ok, err = pcall(m.OnEnable, m)
        if not ok then ns.ReportError(err) end
    end
end

function API:RegisterModule(name, info)
    assert(type(name) == "string" and name:match("^%w+$"), "RUIN module names must be letters and digits")
    if modules[name] then return modules[name] end
    local m = setmetatable({ name = name, info = info or {} }, Module)
    modules[name] = m
    ordered[#ordered + 1] = m
    -- OnEnable is usually defined right after this call returns, so defer.
    if ns.loggedIn then C_Timer.After(0, function() enable(m) end) end
    return m
end

ns:Subscribe("LOGIN", function()
    for _, m in ipairs(ordered) do enable(m) end
end)

---------------------------------------------------------------------------
-- Read-only views for modules
---------------------------------------------------------------------------
-- Another installed module, or nil. Lets modules integrate when both are
-- present (e.g. Muster offering open slots to Finder) without depending on each other.
function API:GetModule(name) return modules[name] end

function API:GetModules()
    local list = {}
    for _, m in ipairs(ordered) do
        list[#list + 1] = { name = m.name, version = m.info.version, enabled = m.enabled }
    end
    return list
end

-- Org summary without channel passwords.
function API:GetOrg()
    local k = ns.Org:Get()
    if not k then return nil end
    local guilds = {}
    for name, g in pairs(k.guilds) do
        guilds[#guilds + 1] = { name = name, tag = g.tag, officerRank = g.o }
    end
    table.sort(guilds, function(a, b) return a.name < b.name end)
    return { name = k.org, rev = k.rev, guilds = guilds, myGuild = ns.guildName,
             inOrg = ns.Org:MyGuildInOrg(), isOfficer = ns.Org:AmOfficer(), isAdmin = ns.Org:IsAdmin() }
end

function API:IsOfficer() return ns.Org:AmOfficer() end

-- RUIN's own dialogs (level 3), so modules don't need Blizzard popups.
-- ShowText: a box to copy from or paste into; onAccept(text) runs on OK.
function API:ShowText(title, hint, text, onAccept, selectAll) ns.UI:ShowText(title, hint, text, onAccept, selectAll) end
function API:Confirm(title, text, onAccept) ns.UI:ShowConfirm(title, text, onAccept) end
function API:Toast(msg, opts) ns.Widgets.Toast(msg, opts) end
function API:OpenTab(which) return ns.UI:OpenTab(which) end

function API:GetPlayer()
    local _, classFile = UnitClass("player")
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return { guid = ns.playerGUID, name = ns.playerName, guild = ns.guildName,
             class = classFile, level = UnitLevel("player"), faction = faction }
end
function API:IsConnected() return ns.Comms:IsJoined("ORG") end
-- "forever" or "retail" (level 4). Data written for one game checks this.
function API:GetClient() return ns.CLIENT, ns.CLIENT_NAME end
-- The org's community links, { { label, url }, ... } (level 4).
function API:GetLinks() return ns.Org:GetLinks() end
-- Overlord Forever runs RUIN's world PvP (level 4): is it installed, and open it.
function API:HasOverlord() return ns.UI:FindOverlord() ~= nil end
function API:OpenOverlord() return ns.UI:OpenOverlord() end
API.appName = "RUIN Gaming Companion App"
function API:GetOnlineMembers() return ns.Presence:GetOnlineList() end
function API:GetPlayerGUID() return ns.playerGUID end

-- Events: "KEY_CHANGED", "PEERS_CHANGED", "ROSTER_UPDATED", "GUILD_CHANGED", "CHANNELS_CHANGED"
function API:Subscribe(eventName, fn) ns:Subscribe(eventName, fn) end

-- Module events (see Module:Publish), e.g. "Muster:SPOT" or "Muster:EVENTS".
function API:Publish(eventName, ...) ns:Fire(eventName, ...) end

---------------------------------------------------------------------------
-- Export strings (level 3): copy-paste safe text for sharing a route, a
-- best-in-slot list and so on.  RUIN_API.Util.Encode("ROUTE", tbl) gives
-- "RUIN-ROUTE1:...", and Decode("ROUTE", text) returns the table or nil, err.
---------------------------------------------------------------------------
API.Util = {}

function API.Util.Encode(kind, value)
    local body = ns.Base64Encode(ns.Serialize(value))
    return ("RUIN-%s1:%s.%s"):format(kind, body, ns.Hash(body))
end

function API.Util.Decode(kind, text)
    if type(text) ~= "string" then return nil, "empty" end
    local body, hash = text:gsub("%s", ""):match("^RUIN%-" .. kind .. "1:([%w%+/=]+)%.(%x+)$")
    if not body then return nil, "not a RUIN " .. kind:lower() .. " string" end
    if ns.Hash(body) ~= hash then return nil, "the string is damaged or incomplete" end
    local raw = ns.Base64Decode(body)
    if not raw then return nil, "the string is damaged" end
    return ns.Deserialize(raw)
end

API.Util.DeepCopy = ns.DeepCopy
API.Util.Trim = ns.Trim
API.Util.ShortName = ns.ShortName
