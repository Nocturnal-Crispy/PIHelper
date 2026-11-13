-- CDTrackerCore.lua
-- Pure CD tracker logic: defaults, schema-driven sanitizing, migration, run
-- condition, context selection, unit filtering, buff resolution, custom IDs,
-- PI-ready gate. No WoW API calls (IsSecret only reads a global at call time),
-- so tests/run.lua can load it headless.

local _, ns = ...

local Core = {}

local MAX_SPELL_ID     = 2147483647
local MAX_CUSTOM_IDS   = 100
local MAX_PLAYERS      = 200
local MAX_NAME_LEN     = 64
local DEFAULT_PI_CD    = 120
local GCD_THRESHOLD    = 1.5

-- --- Generic helpers ---------------------------------------------------------

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[DeepCopy(k)] = DeepCopy(x) end
    return out
end
Core.DeepCopy = DeepCopy

-- True only for values the client has marked secret. Every runtime read of
-- unit/aura/cooldown data must pass through this before use.
function Core.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function IsNaN(n) return n ~= n end

local function IsValidSpellID(id)
    return type(id) == "number" and not IsNaN(id) and id == math.floor(id)
        and id >= 1 and id <= MAX_SPELL_ID
end
Core.IsValidSpellID = IsValidSpellID

-- --- Defaults ----------------------------------------------------------------

local function EmptyBuffs()
    return { disabled = {}, potions = false, custom = {} }
end

local function GroupContextDefaults()
    return {
        enabled = true, trackMode = "all", glowStyle = "pixel",
        glowColor = { r = 1, g = 0.82, b = 0, a = 1 },
        durationText = "frame", showAlert = false, playSound = false,
        useOwnBuffs = false, buffs = EmptyBuffs(),
    }
end

Core.DEFAULTS = {
    schemaVersion = 1,
    enabled = true, healerSpecsOnly = true, loadOnAllClasses = false,
    requirePIReady = true, graceSeconds = 5,
    preferLibCustomGlow = true, glowThickness = 2,
    font = "Friz Quadrata TT", frameFontSize = 12,
    alertFontSize = 16,
    sound = "Raid Warning", classColorNames = true,
    customFramePrefix = "",
    trackedPlayers = {},
    buffs = EmptyBuffs(),
    contexts = {
        raid = GroupContextDefaults(),
        dungeon = GroupContextDefaults(),
        focus = {
            enabled = true, glowStyle = "proc",
            glowColor = { r = 0.2, g = 0.8, b = 1, a = 1 },
            durationText = "both", showAlert = true, playSound = true,
            useOwnBuffs = false, buffs = EmptyBuffs(),
        },
    },
    alert = { point = "CENTER", relPoint = "CENTER", x = 0, y = 180, scale = 1.0 },
    minimap = { hide = false, minimapPos = 220 },
}

-- Keys the profile import/export leaves alone.
Core.PROFILE_EXCLUDE = { schemaVersion = true, alert = true, minimap = true }

-- --- Schema ------------------------------------------------------------------
-- One schema drives both lenient (migration) and strict (import) sanitizing.

local function Enum(...)
    local set = {}
    for i = 1, select("#", ...) do set[select(i, ...)] = true end
    return { t = "enum", values = set }
end

local COLOR = { t = "record", fields = {
    r = { t = "num", min = 0, max = 1 }, g = { t = "num", min = 0, max = 1 },
    b = { t = "num", min = 0, max = 1 }, a = { t = "num", min = 0, max = 1 },
} }

local BUFFS = { t = "record", fields = {
    disabled = { t = "idset" },
    potions  = { t = "bool" },
    custom   = { t = "idlist", max = MAX_CUSTOM_IDS },
} }

local function ContextSchema(withTrackMode)
    local fields = {
        enabled = { t = "bool" },
        glowStyle = Enum("pixel", "proc", "border", "countdown", "fill"),
        glowColor = COLOR,
        durationText = Enum("none", "frame", "alert", "both"),
        showAlert = { t = "bool" }, playSound = { t = "bool" },
        useOwnBuffs = { t = "bool" }, buffs = BUFFS,
    }
    if withTrackMode then fields.trackMode = Enum("all", "list") end
    return { t = "record", fields = fields }
end

local MEDIA_NAME = { t = "string", max = 128, check = function(s) return not s:find("|", 1, true) end }
local ANCHOR = { t = "string", max = 16, check = function(s) return s ~= "" end }

local SCHEMA = { t = "record", fields = {
    schemaVersion = { t = "int", min = 0, max = MAX_SPELL_ID },
    enabled = { t = "bool" }, healerSpecsOnly = { t = "bool" }, loadOnAllClasses = { t = "bool" },
    requirePIReady = { t = "bool" }, graceSeconds = { t = "int", min = 0, max = 30 },
    preferLibCustomGlow = { t = "bool" }, glowThickness = { t = "int", min = 1, max = 6 },
    font = MEDIA_NAME, frameFontSize = { t = "int", min = 6, max = 24 },
    alertFontSize = { t = "int", min = 8, max = 32 },
    sound = MEDIA_NAME, classColorNames = { t = "bool" },
    customFramePrefix = { t = "string", max = MAX_NAME_LEN,
        check = function(s) return s:find("^[%w_]*$") ~= nil end },
    trackedPlayers = { t = "namelist", max = MAX_PLAYERS },
    buffs = BUFFS,
    contexts = { t = "record", fields = {
        raid = ContextSchema(true), dungeon = ContextSchema(true), focus = ContextSchema(false),
    } },
    alert = { t = "record", fields = {
        point = ANCHOR, relPoint = ANCHOR,
        x = { t = "num", min = -4000, max = 4000 }, y = { t = "num", min = -4000, max = 4000 },
        scale = { t = "num", min = 0.5, max = 2.0 },
    } },
    minimap = { t = "record", fields = {
        hide = { t = "bool" }, minimapPos = { t = "num", min = 0, max = 360 },
    } },
} }

local function IsValidPlayerName(s)
    return type(s) == "string" and s ~= "" and #s <= MAX_NAME_LEN and not s:find("[%c|]")
end

-- --- Sanitize ----------------------------------------------------------------

local SanitizeNode -- forward

-- Never echo arbitrary imported strings into error text.
local function SafeKey(k)
    if type(k) == "string" and #k <= 32 and k:find("^[%w_]+$") then return k end
    return "?"
end

local function Join(path, key)
    if type(key) == "number" then return path .. "[" .. key .. "]" end
    if path == "" then return SafeKey(key) end
    return path .. "." .. SafeKey(key)
end

local function Fail(kind, path)
    if kind == "type" then return nil, "Invalid type for " .. path end
    if kind == "unknown" then return nil, "Unknown setting: " .. path end
    return nil, "Invalid value for " .. path
end

local function Clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function SanitizeNumber(node, v, def, strict, path)
    if type(v) ~= "number" or IsNaN(v) then
        if strict then return Fail(type(v) == "number" and "value" or "type", path) end
        return def
    end
    if strict then
        if v < node.min or v > node.max then return Fail("value", path) end
        if node.t == "int" and v ~= math.floor(v) then return Fail("value", path) end
        return v
    end
    if node.t == "int" then v = math.floor(v) end
    return Clamp(v, node.min, node.max)
end

local function SanitizeScalar(node, v, def, strict, path)
    local t = node.t
    if t == "bool" then
        if type(v) == "boolean" then return v end
        if strict then return Fail("type", path) end
        return def
    end
    if t == "int" or t == "num" then return SanitizeNumber(node, v, def, strict, path) end
    if type(v) ~= "string" then
        if strict then return Fail("type", path) end
        return def
    end
    local ok
    if t == "enum" then
        ok = node.values[v] == true
    else
        ok = #v <= node.max and (node.check == nil or node.check(v))
    end
    if ok then return v end
    if strict then return Fail("value", path) end
    return def
end

-- True when t has exactly the keys 1..#t.
local function IsSequence(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

local function SanitizeList(node, v, strict, path, isValid, keyOf)
    local out, seen = {}, {}
    if strict and not IsSequence(v) then return Fail("value", path) end
    for i, x in ipairs(v) do
        local key = isValid(x) and keyOf(x) or nil
        if key == nil or seen[key] or #out >= node.max then
            if strict then return Fail("value", Join(path, i)) end
        else
            seen[key] = true
            out[#out + 1] = x
        end
    end
    return out
end

local function SanitizeIdSet(v, strict, path)
    local out = {}
    for k, x in pairs(v) do
        if IsValidSpellID(k) and x == true then
            out[k] = true
        elseif strict then
            return Fail("value", path)
        end
    end
    return out
end

local function SanitizeRecord(node, v, def, strict, path)
    local out = {}
    if strict then
        for k in pairs(v) do
            if type(k) ~= "string" or node.fields[k] == nil then
                return Fail("unknown", Join(path, k))
            end
        end
    end
    for key, child in pairs(node.fields) do
        local res, err = SanitizeNode(child, v[key], def[key], strict, Join(path, key))
        if res == nil then return nil, err end
        out[key] = res
    end
    return out
end

local function LowerKey(s) return s:lower() end
local function IdKey(n) return n end

SanitizeNode = function(node, v, def, strict, path)
    local t = node.t
    if t == "record" or t == "idset" or t == "idlist" or t == "namelist" then
        if v == nil then return DeepCopy(def) end
        if type(v) ~= "table" then
            if strict then return Fail("type", path) end
            return DeepCopy(def)
        end
        if t == "record" then return SanitizeRecord(node, v, def, strict, path) end
        if t == "idset" then return SanitizeIdSet(v, strict, path) end
        if t == "idlist" then return SanitizeList(node, v, strict, path, IsValidSpellID, IdKey) end
        return SanitizeList(node, v, strict, path, IsValidPlayerName, LowerKey)
    end
    if v == nil then return def end
    return SanitizeScalar(node, v, def, strict, path)
end

-- mode "lenient": always returns a table (bad values -> defaults, clamped,
-- unknown keys dropped). mode "strict": returns nil, err on the first problem.
-- The result never shares a reference with the input or DEFAULTS.
function Core.Sanitize(input, mode)
    local strict = mode == "strict"
    if type(input) ~= "table" then
        if strict then return nil, "Invalid type for settings" end
        return DeepCopy(Core.DEFAULTS)
    end
    return SanitizeNode(SCHEMA, input, Core.DEFAULTS, strict, "")
end

-- Returns cfg, newer (true when the saved schemaVersion is above ours).
function Core.Migrate(db)
    local saved = db.cdTracker
    if type(saved) ~= "table" then saved = {} end
    local sv = saved.schemaVersion
    local newer = type(sv) == "number" and sv > 1
    local cfg = Core.Sanitize(saved, "lenient")
    cfg.schemaVersion = 1
    db.cdTracker = cfg
    return cfg, newer
end

-- --- Run condition and context -----------------------------------------------

function Core.ShouldRun(player, cfg)
    if not cfg.enabled then return false, "disabled" end
    if cfg.loadOnAllClasses then return true, "all_classes" end
    if player.classFile ~= "PRIEST" then return false, "not_priest" end
    if cfg.healerSpecsOnly and not (player.specID == 256 or player.specID == 257) then
        return false, "not_healer_spec"
    end
    return true, "ok"
end

function Core.SelectContext(cfg, gs)
    local c = cfg.contexts
    if c.focus.enabled and gs.focusValid then return "focus" end
    if gs.inRaid then
        if c.raid.enabled then return "raid" end
        return nil
    end
    if gs.inGroup and c.dungeon.enabled then return "dungeon" end
    return nil
end

-- --- Names and unit filtering ------------------------------------------------

function Core.NormalizeName(name, playerRealm)
    if type(name) ~= "string" then return nil end
    name = Trim(name)
    if name == "" or #name > MAX_NAME_LEN or name:find("[%c|]") then return nil end
    if not name:find("-", 1, true) and type(playerRealm) == "string" and playerRealm ~= "" then
        name = name .. "-" .. playerRealm
    end
    if #name > MAX_NAME_LEN then return nil end
    return name
end

function Core.IsTrackedPlayer(list, name)
    if type(name) ~= "string" or type(list) ~= "table" then return false end
    local lower = name:lower()
    for _, n in ipairs(list) do
        if type(n) == "string" and n:lower() == lower then return true end
    end
    return false
end

function Core.AddTrackedPlayer(list, name, realm)
    local norm = Core.NormalizeName(name, realm)
    if not norm then return nil, "Invalid name." end
    if Core.IsTrackedPlayer(list, norm) then return nil, "Already listed." end
    if #list >= MAX_PLAYERS then return nil, "List is full (200)." end
    local out = DeepCopy(list)
    out[#out + 1] = norm
    return out
end

function Core.RemoveTrackedPlayer(list, name)
    local out, removed = {}, false
    local lower = type(name) == "string" and name:lower() or nil
    for _, n in ipairs(list) do
        if lower and n:lower() == lower then removed = true else out[#out + 1] = n end
    end
    return out, removed
end

function Core.ShouldTrackUnit(info, cfg, ctx)
    if ctx == "focus" then return true end
    if Core.IsTrackedPlayer(cfg.trackedPlayers, info.name) then return true end
    if info.isSelf then return false end
    if cfg.contexts[ctx].trackMode == "list" then return false end
    if info.role == "TANK" or info.role == "HEALER" then return false end
    return true
end

-- --- Buffs -------------------------------------------------------------------

function Core.ClassSpellIDs(data, classFile)
    local set = {}
    for _, entry in ipairs(data.CATALOG) do
        if entry.class == classFile then
            for _, s in ipairs(entry.spells) do set[s.id] = true end
        end
    end
    return set
end

local function IsDefaultID(data, id)
    for _, entry in ipairs(data.CATALOG) do
        for _, s in ipairs(entry.spells) do
            if s.id == id then return true end
        end
    end
    for _, p in ipairs(data.POTIONS) do
        if p.id == id then return true end
    end
    return false
end
Core.IsDefaultID = IsDefaultID

function Core.BuffSource(cfg, ctx)
    local c = ctx and cfg.contexts[ctx]
    if c and c.useOwnBuffs then return c.buffs end
    return cfg.buffs
end

function Core.ResolveBuffSet(cfg, ctx, data)
    local src = Core.BuffSource(cfg, ctx)
    local set = {}
    for _, entry in ipairs(data.CATALOG) do
        for _, s in ipairs(entry.spells) do
            if not src.disabled[s.id] then set[s.id] = true end
        end
    end
    if src.potions then
        for _, p in ipairs(data.POTIONS) do set[p.id] = true end
    end
    for _, id in ipairs(src.custom) do set[id] = true end
    local list = {}
    for id in pairs(set) do list[#list + 1] = id end
    table.sort(list)
    return set, list
end

function Core.ValidateSpellIDInput(text)
    if type(text) ~= "string" then return nil, "Enter a spell ID." end
    local s = Trim(text)
    if s == "" then return nil, "Enter a spell ID." end
    if not s:find("^%d+$") then return nil, "Spell ID must be a whole number." end
    local digits = s:gsub("^0+", "")
    if #digits > 9 then return nil, "Spell ID out of range." end
    local id = tonumber(s)
    if not id or id < 1 or id > MAX_SPELL_ID then return nil, "Spell ID out of range." end
    return id
end

function Core.AddCustomID(buffs, id, data)
    for _, x in ipairs(buffs.custom) do
        if x == id then return nil, "Already tracked." end
    end
    if IsDefaultID(data, id) then
        return nil, "That is a default buff; enable it in the list instead."
    end
    if #buffs.custom >= MAX_CUSTOM_IDS then return nil, "Custom ID limit (100) reached." end
    local out = DeepCopy(buffs)
    out.custom[#out.custom + 1] = id
    return out
end

function Core.RemoveCustomID(buffs, id)
    local out = DeepCopy(buffs)
    local kept, removed = {}, false
    for _, x in ipairs(out.custom) do
        if x == id then removed = true else kept[#kept + 1] = x end
    end
    out.custom = kept
    return out, removed
end

-- entries: { {id, expirationTime?, duration?, icon?}, ... }
function Core.PickHighlight(entries)
    local best
    for _, e in ipairs(entries) do
        if type(e.expirationTime) == "number"
            and (best == nil or e.expirationTime > best.expirationTime) then
            best = e
        end
    end
    return best or entries[1]
end

function Core.FormatDuration(remaining)
    if type(remaining) ~= "number" or IsNaN(remaining) or remaining <= 0 then return nil end
    if remaining >= 10 then return string.format("%d", math.floor(remaining)) end
    return string.format("%.1f", remaining)
end

-- --- PI gate -----------------------------------------------------------------

local function ClassifyRemaining(remaining, grace)
    if remaining == nil then return { allowed = false, reason = "cooldown" } end
    if remaining <= 0 then return { allowed = true, reason = "ready", remaining = 0 } end
    if remaining <= grace then return { allowed = true, reason = "grace", remaining = remaining } end
    return { allowed = false, reason = "cooldown", remaining = remaining }
end

-- i = {applies, now, grace, cd={readable,isActive,isOnGCD,startTime,duration}|nil,
--      castAt, lastDuration}. Numbers must already be non-secret (or nil).
function Core.ComputePIGate(i)
    if not i.applies then return { allowed = true, reason = "n/a" } end
    local grace = i.grace or 0
    local last = i.lastDuration or DEFAULT_PI_CD
    local castAt = type(i.castAt) == "number" and i.castAt or nil
    local cd = i.cd
    if cd and cd.readable then
        if not cd.isActive or cd.isOnGCD == true then
            return { allowed = true, reason = "ready", remaining = 0 }
        end
        local remaining
        if type(cd.startTime) == "number" and type(cd.duration) == "number"
            and cd.duration > GCD_THRESHOLD then
            remaining = cd.startTime + cd.duration - i.now
        elseif castAt then
            remaining = castAt + last - i.now
        end
        return ClassifyRemaining(remaining, grace)
    end
    if castAt then
        local remaining = castAt + last - i.now
        if remaining > 0 then return ClassifyRemaining(remaining, grace) end
        return { allowed = true, reason = "ready_est", remaining = 0 }
    end
    return { allowed = true, reason = "unknown" }
end

-- --- Alert mover -------------------------------------------------------------

function Core.SnapOffset(x, y, threshold)
    if math.abs(x) <= threshold then x = 0 end
    if math.abs(y) <= threshold then y = 0 end
    return x, y
end

ns.CDCore = Core
