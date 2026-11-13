-- CDTracker.lua
-- CD tracker runtime: run condition, context selection, candidate units,
-- aura scanning under Midnight secret-value rules, highlight state, PI-ready
-- gate and rendering through CDGlow / CDAlert. Settings writes go through
-- ns.CD.ApplySettingsChange. Slash commands live in CDTrackerSlash.lua and
-- settings helpers in CDTrackerSettings.lua.

local _, ns = ...

local Core, Data = ns.CDCore, ns.CDData
local Frames, Glow, Alert, Media = ns.CDFrames, ns.CDGlow, ns.CDAlert, ns.CDMedia
local IsSecret = Core.IsSecret

local CD = {}
ns.CD = CD

local GetUnitAuraBySpellID = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
local PI = Data.PI_SPELL_ID
local SCAN_THROTTLE = 0.25
local TICK = 0.1
local GATE_POLL = 0.5
local SOUND_THROTTLE = 2
local ROSTER_SECOND_PASS = 2

local BASE_EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED", "TRAIT_CONFIG_UPDATED", "SPELLS_CHANGED",
}
local ACTIVE_EVENTS = {
    "UNIT_AURA", "SPELL_UPDATE_COOLDOWN", "GROUP_ROSTER_UPDATE", "PLAYER_FOCUS_CHANGED",
    "PLAYER_ROLES_ASSIGNED", "PLAYER_REGEN_ENABLED",
}

local S = {
    running = false, reason = "loading", context = nil, apiMissing = false,
    candidates = {}, highlights = {}, dirty = {}, flushPending = false, seq = 0,
    lastFullScan = -math.huge, scanScheduled = false,
    activeSet = {}, activeList = {}, perClass = {}, otherIDs = {},
    castAt = nil, lastDuration = 120, cd = nil, gate = { allowed = true, reason = "n/a" },
    rendered = {}, testOverlays = {}, alertKey = nil, lastSound = -math.huge,
}
CD.state = S

local ev = CreateFrame("Frame")

-- --- Helpers -----------------------------------------------------------------

function CD.GetConfig()
    return PIHelperDB and PIHelperDB.cdTracker
end

function CD.Print(msg) print("|cff00ccffPIHelper:|r " .. msg) end
function CD.PrintError(msg) print("|cffff4444PIHelper:|r " .. msg) end

-- Returns v when it is a readable, non-secret value; nil otherwise.
local function Plain(v)
    if IsSecret(v) then return nil end
    return v
end
CD.Plain = Plain

local function PlainNumber(v)
    v = Plain(v)
    if type(v) == "number" then return v end
    return nil
end

local function PlainBool(v)
    v = Plain(v)
    if type(v) == "boolean" then return v end
    return nil
end

local function PlayerRealm()
    return GetNormalizedRealmName and Plain(GetNormalizedRealmName()) or nil
end

local function UnitClassFile(unit)
    local _, classFile = UnitClass(unit)
    classFile = Plain(classFile)
    return type(classFile) == "string" and classFile or nil
end

local function UnitNormName(unit)
    local n = Plain(GetUnitName(unit, true))
    return Core.NormalizeName(n, PlayerRealm())
end

function CD.PIKnown()
    local known
    if C_SpellBook and C_SpellBook.IsSpellKnown then known = PlainBool(C_SpellBook.IsSpellKnown(PI)) end
    if known == nil and IsPlayerSpell then known = PlainBool(IsPlayerSpell(PI)) end
    return known == true
end

local function SpellIsSecret(id)
    if not (C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) then return false end
    return PlainBool(C_Secrets.ShouldSpellAuraBeSecret(id)) == true
end
CD.SpellIsSecret = SpellIsSecret

-- --- Events ------------------------------------------------------------------

local function SetActiveEvents(on)
    for _, e in ipairs(ACTIVE_EVENTS) do
        if on then ev:RegisterEvent(e) else ev:UnregisterEvent(e) end
    end
    if on then
        ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        ev:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end

-- --- Buff set and candidates -------------------------------------------------

local function RebuildBuffSet()
    local cfg = CD.GetConfig()
    S.activeSet, S.activeList = Core.ResolveBuffSet(cfg, S.context or "raid", Data)
    local catalogClass = {}
    for _, entry in ipairs(Data.CATALOG) do
        for _, sp in ipairs(entry.spells) do catalogClass[sp.id] = entry.class end
    end
    S.otherIDs, S.perClass = {}, {}
    for _, id in ipairs(S.activeList) do
        local class = catalogClass[id]
        if class then
            S.perClass[class] = S.perClass[class] or {}
            table.insert(S.perClass[class], id)
        else
            S.otherIDs[#S.otherIDs + 1] = id
        end
    end
end

local function ContextTokens(ctx)
    if ctx == "focus" then return { "focus" } end
    if ctx == "dungeon" then return { "player", "party1", "party2", "party3", "party4" } end
    local list = {}
    local n = PlainNumber(GetNumGroupMembers()) or 0
    for i = 1, n do list[i] = "raid" .. i end
    return list
end

local function IsSelf(token)
    if token == "player" then return true end
    return PlainBool(UnitIsUnit(token, "player")) == true
end

local function RebuildCandidates()
    local cfg = CD.GetConfig()
    S.candidates = {}
    if not S.context then return end
    for _, token in ipairs(ContextTokens(S.context)) do
        if PlainBool(UnitExists(token)) then
            local role = Plain(UnitGroupRolesAssigned(token))
            if type(role) ~= "string" then role = "NONE" end
            local info = { name = UnitNormName(token), role = role, isSelf = IsSelf(token) }
            if Core.ShouldTrackUnit(info, cfg, S.context) then
                S.candidates[token] = { name = info.name, classFile = UnitClassFile(token) }
            end
        end
    end
end

-- --- Aura scanning -----------------------------------------------------------

-- One aura lookup. Returns nil (absent) or an entry {id, expirationTime?, duration?, icon?}.
local function ReadAura(token, id)
    local ok, aura = pcall(GetUnitAuraBySpellID, token, id)
    if not ok then return nil end
    if IsSecret(aura) then return { id = id } end
    if type(aura) ~= "table" then return nil end
    if issecrettable and issecrettable(aura) then return { id = id } end
    local exp, dur = PlainNumber(aura.expirationTime), PlainNumber(aura.duration)
    if not exp or exp <= 0 or not dur or dur <= 0 then exp, dur = nil, nil end
    return { id = id, expirationTime = exp, duration = dur, icon = Plain(aura.icon) }
end

local function IDsFor(classFile)
    if not classFile then return S.activeList end
    local list = {}
    for _, id in ipairs(S.perClass[classFile] or {}) do list[#list + 1] = id end
    for _, id in ipairs(S.otherIDs) do list[#list + 1] = id end
    return list
end

local function PlayStartSound(ctxCfg)
    local cfg = CD.GetConfig()
    if not ctxCfg.playSound or not S.gate.allowed then return end
    local now = GetTime()
    if now - S.lastSound < SOUND_THROTTLE then return end
    S.lastSound = now
    Media.PlaySound(cfg.sound)
end

local function SetHighlight(token, entry, cand)
    local prev = S.highlights[token]
    if not entry then
        S.highlights[token] = nil
        return
    end
    local h = {
        id = entry.id, expirationTime = entry.expirationTime, duration = entry.duration,
        icon = entry.icon, name = cand.name, classFile = cand.classFile,
    }
    if entry.expirationTime then h.start = entry.expirationTime - entry.duration end
    if prev then
        h.seq = prev.seq
    else
        S.seq = S.seq + 1
        h.seq = S.seq
        PlayStartSound(CD.GetConfig().contexts[S.context])
    end
    S.highlights[token] = h
end

local function ScanUnit(token)
    local cand = S.candidates[token]
    if not cand or not GetUnitAuraBySpellID then
        S.highlights[token] = nil
        return
    end
    local found = {}
    for _, id in ipairs(IDsFor(cand.classFile)) do
        if not SpellIsSecret(id) then
            local entry = ReadAura(token, id)
            if entry then found[#found + 1] = entry end
        end
    end
    SetHighlight(token, Core.PickHighlight(found), cand)
end

-- --- Rendering ---------------------------------------------------------------

local function FramesFor(token)
    if token == "focus" then
        local mapped = Frames.FindFocusToken()
        return mapped and Frames.GetFrames(mapped) or {}
    end
    return Frames.GetFrames(token)
end

local function NewestHighlight()
    local bestToken, best
    for token, h in pairs(S.highlights) do
        if not best or h.seq > best.seq then bestToken, best = token, h end
    end
    return bestToken, best
end

local function Timing(h)
    if h.start and h.duration then return { start = h.start, duration = h.duration } end
    return nil
end

local function FrameText(ctxCfg, h, now)
    local mode = ctxCfg.durationText
    if (mode ~= "frame" and mode ~= "both") or not h.expirationTime then return "" end
    return Core.FormatDuration(h.expirationTime - now) or ""
end

local function RenderGlows(cfg, ctxCfg, visible)
    local now = GetTime()
    local used, timed = {}, false
    if visible then
        for token, h in pairs(S.highlights) do
            for _, frame in ipairs(FramesFor(token)) do
                local ov = Glow.Acquire(frame)
                Glow.Show(ov, ctxCfg.glowStyle, ctxCfg.glowColor, Timing(h), cfg.glowThickness)
                Glow.SetText(ov, FrameText(ctxCfg, h, now))
                used[ov] = token
            end
            if h.expirationTime then timed = true end
        end
    end
    for ov in pairs(S.rendered) do
        if not used[ov] and not S.testOverlays[ov] then Glow.Hide(ov) end
    end
    S.rendered = used
    return timed
end

local function RenderAlert(ctxCfg, visible)
    local token, h = NewestHighlight()
    if not (visible and ctxCfg.showAlert and h) then
        if S.alertKey then Alert.Hide() end
        S.alertKey = nil
        return
    end
    local key = token .. ":" .. h.id .. ":" .. tostring(h.expirationTime)
    if key == S.alertKey then return end
    S.alertKey = key
    local mode = ctxCfg.durationText
    Alert.Show({ name = h.name or "", classFile = h.classFile, icon = h.icon, timing = Timing(h),
        showDuration = mode == "alert" or mode == "both" })
end

local Tick -- forward

local function SetTicker(on)
    if on and not S.ticker then
        S.ticker = C_Timer.NewTicker(TICK, Tick)
    elseif not on and S.ticker then
        S.ticker:Cancel()
        S.ticker = nil
    end
end

function CD.RefreshVisuals()
    local cfg = CD.GetConfig()
    local ctxCfg = cfg and S.context and cfg.contexts[S.context]
    if not (S.running and ctxCfg) then
        RenderGlows(cfg, nil, false)
        if S.alertKey then Alert.Hide() end
        S.alertKey = nil
        SetTicker(false)
        return
    end
    local visible = S.gate.allowed
    local timed = RenderGlows(cfg, ctxCfg, visible)
    RenderAlert(ctxCfg, visible)
    SetTicker(visible and timed)
end

local function ScheduleFlush() -- forward-declared use below
    if S.flushPending then return end
    S.flushPending = true
    C_Timer.After(0, function()
        S.flushPending = false
        local dirty = S.dirty
        S.dirty = {}
        for token in pairs(dirty) do ScanUnit(token) end
        CD.RefreshVisuals()
    end)
end

Tick = function()
    local cfg = CD.GetConfig()
    local ctxCfg = cfg and S.context and cfg.contexts[S.context]
    if not ctxCfg then SetTicker(false) return end
    local now = GetTime()
    local expired = false
    for token, h in pairs(S.highlights) do
        if h.expirationTime and h.expirationTime < now then
            S.highlights[token] = nil
            S.dirty[token] = true
            expired = true
        end
    end
    for ov, token in pairs(S.rendered) do
        local h = S.highlights[token]
        if h then Glow.SetText(ov, FrameText(ctxCfg, h, now)) end
    end
    if expired then ScheduleFlush() end
end

-- --- Full scans and context --------------------------------------------------

local function ClearHighlights()
    S.highlights, S.dirty = {}, {}
end

local function FullScanNow()
    S.lastFullScan = GetTime()
    if not (S.running and S.context) then
        ClearHighlights()
        CD.RefreshVisuals()
        return
    end
    RebuildBuffSet()
    RebuildCandidates()
    for token in pairs(S.highlights) do
        if not S.candidates[token] then S.highlights[token] = nil end
    end
    for token in pairs(S.candidates) do ScanUnit(token) end
    CD.RefreshVisuals()
end

-- Throttled to one per SCAN_THROTTLE; extra requests coalesce.
function CD.RequestFullScan()
    if S.scanScheduled then return end
    local wait = SCAN_THROTTLE - (GetTime() - S.lastFullScan)
    if wait <= 0 then
        FullScanNow()
        return
    end
    S.scanScheduled = true
    C_Timer.After(wait, function()
        S.scanScheduled = false
        FullScanNow()
    end)
end

local function FocusValid()
    if PlainBool(UnitExists("focus")) ~= true then return false end
    if PlainBool(UnitIsPlayer("focus")) ~= true then return false end
    if PlainBool(UnitIsFriend("player", "focus")) ~= true then return false end
    return PlainBool(UnitIsUnit("focus", "player")) == false
end

local function SelectContext()
    local cfg = CD.GetConfig()
    local gs = { inRaid = IsInRaid() and true or false, inGroup = IsInGroup() and true or false,
        focusValid = FocusValid() }
    local ctx = S.running and Core.SelectContext(cfg, gs) or nil
    if ctx ~= S.context then
        ClearHighlights()
        S.context = ctx
        S.alertKey = nil
        CD.RefreshVisuals()
        return true
    end
    return false
end

-- --- PI gate -----------------------------------------------------------------

local EvaluateGate -- forward

local function SetGatePoll(on)
    if on and not S.gatePoll then
        S.gatePoll = C_Timer.NewTicker(GATE_POLL, function()
            CD.ReadCooldown()
            EvaluateGate()
        end)
    elseif not on and S.gatePoll then
        S.gatePoll:Cancel()
        S.gatePoll = nil
    end
end

function CD.ReadCooldown()
    local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(PI)
    if type(info) ~= "table" or (issecrettable and issecrettable(info)) then
        S.cd = { readable = false }
        return
    end
    local isActive = PlainBool(info.isActive)
    local start, dur = PlainNumber(info.startTime), PlainNumber(info.duration)
    local onGCD = PlainBool(info.isOnGCD)
    if dur and dur > 1.5 and onGCD ~= true then S.lastDuration = dur end
    S.cd = { readable = isActive ~= nil, isActive = isActive, isOnGCD = onGCD, startTime = start, duration = dur }
end

EvaluateGate = function()
    local cfg = CD.GetConfig()
    if not cfg then return end
    local applies = S.running and cfg.requirePIReady and CD.PIKnown()
    local prev = S.gate
    S.gate = Core.ComputePIGate({
        applies = applies, now = GetTime(), grace = cfg.graceSeconds, cd = S.cd,
        castAt = S.castAt, lastDuration = S.lastDuration,
    })
    SetGatePoll(S.running and (S.gate.reason == "cooldown" or S.gate.reason == "grace"))
    if prev.allowed ~= S.gate.allowed then
        S.alertKey = nil
        CD.RefreshVisuals()
    end
    if prev.reason ~= S.gate.reason and ns.UI then ns.UI.Refresh() end
end
CD.EvaluateGate = EvaluateGate

-- --- Run condition -----------------------------------------------------------

local function PlayerInfo()
    local specID
    local idx = Plain(GetSpecialization and GetSpecialization())
    if type(idx) == "number" and idx > 0 then
        specID = PlainNumber((GetSpecializationInfo(idx)))
    end
    return { classFile = UnitClassFile("player"), specID = specID }
end

local function Start()
    S.running = true
    SetActiveEvents(true)
    Frames.RequestResolve(0)
    CD.ReadCooldown()
    SelectContext()
    EvaluateGate()
    CD.RequestFullScan()
end

local function Stop()
    S.running = false
    SetActiveEvents(false)
    SetGatePoll(false)
    ClearHighlights()
    S.context = nil
    CD.RefreshVisuals()
    Glow.HideAll()
    S.rendered = {}
end

function CD.Evaluate()
    local cfg = CD.GetConfig()
    if not cfg then return end
    local ok, reason = Core.ShouldRun(PlayerInfo(), cfg)
    if ok and S.apiMissing then ok, reason = false, "aura_api_missing" end
    local changed = reason ~= S.reason or ok ~= S.running
    S.reason = reason
    if ok and not S.running then Start() elseif not ok and S.running then Stop() end
    if changed and ns.UI then ns.UI.Refresh() end
end

-- --- Event handlers ----------------------------------------------------------

local function OnOwnAddonLoaded()
    if type(PIHelperDB) ~= "table" then PIHelperDB = {} end
    local _, newer = Core.Migrate(PIHelperDB)
    if newer then CD.Print("CD tracker settings are from a newer version; unknown options were reset.") end
    if not GetUnitAuraBySpellID then
        S.apiMissing = true
        CD.PrintError("CD tracker unavailable: aura API missing.")
    end
end

local function OnRoster()
    SelectContext()
    Frames.RequestResolve()
    C_Timer.After(ROSTER_SECOND_PASS, function()
        if S.running then Frames.RequestResolve() end
    end)
    CD.RequestFullScan()
end

local H = {}

function H.ADDON_LOADED(name)
    if name == "PIHelper" then
        OnOwnAddonLoaded()
    elseif S.running and Frames.IsProviderAddon(name) then
        Frames.RequestResolve()
    end
end

function H.PLAYER_LOGIN()
    if ns.CDMinimap then ns.CDMinimap.Init() end
    CD.Evaluate()
end

function H.PLAYER_ENTERING_WORLD()
    CD.Evaluate()
    if not S.running then return end
    Frames.RequestResolve()
    CD.ReadCooldown()
    EvaluateGate()
    SelectContext()
    CD.RequestFullScan()
end

function H.PLAYER_SPECIALIZATION_CHANGED(unit)
    if unit == "player" then CD.Evaluate() end
end
H.ACTIVE_TALENT_GROUP_CHANGED = function() CD.Evaluate() EvaluateGate() end
H.TRAIT_CONFIG_UPDATED = H.ACTIVE_TALENT_GROUP_CHANGED
H.SPELLS_CHANGED = H.ACTIVE_TALENT_GROUP_CHANGED

function H.UNIT_AURA(unit)
    if not S.context then return end
    if IsSecret(unit) then
        for token in pairs(S.candidates) do S.dirty[token] = true end
    elseif S.candidates[unit] then
        S.dirty[unit] = true
    elseif S.context == "focus" and type(unit) == "string"
        and (unit:find("^raid%d+$") or unit:find("^party%d$"))
        and PlainBool(UnitIsUnit(unit, "focus")) then
        S.dirty.focus = true -- the focus's group token changed; nameplates/boss/target are ignored
    else
        return
    end
    ScheduleFlush()
end

function H.SPELL_UPDATE_COOLDOWN()
    CD.ReadCooldown()
    EvaluateGate()
end

function H.UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
    if PlainNumber(spellID) == PI then
        S.castAt = GetTime()
        CD.ReadCooldown()
        EvaluateGate()
    end
end

H.GROUP_ROSTER_UPDATE = OnRoster

function H.PLAYER_FOCUS_CHANGED()
    SelectContext()
    CD.RequestFullScan()
end

function H.PLAYER_ROLES_ASSIGNED() CD.RequestFullScan() end

function H.PLAYER_REGEN_ENABLED()
    Frames.OnRegenEnabled()
    CD.RequestFullScan()
end

function H.SPELL_DATA_LOAD_RESULT(spellID)
    if CD.OnSpellDataLoaded then CD.OnSpellDataLoaded(spellID) end
end

for _, e in ipairs(BASE_EVENTS) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, event, ...)
    local fn = H[event]
    if fn then fn(...) end
end)
CD.eventFrame = ev

-- --- Hooks used by other modules ---------------------------------------------

function CD.OnFramesResolved()
    if S.running then CD.RefreshVisuals() end
end

-- Re-evaluates everything after a settings write. Every UI control and slash
-- command that changes cdTracker settings calls this.
function CD.ApplySettingsChange(fn)
    local cfg = CD.GetConfig()
    if not cfg then return end
    local prefix = cfg.customFramePrefix
    if fn then fn(cfg) end
    cfg = CD.GetConfig()
    CD.Evaluate()
    if cfg.customFramePrefix ~= prefix and S.running then Frames.RequestResolve() end
    local font = Media.FetchFont(cfg.font)
    Glow.ApplyFont(font, cfg.frameFontSize)
    Alert.ApplyFont()
    Alert.ApplyLayout()
    if ns.CDMinimap then ns.CDMinimap.Refresh() end
    SelectContext()
    EvaluateGate()
    S.alertKey = nil
    CD.RequestFullScan()
    if ns.UI then ns.UI.Refresh() end
end

function CD.GetState()
    local labels = Data.CONTEXT_LABELS
    local n = 0
    for _ in pairs(S.candidates) do n = n + 1 end
    local detectable = 0
    for _, id in ipairs(S.activeList) do
        if not SpellIsSecret(id) then detectable = detectable + 1 end
    end
    return {
        running = S.running, reason = S.reason, context = S.context,
        contextLabel = S.context and labels[S.context] or nil, gate = S.gate,
        candidates = n, detectable = detectable, activeIDs = #S.activeList,
    }
end

function CD.GetStatusLine()
    if S.running then
        return "CD tracker: Active (" .. (S.context and Data.CONTEXT_LABELS[S.context] or "no context") .. ")"
    end
    return "CD tracker: Inactive (" .. tostring(S.reason) .. ")"
end

-- The context used for test highlights: the current one, or raid.
function CD.DisplayContext()
    return S.context or "raid"
end

function CD.ActiveBuffList()
    if #S.activeList == 0 and CD.GetConfig() then RebuildBuffSet() end
    return S.activeList
end
