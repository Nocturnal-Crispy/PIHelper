-- CDTrackerSerialize.lua
-- Self-contained profile import/export: RFC 4648 Base64 plus a tiny typed
-- encoding parsed by a hand-written cursor. Imports are read as plain data and
-- never executed. Pure Lua; no WoW API calls.

local _, ns = ...

local S = {}

local PREFIX        = "PIHCD1:"
local FORMAT_VER    = 1
local MAX_INPUT     = 65536
local MAX_DEPTH     = 8
local MAX_VALUES    = 5000
local MAX_STRING    = 4096
local MAX_NUM_REPR  = 32
local INT_LIMIT     = 9007199254740992 -- 2^53

local ERR_PREFIX  = "Not a PIHelper CD tracker string."
local ERR_CORRUPT = "Corrupt import string."
local ERR_VERSION = "Unsupported version."

-- --- Base64 ------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
    local c = ALPHABET:sub(i, i)
    ENC[i - 1] = c
    DEC[c:byte()] = i - 1
end

local floor = math.floor

function S.Base64Encode(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = floor(n / 262144) % 64
        local c2 = floor(n / 4096) % 64
        local c3 = floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = ENC[c1] .. ENC[c2]
            .. (b and ENC[c3] or "=") .. (c and ENC[c4] or "=")
    end
    return table.concat(out)
end

-- Strips whitespace; rejects any other non-alphabet byte and bad padding.
function S.Base64Decode(s)
    if type(s) ~= "string" then return nil, ERR_CORRUPT end
    s = s:gsub("%s", "")
    if #s % 4 ~= 0 then return nil, ERR_CORRUPT end
    local pad = 0
    if s:sub(-2) == "==" then pad = 2 elseif s:sub(-1) == "=" then pad = 1 end
    local body = s:sub(1, #s - pad)
    if body:find("[^%w%+/]") then return nil, ERR_CORRUPT end
    local out = {}
    for i = 1, #s, 4 do
        local q1, q2, q3, q4 = s:byte(i, i + 3)
        local v1, v2 = DEC[q1], DEC[q2]
        local v3 = q3 ~= 61 and DEC[q3] or nil
        local v4 = q4 ~= 61 and DEC[q4] or nil
        if v1 == nil or v2 == nil then return nil, ERR_CORRUPT end
        local last = i + 3 >= #s
        if (v3 == nil or v4 == nil) and not last then return nil, ERR_CORRUPT end
        if v3 == nil and v4 ~= nil then return nil, ERR_CORRUPT end
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        local b1 = floor(n / 65536) % 256
        local b2 = floor(n / 256) % 256
        local b3 = n % 256
        if v3 == nil then
            if b2 ~= 0 then return nil, ERR_CORRUPT end -- non-canonical padding bits
            out[#out + 1] = string.char(b1)
        elseif v4 == nil then
            if b3 ~= 0 then return nil, ERR_CORRUPT end
            out[#out + 1] = string.char(b1, b2)
        else
            out[#out + 1] = string.char(b1, b2, b3)
        end
    end
    return table.concat(out)
end

-- --- Encode ------------------------------------------------------------------

local function IsFiniteNumber(n)
    return n == n and n ~= math.huge and n ~= -math.huge
end

local function EncodeNumber(n)
    if not IsFiniteNumber(n) then return nil, "Cannot encode NaN or infinity." end
    if n == floor(n) and math.abs(n) < INT_LIMIT then
        -- %d is 32-bit on some Lua 5.1 builds; %.0f prints the same digits
        -- for every integer below 2^53.
        local fmt = math.abs(n) < 2147483648 and "%d" or "%.0f"
        return "N" .. string.format(fmt, n) .. ";"
    end
    return "N" .. string.format("%.17g", n) .. ";"
end

local EncodeValue -- forward

local function SortedKeys(t)
    local ints, strs = {}, {}
    for k in pairs(t) do
        if type(k) == "number" and k >= 1 and k == floor(k) and IsFiniteNumber(k) then
            ints[#ints + 1] = k
        elseif type(k) == "string" then
            strs[#strs + 1] = k
        else
            return nil
        end
    end
    table.sort(ints)
    table.sort(strs)
    for _, k in ipairs(strs) do ints[#ints + 1] = k end
    return ints
end

local function EncodeTable(t, out, depth)
    if depth > MAX_DEPTH then return "Table nesting too deep." end
    local keys = SortedKeys(t)
    if not keys then return "Unsupported table key." end
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do
        local err = EncodeValue(k, out, depth) or EncodeValue(t[k], out, depth)
        if err then return err end
    end
    out[#out + 1] = "}"
    return nil
end

-- Appends the encoding of v to out; returns an error string or nil.
EncodeValue = function(v, out, depth)
    local tv = type(v)
    if tv == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif tv == "number" then
        local s, err = EncodeNumber(v)
        if not s then return err end
        out[#out + 1] = s
    elseif tv == "string" then
        out[#out + 1] = "S" .. #v .. ":" .. v
    elseif tv == "table" then
        return EncodeTable(v, out, depth + 1)
    else
        return "Cannot encode a " .. tv .. "."
    end
    return nil
end

function S.Encode(v)
    local out = {}
    local err = EncodeValue(v, out, 0)
    if err then return nil, err end
    return table.concat(out)
end

-- --- Decode ------------------------------------------------------------------
-- Cursor parser over the grammar written by Encode. Any deviation -> corrupt.

local ReadValue -- forward

local function ReadNumber(st)
    local stop = st.s:find(";", st.pos, true)
    if not stop then return nil end
    local repr = st.s:sub(st.pos, stop - 1)
    if repr == "" or #repr > MAX_NUM_REPR or repr:find("[^%-%+%d%.eE]") then return nil end
    local n = tonumber(repr)
    if n == nil or not IsFiniteNumber(n) then return nil end
    st.pos = stop + 1
    return n
end

local function ReadString(st)
    local colon = st.s:find(":", st.pos, true)
    if not colon or colon - st.pos > 4 then return nil end
    local lenRepr = st.s:sub(st.pos, colon - 1)
    if not lenRepr:find("^%d+$") then return nil end
    local len = tonumber(lenRepr)
    if len > MAX_STRING then return nil end
    local first = colon + 1
    if first + len - 1 > #st.s then return nil end
    st.pos = first + len
    return st.s:sub(first, first + len - 1)
end

local function ReadTable(st, depth)
    if depth > MAX_DEPTH then return nil end
    local t = {}
    while true do
        if st.pos > #st.s then return nil end
        if st.s:sub(st.pos, st.pos) == "}" then
            st.pos = st.pos + 1
            return t
        end
        local k = ReadValue(st, depth)
        if k == nil then return nil end
        local tk = type(k)
        if tk ~= "string" and tk ~= "number" then return nil end
        if t[k] ~= nil then return nil end
        local v = ReadValue(st, depth)
        if v == nil then return nil end
        t[k] = v
    end
end

ReadValue = function(st, depth)
    st.count = st.count + 1
    if st.count > MAX_VALUES then return nil end
    local tag = st.s:sub(st.pos, st.pos)
    st.pos = st.pos + 1
    if tag == "T" then return true end
    if tag == "F" then return false end
    if tag == "N" then return ReadNumber(st) end
    if tag == "S" then return ReadString(st) end
    if tag == "{" then return ReadTable(st, depth + 1) end
    return nil
end

function S.Decode(s)
    if type(s) ~= "string" or #s > MAX_INPUT then return nil, ERR_CORRUPT end
    local st = { s = s, pos = 1, count = 0 }
    local v = ReadValue(st, 0)
    if v == nil or st.pos ~= #s + 1 then return nil, ERR_CORRUPT end
    return v
end

-- --- Profiles ----------------------------------------------------------------

function S.ExportSettings(cfg)
    local Core = ns.CDCore
    local settings = {}
    for k, v in pairs(cfg) do
        if not Core.PROFILE_EXCLUDE[k] then settings[k] = Core.DeepCopy(v) end
    end
    local body = assert(S.Encode({ v = FORMAT_VER, settings = settings }))
    return PREFIX .. S.Base64Encode(body)
end

local function ParseEnvelope(text)
    if type(text) ~= "string" or #text > MAX_INPUT then return nil, ERR_CORRUPT end
    text = ns.CDCore.Trim(text)
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, ERR_PREFIX end
    local raw = S.Base64Decode(text:sub(#PREFIX + 1))
    if not raw then return nil, ERR_CORRUPT end
    local payload = S.Decode(raw)
    if type(payload) ~= "table" then return nil, ERR_CORRUPT end
    return payload
end

-- Returns a new, strictly sanitized cdTracker table (current alert/minimap kept)
-- or nil, err. Never mutates currentCfg.
function S.ImportSettings(text, currentCfg)
    local Core = ns.CDCore
    local payload, err = ParseEnvelope(text)
    if not payload then return nil, err end
    if payload.v ~= FORMAT_VER then return nil, ERR_VERSION end
    for k in pairs(payload) do
        if k ~= "v" and k ~= "settings" then return nil, ERR_CORRUPT end
    end
    if type(payload.settings) ~= "table" then return nil, ERR_CORRUPT end
    local cfg, serr = Core.Sanitize(payload.settings, "strict")
    if not cfg then return nil, serr end
    local keep = type(currentCfg) == "table" and currentCfg or Core.DEFAULTS
    cfg.schemaVersion = 1
    cfg.alert = Core.DeepCopy(keep.alert or Core.DEFAULTS.alert)
    cfg.minimap = Core.DeepCopy(keep.minimap or Core.DEFAULTS.minimap)
    return cfg
end

ns.CDSerialize = S
