-- CDOptionsDisplay.lua
-- CD tracker settings pages: Glow & Text, Alert, Frames, Profiles.
-- Every write goes through ns.CD; the config table is re-read in each callback.

local _, ns = ...

local T = ns.Theme
local M = T.metric
local W = ns.Widgets

local GROUP = "CD TRACKER"
local WIDE = M.windowW - M.sidebarW - M.contentX - M.contentRight - 2 * M.rowInset

local function Cfg() return ns.CD.GetConfig() end
local function Apply(fn) ns.CD.ApplySettingsChange(fn) end

local function RefreshStack(page)
    page.stack:Refresh()
    page.stack:Reflow()
end

local function KeySlider(content, key, lo, hi, step)
    return W.Slider(content, { min = lo, max = hi, step = step,
        get = function() return Cfg()[key] end,
        set = function(v) Apply(function(c) c[key] = v end) end })
end

local function NameItems(list)
    local out = {}
    for i, name in ipairs(list) do out[i] = { value = name, label = name } end
    return out
end

-- Holds several controls side by side, right-aligned, as one row control.
local function Group(content, controls)
    local holder = CreateFrame("Frame", nil, content)
    local w, h = 0, M.buttonH
    for i = #controls, 1, -1 do
        local c = controls[i]
        c:SetParent(holder)
        c:ClearAllPoints()
        c:SetPoint("RIGHT", holder, "RIGHT", -w, 0)
        w = w + c:GetWidth() + (i > 1 and M.gap or 0)
        h = math.max(h, c:GetHeight())
    end
    holder:SetSize(w, h)
    holder.controls = controls
    function holder:refresh()
        for _, c in ipairs(self.controls) do if c.refresh then c:refresh() end end
    end
    return holder
end

-- --- Glow & Text -------------------------------------------------------------

local function BuildDisplay(content, page)
    local st = W.Stack(content)
    page.stack = st
    st:Section("Glow")
    page.lcgRow = st:Row("Prefer LibCustomGlow", nil, W.Toggle(content, {
        get = function() return Cfg().preferLibCustomGlow end,
        set = function(v) Apply(function(c) c.preferLibCustomGlow = v end) end }))
    st:Row("Glow thickness", nil, KeySlider(content, "glowThickness", 1, 6, 1))
    st:Section("Text")
    st:Row("Font", "Used for frame and alert text.", W.Dropdown(content, {
        items = function() return NameItems(ns.CDMedia.ListFonts()) end,
        get = function() return Cfg().font end,
        set = function(v) Apply(function(c) c.font = v end) end }))
    st:Row("Frame text size", nil, KeySlider(content, "frameFontSize", 6, 24, 1))
    st:Row("Alert text size", nil, KeySlider(content, "alertFontSize", 8, 32, 1))
    st:Row("Class-colored names", "Color the alert name by class.", W.Toggle(content, {
        get = function() return Cfg().classColorNames end,
        set = function(v) Apply(function(c) c.classColorNames = v end) end }))
    st:Section("Sound")
    local dd = W.Dropdown(content, {
        items = function() return NameItems(ns.CDMedia.ListSounds()) end,
        get = function() return Cfg().sound end,
        set = function(v) Apply(function(c) c.sound = v end) end })
    local play = W.Button(content, { label = "Play", onClick = function() ns.CDMedia.PlaySound(Cfg().sound) end })
    st:Row("Alert sound", "Played when a highlight starts.", Group(content, { dd, play }))
end

local function RefreshDisplay(_, page)
    local lcg = ns.CDGlow.LCGAvailable()
    page.lcgRow:SetLabel("Prefer LibCustomGlow", lcg and "Use LibCustomGlow for Pixel and Proc when loaded."
        or "LibCustomGlow not loaded.")
    RefreshStack(page)
    page.lcgRow:SetEnabled(lcg)
end

-- --- Alert -------------------------------------------------------------------

local function BuildAlert(content, page)
    local st = W.Stack(content)
    page.stack = st
    st:Section("Position")
    page.lockBtn = W.Button(content, { label = "Unlock alert", primary = true, width = 110, onClick = function()
        if ns.CDAlert.IsUnlocked() then ns.CDAlert.Lock() else ns.CDAlert.Unlock() end
    end })
    local reset = W.Button(content, { label = "Reset position", onClick = function() ns.CDAlert.ResetPosition() end })
    st:Row("Move alert", "Drag the alert; it snaps to the screen center within 8 px.", Group(content, { page.lockBtn, reset }))
    page.posText = W.Text(content, "label", "muted")
    local posHolder = CreateFrame("Frame", nil, content)
    posHolder:SetSize(140, M.buttonH)
    page.posText:SetParent(posHolder)
    page.posText:SetPoint("RIGHT", posHolder, "RIGHT")
    page.posText:SetJustifyH("RIGHT")
    st:Row("Offset from center", nil, posHolder)
    st:Row("Scale", nil, W.Slider(content, { min = 0.5, max = 2.0, step = 0.05,
        get = function() return Cfg().alert.scale end,
        set = function(v) Apply(function(c) c.alert.scale = v end) end }))
    st:Section("Preview")
    st:Row("Test alert", "Shows a sample alert for 10 seconds.", W.Button(content, {
        label = "Test alert", onClick = function() ns.CDAlert.Test(10) end }))
end

local function RefreshAlert(_, page)
    page.lockBtn:SetLabel(ns.CDAlert.IsUnlocked() and "Lock alert" or "Unlock alert")
    local x, y = ns.CDAlert.GetPosition()
    page.posText:SetText(string.format("X: %d   Y: %d", x, y))
    RefreshStack(page)
end

-- --- Frames ------------------------------------------------------------------

local COLS = { 0, 220, 340 }

local function TableLine(parent, colorKey)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(M.menuRowH + 4)
    line.cells = {}
    for i, x in ipairs(COLS) do
        local fs = W.Text(line, "label", colorKey)
        fs:SetPoint("LEFT", line, "LEFT", M.rowInset + x, 0)
        line.cells[i] = fs
    end
    local div = T.Hairline(line, "line", T.alpha.rule)
    div:SetPoint("BOTTOMLEFT"); div:SetPoint("BOTTOMRIGHT")
    return line
end

local function BuildFrames(content, page)
    local st = W.Stack(content)
    page.stack = st
    st:Section("Frame providers")
    local head = st:Add(TableLine(content, "muted"))
    head.cells[1]:SetText("Provider"); head.cells[2]:SetText("Loaded"); head.cells[3]:SetText("Frames found")
    page.lines = {}
    for i = 1, #ns.CDFrames.GetProviderStats() do page.lines[i] = st:Add(TableLine(content, "fg")) end
    st:Section("Options")
    st:Row("Custom frame prefix", "Frame name prefix for unsupported frame addons. Letters, digits, _.",
        W.EditBox(content, { width = M.dropdownW, maxLetters = 64,
            get = function() return Cfg().customFramePrefix end,
            set = function(text)
                text = text:gsub("^%s+", ""):gsub("%s+$", "")
                if #text > 64 or not text:find("^[%w_]*$") then
                    page.prefixError:SetText("Prefix may only contain letters, digits and _.", "danger")
                    return
                end
                page.prefixError:SetText("")
                Apply(function(c) c.customFramePrefix = text end)
            end }))
    page.prefixError = st:Note("", "danger")
    local rescan = W.Button(content, { label = "Re-scan frames", onClick = function()
        ns.CDFrames.RequestResolve(0)
        ns.UI.Refresh()
    end })
    local test = W.Button(content, { label = "Test highlight", onClick = function() ns.CD.Test(10) end })
    st:Row("Frames", "Re-scan after changing frame addons or layouts.", Group(content, { rescan, test }))
end

local function RefreshFrames(_, page)
    for i, p in ipairs(ns.CDFrames.GetProviderStats()) do
        local line = page.lines[i]
        if line then
            line.cells[1]:SetText(p.label)
            line.cells[2]:SetText(p.loaded and "Yes" or "No")
            line.cells[3]:SetText(tostring(p.count))
            T.SetTextColor(line.cells[2], p.loaded and "success" or "muted")
        end
    end
    RefreshStack(page)
end

-- --- Profiles ----------------------------------------------------------------

local function Box(st, content, opts)
    local holder = CreateFrame("Frame", nil, content)
    holder:SetHeight(M.multiEditH + M.gap)
    local box = W.MultiEdit(holder, opts)
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", M.rowInset, 0)
    st:Add(holder)
    return box
end

local function SetStatus(page, text, key)
    page.status:SetText(text or "", key)
end

local function DoExport(page)
    page.exportBox:SetText(ns.CD.ExportString())
    page.exportBox:HighlightAll()
    page.exportNote:SetText("Press Ctrl+C to copy.", "muted")
end

local function BuildProfiles(content, page)
    local st = W.Stack(content)
    page.stack = st
    st:Section("Export", { label = "Export", primary = true, onClick = function() DoExport(page) end })
    page.exportBox = Box(st, content, { width = WIDE, readOnly = true })
    page.exportNote = st:Note("")
    st:Section("Import", { label = "Import", primary = true, onClick = function()
        local ok, err = ns.CD.ImportString(page.importBox:GetText())
        if ok then
            page.importBox:Clear()
            SetStatus(page, "Profile imported.", "success")
        else
            SetStatus(page, err, "danger")
        end
    end })
    page.importBox = Box(st, content, { width = WIDE, maxLetters = 65536 })
    page.status = st:Note("")
    st:Section("Reset")
    st:Row("Reset to defaults", "Alert position and minimap button are kept.", W.Button(content, {
        label = "Reset to defaults", onClick = function()
            W.Confirm(ns.UI.Window(), "Reset all CD tracker settings to their defaults?", "Reset", function()
                ns.CD.ResetToDefaults()
                SetStatus(page, "Settings reset to defaults.", "success")
            end)
        end }))
end

local function RefreshProfiles(_, page, opts)
    if opts and opts.export then DoExport(page) end
    page.stack:Reflow()
end

-- --- Registration ------------------------------------------------------------

local function Register(key, label, order, subtitle, build, refresh)
    ns.UI.RegisterPage({ key = key, group = GROUP, label = label, order = order, title = label,
        subtitle = subtitle, build = build, refresh = refresh })
end

Register("cd_display", "Glow & Text", 5, "Glow look, fonts and the alert sound.", BuildDisplay, RefreshDisplay)
Register("cd_alert", "Alert", 6, "Position and scale of the on-screen alert.", BuildAlert, RefreshAlert)
Register("cd_frames", "Frames", 7, "Raid frame addons and frame detection.", BuildFrames, RefreshFrames)
Register("cd_profiles", "Profiles", 8, "Import, export or reset the CD tracker profile.", BuildProfiles, RefreshProfiles)
