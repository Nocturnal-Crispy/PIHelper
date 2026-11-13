-- tests/test_gate.lua: PI-ready gate and grace window (spec 7.3).
local ns = ...
local Core = ns.CDCore

local NOW = 1000

local function Gate(over)
    local i = { applies = true, now = NOW, grace = 5, lastDuration = 120 }
    for k, v in pairs(over or {}) do i[k] = v end
    return Core.ComputePIGate(i)
end

-- Readable active cooldown with `rem` seconds left.
local function Active(rem)
    return { readable = true, isActive = true, isOnGCD = false, startTime = NOW + rem - 120, duration = 120 }
end

local function Expect(t, g, allowed, reason, label)
    t.eq(g.allowed, allowed, (label or "") .. " allowed")
    t.eq(g.reason, reason, (label or "") .. " reason")
end

local T = {}

T["not applicable"] = function(t)
    Expect(t, Gate({ applies = false, cd = Active(60) }), true, "n/a")
end

T["readable inactive is ready"] = function(t)
    Expect(t, Gate({ cd = { readable = true, isActive = false } }), true, "ready")
end

T["active only because of GCD is ready"] = function(t)
    Expect(t, Gate({ cd = { readable = true, isActive = true, isOnGCD = true, startTime = NOW, duration = 1.5 } }),
        true, "ready")
end

T["remaining vs grace"] = function(t)
    Expect(t, Gate({ cd = Active(20) }), false, "cooldown", "20s")
    local g = Gate({ cd = Active(5) })
    Expect(t, g, true, "grace", "5s inclusive")
    t.eq(g.remaining, 5)
    Expect(t, Gate({ cd = Active(4.9) }), true, "grace", "4.9s")
    Expect(t, Gate({ cd = Active(0) }), true, "ready", "0s")
end

T["grace zero"] = function(t)
    Expect(t, Gate({ grace = 0, cd = Active(0.5) }), false, "cooldown")
    Expect(t, Gate({ grace = 0, cd = Active(0) }), true, "ready")
end

T["readable with secret numbers uses cast estimate"] = function(t)
    local cd = { readable = true, isActive = true, isOnGCD = false } -- numbers withheld (secret)
    Expect(t, Gate({ cd = cd, castAt = NOW - 117 }), true, "grace", "3s left")
    Expect(t, Gate({ cd = cd, castAt = NOW - 10 }), false, "cooldown", "110s left")
end

T["readable short duration ignored"] = function(t)
    local cd = { readable = true, isActive = true, isOnGCD = false, startTime = NOW, duration = 1.5 }
    Expect(t, Gate({ cd = cd, castAt = NOW - 118 }), true, "grace")
end

T["readable no timing no cast is cooldown"] = function(t)
    Expect(t, Gate({ cd = { readable = true, isActive = true, isOnGCD = false } }), false, "cooldown")
end

T["unreadable with cast inside window"] = function(t)
    local cd = { readable = false }
    Expect(t, Gate({ cd = cd, castAt = NOW - 60 }), false, "cooldown")
    Expect(t, Gate({ cd = cd, castAt = NOW - 116 }), true, "grace")
    Expect(t, Gate({ cd = nil, castAt = NOW - 60 }), false, "cooldown", "nil cd")
end

T["unreadable after estimate ends"] = function(t)
    Expect(t, Gate({ cd = { readable = false }, castAt = NOW - 121 }), true, "ready_est")
    Expect(t, Gate({ cd = { readable = false }, castAt = NOW - 120 }), true, "ready_est", "exact")
end

T["unreadable no cast fails open"] = function(t)
    Expect(t, Gate({ cd = { readable = false } }), true, "unknown")
    Expect(t, Gate({ cd = nil }), true, "unknown")
end

T["lastDuration override"] = function(t)
    local cd = { readable = false }
    Expect(t, Gate({ cd = cd, castAt = NOW - 85, lastDuration = 90 }), true, "grace")
    Expect(t, Gate({ cd = cd, castAt = NOW - 85 }), false, "cooldown", "default 120")
    Expect(t, Gate({ cd = cd, castAt = NOW - 85, lastDuration = nil }), false, "cooldown")
end

return T
