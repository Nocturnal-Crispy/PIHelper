-- UITheme.lua
-- The single source of colors and sizes for PIHelper's flat-dark UI, plus the
-- drawing primitives every widget is built from. Original implementation using
-- only Interface\Buttons\WHITE8X8 and stock game fonts.
--
-- Loads headless: nothing here calls a WoW API until a primitive is invoked.

local _, ns = ...

local function Hex(r, g, b) return { r = r / 255, g = g / 255, b = b / 255 } end

local T = {
    color = {
        bg         = Hex(0x19, 0x1B, 0x1D),
        panel      = Hex(0x1E, 0x20, 0x22),
        line       = Hex(0x37, 0x3B, 0x40),
        fg         = Hex(0xF0, 0xF1, 0xF3),
        muted      = Hex(0x9A, 0x9E, 0xA6),
        accent     = Hex(0x00, 0x91, 0xED),
        accentSoft = Hex(0x4D, 0xB5, 0xF5),
        grey       = Hex(0x3D, 0x41, 0x46),
        danger     = Hex(0xFF, 0x59, 0x59),
        success    = Hex(0x36, 0xC5, 0x8A),
        black      = Hex(0x00, 0x00, 0x00),
        white      = Hex(0xFF, 0xFF, 0xFF),
    },
    alpha = {
        window = 0.97, buttonRest = 0.9, navFill = 0.16, navOff = 0.45,
        dim = 0.3, rule = 0.6, tooltip = 0.98, scrollTrack = 0.6, scrollThumb = 0.8,
        sidebarShade = 0.15, shadow = 0.4, moverFill = 0.16, guide = 0.5,
        swipe = 0.35, modalDim = 0.5,
    },
    font = { heading = "Fonts\\FRIZQT__.TTF", body = "Fonts\\ARIALN.TTF" },
    size = {
        navText = 14, groupLabel = 11, crumb = 12, title = 20, subtitle = 12,
        section = 14, label = 13, note = 11, control = 12, button = 12, tooltipTitle = 12,
        tooltipBody = 11, brand = 18, version = 11, preview = 12,
    },
    metric = {
        windowW = 760, windowH = 540, sidebarW = 190, brandH = 56, headerH = 76,
        navRowH = 28, navInset = 8, navTextX = 18, navMarkerW = 3, groupX = 20, groupStep = 28,
        contentX = 26, contentRight = 30, rowH = 44, sectionH = 36, rowInset = 20, labelGap = 8,
        buttonH = 24, buttonW = 90, wideButtonW = 200, toggleW = 40, toggleH = 20, toggleInset = 2,
        sliderTrackW = 120, sliderTrackH = 4, sliderThumb = 12, valueBoxW = 40, valueBoxH = 22,
        dropdownW = 160, dropdownH = 24, dropdownTextX = 8, menuRowH = 22, menuMaxH = 300,
        editH = 24, editInset = 6, swatchW = 40, swatchH = 20, segH = 24,
        scrollW = 6, scrollGap = 6, scrollStep = 60, closeSize = 24, shadowSize = 6,
        tooltipW = 240, tooltipPad = 8, snap = 8,
        buttonPad = 24, pillPad = 8, hitPad = 4, thumbMin = 24, chevronLen = 6,
        modalW = 340, modalH = 110, previewH = 110, multiEditH = 120, gap = 8,
        controlGap = 16, segW = 64, borderLevel = 50, targetNameW = 140,
    },
}

local WHITE = "Interface\\Buttons\\WHITE8X8"
T.WHITE = WHITE

-- --- Colors ------------------------------------------------------------------

function T.RGB(key)
    local c = T.color[key] or T.color.fg
    return c.r, c.g, c.b
end

-- Accepts a theme key (+ alpha) or explicit r, g, b, a.
function T.Color(keyOrR, g, b, a)
    if type(keyOrR) == "string" then
        local r, gg, bb = T.RGB(keyOrR)
        return r, gg, bb, g or 1
    end
    return keyOrR, g, b, a or 1
end

function T.Paint(tex, keyOrR, g, b, a)
    tex:SetColorTexture(T.Color(keyOrR, g, b, a))
end

function T.SetTextColor(fs, key, alpha)
    local r, g, b = T.RGB(key)
    fs:SetTextColor(r, g, b, alpha or 1)
end

-- --- Physical pixels ---------------------------------------------------------

local pixelRegions = setmetatable({}, { __mode = "k" })
local scaleWatcher

local function PixelSize(region)
    local factor = (PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor()) or 1
    local scale = region:GetEffectiveScale()
    if not scale or scale <= 0 then scale = 1 end
    return factor / scale
end
T.PixelSize = PixelSize

local function ApplyPixel(obj)
    if obj.Apply then obj:Apply() end
end

function T.RefreshPixels()
    for obj in pairs(pixelRegions) do ApplyPixel(obj) end
end

-- Created on first use (the window build), never at load.
function T.EnsureScaleWatcher()
    if scaleWatcher then return end
    scaleWatcher = CreateFrame("Frame")
    scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
    scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    scaleWatcher:SetScript("OnEvent", T.RefreshPixels)
end

local function Track(obj, owner)
    pixelRegions[obj] = true
    T.EnsureScaleWatcher()
    if owner and owner.HookScript then
        owner:HookScript("OnShow", function() obj:Apply() end)
    end
    obj:Apply()
end

-- --- Primitives --------------------------------------------------------------

function T.Solid(parent, layer, colorKey, alpha)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    T.Paint(tex, colorKey or "panel", alpha or 1)
    return tex
end

-- A 1-physical-pixel line. orientation "H" (default) sets height, "V" width.
function T.Hairline(parent, colorKey, alpha, orientation)
    local tex = parent:CreateTexture(nil, "BORDER")
    T.Paint(tex, colorKey or "line", alpha or 1)
    local line = { tex = tex, vertical = orientation == "V" }
    function line:Apply()
        local px = PixelSize(self.tex)
        if self.vertical then self.tex:SetWidth(px) else self.tex:SetHeight(px) end
    end
    Track(line, parent)
    return tex
end

local BorderMethods = {}
BorderMethods.__index = BorderMethods

function BorderMethods:Apply()
    local px = PixelSize(self.frame)
    self.top:SetHeight(px)
    self.bottom:SetHeight(px)
    self.left:SetWidth(px)
    self.right:SetWidth(px)
end

function BorderMethods:SetColor(keyOrR, g, b, a)
    for _, edge in ipairs(self.edges) do T.Paint(edge, keyOrR, g, b, a) end
end

function BorderMethods:Show() for _, e in ipairs(self.edges) do e:Show() end end
function BorderMethods:Hide() for _, e in ipairs(self.edges) do e:Hide() end end

-- Four edges exactly one physical pixel wide, drawn inside the frame.
function T.Border(frame, colorKey, alpha)
    local function Edge() return frame:CreateTexture(nil, "BORDER", nil, 7) end
    local b = setmetatable({ frame = frame }, BorderMethods)
    b.top, b.bottom, b.left, b.right = Edge(), Edge(), Edge(), Edge()
    b.edges = { b.top, b.bottom, b.left, b.right }
    b.top:SetPoint("TOPLEFT"); b.top:SetPoint("TOPRIGHT")
    b.bottom:SetPoint("BOTTOMLEFT"); b.bottom:SetPoint("BOTTOMRIGHT")
    b.left:SetPoint("TOPLEFT"); b.left:SetPoint("BOTTOMLEFT")
    b.right:SetPoint("TOPRIGHT"); b.right:SetPoint("BOTTOMRIGHT")
    b:SetColor(colorKey or "line", alpha or 1)
    Track(b, frame)
    return b
end

function T.Font(parent, sizeKey, colorKey, heading, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(heading and T.font.heading or T.font.body, T.size[sizeKey] or T.size.label, flags or "")
    T.SetTextColor(fs, colorKey or "fg")
    if heading then
        local r, g, b = T.RGB("black")
        fs:SetShadowColor(r, g, b, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
    return fs
end

function T.Shadow(frame)
    local s = T.metric.shadowSize
    local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    T.Paint(tex, "black", T.alpha.shadow)
    tex:SetPoint("TOPLEFT", -s, s)
    tex:SetPoint("BOTTOMRIGHT", s, -s)
    return tex
end

ns.Theme = T
