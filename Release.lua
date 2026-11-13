-- RUIN Core: new-version prompts.
-- Every hello says which RUIN its sender runs. When RUIN hears of a newer
-- version than this one, it says so in chat and, once per version, in a
-- window: a new version is out, update through CurseForge or GitHub.
local ADDON, ns = ...

local Release = {}
ns.Release = Release
Release.WHERE = "CurseForge or GitHub"

local function sane(v)
    if type(v) ~= "string" or not v:find("^%d+%.%d+%.%d+$") then return false end
    -- a version far beyond this one is someone's typo or a joke, not a release
    local major = tonumber(v:match("^(%d+)"))
    local mine = tonumber(ns.VERSION:match("^(%d+)")) or 0
    return major <= mine + 1
end

-- The newest version this client has heard of, if newer than its own.
function Release.Newer()
    local v = ns.db and ns.db.newestSeen
    if type(v) == "string" and ns.CompareVersions(v, ns.VERSION) > 0 then return v end
end

local shownThisSession = {}
local function prompt(v, from)
    if shownThisSession[v] then return end
    shownThisSession[v] = true
    ns:Print(("RUIN %s is out (you have %s). Update through %s."):format(v, ns.VERSION, Release.WHERE))
    ns:Fire("RELEASE_AVAILABLE", v)
    ns.db.releaseShown = type(ns.db.releaseShown) == "table" and ns.db.releaseShown or {}
    if not ns.db.releaseShown[v] and ns.UI and ns.UI.ShowNotice then
        ns.db.releaseShown[v] = true
        ns.UI:ShowNotice("RUIN " .. v .. " is out",
            ("A new version of RUIN is out: %s (you have %s).\n\nUpdate any time through %s."):format(v, ns.VERSION, Release.WHERE))
    end
end

-- A hello (or any message) says someone runs version v.
function Release.Heard(v, from)
    if not sane(v) or ns.CompareVersions(v, ns.VERSION) <= 0 then return end
    local cur = ns.db.newestSeen
    if type(cur) ~= "string" or ns.CompareVersions(v, cur) > 0 then ns.db.newestSeen = v end
    prompt(v, from)
end

-- On login, a newer version heard of before is mentioned again in chat
-- (the window shows once per version).
ns:Subscribe("LOGIN", function()
    C_Timer.After(15, function()
        local v = Release.Newer()
        if v then prompt(v) end
    end)
end)
