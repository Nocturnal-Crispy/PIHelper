-- UIWidgets.lua
-- Flat widget kit for the settings window: buttons, toggles, sliders, edit
-- boxes, segmented controls, swatches, pills, rows and a vertical layout
-- stack. Every value widget takes get/set callbacks and exposes :refresh().
-- Colors and sizes come only from ns.Theme. Dropdowns, multi-line edit boxes
-- and the modal live in UIWidgetsMenu.lua.

local _, ns = ...

local T = ns.Theme
local M = T.metric
local W = {}
ns.Widgets = W

local function Noop() end

-- Applies enabled/disabled look and mouse handling to any widget frame.
local function SetFrameEnabled(frame, enabled)
    frame.enabled = enabled
    frame:SetAlpha(enabled and 1 or T.alpha.dim)
    frame:EnableMouse(enabled)
end
W.SetFrameEnabled = SetFrameEnabled

-- Rounds v to the step grid starting at lo and clamps to [lo, hi].
function W.StepValue(v, lo, hi, step)
    if v < lo then v = lo elseif v > hi then v = hi end
    local n = math.floor((v - lo) / step + 0.5)
    v = lo + n * step
    if v > hi then v = hi end
    return tonumber(string.format("%.4f", v))
end

-- --- Text --------------------------------------------------------------------

function W.Text(parent, sizeKey, colorKey, heading)
    local fs = T.Font(parent, sizeKey or "label", colorKey or "fg", heading)
    fs:SetJustifyH("LEFT")
    return fs
end

-- --- Button ------------------------------------------------------------------

local function PaintButton(b)
    local hover = b.hovered and b.enabled
    if b.primary then
        T.Paint(b.fill, hover and "accentSoft" or "accent", 1)
        b.border:SetColor(hover and "accentSoft" or "accent", 1)
        T.SetTextColor(b.label, "bg")
    else
        T.Paint(b.fill, "panel", hover and 1 or T.alpha.buttonRest)
        b.border:SetColor(hover and "accent" or "line", 1)
        T.SetTextColor(b.label, "fg")
    end
end

local function FitButton(b)
    local w = math.max(b.minWidth, math.ceil(b.label:GetStringWidth() + M.buttonPad))
    b:SetWidth(w)
end

-- opts = { label, onClick, primary, width, tooltip }
function W.Button(parent, opts)
    local b = CreateFrame("Button", nil, parent)
    b.minWidth = opts.width or M.buttonW
    b:SetHeight(M.buttonH)
    b.fill = T.Solid(b, "BACKGROUND", "panel", T.alpha.buttonRest)
    b.fill:SetAllPoints()
    b.border = T.Border(b, "line")
    b.label = T.Font(b, "button", "fg", true)
    b.label:SetPoint("CENTER")
    b.primary = opts.primary and true or false
    b.enabled = true
    b.onClick = opts.onClick or Noop

    function b:SetLabel(text)
        self.label:SetText(text)
        FitButton(self)
    end
    function b:SetPrimary(on)
        self.primary = on and true or false
        PaintButton(self)
    end
    function b:SetEnabled(on)
        SetFrameEnabled(self, on)
        PaintButton(self)
    end
    b.refresh = Noop

    b:SetScript("OnEnter", function(self)
        self.hovered = true
        PaintButton(self)
        if opts.tooltip and ns.UI then ns.UI.ShowTooltip(self, opts.label, opts.tooltip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = false
        PaintButton(self)
        if ns.UI then ns.UI.HideTooltip() end
    end)
    b:SetScript("OnClick", function(self) self.onClick(self) end)
    b:SetLabel(opts.label or "")
    PaintButton(b)
    return b
end

-- --- Toggle ------------------------------------------------------------------

local function PaintToggle(tg)
    local on = tg.value
    local hover = tg.hovered and tg.enabled
    if on then
        T.Paint(tg.track, hover and "accentSoft" or "accent", 1)
        T.Paint(tg.knob, "white", 1)
    else
        T.Paint(tg.track, hover and "grey" or "line", 1)
        T.Paint(tg.knob, "fg", 1)
    end
    tg.knob:ClearAllPoints()
    if on then
        tg.knob:SetPoint("RIGHT", tg.track, "RIGHT", -M.toggleInset, 0)
    else
        tg.knob:SetPoint("LEFT", tg.track, "LEFT", M.toggleInset, 0)
    end
end

-- opts = { get, set }
function W.Toggle(parent, opts)
    local pad = M.hitPad
    local tg = CreateFrame("Button", nil, parent)
    tg:SetSize(M.toggleW + 2 * pad, M.toggleH + 2 * pad)
    tg.track = tg:CreateTexture(nil, "ARTWORK")
    tg.track:SetPoint("TOPLEFT", pad, -pad)
    tg.track:SetPoint("BOTTOMRIGHT", -pad, pad)
    tg.knob = tg:CreateTexture(nil, "OVERLAY")
    local k = M.toggleH - 2 * M.toggleInset
    tg.knob:SetSize(k, k)
    tg.enabled = true

    function tg:refresh()
        self.value = opts.get() and true or false
        PaintToggle(self)
    end
    function tg:SetEnabled(on)
        SetFrameEnabled(self, on)
        PaintToggle(self)
    end
    tg:SetScript("OnEnter", function(self) self.hovered = true; PaintToggle(self) end)
    tg:SetScript("OnLeave", function(self) self.hovered = false; PaintToggle(self) end)
    tg:SetScript("OnClick", function(self)
        opts.set(not self.value)
        self:refresh()
    end)
    tg:refresh()
    return tg
end

-- --- Edit box ----------------------------------------------------------------

local function PaintEdit(eb)
    local active = eb.hovered or eb:HasFocus()
    eb.border:SetColor(active and "accent" or "black", 1)
end

-- Styles a raw EditBox (shared by single- and multi-line variants).
function W.StyleEditBox(eb, sizeKey)
    eb:SetAutoFocus(false)
    eb:SetFont(T.font.body, T.size[sizeKey or "control"], "")
    T.SetTextColor(eb, "fg")
    eb:SetTextInsets(M.editInset, M.editInset, 0, 0)
    eb.bgTex = T.Solid(eb, "BACKGROUND", "bg", 1)
    eb.bgTex:SetAllPoints()
    eb.border = T.Border(eb, "black")
    eb:HookScript("OnEnter", function(self) self.hovered = true; PaintEdit(self) end)
    eb:HookScript("OnLeave", function(self) self.hovered = false; PaintEdit(self) end)
    eb:HookScript("OnEditFocusGained", PaintEdit)
    eb:HookScript("OnEditFocusLost", PaintEdit)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

-- opts = { get, set(text), width, maxLetters, commitOnBlur }
-- `set` runs on Enter (and on focus loss when commitOnBlur).
function W.EditBox(parent, opts)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(opts.width or M.dropdownW, M.editH)
    W.StyleEditBox(eb)
    eb:SetMaxLetters(opts.maxLetters or 64)
    local function Commit(self)
        if opts.set then opts.set(self:GetText() or "") end
        if self.refresh then self:refresh() end
    end
    eb:SetScript("OnEnterPressed", function(self)
        Commit(self)
        self:ClearFocus()
    end)
    if opts.commitOnBlur then
        eb:HookScript("OnEditFocusLost", Commit)
    end
    function eb:refresh()
        if opts.get and not self:HasFocus() then self:SetText(opts.get() or "") end
    end
    function eb:SetEnabled(on) SetFrameEnabled(self, on) end
    eb:refresh()
    return eb
end

-- --- Slider ------------------------------------------------------------------

local function Decimals(step)
    if step >= 1 then return 0 end
    if step >= 0.1 then return 1 end
    return 2
end

-- opts = { min, max, step, get, set }
function W.Slider(parent, opts)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(M.sliderTrackW + M.gap + M.valueBoxW, M.valueBoxH)
    local fmt = "%." .. Decimals(opts.step) .. "f"

    local s = CreateFrame("Slider", nil, holder)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(M.sliderTrackW, M.sliderThumb + 2 * M.hitPad)
    s:SetPoint("LEFT")
    s:SetMinMaxValues(opts.min, opts.max)
    s:SetValueStep(opts.step)
    s:SetObeyStepOnDrag(true)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    T.Paint(thumb, "fg", 1)
    thumb:SetSize(M.sliderThumb, M.sliderThumb)
    s:SetThumbTexture(thumb)
    local rail = T.Solid(s, "BACKGROUND", "line", 1)
    rail:SetHeight(M.sliderTrackH)
    rail:SetPoint("LEFT"); rail:SetPoint("RIGHT")
    local fillTex = T.Solid(s, "ARTWORK", "accent", 1)
    fillTex:SetHeight(M.sliderTrackH)
    fillTex:SetPoint("LEFT", rail, "LEFT")
    fillTex:SetPoint("RIGHT", thumb, "CENTER")

    local box = CreateFrame("EditBox", nil, holder)
    box:SetSize(M.valueBoxW, M.valueBoxH)
    box:SetPoint("LEFT", s, "RIGHT", M.gap, 0)
    W.StyleEditBox(box)
    box:SetJustifyH("CENTER")
    box:SetMaxLetters(6)

    local function Commit(v)
        v = W.StepValue(v, opts.min, opts.max, opts.step)
        opts.set(v)
        holder:refresh()
    end
    s:SetScript("OnValueChanged", function(_, v, userInput)
        if holder.updating or userInput == false then return end
        Commit(v)
    end)
    local function CommitBox(self)
        local v = tonumber(self:GetText() or "")
        if v then Commit(v) else holder:refresh() end
    end
    box:SetScript("OnEnterPressed", function(self) CommitBox(self); self:ClearFocus() end)
    box:HookScript("OnEditFocusLost", CommitBox)

    function holder:refresh()
        local v = opts.get()
        self.updating = true
        s:SetValue(v)
        self.updating = false
        if not box:HasFocus() then box:SetText(string.format(fmt, v)) end
    end
    function holder:SetEnabled(on)
        SetFrameEnabled(self, on)
        s:EnableMouse(on)
        box:EnableMouse(on)
    end
    holder:refresh()
    return holder
end

-- --- Segmented control -------------------------------------------------------

-- opts = { items = {{value, label}}, get, set, width }
function W.Segmented(parent, opts)
    local holder = CreateFrame("Frame", nil, parent)
    local n = #opts.items
    local segW = math.floor((opts.width or (n * M.buttonW)) / n)
    holder:SetSize(segW * n, M.segH)
    holder.buttons = {}
    for i, item in ipairs(opts.items) do
        local b = W.Button(holder, { label = item.label, width = segW, onClick = function()
            opts.set(item.value)
            holder:refresh()
        end })
        b:SetHeight(M.segH)
        b:SetWidth(segW)
        b:SetPoint("LEFT", holder, "LEFT", (i - 1) * segW, 0)
        b.value = item.value
        holder.buttons[i] = b
    end
    function holder:refresh()
        local cur = opts.get()
        for _, b in ipairs(self.buttons) do b:SetPrimary(b.value == cur) end
    end
    function holder:SetEnabled(on)
        SetFrameEnabled(self, on)
        for _, b in ipairs(self.buttons) do b:EnableMouse(on) end
    end
    holder:refresh()
    return holder
end

-- --- Color swatch ------------------------------------------------------------

local function PickerAlpha(fallback)
    if ColorPickerFrame.GetColorAlpha then return ColorPickerFrame:GetColorAlpha() end
    if OpacitySliderFrame then return 1 - OpacitySliderFrame:GetValue() end
    return fallback
end

-- opts = { get = function() return r, g, b, a end, set = function(r, g, b, a) end }
function W.Swatch(parent, opts)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(M.swatchW, M.swatchH)
    sw.color = sw:CreateTexture(nil, "ARTWORK")
    sw.color:SetAllPoints()
    sw.border = T.Border(sw, "line")
    function sw:refresh()
        local r, g, b, a = opts.get()
        self.color:SetColorTexture(r, g, b, a or 1)
    end
    function sw:SetEnabled(on) SetFrameEnabled(self, on) end
    sw:SetScript("OnEnter", function(self) self.border:SetColor("accent", 1) end)
    sw:SetScript("OnLeave", function(self) self.border:SetColor("line", 1) end)
    sw:SetScript("OnClick", function(self)
        if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
        local r, g, b, a = opts.get()
        local prev = { r = r, g = g, b = b, a = a or 1 }
        local function Apply()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            opts.set(nr, ng, nb, PickerAlpha(prev.a))
            self:refresh()
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a or 1, hasOpacity = true,
            swatchFunc = Apply, opacityFunc = Apply,
            cancelFunc = function()
                opts.set(prev.r, prev.g, prev.b, prev.a)
                self:refresh()
            end,
        })
    end)
    sw:refresh()
    return sw
end

-- --- Status pill -------------------------------------------------------------

function W.Pill(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(T.size.note + M.pillPad)
    p.text = T.Font(p, "note", "muted")
    p.text:SetPoint("CENTER")
    p.border = T.Border(p, "muted")
    function p:SetState(text, active)
        local key = active and "accent" or "muted"
        self.text:SetText(text or "")
        T.SetTextColor(self.text, key)
        self.border:SetColor(key, 1)
        self:SetWidth(math.ceil(self.text:GetStringWidth()) + 2 * M.pillPad)
    end
    return p
end

-- --- Slim scrollbar ----------------------------------------------------------

local function UpdateScrollBar(bar)
    local sf = bar.scrollFrame
    local range = sf:GetVerticalScrollRange() or 0
    if range <= 0 then
        bar:Hide()
        if sf:GetVerticalScroll() ~= 0 then sf:SetVerticalScroll(0) end
        return
    end
    bar:Show()
    local barH = bar:GetHeight()
    local viewH = sf:GetHeight()
    local thumbH = math.max(M.thumbMin, barH * viewH / (viewH + range))
    local pos = (barH - thumbH) * (sf:GetVerticalScroll() / range)
    bar.thumb:SetHeight(thumbH)
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("TOP", bar, "TOP", 0, -pos)
end

local function ScrollBy(sf, delta)
    local range = sf:GetVerticalScrollRange() or 0
    local v = sf:GetVerticalScroll() - delta * M.scrollStep
    if v < 0 then v = 0 elseif v > range then v = range end
    sf:SetVerticalScroll(v)
end

local function DragThumb(bar)
    local _, cy = GetCursorPosition()
    local scale = bar:GetEffectiveScale()
    local dy = (bar.dragStartY - cy) / scale
    local sf = bar.scrollFrame
    local range = sf:GetVerticalScrollRange() or 0
    local travel = bar:GetHeight() - bar.thumb:GetHeight()
    if travel <= 0 then return end
    local v = bar.dragStartScroll + dy * range / travel
    if v < 0 then v = 0 elseif v > range then v = range end
    sf:SetVerticalScroll(v)
end

-- Attaches a slim scrollbar to scrollFrame, placed scrollGap to its right.
function W.SlimScroll(scrollFrame)
    local bar = CreateFrame("Frame", nil, scrollFrame:GetParent())
    bar.scrollFrame = scrollFrame
    bar:SetWidth(M.scrollW)
    bar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", M.scrollGap, 0)
    bar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", M.scrollGap, 0)
    local track = T.Solid(bar, "BACKGROUND", "line", T.alpha.scrollTrack)
    track:SetAllPoints()
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(M.scrollW)
    thumb.tex = T.Solid(thumb, "ARTWORK", "muted", T.alpha.scrollThumb)
    thumb.tex:SetAllPoints()
    bar.thumb = thumb
    thumb:SetScript("OnEnter", function(self) T.Paint(self.tex, "accent", T.alpha.scrollThumb) end)
    thumb:SetScript("OnLeave", function(self) T.Paint(self.tex, "muted", T.alpha.scrollThumb) end)
    thumb:SetScript("OnMouseDown", function()
        local _, cy = GetCursorPosition()
        bar.dragStartY, bar.dragStartScroll = cy, scrollFrame:GetVerticalScroll()
        thumb:SetScript("OnUpdate", function() DragThumb(bar) end)
    end)
    thumb:SetScript("OnMouseUp", function() thumb:SetScript("OnUpdate", nil) end)
    local function Update() UpdateScrollBar(bar) end
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta) ScrollBy(self, delta) end)
    scrollFrame:HookScript("OnScrollRangeChanged", Update)
    scrollFrame:HookScript("OnVerticalScroll", Update)
    scrollFrame:HookScript("OnSizeChanged", Update)
    bar.Update = Update
    bar:Hide()
    return bar
end

-- --- Rows, sections, layout stack --------------------------------------------

local function AttachNoteTooltip(row)
    local hit = CreateFrame("Frame", nil, row)
    hit:SetPoint("TOPLEFT", row.label, "TOPLEFT")
    hit:SetPoint("BOTTOMRIGHT", row.label, "BOTTOMRIGHT")
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", function(self)
        if row.noteText and ns.UI then ns.UI.ShowTooltip(self, row.label:GetText(), row.noteText) end
    end)
    hit:SetScript("OnLeave", function() if ns.UI then ns.UI.HideTooltip() end end)
    row.hit = hit
end

-- A settings row: label (+ optional note) on the left, control on the right.
function W.Row(parent, label, note, control)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(M.rowH)
    row.label = W.Text(row, "label", "fg")
    row.note = W.Text(row, "note", "muted")
    row.note:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -M.labelGap)
    local div = T.Hairline(row, "line", T.alpha.rule)
    div:SetPoint("BOTTOMLEFT"); div:SetPoint("BOTTOMRIGHT")
    AttachNoteTooltip(row)

    function row:SetLabel(text, noteText)
        self.label:SetText(text or "")
        self.noteText = noteText
        self.note:SetText(noteText or "")
        self.note:SetShown(noteText ~= nil and noteText ~= "")
        self.label:ClearAllPoints()
        local offset = self.note:IsShown() and (T.size.note + M.labelGap) / 2 or 0
        self.label:SetPoint("LEFT", self, "LEFT", M.rowInset, offset)
    end
    function row:SetControl(ctrl)
        self.control = ctrl
        if ctrl then
            ctrl:ClearAllPoints()
            ctrl:SetPoint("RIGHT", self, "RIGHT", -M.rowInset, 0)
        end
    end
    function row:SetEnabled(on)
        self:SetAlpha(on and 1 or T.alpha.dim)
        if self.control then
            if self.control.SetEnabled then self.control:SetEnabled(on) else self.control:EnableMouse(on) end
            self.control:SetAlpha(1)
        end
    end
    function row:refresh()
        if self.control and self.control.refresh then self.control:refresh() end
    end
    row:SetLabel(label, note)
    if control then row:SetControl(control) end
    return row
end

-- Section header: accent heading with an optional right-aligned button.
function W.Section(parent, title, buttonOpts)
    local sec = CreateFrame("Frame", nil, parent)
    sec:SetHeight(M.sectionH)
    sec.title = T.Font(sec, "section", "accent", true)
    sec.title:SetPoint("BOTTOMLEFT", sec, "BOTTOMLEFT", 0, 8)
    sec.title:SetText(title or "")
    if buttonOpts then
        sec.button = W.Button(sec, buttonOpts)
        sec.button:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", -M.rowInset, 4)
    end
    return sec
end

-- A muted note line (also used for inline errors with colorKey "danger").
function W.Note(parent, text, colorKey)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(T.size.note + 12)
    f.text = W.Text(f, "note", colorKey or "muted")
    f.text:SetPoint("LEFT", f, "LEFT", M.rowInset, 0)
    f.text:SetPoint("RIGHT", f, "RIGHT", -M.rowInset, 0)
    f.text:SetText(text or "")
    function f:SetText(s, key)
        self.text:SetText(s or "")
        if key then T.SetTextColor(self.text, key) end
    end
    return f
end

local Stack = {}
Stack.__index = Stack

-- Vertical layout over a page content frame. Items are frames with fixed or
-- dynamic heights; Reflow() re-stacks the shown ones and sizes the content.
function W.Stack(content)
    return setmetatable({ content = content, items = {} }, Stack)
end

function Stack:Add(frame, gapAbove)
    frame:SetParent(self.content)
    self.items[#self.items + 1] = { frame = frame, gap = gapAbove or 0 }
    return frame
end

function Stack:Section(title, buttonOpts)
    return self:Add(W.Section(self.content, title, buttonOpts), #self.items > 0 and M.gap or 0)
end

function Stack:Row(label, note, control)
    return self:Add(W.Row(self.content, label, note, control))
end

function Stack:Note(text, colorKey)
    return self:Add(W.Note(self.content, text, colorKey))
end

-- A container for pooled rows (dynamic lists). See W.RowPool.
function Stack:Container()
    local f = CreateFrame("Frame", nil, self.content)
    f:SetHeight(1)
    return self:Add(f)
end

function Stack:Reflow()
    local y = 0
    for _, item in ipairs(self.items) do
        local f = item.frame
        if f:IsShown() then
            y = y + item.gap
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
            f:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
            y = y + f:GetHeight()
        end
    end
    self.content:SetHeight(math.max(1, y + M.gap))
end

function Stack:Refresh()
    for _, item in ipairs(self.items) do
        local f = item.frame
        if f.refresh then f:refresh() end
    end
end

-- Pooled rows inside a container: pool:Get(i) creates or reuses row i via
-- make(container); pool:Finish(n) hides the rest and sizes the container.
function W.RowPool(container, make)
    local pool = { rows = {} }
    function pool:Get(i)
        local row = self.rows[i]
        if not row then
            row = make(container)
            self.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * M.rowH)
        row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        row:Show()
        return row
    end
    function pool:Finish(n)
        for i = n + 1, #self.rows do self.rows[i]:Hide() end
        container:SetHeight(math.max(1, n * M.rowH))
        container:SetShown(n > 0)
    end
    return pool
end
