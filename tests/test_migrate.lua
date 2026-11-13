-- tests/test_migrate.lua: defaults, lenient sanitizing and migration (spec 14).
local ns = ...
local Core = ns.CDCore

-- True when any table reachable from a is also reachable from b.
local function SharesRef(a, b)
    local seen = {}
    local function Mark(t)
        if type(t) ~= "table" or seen[t] then return end
        seen[t] = true
        for _, v in pairs(t) do Mark(v) end
    end
    Mark(b)
    local function Find(t)
        if type(t) ~= "table" then return false end
        if seen[t] then return true end
        for _, v in pairs(t) do
            if Find(v) then return true end
        end
        return false
    end
    return Find(a)
end

local T = {}

T["nil cdTracker becomes defaults"] = function(t)
    local db = {}
    local cfg, newer = Core.Migrate(db)
    t.eq(newer, false)
    t.eq(db.cdTracker, cfg)
    t.deepEq(cfg, Core.DEFAULTS)
    t.eq(SharesRef(cfg, Core.DEFAULTS), false, "no shared references")
end

T["non-table cdTracker becomes defaults"] = function(t)
    local db = { cdTracker = "junk" }
    t.deepEq(Core.Migrate(db), Core.DEFAULTS)
end

T["partial config is filled"] = function(t)
    local db = { cdTracker = { graceSeconds = 12, contexts = { raid = { glowStyle = "fill" } } } }
    local cfg = Core.Migrate(db)
    t.eq(cfg.graceSeconds, 12)
    t.eq(cfg.contexts.raid.glowStyle, "fill")
    t.eq(cfg.contexts.raid.trackMode, "all")
    t.eq(cfg.contexts.dungeon.glowStyle, "pixel")
    t.deepEq(cfg.alert, Core.DEFAULTS.alert)
end

T["wrong types reset"] = function(t)
    local cfg = Core.Migrate({ cdTracker = {
        enabled = "yes", graceSeconds = "5", font = 7, trackedPlayers = "x",
        contexts = { raid = { glowColor = "red", enabled = 1 } }, buffs = { custom = "1" },
    } })
    t.eq(cfg.enabled, true)
    t.eq(cfg.graceSeconds, 5)
    t.eq(cfg.font, "Friz Quadrata TT")
    t.deepEq(cfg.trackedPlayers, {})
    t.deepEq(cfg.contexts.raid.glowColor, Core.DEFAULTS.contexts.raid.glowColor)
    t.eq(cfg.contexts.raid.enabled, true)
    t.deepEq(cfg.buffs.custom, {})
end

T["out of range clamped"] = function(t)
    t.eq(Core.Migrate({ cdTracker = { graceSeconds = 99 } }).graceSeconds, 30)
    t.eq(Core.Migrate({ cdTracker = { graceSeconds = -1 } }).graceSeconds, 0)
    t.eq(Core.Migrate({ cdTracker = { glowThickness = 2.7 } }).glowThickness, 2)
    t.eq(Core.Migrate({ cdTracker = { glowThickness = 0 } }).glowThickness, 1)
    t.eq(Core.Migrate({ cdTracker = { frameFontSize = 100 } }).frameFontSize, 24)
    local cfg = Core.Migrate({ cdTracker = { alert = { scale = 9, x = -9000, y = 3.5 },
        minimap = { minimapPos = 400 }, contexts = { focus = { glowColor = { r = 2, g = -1, b = 0.5, a = 1 } } } } })
    t.eq(cfg.alert.scale, 2.0)
    t.eq(cfg.alert.x, -4000)
    t.eq(cfg.alert.y, 3.5)
    t.eq(cfg.minimap.minimapPos, 360)
    t.deepEq(cfg.contexts.focus.glowColor, { r = 1, g = 0, b = 0.5, a = 1 })
end

T["NaN numbers reset"] = function(t)
    t.eq(Core.Migrate({ cdTracker = { graceSeconds = 0 / 0 } }).graceSeconds, 5)
end

T["bad enums reset"] = function(t)
    local cfg = Core.Migrate({ cdTracker = { contexts = {
        raid = { glowStyle = "rainbow", trackMode = "some", durationText = "loud" },
    }, alert = { point = "", relPoint = "WAYTOOLONGANCHORNAME" } } })
    t.eq(cfg.contexts.raid.glowStyle, "pixel")
    t.eq(cfg.contexts.raid.trackMode, "all")
    t.eq(cfg.contexts.raid.durationText, "frame")
    t.eq(cfg.alert.point, "CENTER")
    t.eq(cfg.alert.relPoint, "CENTER")
end

T["unknown keys and bad entries dropped"] = function(t)
    local cfg = Core.Migrate({ cdTracker = {
        evil = true, locked = true,
        contexts = { focus = { trackMode = "list" }, pvp = {} },
        alert = { locked = true },
        buffs = { custom = { 5, 5, 0, -1, 1.5, "7", 9 }, disabled = { [51271] = true, [0] = true, x = true, [12472] = 1 } },
        trackedPlayers = { "A-R", 5, "a-r", "B|c-R", "", "C-R", string.rep("x", 65) },
        customFramePrefix = "Bad Prefix!",
    } })
    t.eq(cfg.evil, nil)
    t.eq(cfg.locked, nil)
    t.eq(cfg.contexts.focus.trackMode, nil)
    t.eq(cfg.contexts.pvp, nil)
    t.eq(cfg.alert.locked, nil)
    t.deepEq(cfg.buffs.custom, { 5, 9 })
    t.deepEq(cfg.buffs.disabled, { [51271] = true })
    t.deepEq(cfg.trackedPlayers, { "A-R", "C-R" })
    t.eq(cfg.customFramePrefix, "")
end

T["custom limit enforced"] = function(t)
    local ids = {}
    for i = 1, 150 do ids[i] = i end
    t.eq(#Core.Migrate({ cdTracker = { buffs = { custom = ids } } }).buffs.custom, 100)
end

T["idempotent"] = function(t)
    local db = { cdTracker = { graceSeconds = 99, trackedPlayers = { "A-R", "a-r" } } }
    local first = Core.DeepCopy(Core.Migrate(db))
    local second = Core.Migrate(db)
    t.deepEq(second, first)
    t.deepEq(Core.Migrate(db), first)
end

T["sibling PI keys untouched"] = function(t)
    local trinkets = { [12345] = false }
    local pos = { point = "TOP", relPoint = "TOP", x = 1, y = 2 }
    local db = { target = "Bob-Realm", trinketEnabled = trinkets, usePotion = true,
        potionName = "Potion of Zealotry", useVampiricEmbrace = true, framePos = pos }
    Core.Migrate(db)
    t.eq(db.target, "Bob-Realm")
    t.eq(db.trinketEnabled, trinkets)
    t.deepEq(db.trinketEnabled, { [12345] = false })
    t.eq(db.usePotion, true)
    t.eq(db.potionName, "Potion of Zealotry")
    t.eq(db.useVampiricEmbrace, true)
    t.eq(db.framePos, pos)
    t.deepEq(pos, { point = "TOP", relPoint = "TOP", x = 1, y = 2 })
end

T["newer schemaVersion still sanitized"] = function(t)
    local db = { cdTracker = { schemaVersion = 2, futureOption = 1, graceSeconds = 7 } }
    local cfg, newer = Core.Migrate(db)
    t.eq(newer, true)
    t.eq(cfg.schemaVersion, 1)
    t.eq(cfg.futureOption, nil)
    t.eq(cfg.graceSeconds, 7)
end

T["strict sanitize basics"] = function(t)
    local cfg = Core.Sanitize({}, "strict")
    t.deepEq(cfg, Core.DEFAULTS)
    local _, e1 = Core.Sanitize({ contexts = { raid = { glowStyle = "rainbow" } } }, "strict")
    t.eq(e1, "Invalid value for contexts.raid.glowStyle")
    local _, e2 = Core.Sanitize({ trackedPlayers = { "ok-R", "bad|c" } }, "strict")
    t.eq(e2, "Invalid value for trackedPlayers[2]")
    local _, e3 = Core.Sanitize({ buffs = { custom = { 4, 0 } } }, "strict")
    t.eq(e3, "Invalid value for buffs.custom[2]")
    local _, e4 = Core.Sanitize({ contexts = { focus = { trackMode = "all" } } }, "strict")
    t.eq(e4, "Unknown setting: contexts.focus.trackMode")
end

return T
