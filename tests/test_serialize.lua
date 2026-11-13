-- tests/test_serialize.lua: Base64, Encode/Decode, profile import/export (spec 13).
local ns = ...
local S, Core = ns.CDSerialize, ns.CDCore

local PREFIX = "PIHCD1:"

local function Wrap(body) return PREFIX .. S.Base64Encode(body) end

local function Payload(settings, v)
    return Wrap(assert(S.Encode({ v = v or 1, settings = settings })))
end

-- Imports `text` against a fresh config; asserts the exact error and no mutation.
local function Rejects(t, text, expected, label)
    local current = Core.DeepCopy(Core.DEFAULTS)
    current.graceSeconds = 9
    local snapshot = Core.DeepCopy(current)
    local cfg, err = S.ImportSettings(text, current)
    t.eq(cfg, nil, label)
    t.eq(err, expected, label)
    t.deepEq(current, snapshot, (label or "") .. " current unchanged")
end

local function Nested(depth)
    local root = {}
    local node = root
    for _ = 2, depth do
        node.x = {}
        node = node.x
    end
    return root
end

local T = {}

T["base64 RFC 4648 vectors"] = function(t)
    local vectors = {
        { "", "" }, { "f", "Zg==" }, { "fo", "Zm8=" }, { "foo", "Zm9v" },
        { "foob", "Zm9vYg==" }, { "fooba", "Zm9vYmE=" }, { "foobar", "Zm9vYmFy" },
    }
    for _, v in ipairs(vectors) do
        t.eq(S.Base64Encode(v[1]), v[2], v[1])
        t.eq(S.Base64Decode(v[2]), v[1], v[2])
    end
end

T["base64 all byte values"] = function(t)
    local bytes = {}
    for i = 0, 255 do bytes[#bytes + 1] = string.char(i) end
    local s = table.concat(bytes)
    for cut = 254, 256 do
        local part = s:sub(1, cut)
        t.eq(S.Base64Decode(S.Base64Encode(part)), part, "len " .. cut)
    end
end

T["base64 strips whitespace, rejects junk"] = function(t)
    t.eq(S.Base64Decode("Zm9v\r\nYmFy "), "foobar")
    t.eq(S.Base64Decode("Zm9v!mFy"), nil)
    t.eq(S.Base64Decode("Zg="), nil, "short padding")
    t.eq(S.Base64Decode("Z==="), nil, "too much padding")
    t.eq(S.Base64Decode("Zg==Zm9v"), nil, "padding in the middle")
    t.eq(S.Base64Decode("Zh=="), nil, "non-canonical bits")
end

T["encode/decode round trips"] = function(t)
    local values = {
        true, false, 0, -1, 42, 2147483647, 3.14159, -0.5, 1e-7, 123456789012345,
        "", "plain", ":{}|S3:N1;", "caf\195\169 \226\152\131",
        { 1, 2, 3 }, { [1] = "a", [5] = "b", x = { y = { z = false } } },
        { nested = { list = { 1.25, -2, "s" }, flag = true }, [3] = -7.5 },
    }
    for i, v in ipairs(values) do
        local enc = assert(S.Encode(v))
        local dec, err = S.Decode(enc)
        t.eq(err, nil, "value " .. i)
        t.deepEq({ dec }, { v }, "value " .. i)
    end
end

T["encode grammar"] = function(t)
    t.eq(S.Encode(true), "T")
    t.eq(S.Encode(12), "N12;")
    t.eq(S.Encode("ab"), "S2:ab")
    t.eq(S.Encode({ 5, b = 1, a = 2 }), "{N1;N5;S1:aN2;S1:bN1;}")
end

T["encode errors"] = function(t)
    t.eq(S.Encode(nil), nil)
    t.eq(S.Encode(print), nil)
    t.eq(S.Encode(0 / 0), nil)
    t.eq(S.Encode(math.huge), nil)
    t.eq(S.Encode(-math.huge), nil)
    t.eq(S.Encode({ [true] = 1 }), nil)
    t.eq(S.Encode({ [{}] = 1 }), nil)
end

T["export/import defaults"] = function(t)
    local cfg = Core.DeepCopy(Core.DEFAULTS)
    local text = S.ExportSettings(cfg)
    t.eq(text:sub(1, #PREFIX), PREFIX)
    local out, err = S.ImportSettings(text, cfg)
    t.eq(err, nil)
    t.deepEq(out, cfg)
end

T["export/import customized keeps current alert and minimap"] = function(t)
    local cfg = Core.DeepCopy(Core.DEFAULTS)
    cfg.graceSeconds = 12
    cfg.trackedPlayers = { "Bob-Realm", "Al-Other" }
    cfg.buffs.custom = { 123, 456 }
    cfg.buffs.disabled[51271] = true
    cfg.contexts.raid.glowColor = { r = 0.25, g = 0.5, b = 0.75, a = 0.9 }
    cfg.contexts.dungeon.useOwnBuffs = true
    cfg.contexts.dungeon.buffs.potions = true
    cfg.alert.x = 300
    cfg.minimap.minimapPos = 10
    local text = S.ExportSettings(cfg)
    local current = Core.DeepCopy(Core.DEFAULTS)
    current.alert.y = -50
    current.minimap.hide = true
    local out = assert(S.ImportSettings(text, current))
    local expected = Core.DeepCopy(cfg)
    expected.alert = Core.DeepCopy(current.alert)
    expected.minimap = Core.DeepCopy(current.minimap)
    t.deepEq(out, expected)
    t.ok(out.alert ~= current.alert, "alert copied, not shared")
end

T["export excludes schemaVersion alert minimap"] = function(t)
    local text = S.ExportSettings(Core.DeepCopy(Core.DEFAULTS))
    local payload = S.Decode(S.Base64Decode(text:sub(#PREFIX + 1)))
    t.eq(payload.v, 1)
    t.eq(payload.settings.alert, nil)
    t.eq(payload.settings.minimap, nil)
    t.eq(payload.settings.schemaVersion, nil)
end

T["import tolerates pasted line breaks"] = function(t)
    local text = S.ExportSettings(Core.DeepCopy(Core.DEFAULTS))
    local broken = text:sub(1, 20) .. "\n" .. text:sub(21, 60) .. "\r\n  " .. text:sub(61) .. "\n"
    t.ok(S.ImportSettings(broken, Core.DEFAULTS))
end

T["reject envelope problems"] = function(t)
    local good = S.ExportSettings(Core.DeepCopy(Core.DEFAULTS))
    Rejects(t, "XYZ1:" .. good:sub(#PREFIX + 1), "Not a PIHelper CD tracker string.", "prefix")
    Rejects(t, PREFIX .. "Zm9v*mFy", "Corrupt import string.", "bad char")
    Rejects(t, PREFIX .. "Zg=", "Corrupt import string.", "bad padding")
    Rejects(t, good:sub(1, #good - 8), "Corrupt import string.", "truncated")
    Rejects(t, Wrap(S.Base64Decode(good:sub(#PREFIX + 1)) .. "T"), "Corrupt import string.", "trailing")
    Rejects(t, Payload({}, 2), "Unsupported version.", "v=2")
    Rejects(t, PREFIX .. string.rep("A", 65540), "Corrupt import string.", "oversized")
    Rejects(t, Wrap("return os.exit(1)"), "Corrupt import string.", "lua code")
    Rejects(t, PREFIX .. S.Base64Encode("return os.exit(1)"), "Corrupt import string.", "lua code 2")
    Rejects(t, Wrap("S5:hello"), "Corrupt import string.", "not a table")
end

T["reject structural limits"] = function(t)
    Rejects(t, Wrap("{S1:vN1;S8:settings" .. assert(S.Encode(Nested(8))) .. "}"),
        "Corrupt import string.", "depth 9")
    local many = {}
    for i = 1, 2600 do many[i] = i end
    Rejects(t, Payload({ trackedPlayers = many }), "Corrupt import string.", "> 5000 values")
    Rejects(t, Payload({ font = string.rep("a", 4097) }), "Corrupt import string.", "string > 4096")
    Rejects(t, Wrap("{S1:vN nan;}"), "Corrupt import string.", "N nan")
    Rejects(t, Wrap("{S1:vNnan;S8:settings{}}"), "Corrupt import string.", "Nnan")
    Rejects(t, Wrap("{S1:vN inf;S8:settings{}}"), "Corrupt import string.", "N inf")
    Rejects(t, Wrap("{S1:vN1e400;S8:settings{}}"), "Corrupt import string.", "N 1e400")
    Rejects(t, Wrap("{S1:vN1;S8:settings{{}T}}"), "Corrupt import string.", "table key")
    Rejects(t, Wrap("{S1:vN" .. string.rep("1", 33) .. ";S8:settings{}}"), "Corrupt import string.", "long number")
    Rejects(t, Wrap("{S1:vN1;S8:settings{}S4:evilT}"), "Corrupt import string.", "extra payload key")
end

T["depth 8 accepted by decoder"] = function(t)
    local v = Nested(8)
    t.ok(S.Decode(assert(S.Encode(v))), "depth 8 decodes")
    t.eq(S.Decode("{S1:x" .. assert(S.Encode(v)) .. "}"), nil, "depth 9 rejected")
    t.eq(S.Encode(Nested(9)), nil, "encoder refuses depth 9")
end

T["reject bad settings"] = function(t)
    Rejects(t, Payload({ evil = true }), "Unknown setting: evil", "settings.evil")
    Rejects(t, Payload({ graceSeconds = "5" }), "Invalid type for graceSeconds", "grace string")
    Rejects(t, Payload({ graceSeconds = -1 }), "Invalid value for graceSeconds", "grace -1")
    Rejects(t, Payload({ graceSeconds = 2.5 }), "Invalid value for graceSeconds", "grace fraction")
    Rejects(t, Payload({ glowThickness = 99 }), "Invalid value for glowThickness", "thickness")
    Rejects(t, Payload({ contexts = { raid = { glowStyle = "rainbow" } } }),
        "Invalid value for contexts.raid.glowStyle", "glowStyle")
    Rejects(t, Payload({ trackedPlayers = { "Bob|cffff0000-Realm" } }),
        "Invalid value for trackedPlayers[1]", "player |c")
    Rejects(t, Payload({ buffs = { custom = { 0 } } }), "Invalid value for buffs.custom[1]", "custom 0")
    Rejects(t, Payload({ buffs = { custom = { 7, 7 } } }), "Invalid value for buffs.custom[2]", "custom dup")
    Rejects(t, Payload({ font = "x|y" }), "Invalid value for font", "font pipe")
    Rejects(t, Payload({ buffs = { disabled = { [51271] = false } } }), "Invalid value for buffs.disabled", "disabled false")
    Rejects(t, Payload({ contexts = { raid = { glowColor = { r = 2, g = 0, b = 0, a = 1 } } } }),
        "Invalid value for contexts.raid.glowColor.r", "color range")
    Rejects(t, Payload({ customFramePrefix = "a b" }), "Invalid value for customFramePrefix", "prefix")
    Rejects(t, Payload({ [1] = true }), "Unknown setting: [1]", "numeric key")
end

T["serializer source has no code loading"] = function(t)
    local src = t.readFile("CDTrackerSerialize.lua")
    t.ok(src, "read CDTrackerSerialize.lua")
    for _, needle in ipairs({ "loadstring", "load(", "loadfile", "dofile", "setfenv" }) do
        t.eq(src:find(needle, 1, true), nil, needle)
    end
end

return T
