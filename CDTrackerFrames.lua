-- CDTrackerFrames.lua
-- Maps group unit tokens to the raid/party frames that display them, across
-- Blizzard and the supported frame addons. Read-only: frames owned by others
-- are only inspected, never modified. Event wiring lives in CDTracker.lua.

local _, ns = ...

local Core = ns.CDCore
local IsSecret = Core.IsSecret

local Frames = {}
ns.CDFrames = Frames

local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

local GENERIC_ADDONS = { "DandersFrames", "EllesmereUI", "EllesmereUIRaidFrames", "BuzzardFrames", "MichsRaidFrames" }
local GENERIC_PREFIXES = { "Danders", "Ellesmere", "EUI_", "Buzzard", "Mich" }
local PROVIDER_ADDONS = {
    ElvUI = true, Grid2 = true, Cell = true, VuhDo = true,
    DandersFrames = true, EllesmereUI = true, EllesmereUIRaidFrames = true,
    BuzzardFrames = true, MichsRaidFrames = true,
}
local GENERIC_INTERVAL = 2
local DEBOUNCE = 0.5

local unitFrames = {}    -- token -> { frame, ... }
local claimed = {}       -- frame -> provider key
local counts = {}        -- provider key -> n
local resolved = {}      -- ordered { provider, unit, name }
local genericCache = {}  -- frames found by the last generic scan
local lastGenericScan = -math.huge
local genericPending = false   -- a scan was skipped because of combat
local genericRetry = false     -- a throttled scan is scheduled
local resolveTimer

-- --- Unit reading ------------------------------------------------------------

local function ValidUnit(u)
    if IsSecret(u) or type(u) ~= "string" then return nil end
    if u == "player" or u:find("^raid%d+$") or u:find("^party[1-4]$") then return u end
    return nil
end

local function Field(frame, key)
    local v = frame[key]
    if IsSecret(v) then return nil end
    return v
end

-- displayedUnit, then unit, then the "unit" attribute.
local function FrameUnit(frame)
    if type(frame) ~= "table" then return nil end
    if frame.IsForbidden and frame:IsForbidden() then return nil end
    local u = Field(frame, "displayedUnit")
    if u == nil then u = Field(frame, "unit") end
    if u == nil and frame.GetAttribute then
        u = frame:GetAttribute("unit")
    end
    return ValidUnit(u)
end
Frames.FrameUnit = FrameUnit

local function Add(frame, key)
    if type(frame) ~= "table" or claimed[frame] then return end
    local unit = FrameUnit(frame)
    if not unit then return end
    claimed[frame] = key
    local list = unitFrames[unit]
    if not list then
        list = {}
        unitFrames[unit] = list
    end
    list[#list + 1] = frame
    counts[key] = (counts[key] or 0) + 1
    local name = frame.GetName and frame:GetName()
    resolved[#resolved + 1] = { provider = key, unit = unit, name = name or "(unnamed)" }
end

local function AddNamed(name, key)
    Add(_G[name], key)
end

-- --- Providers ---------------------------------------------------------------

local function EnumBlizzard(key)
    for i = 1, 5 do AddNamed("CompactPartyFrameMember" .. i, key) end
    for i = 1, 80 do AddNamed("CompactRaidFrame" .. i, key) end
    for g = 1, 8 do
        for m = 1, 5 do AddNamed("CompactRaidGroup" .. g .. "Member" .. m, key) end
    end
end

local function EnumElvUI(key)
    for i = 1, 5 do AddNamed("ElvUF_PartyGroup1UnitButton" .. i, key) end
    for r = 1, 3 do
        for g = 1, 8 do
            for i = 1, 5 do AddNamed("ElvUF_Raid" .. r .. "Group" .. g .. "UnitButton" .. i, key) end
        end
    end
    for g = 1, 8 do
        for i = 1, 5 do
            AddNamed("ElvUF_RaidGroup" .. g .. "UnitButton" .. i, key)
            AddNamed("ElvUF_Raid40Group" .. g .. "UnitButton" .. i, key)
        end
    end
end

local function EnumGrid2(key)
    for h = 1, 20 do
        for i = 1, 40 do
            local f = _G["Grid2LayoutHeader" .. h .. "UnitButton" .. i]
            if not f then break end
            Add(f, key)
        end
    end
end

local function EnumCell(key)
    for i = 1, 5 do AddNamed("CellPartyFrameHeaderUnitButton" .. i, key) end
    for h = 0, 8 do
        for i = 1, 5 do AddNamed("CellRaidFrameHeader" .. h .. "UnitButton" .. i, key) end
    end
    AddNamed("CellSoloFramePlayer", key)
end

local function VuhDoFn()
    return _G.VUHDO_getUnitButtons or _G.VUHDO_getUnitButtonsSafe
end

local function CandidateTokens()
    local list = { "player" }
    for i = 1, 4 do list[#list + 1] = "party" .. i end
    for i = 1, 40 do list[#list + 1] = "raid" .. i end
    return list
end

local function EnumVuhDo(key)
    local fn = VuhDoFn()
    for _, unit in ipairs(CandidateTokens()) do
        local ok, buttons = pcall(fn, unit)
        if ok and type(buttons) == "table" then
            for k, b in pairs(buttons) do Add(type(b) == "table" and b or k, key) end
        end
    end
end

local function Loaded(name)
    return IsAddOnLoaded and IsAddOnLoaded(name) and true or false
end

local function CustomPrefix()
    local cfg = ns.CD and ns.CD.GetConfig()
    return cfg and cfg.customFramePrefix or ""
end

local function GenericAvailable()
    if CustomPrefix() ~= "" then return true end
    for _, name in ipairs(GENERIC_ADDONS) do
        if Loaded(name) then return true end
    end
    return Loaded("VuhDo") and VuhDoFn() == nil
end

local function NameMatches(name, prefix)
    if type(name) ~= "string" then return false end
    for _, p in ipairs(GENERIC_PREFIXES) do
        if name:sub(1, #p) == p then return true end
    end
    return prefix ~= "" and name:sub(1, #prefix) == prefix
end

local function ParentShowsGroups(frame)
    local parent = frame.GetParent and frame:GetParent()
    if type(parent) ~= "table" then return false end
    return (Field(parent, "showRaid") or Field(parent, "showParty") or Field(parent, "showPlayer")) and true or false
end

local function ScanGeneric()
    local prefix = CustomPrefix()
    local found = {}
    local f = EnumerateFrames()
    while f do
        if not claimed[f] and f.IsObjectType and f:IsObjectType("Button") and FrameUnit(f)
            and (ParentShowsGroups(f) or NameMatches(f:GetName(), prefix)) then
            found[#found + 1] = f
        end
        f = EnumerateFrames(f)
    end
    genericCache = found
    lastGenericScan = GetTime()
    genericPending = false
end

-- The generic scan walks every frame: at most every 2 s and never in combat.
local function EnumGeneric(key)
    if InCombatLockdown() then
        genericPending = true
    elseif GetTime() - lastGenericScan >= GENERIC_INTERVAL then
        ScanGeneric()
    elseif not genericRetry then
        genericRetry = true
        C_Timer.After(GENERIC_INTERVAL, function()
            genericRetry = false
            Frames.RequestResolve(0)
        end)
    end
    for _, f in ipairs(genericCache) do Add(f, key) end
end

local PROVIDERS = {
    { key = "blizzard", label = "Blizzard", available = function() return true end, enum = EnumBlizzard },
    { key = "elvui", label = "ElvUI", available = function() return _G.ElvUI ~= nil end, enum = EnumElvUI },
    { key = "grid2", label = "Grid2", available = function() return _G.Grid2 ~= nil end, enum = EnumGrid2 },
    { key = "cell", label = "Cell", available = function() return _G.Cell ~= nil end, enum = EnumCell },
    { key = "vuhdo", label = "VuhDo", available = function() return VuhDoFn() ~= nil end, enum = EnumVuhDo },
    { key = "generic", label = "Other (generic scan)", available = GenericAvailable, enum = EnumGeneric },
}

-- --- Public API --------------------------------------------------------------

function Frames.ResolveAll()
    unitFrames, claimed, counts, resolved = {}, {}, {}, {}
    for _, p in ipairs(PROVIDERS) do
        if p.available() then p.enum(p.key) end
    end
    if ns.CD and ns.CD.OnFramesResolved then ns.CD.OnFramesResolved() end
end

-- Debounced re-resolve; delay 0 resolves immediately.
function Frames.RequestResolve(delay)
    if delay == 0 then
        if resolveTimer then resolveTimer:Cancel() resolveTimer = nil end
        Frames.ResolveAll()
        return
    end
    if resolveTimer then resolveTimer:Cancel() end
    resolveTimer = C_Timer.NewTimer(delay or DEBOUNCE, function()
        resolveTimer = nil
        Frames.ResolveAll()
    end)
end

-- Frames currently showing `token`. A cached frame whose unit changed is
-- dropped and triggers a re-resolve.
function Frames.GetFrames(token)
    local list = unitFrames[token]
    if not list then return {} end
    local out, stale = {}, false
    for _, f in ipairs(list) do
        if FrameUnit(f) == token then out[#out + 1] = f else stale = true end
    end
    if stale then Frames.RequestResolve() end
    return out
end

function Frames.GetProviderStats()
    local out = {}
    for _, p in ipairs(PROVIDERS) do
        out[#out + 1] = { key = p.key, label = p.label, loaded = p.available() and true or false, count = counts[p.key] or 0 }
    end
    return out
end

function Frames.ListResolved()
    local out = {}
    for i, r in ipairs(resolved) do out[i] = { provider = r.provider, unit = r.unit, name = r.name } end
    return out
end

function Frames.IsProviderAddon(name)
    return type(name) == "string" and PROVIDER_ADDONS[name] == true
end

function Frames.OnRegenEnabled()
    if genericPending then Frames.RequestResolve(0) end
end

local function Usable(v)
    return v ~= nil and not IsSecret(v)
end

local function NameOf(unit)
    local n = GetUnitName(unit, true)
    if not Usable(n) then return nil end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not Usable(realm) then realm = nil end
    local norm = Core.NormalizeName(n, realm)
    return norm and norm:lower() or nil
end

-- The group token whose frames show the focus target, or nil.
function Frames.FindFocusToken()
    local guid = UnitGUID("focus")
    if Usable(guid) then
        for token in pairs(unitFrames) do
            local g = UnitGUID(token)
            if Usable(g) and g == guid then return token end
        end
    end
    local name = NameOf("focus")
    if not name then return nil end
    for token in pairs(unitFrames) do
        if NameOf(token) == name then return token end
    end
    return nil
end
