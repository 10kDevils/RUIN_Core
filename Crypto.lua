-- RUIN Core: cryptography
-- SHA-256, HMAC-SHA256, the ChaCha20 stream cipher, a random pool fed by the
-- game, and Ed25519-style signatures (the Ed25519 curve and equations; the
-- hash is SHA-256 based, see H64 below, so RUIN signatures are RUIN's own).
-- Pure Lua 5.1: XOR and AND use the game's bit library, shifts and rotations
-- are done with exact arithmetic, so it runs the same everywhere.
local ADDON, ns = ...

local Crypto = {}
ns.Crypto = Crypto

local floor = math.floor
local byte, char, concat = string.byte, string.char, table.concat
local TWO32 = 4294967296

---------------------------------------------------------------------------
-- 32-bit words
---------------------------------------------------------------------------
local bxor, band, bnot
do
    local b = rawget(_G, "bit") or rawget(_G, "bit32")
    if b and b.bxor then
        local x, a, n = b.bxor, b.band, b.bnot
        bxor = function(p, q) return x(p, q) % TWO32 end
        band = function(p, q) return a(p, q) % TWO32 end
        bnot = function(p) return n(p) % TWO32 end
    else
        -- Lua 5.3+ (the test runner): native operators, compiled at run time
        -- so a Lua 5.1 parser never sees them
        local f = (loadstring or load)([[return function(p, q) return (math.floor(p) ~ math.floor(q)) & 0xFFFFFFFF end,
                                function(p, q) return (math.floor(p) & math.floor(q)) & 0xFFFFFFFF end,
                                function(p) return (~math.floor(p)) & 0xFFFFFFFF end]])
        if f then
            bxor, band, bnot = f()
        else
            -- plain Lua 5.1 with no bit library: byte tables
            local X, A = {}, {}
            for p = 0, 255 do
                for q = 0, 255 do
                    local x, a, bitv, pp, qq = 0, 0, 1, p, q
                    for _ = 1, 8 do
                        local pb, qb = pp % 2, qq % 2
                        if pb ~= qb then x = x + bitv end
                        if pb == 1 and qb == 1 then a = a + bitv end
                        pp, qq, bitv = (pp - pb) / 2, (qq - qb) / 2, bitv * 2
                    end
                    X[p * 256 + q], A[p * 256 + q] = x, a
                end
            end
            local function op(T, p, q)
                local r, m = 0, 1
                for _ = 1, 4 do
                    local pb, qb = p % 256, q % 256
                    r = r + T[pb * 256 + qb] * m
                    p, q, m = (p - pb) / 256, (q - qb) / 256, m * 256
                end
                return r
            end
            bxor = function(p, q) return op(X, p % TWO32, q % TWO32) end
            band = function(p, q) return op(A, p % TWO32, q % TWO32) end
            bnot = function(p) return TWO32 - 1 - p % TWO32 end
        end
    end
end

local function rotr(x, n) return floor(x / 2 ^ n) + (x % 2 ^ n) * 2 ^ (32 - n) end
local function rotl(x, n) return rotr(x, 32 - n) end
local function shr(x, n) return floor(x / 2 ^ n) end

local function be32(s, i)
    local a, b, c, d = byte(s, i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end
local function le32(s, i)
    local a, b, c, d = byte(s, i, i + 3)
    return ((d * 256 + c) * 256 + b) * 256 + a
end
local function wbe(x)
    return char(floor(x / 16777216) % 256, floor(x / 65536) % 256, floor(x / 256) % 256, x % 256)
end
local function wle(x)
    return char(x % 256, floor(x / 256) % 256, floor(x / 65536) % 256, floor(x / 16777216) % 256)
end

---------------------------------------------------------------------------
-- SHA-256
---------------------------------------------------------------------------
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local W = {}
local function compress(H, s, off)
    for i = 0, 15 do W[i] = be32(s, off + i * 4) end
    for i = 16, 63 do
        local w15, w2 = W[i - 15], W[i - 2]
        local s0 = bxor(bxor(rotr(w15, 7), rotr(w15, 18)), shr(w15, 3))
        local s1 = bxor(bxor(rotr(w2, 17), rotr(w2, 19)), shr(w2, 10))
        W[i] = (W[i - 16] + s0 + W[i - 7] + s1) % TWO32
    end
    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for i = 0, 63 do
        local S1 = bxor(bxor(rotr(e, 6), rotr(e, 11)), rotr(e, 25))
        local ch = bxor(band(e, f), band(bnot(e), g))
        local t1 = (h + S1 + ch + K[i + 1] + W[i]) % TWO32
        local S0 = bxor(bxor(rotr(a, 2), rotr(a, 13)), rotr(a, 22))
        local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
        local t2 = (S0 + maj) % TWO32
        h, g, f, e, d, c, b, a = g, f, e, (d + t1) % TWO32, c, b, a, (t1 + t2) % TWO32
    end
    H[1] = (H[1] + a) % TWO32; H[2] = (H[2] + b) % TWO32; H[3] = (H[3] + c) % TWO32; H[4] = (H[4] + d) % TWO32
    H[5] = (H[5] + e) % TWO32; H[6] = (H[6] + f) % TWO32; H[7] = (H[7] + g) % TWO32; H[8] = (H[8] + h) % TWO32
end

-- 32-byte binary digest
function Crypto.SHA256(msg)
    msg = tostring(msg or "")
    local len = #msg
    local pad = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
    local bits = len * 8
    pad = pad .. wbe(floor(bits / TWO32)) .. wbe(bits % TWO32)
    local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
    for off = 1, #pad, 64 do compress(H, pad, off) end
    local out = {}
    for i = 1, 8 do out[i] = wbe(H[i]) end
    return concat(out)
end

local HEXD = "0123456789abcdef"
function Crypto.Hex(s)
    return (s:gsub(".", function(c)
        local v = byte(c)
        local hi, lo = floor(v / 16), v % 16
        return HEXD:sub(hi + 1, hi + 1) .. HEXD:sub(lo + 1, lo + 1)
    end))
end
function Crypto.Unhex(h)
    if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^%x]") then return nil end
    return (h:gsub("%x%x", function(p) return char(tonumber(p, 16)) end))
end

function Crypto.SHA256Hex(msg) return Crypto.Hex(Crypto.SHA256(msg)) end

local function xorPad(key, v)
    local out = {}
    for i = 1, 64 do out[i] = char(bxor(byte(key, i) or 0, v)) end
    return concat(out)
end
function Crypto.HMAC(key, msg)
    if #key > 64 then key = Crypto.SHA256(key) end
    return Crypto.SHA256(xorPad(key, 0x5c) .. Crypto.SHA256(xorPad(key, 0x36) .. msg))
end

-- Constant-time-ish comparison (no early exit).
function Crypto.Equal(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
    local diff = 0
    for i = 1, #a do if byte(a, i) ~= byte(b, i) then diff = diff + 1 end end
    return diff == 0
end

---------------------------------------------------------------------------
-- ChaCha20 (RFC 8439): key 32 bytes, nonce 12 bytes
---------------------------------------------------------------------------
local function qr(x, a, b, c, d)
    x[a] = (x[a] + x[b]) % TWO32; x[d] = rotl(bxor(x[d], x[a]), 16)
    x[c] = (x[c] + x[d]) % TWO32; x[b] = rotl(bxor(x[b], x[c]), 12)
    x[a] = (x[a] + x[b]) % TWO32; x[d] = rotl(bxor(x[d], x[a]), 8)
    x[c] = (x[c] + x[d]) % TWO32; x[b] = rotl(bxor(x[b], x[c]), 7)
end

local function chachaBlock(key, counter, nonce)
    local st = { 0x61707865, 0x3320646e, 0x79622d32, 0x6b206574 }
    for i = 0, 7 do st[5 + i] = le32(key, 1 + i * 4) end
    st[13] = counter
    for i = 0, 2 do st[14 + i] = le32(nonce, 1 + i * 4) end
    local x = {}
    for i = 1, 16 do x[i] = st[i] end
    for _ = 1, 10 do
        qr(x, 1, 5, 9, 13); qr(x, 2, 6, 10, 14); qr(x, 3, 7, 11, 15); qr(x, 4, 8, 12, 16)
        qr(x, 1, 6, 11, 16); qr(x, 2, 7, 12, 13); qr(x, 3, 8, 9, 14); qr(x, 4, 5, 10, 15)
    end
    local out = {}
    for i = 1, 16 do out[i] = (x[i] + st[i]) % TWO32 end
    return out
end

function Crypto.ChaCha20(key, nonce, data, counter)
    counter = counter or 1
    local out, n = {}, 0
    for off = 1, #data, 64 do
        local ks = chachaBlock(key, counter, nonce)
        counter = counter + 1
        for i = 0, 15 do
            local w = ks[i + 1]
            for j = 0, 3 do
                local p = off + i * 4 + j
                if p > #data then break end
                n = n + 1
                out[n] = char(bxor(byte(data, p), floor(w / 2 ^ (8 * j)) % 256))
            end
        end
    end
    return concat(out)
end

---------------------------------------------------------------------------
-- Random bytes: a SHA-256 pool stirred with everything the game offers
-- (timers to the microsecond, the clock, GUIDs, the frame rate, addon
-- message timings) and math.random. Never used before it's been stirred.
---------------------------------------------------------------------------
local pool, poolCount = Crypto.SHA256("RUIN pool " .. tostring({}) .. tostring(math.random())), 0
function Crypto.Stir(...)
    local parts = { pool, tostring(poolCount) }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local dp = rawget(_G, "debugprofilestop")
    if dp then parts[#parts + 1] = tostring(dp()) end
    parts[#parts + 1] = tostring(os and os.clock and os.clock() or 0)
    parts[#parts + 1] = tostring(time and time() or 0)
    parts[#parts + 1] = tostring(math.random(0, 2147483646))
    poolCount = poolCount + 1
    pool = Crypto.SHA256(concat(parts, "|"))
end

function Crypto.Random(n)
    local GT, GG = rawget(_G, "GetTime"), rawget(_G, "UnitGUID")
    local fr = rawget(_G, "GetFramerate")
    Crypto.Stir(GT and GT(), GG and GG("player"), fr and fr(), tostring({}))
    local out, have = {}, 0
    while have < n do
        poolCount = poolCount + 1
        local block = Crypto.HMAC(pool, "out" .. poolCount)
        out[#out + 1] = block
        have = have + #block
    end
    Crypto.Stir("after", n)
    return concat(out):sub(1, n)
end

local ALNUM = "abcdefghijkmnpqrstuvwxyz23456789"
-- A random token in RUIN's channel alphabet (32 symbols, 5 bits each).
function Crypto.Token(n)
    local raw, t = Crypto.Random(n), {}
    for i = 1, n do
        local v = byte(raw, i) % 32
        t[i] = ALNUM:sub(v + 1, v + 1)
    end
    return concat(t)
end

---------------------------------------------------------------------------
-- Sealed messages: ChaCha20 + HMAC-SHA256 (encrypt, then authenticate the
-- nonce, ciphertext and `ad`: who sent it, to whom). Returns the sealed
-- binary string, or nil.
---------------------------------------------------------------------------
local TAG = 12
local function subkeys(key)
    return Crypto.HMAC(key, "RUIN enc"), Crypto.HMAC(key, "RUIN mac")
end
local cache = {}
local function keys(key)
    local c = cache[key]
    if not c then
        local e, m = subkeys(key)
        c = { e, m }
        cache[key] = c
    end
    return c[1], c[2]
end

function Crypto.Seal(key, plain, ad)
    local ek, mk = keys(key)
    local nonce = Crypto.Random(12)
    local ct = Crypto.ChaCha20(ek, nonce, plain)
    local tag = Crypto.HMAC(mk, (ad or "") .. "\0" .. nonce .. ct):sub(1, TAG)
    return nonce .. ct .. tag
end

function Crypto.Open(key, sealed, ad)
    if type(sealed) ~= "string" or #sealed < 12 + TAG then return nil end
    local ek, mk = keys(key)
    local nonce, ct, tag = sealed:sub(1, 12), sealed:sub(13, -TAG - 1), sealed:sub(-TAG)
    local want = Crypto.HMAC(mk, (ad or "") .. "\0" .. nonce .. ct):sub(1, TAG)
    if not Crypto.Equal(want, tag) then return nil end
    return Crypto.ChaCha20(ek, nonce, ct)
end

-- Addon messages may carry any byte but \0: \1 escapes \0 and itself.
function Crypto.EncodeNul(s)
    return (s:gsub("[%z\1]", function(c) return c == "\0" and "\1\2" or "\1\3" end))
end
function Crypto.DecodeNul(s)
    if s:find("\1[^\2\3]") or s:sub(-1) == "\1" then return nil end
    return (s:gsub("\1([\2\3])", function(c) return c == "\2" and "\0" or "\1" end))
end

---------------------------------------------------------------------------
-- Signatures on the Ed25519 curve (after TweetNaCl). Field elements are 16
-- limbs of 16 bits in doubles; every intermediate stays below 2^53.
-- H64(x) = SHA256(0x00 .. x) .. SHA256(0x01 .. x) stands in for SHA-512.
---------------------------------------------------------------------------
local function H64(m) return Crypto.SHA256("\0" .. m) .. Crypto.SHA256("\1" .. m) end

local function gf(init)
    local r = {}
    for i = 0, 15 do r[i] = (init and init[i + 1]) or 0 end
    return r
end
local gf0, gf1 = gf(), gf({ 1 })
local D2 = gf({ 0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0, 0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406 })
local Dc = gf({ 0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070, 0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203 })
local X = gf({ 0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c, 0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169 })
local Y = gf({ 0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666 })
local I = gf({ 0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43, 0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83 })

local function set25519(r, a) for i = 0, 15 do r[i] = a[i] end end
local function car25519(o)
    for i = 0, 15 do
        o[i] = o[i] + 65536
        local c = floor(o[i] / 65536)
        if i < 15 then o[i + 1] = o[i + 1] + c - 1 else o[0] = o[0] + 38 * (c - 1) end
        o[i] = o[i] - c * 65536
    end
end
local function sel25519(p, q, b)
    if b == 1 then
        for i = 0, 15 do p[i], q[i] = q[i], p[i] end
    end
end
local function pack25519(o, n)
    local m, t = gf(), gf()
    for i = 0, 15 do t[i] = n[i] end
    car25519(t); car25519(t); car25519(t)
    for _ = 1, 2 do
        m[0] = t[0] - 0xffed
        for i = 1, 14 do
            m[i] = t[i] - 0xffff - (floor(m[i - 1] / 65536) % 2)
            m[i - 1] = m[i - 1] % 65536
        end
        m[15] = t[15] - 0x7fff - (floor(m[14] / 65536) % 2)
        local b = floor(m[15] / 65536) % 2
        m[14] = m[14] % 65536
        sel25519(t, m, 1 - b)
    end
    for i = 0, 15 do
        o[2 * i] = t[i] % 256
        o[2 * i + 1] = floor(t[i] / 256) % 256
    end
end
local function neq25519(a, b)
    local c, d = {}, {}
    pack25519(c, a); pack25519(d, b)
    for i = 0, 31 do if c[i] ~= d[i] then return true end end
    return false
end
local function par25519(a)
    local d = {}
    pack25519(d, a)
    return d[0] % 2
end
local function unpack25519(o, n)
    for i = 0, 15 do o[i] = n[2 * i] + n[2 * i + 1] * 256 end
    o[15] = o[15] % 32768
end
local function A(o, a, b) for i = 0, 15 do o[i] = a[i] + b[i] end end
local function Z(o, a, b) for i = 0, 15 do o[i] = a[i] - b[i] end end
local function M(o, a, b)
    local t = {}
    for i = 0, 30 do t[i] = 0 end
    for i = 0, 15 do
        local ai = a[i]
        for j = 0, 15 do t[i + j] = t[i + j] + ai * b[j] end
    end
    for i = 0, 14 do t[i] = t[i] + 38 * t[i + 16] end
    for i = 0, 15 do o[i] = t[i] end
    car25519(o); car25519(o)
end
local function S(o, a) M(o, a, a) end
local function inv25519(o, i)
    local c = gf()
    set25519(c, i)
    for a = 253, 0, -1 do
        S(c, c)
        if a ~= 2 and a ~= 4 then M(c, c, i) end
    end
    set25519(o, c)
end
local function pow2523(o, i)
    local c = gf()
    set25519(c, i)
    for a = 250, 0, -1 do
        S(c, c)
        if a ~= 1 then M(c, c, i) end
    end
    set25519(o, c)
end

local function add(p, q)
    local a, b, c, d, t, e, f, g, h = gf(), gf(), gf(), gf(), gf(), gf(), gf(), gf(), gf()
    Z(a, p[1], p[0]); Z(t, q[1], q[0]); M(a, a, t)
    A(b, p[0], p[1]); A(t, q[0], q[1]); M(b, b, t)
    M(c, p[3], q[3]); M(c, c, D2)
    M(d, p[2], q[2]); A(d, d, d)
    Z(e, b, a); Z(f, d, c); A(g, d, c); A(h, b, a)
    M(p[0], e, f); M(p[1], h, g); M(p[2], g, f); M(p[3], e, h)
end
local function cswap(p, q, b)
    for i = 0, 3 do sel25519(p[i], q[i], b) end
end
local function pack(r, p)
    local tx, ty, zi = gf(), gf(), gf()
    inv25519(zi, p[2])
    M(tx, p[0], zi); M(ty, p[1], zi)
    pack25519(r, ty)
    r[31] = r[31] + 128 * par25519(tx)
end
local function scalarmult(p, q, s)
    set25519(p[0], gf0); set25519(p[1], gf1); set25519(p[2], gf1); set25519(p[3], gf0)
    for i = 255, 0, -1 do
        local b = floor(s[floor(i / 8)] / 2 ^ (i % 8)) % 2
        cswap(p, q, b)
        add(q, p)
        add(p, p)
        cswap(p, q, b)
    end
end
local function newPoint() return { [0] = gf(), gf(), gf(), gf() } end
local function scalarbase(p, s)
    local q = newPoint()
    set25519(q[0], X); set25519(q[1], Y); set25519(q[2], gf1); M(q[3], X, Y)
    scalarmult(p, q, s)
end

local L = { [0] = 0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10 }

local function modL(r, x)
    for i = 63, 32, -1 do
        local carry = 0
        local j = i - 32
        while j < i - 12 do
            x[j] = x[j] + carry - 16 * x[i] * L[j - (i - 32)]
            carry = floor((x[j] + 128) / 256)
            x[j] = x[j] - carry * 256
            j = j + 1
        end
        x[j] = x[j] + carry
        x[i] = 0
    end
    local carry = 0
    for j = 0, 31 do
        x[j] = x[j] + carry - floor(x[31] / 16) * L[j]
        carry = floor(x[j] / 256)
        x[j] = x[j] % 256
    end
    for j = 0, 31 do x[j] = x[j] - carry * L[j] end
    for i = 0, 31 do
        x[i + 1] = (x[i + 1] or 0) + floor(x[i] / 256)
        r[i] = x[i] % 256
    end
end
local function reduce(r)
    local x = {}
    for i = 0, 63 do x[i] = r[i] end
    for i = 0, 63 do r[i] = 0 end
    modL(r, x)
end

local function toArr(s, n)
    local t = {}
    for i = 0, (n or #s) - 1 do t[i] = byte(s, i + 1) or 0 end
    return t
end
local function toStr(t, n)
    local out = {}
    for i = 0, n - 1 do out[i + 1] = char(t[i]) end
    return concat(out)
end

local function unpackneg(r, p)
    local t, chk, num, den, den2, den4, den6 = gf(), gf(), gf(), gf(), gf(), gf(), gf()
    set25519(r[2], gf1)
    unpack25519(r[1], p)
    S(num, r[1]); M(den, num, Dc)
    Z(num, num, r[2]); A(den, r[2], den)
    S(den2, den); S(den4, den2); M(den6, den4, den2)
    M(t, den6, num); M(t, t, den)
    pow2523(t, t)
    M(t, t, num); M(t, t, den); M(t, t, den); M(r[0], t, den)
    S(chk, r[0]); M(chk, chk, den)
    if neq25519(chk, num) then M(r[0], r[0], I) end
    S(chk, r[0]); M(chk, chk, den)
    if neq25519(chk, num) then return false end
    if par25519(r[0]) == floor(p[31] / 128) then Z(r[0], gf0, r[0]) end
    M(r[3], r[0], r[1])
    return true
end

-- seed: 32 random bytes (the secret). Returns the 32-byte public key.
function Crypto.SignKeyPair(seed)
    local d = toArr(H64(seed), 64)
    d[0] = d[0] - d[0] % 8
    d[31] = d[31] % 64 + 64
    local p, pk = newPoint(), {}
    scalarbase(p, d)
    pack(pk, p)
    return toStr(pk, 32)
end

-- Returns the 64-byte signature of msg.
function Crypto.Sign(seed, msg)
    local pkStr = Crypto.SignKeyPair(seed)
    local dStr = H64(seed)
    local d = toArr(dStr, 64)
    d[0] = d[0] - d[0] % 8
    d[31] = d[31] % 64 + 64
    local r = toArr(H64(dStr:sub(33, 64) .. msg), 64)
    reduce(r)
    local p, R = newPoint(), {}
    scalarbase(p, r)
    pack(R, p)
    local Rs = toStr(R, 32)
    local h = toArr(H64(Rs .. pkStr .. msg), 64)
    reduce(h)
    local x = {}
    for i = 0, 63 do x[i] = 0 end
    for i = 0, 31 do x[i] = r[i] end
    for i = 0, 31 do
        for j = 0, 31 do x[i + j] = x[i + j] + h[i] * d[j] end
    end
    local s = {}
    modL(s, x)
    return Rs .. toStr(s, 32)
end

-- true when sig (64 bytes) is pk's signature of msg.
function Crypto.Verify(pk, msg, sig)
    if type(pk) ~= "string" or #pk ~= 32 or type(sig) ~= "string" or #sig ~= 64 then return false end
    -- S must be below L
    for i = 32, 1, -1 do
        local v, l = byte(sig, 32 + i), L[i - 1]
        if v < l then break end
        if v > l then return false end
        if i == 1 then return false end
    end
    local q = newPoint()
    if not unpackneg(q, toArr(pk, 32)) then return false end
    local h = toArr(H64(sig:sub(1, 32) .. pk .. msg), 64)
    reduce(h)
    local p = newPoint()
    scalarmult(p, q, h)
    local sb = newPoint()
    scalarbase(sb, toArr(sig:sub(33, 64), 32))
    add(p, sb)
    local t = {}
    pack(t, p)
    return Crypto.Equal(toStr(t, 32), sig:sub(1, 32))
end

-- Verified signatures are remembered (checking one takes a moment).
local verified = {}
function Crypto.VerifyCached(pk, msg, sig)
    local id = Crypto.SHA256(pk .. "\0" .. sig .. "\0" .. msg)
    if verified[id] ~= nil then return verified[id] end
    local ok = Crypto.Verify(pk, msg, sig)
    verified[id] = ok
    return ok
end

-- Canonical text of a value (sorted keys), so a signature checks out the
-- same on every client whatever order Lua lists a table in.
local function canon(v, out)
    local t = type(v)
    if t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then out[#out + 1] = "n" .. ((v == floor(v) and v > -1e15 and v < 1e15) and string.format("%d", v) or tostring(v)) .. ";"
    elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        local keys = {}
        for k in pairs(v) do
            local kt = type(k)
            if kt == "string" or kt == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta == "number" end
            return a < b
        end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do canon(k, out); canon(v[k], out) end
        out[#out + 1] = "}"
    else out[#out + 1] = "N" end
end
function Crypto.Canonical(v)
    local out = {}
    canon(v, out)
    return concat(out)
end

Crypto.H64 = H64
