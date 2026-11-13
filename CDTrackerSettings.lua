-- CDTrackerSettings.lua
-- Settings operations shared by the options pages and slash commands: buff
-- scopes, custom IDs, tracked players, spell names, profiles and the test
-- highlight. Every write goes through ns.CD.ApplySettingsChange.

local _, ns = ...

local CD, Core, Data = ns.CD, ns.CDCore, ns.CDData
local Serialize, Glow, Alert, Frames = ns.CDSerialize, ns.CDGlow, ns.CDAlert, ns.CDFrames
local Plain = CD.Plain

-- --- Buff scopes -------------------------------------------------------------
-- scope is "shared" or a context key ("raid", "dungeon", "focus").

local function IsContext(scope)
    return scope == "raid" or scope == "dungeon" or scope == "focus"
end
CD.IsContextScope = IsContext

function CD.BuffsFor(scope, cfg)
    cfg = cfg or CD.GetConfig()
    if IsContext(scope) then return cfg.contexts[scope].buffs end
    return cfg.buffs
end

local function SetBuffs(cfg, scope, buffs)
    if IsContext(scope) then cfg.contexts[scope].buffs = buffs else cfg.buffs = buffs end
end

local function IsPristine(buffs)
    return next(buffs.disabled) == nil and not buffs.potions and #buffs.custom == 0
end

-- Switching own buffs on for the first time (context buffs never customized)
-- seeds them with a copy of the shared buffs (spec 4.4).
local function EnableOwnBuffs(cfg, ctx)
    local c = cfg.contexts[ctx]
    if not c.useOwnBuffs and IsPristine(c.buffs) then c.buffs = Core.DeepCopy(cfg.buffs) end
    c.useOwnBuffs = true
end

function CD.SetUseOwnBuffs(ctx, on)
    if not IsContext(ctx) then return end
    CD.ApplySettingsChange(function(cfg)
        if on then EnableOwnBuffs(cfg, ctx) else cfg.contexts[ctx].useOwnBuffs = false end
    end)
end

function CD.SetBuffEnabled(scope, id, enabled)
    CD.ApplySettingsChange(function(cfg)
        CD.BuffsFor(scope, cfg).disabled[id] = (not enabled) and true or nil
    end)
end

function CD.SetPotions(scope, on)
    CD.ApplySettingsChange(function(cfg)
        CD.BuffsFor(scope, cfg).potions = on and true or false
    end)
end

-- --- Spell names -------------------------------------------------------------

local pendingLoads = {}

function CD.SpellName(id)
    local name
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if type(info) == "table" and not (issecrettable and issecrettable(info)) then name = Plain(info.name) end
    end
    if type(name) ~= "string" and C_Spell and C_Spell.GetSpellName then name = Plain(C_Spell.GetSpellName(id)) end
    if type(name) == "string" and name ~= "" then return name end
    if C_Spell and C_Spell.RequestLoadSpellData and not pendingLoads[id] then
        pendingLoads[id] = true
        CD.eventFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
        C_Spell.RequestLoadSpellData(id)
    end
    return "Spell #" .. id
end

-- Only registered while a load we asked for is outstanding.
function CD.OnSpellDataLoaded(spellID)
    spellID = Plain(spellID)
    if spellID == nil or not pendingLoads[spellID] then return end
    pendingLoads[spellID] = nil
    if next(pendingLoads) == nil then CD.eventFrame:UnregisterEvent("SPELL_DATA_LOAD_RESULT") end
    if ns.UI then ns.UI.Refresh() end
end

-- --- Custom IDs --------------------------------------------------------------

function CD.AddCustomID(text, scope)
    local id, err = Core.ValidateSpellIDInput(text)
    if not id then return false, err end
    if C_Spell and C_Spell.DoesSpellExist and Plain(C_Spell.DoesSpellExist(id)) == false then
        return false, "Unknown spell ID."
    end
    local cfg = CD.GetConfig()
    local work = Core.DeepCopy(cfg)
    if IsContext(scope) then EnableOwnBuffs(work, scope) end
    local newBuffs, aerr = Core.AddCustomID(CD.BuffsFor(scope, work), id, Data)
    if not newBuffs then return false, aerr end
    CD.ApplySettingsChange(function(c)
        if IsContext(scope) then EnableOwnBuffs(c, scope) end
        SetBuffs(c, scope, newBuffs)
    end)
    return true, "Added " .. CD.SpellName(id) .. " (" .. id .. ")."
end

function CD.RemoveCustomID(idOrText, scope)
    local id = idOrText
    if type(id) ~= "number" then
        local err
        id, err = Core.ValidateSpellIDInput(idOrText)
        if not id then return false, err end
    end
    local cfg = CD.GetConfig()
    local work = Core.DeepCopy(cfg)
    if IsContext(scope) then EnableOwnBuffs(work, scope) end
    local newBuffs, removed = Core.RemoveCustomID(CD.BuffsFor(scope, work), id)
    if not removed then return false, "Spell ID " .. id .. " is not a custom ID." end
    CD.ApplySettingsChange(function(c)
        if IsContext(scope) then EnableOwnBuffs(c, scope) end
        SetBuffs(c, scope, newBuffs)
    end)
    return true, "Removed " .. id .. "."
end

-- --- Tracked players ---------------------------------------------------------

function CD.AddTrackedPlayer(name)
    local realm = GetNormalizedRealmName and Plain(GetNormalizedRealmName()) or nil
    local list, err = Core.AddTrackedPlayer(CD.GetConfig().trackedPlayers, name, realm)
    if not list then return false, err end
    CD.ApplySettingsChange(function(c) c.trackedPlayers = list end)
    return true
end

function CD.AddTrackedPlayerFromTarget()
    if Plain(UnitExists("target")) ~= true or Plain(UnitIsPlayer("target")) ~= true then
        return false, "No valid target."
    end
    local name = Plain(GetUnitName("target", true))
    if type(name) ~= "string" then return false, "Invalid name." end
    return CD.AddTrackedPlayer(name)
end

function CD.RemoveTrackedPlayer(name)
    local list, removed = Core.RemoveTrackedPlayer(CD.GetConfig().trackedPlayers, name)
    if removed then CD.ApplySettingsChange(function(c) c.trackedPlayers = list end) end
    return removed
end

-- --- Profiles ----------------------------------------------------------------

function CD.ExportString()
    return Serialize.ExportSettings(CD.GetConfig())
end

-- Applies a profile string. On failure nothing changes.
function CD.ImportString(text)
    local cfg, err = Serialize.ImportSettings(text, CD.GetConfig())
    if not cfg then
        CD.PrintError(err)
        return false, err
    end
    PIHelperDB.cdTracker = cfg
    CD.ApplySettingsChange()
    Frames.RequestResolve()
    CD.Print("Profile imported.")
    return true
end

-- Resets the profile but keeps the alert position and minimap settings.
function CD.ResetToDefaults()
    local cur = CD.GetConfig()
    local fresh = Core.DeepCopy(Core.DEFAULTS)
    fresh.alert = Core.DeepCopy(cur.alert)
    fresh.minimap = Core.DeepCopy(cur.minimap)
    PIHelperDB.cdTracker = fresh
    CD.ApplySettingsChange()
    Frames.RequestResolve()
end

-- --- Test highlight ----------------------------------------------------------

local test -- { overlays, ticker, untilTime }

local function PlayerFrames()
    local list = {}
    local seen = {}
    local function AddAll(token)
        for _, f in ipairs(Frames.GetFrames(token)) do
            if not seen[f] then seen[f] = true; list[#list + 1] = f end
        end
    end
    AddAll("player")
    local idx = Plain(UnitInRaid and UnitInRaid("player"))
    if type(idx) == "number" then AddAll("raid" .. idx) end
    return list
end

local function EndTest()
    if not test then return end
    test.ticker:Cancel()
    for ov in pairs(test.overlays) do
        CD.state.testOverlays[ov] = nil
        Glow.Hide(ov)
    end
    test = nil
    CD.RefreshVisuals()
end

local function TestText(ctxCfg)
    local mode = ctxCfg.durationText
    if mode ~= "frame" and mode ~= "both" then return "" end
    return Core.FormatDuration(test.untilTime - GetTime()) or ""
end

-- A fake highlight on the player's own frames plus the alert, ignoring the
-- run condition and the PI gate. ctx defaults to the current context (raid
-- when there is none).
function CD.Test(seconds, ctx)
    seconds = seconds or 10
    EndTest()
    Frames.ResolveAll()
    local cfg = CD.GetConfig()
    local ctxCfg = cfg.contexts[IsContext(ctx) and ctx or CD.DisplayContext()]
    local now = GetTime()
    test = { overlays = {}, untilTime = now + seconds }
    local timing = { start = now, duration = seconds }
    for _, f in ipairs(PlayerFrames()) do
        local ov = Glow.Acquire(f)
        Glow.Show(ov, ctxCfg.glowStyle, ctxCfg.glowColor, timing, cfg.glowThickness)
        test.overlays[ov] = true
        CD.state.testOverlays[ov] = true
    end
    local function Update()
        if not test then return end
        if GetTime() >= test.untilTime then EndTest() return end
        local text = TestText(ctxCfg)
        for ov in pairs(test.overlays) do Glow.SetText(ov, text) end
    end
    test.ticker = C_Timer.NewTicker(0.1, Update)
    Update()
    Alert.Test(seconds)
    local n = 0
    for _ in pairs(test.overlays) do n = n + 1 end
    return n
end
