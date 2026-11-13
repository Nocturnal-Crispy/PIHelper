-- CDTrackerAlert.lua
-- The on-screen CD alert (PIHelperCDAlert): buff icon, player name and an
-- optional duration. Also the session-only mover mode: unlock, drag with
-- center guides, snap to center, save CENTER/CENTER offsets, lock.

local _, ns = ...

local T = ns.Theme
local Core = ns.CDCore

local Alert = {}
ns.CDAlert = Alert

local ICON_SIZE = 48
local WIDTH = 200
local OFFSET_LIMIT = 4000
local TICK = 0.1
local FALLBACK_ICON = "Interface\\Icons\\Spell_Holy_PowerInfusion"
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 180 }

local frame, mover, guides
local unlocked = false
local current -- data passed to the last Show()

local function Cfg() return ns.CD and ns.CD.GetConfig() end

local function PIIcon()
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ns.CDData.PI_SPELL_ID)
    return tex or FALLBACK_ICON
end

-- --- Frame -------------------------------------------------------------------

local function UpdateDuration(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc < TICK then return end
    self.acc = 0
    local d = current
    if unlocked or not (d and d.showDuration and d.timing) then return end
    local remaining = d.timing.start + d.timing.duration - GetTime()
    self.duration:SetText(Core.FormatDuration(remaining) or "")
end

local function Ensure()
    if frame then return frame end
    frame = CreateFrame("Frame", "PIHelperCDAlert", UIParent)
    frame:SetSize(WIDTH, ICON_SIZE + 44)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(ICON_SIZE, ICON_SIZE)
    frame.icon:SetPoint("TOP")
    frame.name = frame:CreateFontString(nil, "OVERLAY")
    frame.name:SetPoint("TOP", frame.icon, "BOTTOM", 0, -4)
    frame.duration = frame:CreateFontString(nil, "OVERLAY")
    frame.duration:SetPoint("TOP", frame.name, "BOTTOM", 0, -2)
    frame:Hide()
    Alert.ApplyFont()
    Alert.ApplyLayout()
    return frame
end

function Alert.ApplyFont()
    if not frame then return end
    local cfg = Cfg()
    if not cfg then return end
    local path = ns.CDMedia.FetchFont(cfg.font)
    frame.name:SetFont(path, cfg.alertFontSize, "OUTLINE")
    frame.duration:SetFont(path, cfg.alertFontSize, "OUTLINE")
end

function Alert.ApplyLayout()
    if not frame then return end
    local cfg = Cfg()
    local a = cfg and cfg.alert or DEFAULT_POS
    frame:SetScale(a.scale or 1)
    frame:ClearAllPoints()
    frame:SetPoint(a.point, UIParent, a.relPoint, a.x, a.y)
end

local function NameColor(classFile)
    local cfg = Cfg()
    if cfg and cfg.classColorNames and type(classFile) == "string"
        and C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(classFile)
        if c then return c.r, c.g, c.b end
    end
    return T.RGB("fg")
end

local function Render(d)
    frame.icon:SetTexture(d.icon or PIIcon())
    frame.name:SetText(d.name or "")
    frame.name:SetTextColor(NameColor(d.classFile))
    frame.duration:SetText("")
    frame.duration:SetShown(d.showDuration and true or false)
    if d.showDuration and d.timing then
        frame:SetScript("OnUpdate", UpdateDuration)
        UpdateDuration(frame, TICK)
    else
        frame:SetScript("OnUpdate", nil)
    end
end

local function RenderPlaceholder()
    frame:SetScript("OnUpdate", nil)
    frame.icon:SetTexture(PIIcon())
    frame.name:SetText("Player Name")
    frame.name:SetTextColor(T.RGB("fg"))
    frame.duration:SetText("12.3")
    frame.duration:Show()
end

-- data = { name, classFile, icon, timing = {start, duration} | nil, showDuration }
function Alert.Show(data)
    Ensure()
    current = data
    if unlocked then return end
    Render(data)
    frame:Show()
end

function Alert.Hide()
    current = nil
    if not frame then return end
    frame:SetScript("OnUpdate", nil)
    if not unlocked then frame:Hide() end
end

function Alert.IsShowing()
    return frame ~= nil and frame:IsShown() and current ~= nil
end

-- --- Mover mode --------------------------------------------------------------

local function EnsureGuides()
    if guides then return guides end
    guides = CreateFrame("Frame", nil, UIParent)
    guides:SetAllPoints(UIParent)
    guides:SetFrameStrata("HIGH")
    guides.v = T.Solid(guides, "OVERLAY", "accent", T.alpha.guide)
    guides.v:SetPoint("TOP", UIParent, "TOP")
    guides.v:SetPoint("BOTTOM", UIParent, "BOTTOM")
    guides.h = T.Solid(guides, "OVERLAY", "accent", T.alpha.guide)
    guides.h:SetPoint("LEFT", UIParent, "LEFT")
    guides.h:SetPoint("RIGHT", UIParent, "RIGHT")
    guides:SetScript("OnShow", function(self)
        local px = T.PixelSize(self)
        self.v:SetWidth(px)
        self.h:SetHeight(px)
    end)
    guides:Hide()
    return guides
end

local function Clamp(v)
    v = math.floor(v + 0.5)
    if v > OFFSET_LIMIT then return OFFSET_LIMIT end
    if v < -OFFSET_LIMIT then return -OFFSET_LIMIT end
    return v
end

-- Converts the dropped frame position into CENTER/CENTER offsets in the
-- alert's own (scaled) units, snaps, rounds, clamps and saves.
local function SaveDrop()
    frame:StopMovingOrSizing()
    if guides then guides:Hide() end
    local fx, fy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (fx and ux) then return end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x = (fx * ratio - ux) / ratio
    local y = (fy * ratio - uy) / ratio
    x, y = Core.SnapOffset(x, y, T.metric.snap)
    x, y = Clamp(x), Clamp(y)
    ns.CD.ApplySettingsChange(function(c)
        c.alert.point, c.alert.relPoint, c.alert.x, c.alert.y = "CENTER", "CENTER", x, y
    end)
    Alert.ApplyLayout()
end

local function EnsureMover()
    if mover then return mover end
    mover = CreateFrame("Frame", nil, frame)
    mover:SetAllPoints(frame)
    mover:SetFrameLevel(frame:GetFrameLevel() + 10)
    mover.fill = T.Solid(mover, "BACKGROUND", "accent", T.alpha.moverFill)
    mover.fill:SetAllPoints()
    mover.border = T.Border(mover, "accent")
    mover.label = T.Font(mover, "note", "fg")
    mover.label:SetPoint("TOPLEFT", mover, "TOPLEFT", 4, -4)
    mover.label:SetText("PI Alert")
    mover.hint = T.Font(mover, "note", "muted")
    mover.hint:SetPoint("TOP", mover, "BOTTOM", 0, -4)
    mover.hint:SetText("Drag to move. Right-click to lock.")
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function()
        EnsureGuides():Show()
        frame:StartMoving()
    end)
    mover:SetScript("OnDragStop", SaveDrop)
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Alert.Lock() end
    end)
    mover:SetScript("OnEvent", function() Alert.Lock() end)
    mover:Hide()
    return mover
end

function Alert.Unlock()
    Ensure()
    EnsureMover()
    unlocked = true
    RenderPlaceholder()
    Alert.ApplyLayout()
    frame:Show()
    mover:Show()
    mover:RegisterEvent("PLAYER_REGEN_DISABLED")
    if ns.UI then ns.UI.Refresh() end
end

function Alert.Lock()
    if not unlocked then return end
    unlocked = false
    if frame then frame:StopMovingOrSizing() end
    if guides then guides:Hide() end
    if mover then
        mover:UnregisterEvent("PLAYER_REGEN_DISABLED")
        mover:Hide()
    end
    if current then Render(current) else frame:Hide() end
    if ns.CD and ns.CD.RefreshVisuals then ns.CD.RefreshVisuals() end
    if ns.UI then ns.UI.Refresh() end
end

function Alert.IsUnlocked() return unlocked end

function Alert.ResetPosition()
    ns.CD.ApplySettingsChange(function(c)
        c.alert.point, c.alert.relPoint = DEFAULT_POS.point, DEFAULT_POS.relPoint
        c.alert.x, c.alert.y = DEFAULT_POS.x, DEFAULT_POS.y
    end)
    Alert.ApplyLayout()
end

function Alert.GetPosition()
    local cfg = Cfg()
    if not cfg then return 0, 0 end
    return cfg.alert.x, cfg.alert.y
end

-- Shows a sample alert for `seconds`, ignoring run and gate conditions.
function Alert.Test(seconds)
    seconds = seconds or 10
    local name = UnitName("player")
    local _, classFile = UnitClass("player")
    if Core.IsSecret(name) then name = "Player" end
    if Core.IsSecret(classFile) then classFile = nil end
    local data = { name = name, classFile = classFile, timing = { start = GetTime(), duration = seconds },
        showDuration = true, test = true }
    Alert.Show(data)
    C_Timer.After(seconds, function()
        if current == data then
            Alert.Hide()
            if ns.CD and ns.CD.RefreshVisuals then ns.CD.RefreshVisuals() end
        end
    end)
end
