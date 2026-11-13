-- tests/test_buffs.lua: buff resolution and custom ID validation (spec 4, 5).
local ns = ...
local Core, Data = ns.CDCore, ns.CDData

local function Cfg() return Core.DeepCopy(Core.DEFAULTS) end

local function Count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

local function CatalogCount()
    local n = 0
    for _, e in ipairs(Data.CATALOG) do n = n + #e.spells end
    return n
end

local T = {}

T["catalog included by default"] = function(t)
    local set, list = Core.ResolveBuffSet(Cfg(), "raid", Data)
    t.eq(Count(set), CatalogCount())
    t.eq(#list, CatalogCount())
    t.ok(set[51271] and set[1719] and set[375087])
    t.eq(set[1236616], nil, "potions off by default")
end

T["catalog matches spec"] = function(t)
    t.eq(Data.PI_SPELL_ID, 10060)
    t.ok(Data.HEALER_SPEC_IDS[256] and Data.HEALER_SPEC_IDS[257])
    t.eq(CatalogCount(), 29)
    t.eq(#Data.POTIONS, 4)
end

T["disabled excluded"] = function(t)
    local cfg = Cfg()
    cfg.buffs.disabled[51271] = true
    local set = Core.ResolveBuffSet(cfg, "raid", Data)
    t.eq(set[51271], nil)
    t.ok(set[47568])
end

T["potions toggle as a group"] = function(t)
    local cfg = Cfg()
    cfg.buffs.potions = true
    local set = Core.ResolveBuffSet(cfg, "dungeon", Data)
    for _, p in ipairs(Data.POTIONS) do t.ok(set[p.id], "potion " .. p.id) end
end

T["custom included and deduplicated"] = function(t)
    local cfg = Cfg()
    cfg.buffs.custom = { 999999, 5 }
    cfg.buffs.potions = true
    local set, list = Core.ResolveBuffSet(cfg, "raid", Data)
    t.ok(set[999999] and set[5])
    t.eq(#list, CatalogCount() + #Data.POTIONS + 2)
    for i = 2, #list do t.ok(list[i - 1] < list[i], "sorted and unique") end
end

T["shared versus own buffs"] = function(t)
    local cfg = Cfg()
    cfg.buffs.custom = { 777 }
    cfg.contexts.raid.buffs.custom = { 888 }
    local s1 = Core.ResolveBuffSet(cfg, "raid", Data)
    t.ok(s1[777]); t.eq(s1[888], nil)
    cfg.contexts.raid.useOwnBuffs = true
    local s2 = Core.ResolveBuffSet(cfg, "raid", Data)
    t.ok(s2[888]); t.eq(s2[777], nil)
    local s3 = Core.ResolveBuffSet(cfg, "dungeon", Data)
    t.ok(s3[777], "other contexts stay shared")
end

T["class spell ids"] = function(t)
    local set = Core.ClassSpellIDs(Data, "MAGE")
    t.ok(set[190319] and set[12472] and set[365362])
    t.eq(set[51271], nil)
    t.eq(next(Core.ClassSpellIDs(Data, "WARLOCK")), nil)
end

T["ValidateSpellIDInput accepts"] = function(t)
    t.eq(Core.ValidateSpellIDInput("123"), 123)
    t.eq(Core.ValidateSpellIDInput(" 456 "), 456)
    t.eq(Core.ValidateSpellIDInput("0123"), 123)
    t.eq(Core.ValidateSpellIDInput("999999999"), 999999999)
end

T["ValidateSpellIDInput rejects"] = function(t)
    local cases = {
        { "", "Enter a spell ID." }, { nil, "Enter a spell ID." }, { "   ", "Enter a spell ID." },
        { "abc", "Spell ID must be a whole number." }, { "12a", "Spell ID must be a whole number." },
        { "-5", "Spell ID must be a whole number." }, { "1.5", "Spell ID must be a whole number." },
        { "1e5", "Spell ID must be a whole number." }, { "0x10", "Spell ID must be a whole number." },
        { "1 2", "Spell ID must be a whole number." },
        { "0", "Spell ID out of range." }, { "9999999999", "Spell ID out of range." },
        { "99999999999", "Spell ID out of range." }, { "2147483648", "Spell ID out of range." },
    }
    for _, c in ipairs(cases) do
        local id, err = Core.ValidateSpellIDInput(c[1])
        t.eq(id, nil, tostring(c[1]))
        t.eq(err, c[2], tostring(c[1]))
    end
end

T["AddCustomID"] = function(t)
    local buffs = { disabled = {}, potions = false, custom = { 100 } }
    local out, err = Core.AddCustomID(buffs, 200, Data)
    t.eq(err, nil)
    t.deepEq(out.custom, { 100, 200 })
    t.deepEq(buffs.custom, { 100 }, "input not mutated")
    t.ok(out ~= buffs and out.custom ~= buffs.custom)
    local _, e1 = Core.AddCustomID(buffs, 100, Data)
    t.eq(e1, "Already tracked.")
    local _, e2 = Core.AddCustomID(buffs, 51271, Data)
    t.eq(e2, "That is a default buff; enable it in the list instead.")
    local _, e3 = Core.AddCustomID(buffs, 1236616, Data)
    t.eq(e3, "That is a default buff; enable it in the list instead.", "potion")
end

T["AddCustomID limit"] = function(t)
    local buffs = { disabled = {}, potions = false, custom = {} }
    for i = 1, 100 do
        local nb, err = Core.AddCustomID(buffs, 5000000 + i, Data)
        t.eq(err, nil)
        buffs = nb
    end
    local before = #buffs.custom
    local out, err = Core.AddCustomID(buffs, 6000000, Data)
    t.eq(out, nil)
    t.eq(err, "Custom ID limit (100) reached.")
    t.eq(#buffs.custom, before)
end

T["RemoveCustomID"] = function(t)
    local buffs = { disabled = { [51271] = true }, potions = true, custom = { 1, 2, 3 } }
    local out, removed = Core.RemoveCustomID(buffs, 2)
    t.ok(removed)
    t.deepEq(out.custom, { 1, 3 })
    t.deepEq(buffs.custom, { 1, 2, 3 }, "input not mutated")
    t.eq(out.potions, true)
    t.eq(out.disabled[51271], true)
    local out2, removed2 = Core.RemoveCustomID(buffs, 9)
    t.eq(removed2, false)
    t.deepEq(out2.custom, { 1, 2, 3 })
end

return T
