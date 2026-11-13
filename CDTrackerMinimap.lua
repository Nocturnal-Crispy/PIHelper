-- CDTrackerMinimap.lua
-- Minimap launcher: LibDataBroker + LibDBIcon when BOTH are already loaded,
-- otherwise a self-contained PIHelperMinimapButton dragged around the edge.

local _, ns = ...

local MM = {}
ns.CDMinimap = MM

local FALLBACK_ICON = "Interface\\Icons\\Spell_Holy_PowerInfusion"
local BUTTON_SIZE = 31
local EDGE_PAD = 10

local initialized = false
local dbIcon, button

local function Lib(name)
    if not LibStub then return nil end
    local ok, lib = pcall(LibStub, name, true)
    if ok then return lib end
    return nil
end

local function Icon()
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ns.CDData.PI_SPELL_ID)
    return tex or FALLBACK_ICON
end

local function Cfg() return ns.CD.GetConfig() end

-- --- Shared behavior ---------------------------------------------------------

local function PILine(g)
    if g.reason == "n/a" then return "PI: n/a" end
    if g.reason == "unknown" then return "PI: Unknown" end
    if (g.reason == "cooldown" or g.reason == "grace") then
        if type(g.remaining) == "number" and g.remaining > 0 then
            return "PI: " .. math.ceil(g.remaining) .. "s"
        end
        return "PI: Unknown"
    end
    return "PI: Ready"
end

local function TrackerLine(st)
    if st.running then
        return "CD Tracker: Active (" .. (st.contextLabel or "no context") .. ")"
    end
    return "CD Tracker: Inactive (" .. tostring(st.reason) .. ")"
end

local function FillTooltip(tt)
    local st = ns.CD.GetState()
    local target = PIHelperDB and PIHelperDB.target
    tt:AddLine("PIHelper")
    tt:AddLine(TrackerLine(st))
    tt:AddLine(PILine(st.gate))
    tt:AddLine("PI target: " .. ((type(target) == "string" and target ~= "") and target or "(none)"))
    tt:AddLine(" ")
    tt:AddLine("Left-click: CD Tracker settings")
    tt:AddLine("Right-click: PI Macro settings")
    tt:AddLine("Drag: move")
end

local function OnClick(mouseButton)
    if not ns.UI then return end
    if mouseButton == "RightButton" then ns.UI.Toggle("pi_macro") else ns.UI.Toggle("cd_general") end
end

-- --- LibDBIcon path ----------------------------------------------------------

local function InitLDB(ldb, dbi)
    local obj = ldb:NewDataObject("PIHelper", {
        type = "launcher", label = "PIHelper", icon = Icon(),
        OnClick = function(_, mouseButton) OnClick(mouseButton) end,
        OnTooltipShow = function(tt) FillTooltip(tt) end,
    })
    if not obj then return false end
    local ok = pcall(dbi.Register, dbi, "PIHelper", obj, Cfg().minimap)
    if not ok then return false end
    dbIcon = dbi
    return true
end

-- --- Self-contained button ---------------------------------------------------

local function Place(angle)
    local r = Minimap:GetWidth() / 2 + EDGE_PAD
    local rad = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

local function CursorAngle()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    return math.deg(math.atan2(py - my, px - mx)) % 360
end

local function OnDragUpdate(self)
    self.angle = CursorAngle()
    Place(self.angle)
end

local function CreateButton()
    button = CreateFrame("Button", "PIHelperMinimapButton", Minimap)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(Icon())
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button:SetScript("OnClick", function(_, mouseButton) OnClick(mouseButton) end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        local angle = self.angle
        if angle then ns.CD.ApplySettingsChange(function(c) c.minimap.minimapPos = angle end) end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        FillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- --- Public API --------------------------------------------------------------

function MM.Init()
    if initialized or not Cfg() then return end
    initialized = true
    local ldb, dbi = Lib("LibDataBroker-1.1"), Lib("LibDBIcon-1.0")
    if not (ldb and dbi and InitLDB(ldb, dbi)) then CreateButton() end
    MM.Refresh()
end

function MM.Refresh()
    if not initialized then return end
    local m = Cfg().minimap
    if dbIcon then
        if dbIcon.Refresh then pcall(dbIcon.Refresh, dbIcon, "PIHelper", m) end
        if m.hide then dbIcon:Hide("PIHelper") else dbIcon:Show("PIHelper") end
        return
    end
    Place(m.minimapPos)
    button:SetShown(not m.hide)
end

function MM.Toggle()
    ns.CD.ApplySettingsChange(function(c) c.minimap.hide = not c.minimap.hide end)
end
