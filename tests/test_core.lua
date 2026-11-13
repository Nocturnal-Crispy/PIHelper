-- tests/test_core.lua: run condition, context selection, unit filter, names, snap.
local ns = ...
local Core = ns.CDCore

local function Cfg(over)
    local c = Core.DeepCopy(Core.DEFAULTS)
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

local T = {}

T["ShouldRun table"] = function(t)
    local players = {
        { "PRIEST", 256 }, { "PRIEST", 257 }, { "PRIEST", 258 }, { "PRIEST", nil },
        { "MAGE", 62 }, { "WARRIOR", nil },
    }
    for _, p in ipairs(players) do
        for _, enabled in ipairs({ true, false }) do
            for _, healerOnly in ipairs({ true, false }) do
                for _, allClasses in ipairs({ true, false }) do
                    local cfg = Cfg({ enabled = enabled, healerSpecsOnly = healerOnly, loadOnAllClasses = allClasses })
                    local ok, reason = Core.ShouldRun({ classFile = p[1], specID = p[2] }, cfg)
                    local eok, ereason
                    if not enabled then
                        eok, ereason = false, "disabled"
                    elseif allClasses then
                        eok, ereason = true, "all_classes"
                    elseif p[1] ~= "PRIEST" then
                        eok, ereason = false, "not_priest"
                    elseif healerOnly and p[2] ~= 256 and p[2] ~= 257 then
                        eok, ereason = false, "not_healer_spec"
                    else
                        eok, ereason = true, "ok"
                    end
                    local label = string.format("%s/%s e=%s h=%s a=%s", p[1], tostring(p[2]),
                        tostring(enabled), tostring(healerOnly), tostring(allClasses))
                    t.eq(ok, eok, label)
                    t.eq(reason, ereason, label)
                end
            end
        end
    end
end

T["ShouldRun explicit pairs"] = function(t)
    local cfg = Cfg()
    local ok, r = Core.ShouldRun({ classFile = "PRIEST", specID = 258 }, cfg)
    t.eq(ok, false); t.eq(r, "not_healer_spec")
    ok, r = Core.ShouldRun({ classFile = "PRIEST", specID = 257 }, cfg)
    t.eq(ok, true); t.eq(r, "ok")
    ok, r = Core.ShouldRun({ classFile = "MAGE" }, cfg)
    t.eq(ok, false); t.eq(r, "not_priest")
end

T["SelectContext priority"] = function(t)
    local cfg = Cfg()
    t.eq(Core.SelectContext(cfg, { inRaid = true, inGroup = true, focusValid = true }), "focus")
    t.eq(Core.SelectContext(cfg, { inRaid = false, inGroup = true, focusValid = true }), "focus")
    t.eq(Core.SelectContext(cfg, { inRaid = true, inGroup = true, focusValid = false }), "raid")
    t.eq(Core.SelectContext(cfg, { inRaid = false, inGroup = true, focusValid = false }), "dungeon")
    t.eq(Core.SelectContext(cfg, { inRaid = false, inGroup = false, focusValid = false }), nil)
    cfg.contexts.focus.enabled = false
    t.eq(Core.SelectContext(cfg, { inRaid = true, inGroup = true, focusValid = true }), "raid")
    t.eq(Core.SelectContext(cfg, { inRaid = false, inGroup = true, focusValid = true }), "dungeon")
    cfg.contexts.raid.enabled = false
    t.eq(Core.SelectContext(cfg, { inRaid = true, inGroup = true, focusValid = false }), nil, "no fall-through")
    cfg.contexts.dungeon.enabled = false
    t.eq(Core.SelectContext(cfg, { inRaid = false, inGroup = true, focusValid = false }), nil)
end

T["SelectContext solo with focus"] = function(t)
    t.eq(Core.SelectContext(Cfg(), { inRaid = false, inGroup = false, focusValid = true }), "focus")
end

T["ShouldTrackUnit roles"] = function(t)
    local cfg = Cfg()
    t.eq(Core.ShouldTrackUnit({ name = "A-R", role = "TANK" }, cfg, "raid"), false)
    t.eq(Core.ShouldTrackUnit({ name = "A-R", role = "HEALER" }, cfg, "raid"), false)
    t.eq(Core.ShouldTrackUnit({ name = "A-R", role = "DAMAGER" }, cfg, "raid"), true)
    t.eq(Core.ShouldTrackUnit({ name = "A-R", role = "NONE" }, cfg, "dungeon"), true)
end

T["ShouldTrackUnit self and list"] = function(t)
    local cfg = Cfg({ trackedPlayers = { "Tanky-Realm", "Me-Realm" } })
    t.eq(Core.ShouldTrackUnit({ name = "Other-Realm", role = "DAMAGER", isSelf = true }, cfg, "raid"), false)
    t.eq(Core.ShouldTrackUnit({ name = "me-realm", role = "HEALER", isSelf = true }, cfg, "raid"), true)
    t.eq(Core.ShouldTrackUnit({ name = "TANKY-REALM", role = "TANK" }, cfg, "raid"), true)
    cfg.contexts.raid.trackMode = "list"
    t.eq(Core.ShouldTrackUnit({ name = "Tanky-Realm", role = "TANK" }, cfg, "raid"), true)
    t.eq(Core.ShouldTrackUnit({ name = "Dps-Realm", role = "DAMAGER" }, cfg, "raid"), false)
    t.eq(Core.ShouldTrackUnit({ name = "Dps-Realm", role = "DAMAGER" }, cfg, "dungeon"), true)
end

T["ShouldTrackUnit focus always"] = function(t)
    local cfg = Cfg()
    t.eq(Core.ShouldTrackUnit({ name = "X-R", role = "TANK", isSelf = false }, cfg, "focus"), true)
    t.eq(Core.ShouldTrackUnit({ name = nil, role = "HEALER" }, cfg, "focus"), true)
end

T["Name matching adds realm"] = function(t)
    local cfg = Cfg({ trackedPlayers = { (Core.NormalizeName("Friend", "Silvermoon")) } })
    local norm = Core.NormalizeName("FRIEND", "Silvermoon")
    t.eq(Core.ShouldTrackUnit({ name = norm, role = "TANK" }, cfg, "raid"), true)
end

T["NormalizeName"] = function(t)
    t.eq(Core.NormalizeName("  Bob  ", "Realm"), "Bob-Realm")
    t.eq(Core.NormalizeName("Bob-Other", "Realm"), "Bob-Other")
    t.eq(Core.NormalizeName("", "Realm"), nil)
    t.eq(Core.NormalizeName("   ", "Realm"), nil)
    t.eq(Core.NormalizeName(string.rep("a", 65), "Realm"), nil)
    t.eq(Core.NormalizeName("Bo|cffb", "Realm"), nil)
    t.eq(Core.NormalizeName("Bo\1b", "Realm"), nil)
    t.eq(Core.NormalizeName("Bo\nb", "Realm"), nil)
    t.eq(Core.NormalizeName(nil, "Realm"), nil)
    t.eq(Core.NormalizeName(42, "Realm"), nil)
end

T["Tracked players add/remove"] = function(t)
    local list = { "A-R" }
    local out, err = Core.AddTrackedPlayer(list, "b", "R")
    t.eq(err, nil); t.deepEq(out, { "A-R", "b-R" }); t.deepEq(list, { "A-R" }, "input untouched")
    local _, e2 = Core.AddTrackedPlayer(list, "a", "R")
    t.eq(e2, "Already listed.")
    local _, e3 = Core.AddTrackedPlayer(list, "x|y", "R")
    t.eq(e3, "Invalid name.")
    local full = {}
    for i = 1, 200 do full[i] = "P" .. i .. "-R" end
    local _, e4 = Core.AddTrackedPlayer(full, "New", "R")
    t.eq(e4, "List is full (200).")
    local rem, removed = Core.RemoveTrackedPlayer({ "A-R", "B-R" }, "a-r")
    t.ok(removed); t.deepEq(rem, { "B-R" })
    local _, removed2 = Core.RemoveTrackedPlayer({ "A-R" }, "Z-R")
    t.eq(removed2, false)
end

T["SnapOffset"] = function(t)
    local x, y = Core.SnapOffset(5, -7, 8); t.eq(x, 0); t.eq(y, 0)
    x, y = Core.SnapOffset(9, 3, 8); t.eq(x, 9); t.eq(y, 0)
    x, y = Core.SnapOffset(-8, 8, 8); t.eq(x, 0); t.eq(y, 0)
    x, y = Core.SnapOffset(100, 200, 8); t.eq(x, 100); t.eq(y, 200)
end

T["FormatDuration"] = function(t)
    t.eq(Core.FormatDuration(12.7), "12")
    t.eq(Core.FormatDuration(10), "10")
    t.eq(Core.FormatDuration(9.96), "10.0")
    t.eq(Core.FormatDuration(4.24), "4.2")
    t.eq(Core.FormatDuration(0), nil)
    t.eq(Core.FormatDuration(nil), nil)
end

T["PickHighlight"] = function(t)
    local a = { id = 1 }
    local b = { id = 2, expirationTime = 10 }
    local c = { id = 3, expirationTime = 20 }
    t.eq(Core.PickHighlight({ a, b, c }), c)
    t.eq(Core.PickHighlight({ a, { id = 4 } }), a)
    t.eq(Core.PickHighlight({}), nil)
end

T["IsSecret without client"] = function(t)
    t.eq(Core.IsSecret(5), false)
end

return T
