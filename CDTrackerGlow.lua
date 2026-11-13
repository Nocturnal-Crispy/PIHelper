-- CDTrackerGlow.lua
-- One pooled overlay per target frame and five self-contained glow styles
-- (pixel, proc, border, countdown, fill) drawn with WHITE8X8 color textures.
-- LibCustomGlow-1.0 is used for pixel/proc only when it is already loaded and
-- preferred; any error falls back to the built-in style. Overlays are our own
-- child frames: nothing is set on the target frame itself.

local _, ns = ...

local Glow = {}
ns.CDGlow = Glow

local WHITE = "Interface\\Buttons\\WHITE8X8"
local LCG_KEY = "PIHelperCD"
local PIXEL_SEGMENTS = 8
local PIXEL_LAP = 4
local PROC_OUTSET = 6
local PROC_MIN_ALPHA = 0.35
local PROC_PERIOD = 0.6
local SWIPE_ALPHA = 0.35
local FILL_ALPHA = 0.30
local LEVEL_BOOST = 10

local overlays = {} -- target frame -> overlay

local function LCG()
    if not LibStub then return nil end
    local ok, lib = pcall(LibStub, "LibCustomGlow-1.0", true)
    if ok then return lib end
    return nil
end

function Glow.LCGAvailable()
    return LCG() ~= nil
end

local function PreferLCG()
    local cfg = ns.CD and ns.CD.GetConfig()
    return cfg and cfg.preferLibCustomGlow
end

local function ColorTex(parent, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetTexture(WHITE)
    return t
end

local function Paint(tex, c, alpha)
    tex:SetColorTexture(c.r, c.g, c.b, alpha or c.a or 1)
end

-- --- Overlay construction ----------------------------------------------------

function Glow.Acquire(target)
    local ov = overlays[target]
    if ov then return ov end
    ov = CreateFrame("Frame", nil, target)
    ov:SetAllPoints(target)
    ov:SetFrameLevel(target:GetFrameLevel() + LEVEL_BOOST)
    ov.target = target
    ov:Hide()
    local tf = CreateFrame("Frame", nil, ov)
    tf:SetAllPoints(ov)
    tf:SetFrameLevel(ov:GetFrameLevel() + 5)
    ov.text = tf:CreateFontString(nil, "OVERLAY")
    ov.text:SetPoint("CENTER")
    local cfg = ns.CD and ns.CD.GetConfig()
    local size = cfg and cfg.frameFontSize or 12
    ov.text:SetFont(ns.CDMedia.FetchFont(cfg and cfg.font), size, "OUTLINE")
    overlays[target] = ov
    return ov
end

local function Edges(ov)
    if ov.edges then return ov.edges end
    local e = {}
    for i = 1, 4 do e[i] = ColorTex(ov) end
    ov.edges = e
    return e
end

local function LayoutEdges(edges, th, outset)
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    local o = outset or 0
    for _, t in ipairs(edges) do t:ClearAllPoints() end
    top:SetPoint("TOPLEFT", -o, o); top:SetPoint("TOPRIGHT", o, o); top:SetHeight(th)
    bottom:SetPoint("BOTTOMLEFT", -o, -o); bottom:SetPoint("BOTTOMRIGHT", o, -o); bottom:SetHeight(th)
    left:SetPoint("TOPLEFT", -o, o); left:SetPoint("BOTTOMLEFT", -o, -o); left:SetWidth(th)
    right:SetPoint("TOPRIGHT", o, o); right:SetPoint("BOTTOMRIGHT", o, -o); right:SetWidth(th)
end

local function ProcFrame(ov)
    if ov.proc then return ov.proc end
    local pf = CreateFrame("Frame", nil, ov)
    pf:SetAllPoints(ov)
    pf.bands = {}
    for i = 1, 4 do pf.bands[i] = ColorTex(pf) end
    LayoutEdges(pf.bands, PROC_OUTSET, PROC_OUTSET)
    local ag = pf:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(PROC_MIN_ALPHA)
    a:SetDuration(PROC_PERIOD)
    pf.anim = ag
    ov.proc = pf
    return pf
end

local function Segments(ov)
    if ov.segs then return ov.segs end
    local s = {}
    for i = 1, PIXEL_SEGMENTS do s[i] = ColorTex(ov) end
    ov.segs = s
    return s
end

-- Places one segment starting `pos` px along the perimeter (clockwise from
-- the top-left corner), clipped at the corner it would cross.
local function PlaceSegment(tex, pos, len, w, h, th)
    tex:ClearAllPoints()
    if pos < w then
        tex:SetPoint("TOPLEFT", pos, 0); tex:SetSize(math.min(len, w - pos), th)
    elseif pos < w + h then
        local y = pos - w
        tex:SetPoint("TOPRIGHT", 0, -y); tex:SetSize(th, math.min(len, h - y))
    elseif pos < 2 * w + h then
        local x = pos - w - h
        tex:SetPoint("BOTTOMRIGHT", -x, 0); tex:SetSize(math.min(len, w - x), th)
    else
        local y = pos - 2 * w - h
        tex:SetPoint("BOTTOMLEFT", 0, y); tex:SetSize(th, math.min(len, h - y))
    end
end

local function UpdatePixel(ov)
    local w, h = ov:GetWidth(), ov:GetHeight()
    if not w or w <= 0 or not h or h <= 0 then return end
    local perimeter = 2 * (w + h)
    local len = perimeter / (2 * PIXEL_SEGMENTS)
    local base = (GetTime() % PIXEL_LAP) / PIXEL_LAP * perimeter
    for i, tex in ipairs(ov.segs) do
        local pos = (base + (i - 1) * perimeter / PIXEL_SEGMENTS) % perimeter
        PlaceSegment(tex, pos, len, w, h, ov.thickness)
    end
end

local function UpdateFill(ov)
    local t = ov.timing
    local w = ov:GetWidth() or 0
    if not t or not t.duration or t.duration <= 0 then
        ov.fill:SetWidth(w)
        return
    end
    local remaining = t.start + t.duration - GetTime()
    if remaining < 0 then remaining = 0 end
    ov.fill:SetWidth(math.max(0.01, w * remaining / t.duration))
end

local function OnUpdate(ov)
    if ov.style == "pixel" and not ov.lcg then UpdatePixel(ov) end
    if ov.style == "fill" then UpdateFill(ov) end
end

-- --- Show / hide -------------------------------------------------------------

local function StopLCG(ov)
    if not ov.lcg then return end
    local lib = LCG()
    if lib then
        if ov.lcg == "pixel" and lib.PixelGlow_Stop then pcall(lib.PixelGlow_Stop, ov, LCG_KEY) end
        if ov.lcg == "proc" and lib.ProcGlow_Stop then pcall(lib.ProcGlow_Stop, ov, LCG_KEY) end
        if ov.lcg == "button" and lib.ButtonGlow_Stop then pcall(lib.ButtonGlow_Stop, ov) end
    end
    ov.lcg = nil
end

local function HideParts(ov)
    StopLCG(ov)
    for _, t in ipairs(ov.edges or {}) do t:Hide() end
    for _, t in ipairs(ov.segs or {}) do t:Hide() end
    if ov.proc then ov.proc.anim:Stop(); ov.proc:Hide() end
    if ov.cd then ov.cd:Clear(); ov.cd:Hide() end
    if ov.fill then ov.fill:Hide() end
    ov:SetScript("OnUpdate", nil)
end

local function TryLCG(ov, style, c, thickness)
    local lib = LCG()
    if not lib or not PreferLCG() then return false end
    local color = { c.r, c.g, c.b, c.a or 1 }
    if style == "pixel" and lib.PixelGlow_Start then
        if pcall(lib.PixelGlow_Start, ov, color, PIXEL_SEGMENTS, 0.25, nil, thickness, 0, 0, false, LCG_KEY) then
            ov.lcg = "pixel"
            return true
        end
    elseif style == "proc" then
        if lib.ProcGlow_Start then
            if pcall(lib.ProcGlow_Start, ov, { color = color, key = LCG_KEY }) then ov.lcg = "proc" return true end
        elseif lib.ButtonGlow_Start then
            if pcall(lib.ButtonGlow_Start, ov, color) then ov.lcg = "button" return true end
        end
    end
    StopLCG(ov)
    return false
end

local function ShowBorder(ov, c, th)
    local e = Edges(ov)
    LayoutEdges(e, th, 0)
    for _, t in ipairs(e) do Paint(t, c); t:Show() end
end

local function ShowPixel(ov, c)
    for _, t in ipairs(Segments(ov)) do Paint(t, c); t:Show() end
    UpdatePixel(ov)
    ov:SetScript("OnUpdate", OnUpdate)
end

local function ShowProc(ov, c)
    local pf = ProcFrame(ov)
    for _, t in ipairs(pf.bands) do Paint(t, c) end
    pf:Show()
    pf.anim:Play()
end

local function ShowCountdown(ov, c, timing)
    if not ov.cd then
        local cd = CreateFrame("Cooldown", nil, ov, "CooldownFrameTemplate")
        cd:SetAllPoints(ov)
        cd:SetReverse(true)
        cd:SetDrawEdge(false)
        if cd.SetDrawBling then cd:SetDrawBling(false) end
        cd:SetHideCountdownNumbers(true)
        ov.cd = cd
    end
    ov.cd:SetSwipeColor(c.r, c.g, c.b, SWIPE_ALPHA)
    ov.cd:Show()
    ov.cd:SetCooldown(timing.start, timing.duration)
end

local function ShowFill(ov, c)
    if not ov.fill then
        ov.fill = ColorTex(ov, "ARTWORK")
    end
    ov.fill:ClearAllPoints()
    ov.fill:SetPoint("TOPLEFT"); ov.fill:SetPoint("BOTTOMLEFT")
    Paint(ov.fill, c, FILL_ALPHA)
    ov.fill:Show()
    UpdateFill(ov)
    ov:SetScript("OnUpdate", OnUpdate)
end

local function Signature(style, c, timing, th)
    return table.concat({ style, c.r, c.g, c.b, c.a or 1, th,
        timing and timing.start or "-", timing and timing.duration or "-", PreferLCG() and "L" or "S" }, ":")
end

-- timing = { start, duration } or nil. Re-showing with identical arguments is a no-op.
function Glow.Show(ov, style, color, timing, thickness)
    thickness = thickness or 2
    local sig = Signature(style, color, timing, thickness)
    ov:SetFrameLevel(ov.target:GetFrameLevel() + LEVEL_BOOST)
    if ov.sig == sig and ov:IsShown() then return end
    HideParts(ov)
    ov.sig, ov.style, ov.timing, ov.thickness = sig, style, timing, thickness
    ov:Show()
    if (style == "pixel" or style == "proc") and TryLCG(ov, style, color, thickness) then return end
    if style == "pixel" then
        ShowPixel(ov, color)
    elseif style == "proc" then
        ShowProc(ov, color)
    elseif style == "countdown" then
        ShowBorder(ov, color, thickness)
        if timing then ShowCountdown(ov, color, timing) end
    elseif style == "fill" then
        ShowFill(ov, color)
    else
        ShowBorder(ov, color, thickness)
    end
end

function Glow.Hide(ov)
    if not ov then return end
    HideParts(ov)
    ov.sig = nil
    ov.text:SetText("")
    ov:Hide()
end

function Glow.SetText(ov, text)
    ov.text:SetText(text or "")
end

function Glow.ApplyFont(path, size)
    for _, ov in pairs(overlays) do ov.text:SetFont(path, size, "OUTLINE") end
end

function Glow.HideAll()
    for _, ov in pairs(overlays) do Glow.Hide(ov) end
end

function Glow.ForEach(fn)
    for target, ov in pairs(overlays) do fn(ov, target) end
end
