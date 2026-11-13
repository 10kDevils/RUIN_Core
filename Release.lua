-- RUIN Core: new-version notices.
-- Each release build carries a notice (its version, date and highlights)
-- signed with the RUIN release key; the matching public key is below. When
-- RUIN sees someone running an older version, it hands them the newest notice
-- it knows (signed, so it can be passed on by anyone and faked by nobody).
-- Their RUIN tells them a new version is out on CurseForge and GitHub, and
-- passes the notice on in turn, so the news reaches players who never meet
-- anyone on the new version. Starts with 0.7.3; older RUINs don't listen.
local ADDON, ns = ...
local C = ns.Crypto

local Release = {}
ns.Release = Release

Release.PUBLIC_KEY = "794f0080d6bc62db556f446e188036acb526cd5c5c08aa3418bbe0fedeb3dbb3"
Release.WHERE = "CurseForge or GitHub"

local function message(n)
    return ("RUINR1|%s|%d|%s"):format(n.v, n.t, table.concat(n.notes or {}, "\n"))
end

-- Is n a genuine release notice?
function Release.Valid(n)
    if type(n) ~= "table" or type(n.v) ~= "string" or not n.v:find("^%d+%.%d+%.%d+$") then return false end
    if type(n.t) ~= "number" or type(n.s) ~= "string" then return false end
    n.notes = type(n.notes) == "table" and n.notes or {}
    if #n.notes > 8 then return false end
    for _, line in ipairs(n.notes) do if type(line) ~= "string" or #line > 200 then return false end end
    local sig = C.Unhex(n.s)
    return sig ~= nil and #sig == 64 and C.VerifyCached(C.Unhex(Release.PUBLIC_KEY), message(n), sig)
end

local function clean(n) return { v = n.v, t = n.t, notes = n.notes, s = n.s } end

-- The newest genuine notice this client knows (its own build's, or one it heard).
function Release.Latest()
    local best
    local own = ns.RELEASE_NOTICE
    if own and own.v == ns.VERSION and Release.Valid(own) then best = own end
    local heard = ns.db and ns.db.latestRelease
    if heard and (not best or ns.CompareVersions(heard.v, best.v) > 0) and Release.Valid(heard) then best = heard end
    return best
end

-- A newer version is out (one this client heard of)?
function Release.Newer()
    local n = Release.Latest()
    if n and ns.CompareVersions(n.v, ns.VERSION) > 0 then return n end
end

local shownThisSession = {}
local function notify(n, popup)
    if shownThisSession[n.v] then return end
    shownThisSession[n.v] = true
    ns:Print(("RUIN %s is out (you have %s). Update through %s."):format(n.v, ns.VERSION, Release.WHERE))
    ns:Fire("RELEASE_AVAILABLE", n)
    ns.db.releaseShown = type(ns.db.releaseShown) == "table" and ns.db.releaseShown or {}
    if popup and not ns.db.releaseShown[n.v] and ns.UI and ns.UI.ShowNotice then
        ns.db.releaseShown[n.v] = true
        local lines = {}
        for _, l in ipairs(n.notes or {}) do lines[#lines + 1] = "  •  " .. ns.Escape(l) end
        ns.UI:ShowNotice("RUIN " .. n.v .. " is out",
            ("A new version of RUIN is out: %s (you have %s).%s\n\nUpdate any time through %s."):format(n.v, ns.VERSION,
                #lines > 0 and ("\n\n" .. table.concat(lines, "\n")) or "", Release.WHERE))
    end
end

-- A notice arrived (or this client found one).
function Release.Take(n)
    if not Release.Valid(n) then return false end
    n = clean(n)
    local cur = ns.db.latestRelease
    if not cur or ns.CompareVersions(n.v, cur.v) > 0 then ns.db.latestRelease = n end
    if ns.CompareVersions(n.v, ns.VERSION) > 0 then notify(n, true) end
    return true
end

ns.Comms:Register("RELNOTE", function(d, sender)
    if type(d) == "table" then Release.Take(d.n) end
end)

-- Someone's hello says they run an older version: hand them the newest
-- notice. One RUIN per guild answers its guildmates (the roster sender);
-- officers and the admin answer the rest of the org. Each player once.
local told = {}
function Release.OnPeer(v, name, scope)
    if type(v) ~= "string" or type(name) ~= "string" then return end
    local n = Release.Latest()
    if not n or ns.CompareVersions(n.v, v) <= 0 then return end
    -- RUIN before 0.7.3 doesn't understand notices
    if ns.CompareVersions(v, "0.7.3") < 0 then return end
    local key = ns.NormalizeName(name) .. "|" .. n.v
    if told[key] then return end
    if scope == "GUILD" then
        if not (ns.Presence and ns.Presence:IsRosterSender()) then return end
    elseif not (ns.Org and (ns.Org:AmOfficer() or ns.Org:IsAdmin())) then
        return
    end
    told[key] = true
    C_Timer.After(2 + math.random() * 10, function()
        ns.Comms:Send("RELNOTE", { n = clean(n) }, "PEER", name, ns.Comms.PRIORITY.BULK)
    end)
end

-- On login: this build's notice becomes the newest known if it is; a newer
-- one heard before is mentioned again (the window shows once per version).
ns:Subscribe("LOGIN", function()
    C_Timer.After(15, function()
        local own = ns.RELEASE_NOTICE
        if own and own.v == ns.VERSION and Release.Valid(own) then
            local cur = ns.db.latestRelease
            if not cur or ns.CompareVersions(own.v, cur.v) >= 0 then ns.db.latestRelease = clean(own) end
        end
        local n = Release.Newer()
        if n then notify(n, true) end
    end)
end)
