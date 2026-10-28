-- RUIN Core: helpers (serializer, base64, hashing, names, versions)
-- Pure Lua 5.1 with no WoW API calls, so it can be tested outside the game.
local ADDON, ns = ...

---------------------------------------------------------------------------
-- Strings and names
---------------------------------------------------------------------------
-- Text from other players shown in the UI: "|" starts WoW escape codes, so
-- double it to show it literally.
function ns.Escape(s)
    return (tostring(s or ""):gsub("|", "||"))
end

function ns.Trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- WoW Forever names are "First Last" and APIs disagree on spaces and realm
-- suffixes, so compare names only in this normalized form (and prefer GUIDs).
function ns.NormalizeName(name)
    if type(name) ~= "string" then return "" end
    name = name:gsub("%-.*$", "")
    name = name:gsub("%s+", "")
    return name:lower()
end

function ns.ShortName(name)
    if type(name) ~= "string" then return "?" end
    return (name:gsub("%-.*$", ""))
end

-- "Ashen Order, 2, Ashen" -> "Ashen Order", 2, "Ashen"
function ns.ParseGuildSpec(text)
    local parts = {}
    for piece in (text or ""):gmatch("[^,]+") do
        parts[#parts + 1] = ns.Trim(piece)
    end
    local name = parts[1] or ""
    local rank = tonumber(parts[2]) or 1
    local tag = parts[3]
    if tag == "" then tag = nil end
    return name, rank, tag
end

---------------------------------------------------------------------------
-- Versions: "0.1.10" > "0.1.9"
---------------------------------------------------------------------------
function ns.CompareVersions(a, b)
    local function parts(v)
        local t = {}
        for num in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(num) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

---------------------------------------------------------------------------
-- Random tokens for channel names and passwords
---------------------------------------------------------------------------
local ALNUM = "abcdefghijkmnpqrstuvwxyz23456789"
function ns.RandomToken(n)
    local t = {}
    for i = 1, n do
        local r = math.random(1, #ALNUM)
        t[i] = ALNUM:sub(r, r)
    end
    return table.concat(t)
end

---------------------------------------------------------------------------
-- Hash: djb2 mod 2^32, printed as 8 hex digits (no bit library needed)
---------------------------------------------------------------------------
local HEX = "0123456789abcdef"
function ns.Hash(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 4294967296
    end
    local out = {}
    for i = 8, 1, -1 do
        local d = h % 16
        out[i] = HEX:sub(d + 1, d + 1)
        h = math.floor(h / 16)
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Serializer
-- s<len>:<bytes>  n<number>;  T F N  { key value ... }
-- Length-prefixed strings need no escaping; addon messages only forbid \0.
---------------------------------------------------------------------------
local MAX_DEPTH = 20

local function writeValue(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        out[#out + 1] = "n" .. tostring(v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            local kt, vt = type(k), type(val)
            if (kt == "string" or kt == "number") and
               (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
                writeValue(k, out)
                writeValue(val, out)
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "N"
    end
end

function ns.Serialize(v)
    local out = {}
    writeValue(v, out)
    return table.concat(out)
end

local function readValue(s, pos, depth)
    local c = s:sub(pos, pos)
    if c == "s" then
        local colon = s:find(":", pos + 1, true)
        if not colon then return nil, nil, "bad string" end
        local len = tonumber(s:sub(pos + 1, colon - 1))
        if not len or len < 0 then return nil, nil, "bad length" end
        local last = colon + len
        if last > #s then return nil, nil, "truncated string" end
        return s:sub(colon + 1, last), last + 1
    elseif c == "n" then
        local semi = s:find(";", pos + 1, true)
        if not semi then return nil, nil, "bad number" end
        local num = tonumber(s:sub(pos + 1, semi - 1))
        -- NaN and infinities never travel: NaN breaks table keys, infinity
        -- breaks every "newest wins" comparison.
        if not num or num ~= num or num == math.huge or num == -math.huge then return nil, nil, "bad number" end
        return num, semi + 1
    elseif c == "T" then
        return true, pos + 1
    elseif c == "F" then
        return false, pos + 1
    elseif c == "N" then
        return nil, pos + 1
    elseif c == "{" then
        if depth >= MAX_DEPTH then return nil, nil, "too deep" end
        local tbl = {}
        pos = pos + 1
        while true do
            if pos > #s then return nil, nil, "unterminated table" end
            if s:sub(pos, pos) == "}" then return tbl, pos + 1 end
            local k, afterKey, err = readValue(s, pos, depth + 1)
            if err then return nil, nil, err end
            local val, afterVal, err2 = readValue(s, afterKey, depth + 1)
            if err2 then return nil, nil, err2 end
            if k ~= nil then tbl[k] = val end
            pos = afterVal
        end
    end
    return nil, nil, "bad tag"
end

-- Returns value, err
function ns.Deserialize(s)
    if type(s) ~= "string" or s == "" then return nil, "empty" end
    local v, nextPos, err = readValue(s, 1, 0)
    if err then return nil, err end
    if nextPos ~= #s + 1 then return nil, "trailing data" end
    return v
end

---------------------------------------------------------------------------
-- Base64 (for copy-paste safe org keys)
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64DEC = {}
for i = 1, 64 do B64DEC[B64:byte(i)] = i - 1 end

local function b64char(n) return B64:sub(n + 1, n + 1) end

function ns.Base64Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = b64char(math.floor(n / 262144) % 64)
            .. b64char(math.floor(n / 4096) % 64)
            .. (b and b64char(math.floor(n / 64) % 64) or "=")
            .. (c and b64char(n % 64) or "=")
    end
    return table.concat(out)
end

function ns.Base64Decode(str)
    str = str:gsub("[^%w%+/=]", "")
    if #str % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #str, 4 do
        local s1, s2, s3, s4 = str:byte(i, i + 3)
        local v1, v2 = B64DEC[s1], B64DEC[s2]
        local pad3, pad4 = (s3 == 61), (s4 == 61)
        local v3 = pad3 and 0 or B64DEC[s3]
        local v4 = pad4 and 0 or B64DEC[s4]
        if not (v1 and v2 and v3 and v4) then return nil end
        local n = v1 * 262144 + v2 * 4096 + v3 * 64 + v4
        local a = math.floor(n / 65536) % 256
        local b = math.floor(n / 256) % 256
        local c = n % 256
        if pad3 then
            out[#out + 1] = string.char(a)
        elseif pad4 then
            out[#out + 1] = string.char(a, b)
        else
            out[#out + 1] = string.char(a, b, c)
        end
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------
function ns.DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = ns.DeepCopy(val) end
    return t
end

function ns.Now()
    return (GetServerTime and GetServerTime()) or time()
end

---------------------------------------------------------------------------
-- Text from other players
-- Everything RUIN receives is cleaned once, where it arrives (Comms, pasted
-- keys and export strings): game links (items, spells, quests...) stay
-- clickable, every other "|" escape code (colors, textures, fake links) is
-- turned into a plain "/", and line breaks become spaces, so nobody can
-- dress their text up as a system message or a link it isn't.
---------------------------------------------------------------------------
local LINK_TYPES = { item = true, spell = true, enchant = true, quest = true, achievement = true, currency = true,
                     trade = true, talent = true, battlepet = true, mount = true, transmogillusion = true,
                     instancelock = true, journal = true, keystone = true }

function ns.SafeText(s)
    if type(s) ~= "string" or not s:find("[|\r\n\001\002]") then return s end
    s = s:gsub("[\001\002]", "")
    local kept = {}
    local function keep(all, kind)
        if not LINK_TYPES[kind] then return nil end
        kept[#kept + 1] = all
        return "\001" .. #kept .. "\002"
    end
    s = s:gsub("(|c%x%x%x%x%x%x%x%x|H(%a+):[^|]*|h%[[^|%]]*%]|h|r)", keep)
    s = s:gsub("(|cn[%w_]+:|H(%a+):[^|]*|h%[[^|%]]*%]|h|r)", keep)
    s = s:gsub("(|H(%a+):[^|]*|h%[[^|%]]*%]|h)", keep)
    s = s:gsub("|", "/"):gsub("[\r\n]", " ")
    s = s:gsub("\001(%d+)\002", function(i) return kept[tonumber(i)] or "" end)
    return s
end

-- A received table with every string (keys too) passed through SafeText.
function ns.SanitizeTree(v, depth)
    local t = type(v)
    if t == "string" then return ns.SafeText(v) end
    if t ~= "table" then return v end
    depth = depth or 0
    if depth > 24 then return nil end
    local out = {}
    for k, val in pairs(v) do
        local ck = type(k) == "string" and ns.SafeText(k) or k
        out[ck] = ns.SanitizeTree(val, depth + 1)
    end
    return out
end

-- A timestamp from another player, or nil when it isn't one. A time more
-- than a few minutes in the future would win every "newest wins" comparison
-- forever, so it is refused.
ns.CLOCK_SLACK = 300
function ns.SaneTime(t)
    t = tonumber(t)
    if not t or t ~= t or t < 0 or t > ns.Now() + ns.CLOCK_SLACK then return nil end
    return t
end
