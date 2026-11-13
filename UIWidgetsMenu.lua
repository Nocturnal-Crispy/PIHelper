-- UIWidgetsMenu.lua
-- The heavier widgets: dropdown with its shared popup menu, multi-line edit
-- box in a slim-scroll frame, and the confirmation modal. Split out of
-- UIWidgets.lua to keep both files focused.

local _, ns = ...

local T = ns.Theme
local M = T.metric
local W = ns.Widgets

-- --- Shared dropdown menu ----------------------------------------------------

local menu -- created on first open

local function CloseMenu()
    if not menu then return end
    menu:Hide()
    menu.catcher:Hide()
    menu:UnregisterEvent("PLAYER_REGEN_DISABLED")
    menu.owner = nil
end
W.CloseMenu = CloseMenu

local function MenuRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(M.menuRowH)
    b.hl = T.Solid(b, "BACKGROUND", "accent", T.alpha.navFill)
    b.hl:SetAllPoints()
    b.hl:Hide()
    b.text = W.Text(b, "control", "fg")
    b.text:SetPoint("LEFT", b, "LEFT", M.dropdownTextX, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -M.dropdownTextX, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function(self) self.hl:Show() end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    b:SetScript("OnClick", function(self)
        local owner = menu.owner
        CloseMenu()
        if owner then owner:Choose(self.value) end
    end)
    return b
end

local function CreateMenu()
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu.bg = T.Solid(menu, "BACKGROUND", "panel", 1)
    menu.bg:SetAllPoints()
    menu.border = T.Border(menu, "line")
    menu.scroll = CreateFrame("ScrollFrame", nil, menu)
    menu.scroll:SetPoint("TOPLEFT", 1, -1)
    menu.scroll:SetPoint("BOTTOMRIGHT", -(M.scrollW + M.scrollGap + 1), 1)
    menu.child = CreateFrame("Frame", nil, menu.scroll)
    menu.child:SetSize(1, 1)
    menu.scroll:SetScrollChild(menu.child)
    menu.bar = W.SlimScroll(menu.scroll)
    menu.bar:ClearAllPoints()
    menu.bar:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -1)
    menu.bar:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -1, 1)
    menu.rows = {}

    -- Full-screen click catcher one strata below the menu closes it.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", CloseMenu)
    catcher:Hide()
    menu.catcher = catcher

    -- Escape closes the menu without leaking other keys. Keyboard capture is
    -- never enabled in combat, where SetPropagateKeyboardInput is restricted.
    menu:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then CloseMenu() end
    end)
    menu:SetScript("OnEvent", CloseMenu) -- PLAYER_REGEN_DISABLED, only while open
    menu:Hide()
end

local function OpenMenu(dd)
    if not menu then CreateMenu() end
    if menu.owner == dd and menu:IsShown() then CloseMenu() return end
    local items = dd.opts.items()
    local width = dd:GetWidth()
    local current = dd.opts.get()
    for i, item in ipairs(items) do
        local row = menu.rows[i] or MenuRow(menu.child)
        menu.rows[i] = row
        row.value = item.value
        row.text:SetText(item.label)
        T.SetTextColor(row.text, item.value == current and "accent" or "fg")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu.child, "TOPLEFT", 0, -(i - 1) * M.menuRowH)
        row:SetWidth(width - M.scrollW - M.scrollGap - 2)
        row:Show()
    end
    for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
    local contentH = math.max(1, #items * M.menuRowH)
    menu.child:SetSize(width - M.scrollW - M.scrollGap - 2, contentH)
    menu:SetSize(width, math.min(contentH, M.menuMaxH) + 2)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    menu.scroll:SetVerticalScroll(0)
    menu.owner = dd
    menu.catcher:Show()
    menu:Show()
    menu:Raise()
    menu:EnableKeyboard(not InCombatLockdown())
    menu:RegisterEvent("PLAYER_REGEN_DISABLED")
    menu.bar.Update()
end

-- --- Dropdown ----------------------------------------------------------------

local function Chevron(dd)
    local function Line(rot, dx)
        local l = dd:CreateTexture(nil, "OVERLAY")
        T.Paint(l, "muted", 1)
        l:SetSize(1, M.chevronLen)
        l:SetPoint("RIGHT", dd, "RIGHT", -(M.dropdownTextX + 2) + dx, 0)
        l:SetRotation(rot)
        return l
    end
    Line(math.rad(45), -4)
    Line(math.rad(-45), 0)
end

-- opts = { items = function() return {{value, label}} end, get, set, width }
-- Items are rebuilt every time the menu opens (late-registered media shows up).
function W.Dropdown(parent, opts)
    local dd = CreateFrame("Button", nil, parent)
    dd.opts = opts
    dd:SetSize(opts.width or M.dropdownW, M.dropdownH)
    dd.bg = T.Solid(dd, "BACKGROUND", "panel", 1)
    dd.bg:SetAllPoints()
    dd.border = T.Border(dd, "line")
    dd.text = W.Text(dd, "control", "fg")
    dd.text:SetPoint("LEFT", dd, "LEFT", M.dropdownTextX, 0)
    dd.text:SetPoint("RIGHT", dd, "RIGHT", -(M.dropdownTextX + M.chevronLen + 8), 0)
    dd.text:SetWordWrap(false)
    Chevron(dd)
    dd.enabled = true

    function dd:Choose(value)
        self.opts.set(value)
        self:refresh()
    end
    function dd:refresh()
        local cur = self.opts.get()
        local label = cur ~= nil and tostring(cur) or ""
        for _, item in ipairs(self.opts.items()) do
            if item.value == cur then label = item.label break end
        end
        self.text:SetText(label)
    end
    function dd:SetEnabled(on)
        W.SetFrameEnabled(self, on)
        if not on and menu and menu.owner == self then CloseMenu() end
    end
    dd:SetScript("OnEnter", function(self) self.border:SetColor("accent", 1) end)
    dd:SetScript("OnLeave", function(self) self.border:SetColor("line", 1) end)
    dd:SetScript("OnClick", function(self) OpenMenu(self) end)
    dd:SetScript("OnHide", function(self)
        if menu and menu.owner == self then CloseMenu() end
    end)
    dd:refresh()
    return dd
end

-- --- Multi-line edit box -----------------------------------------------------

-- opts = { width, height, readOnly, maxLetters }
-- Returns a holder with :SetText, :GetText, :HighlightAll, :Focus, :Clear.
function W.MultiEdit(parent, opts)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(opts.width or 400, opts.height or M.multiEditH)
    holder.bg = T.Solid(holder, "BACKGROUND", "bg", 1)
    holder.bg:SetAllPoints()
    holder.border = T.Border(holder, "black")

    local sf = CreateFrame("ScrollFrame", nil, holder)
    sf:SetPoint("TOPLEFT", M.editInset, -M.editInset)
    sf:SetPoint("BOTTOMRIGHT", -(M.scrollW + M.scrollGap + M.editInset), M.editInset)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(T.font.body, T.size.control, "")
    T.SetTextColor(eb, "fg")
    eb:SetMaxLetters(opts.maxLetters or 0)
    eb:SetWidth((opts.width or 400) - M.scrollW - M.scrollGap - 2 * M.editInset)
    sf:SetScrollChild(eb)
    local bar = W.SlimScroll(sf)
    bar:ClearAllPoints()
    bar:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -M.editInset, -M.editInset)
    bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -M.editInset, M.editInset)
    holder.edit = eb

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function() holder.border:SetColor("accent", 1) end)
    eb:SetScript("OnEditFocusLost", function() holder.border:SetColor("black", 1) end)
    eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local top = sf:GetVerticalScroll()
        local viewH = sf:GetHeight()
        y = -y
        if y < top then sf:SetVerticalScroll(y)
        elseif y + h > top + viewH then sf:SetVerticalScroll(math.min(sf:GetVerticalScrollRange(), y + h - viewH)) end
    end)
    if opts.readOnly then
        eb:SetScript("OnTextChanged", function(self, userInput)
            if userInput and holder.fixed then self:SetText(holder.fixed) self:HighlightText() end
        end)
    end
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() eb:SetFocus() end)

    function holder:SetText(s)
        self.fixed = s
        eb:SetText(s or "")
        eb:SetCursorPosition(0)
        sf:SetVerticalScroll(0)
    end
    function holder:GetText() return eb:GetText() or "" end
    function holder:HighlightAll() eb:SetFocus() eb:HighlightText() end
    function holder:Focus() eb:SetFocus() end
    function holder:Clear() self:SetText("") end
    return holder
end

-- --- Confirmation modal ------------------------------------------------------

local modal

local function CreateModal(window)
    modal = CreateFrame("Frame", nil, window)
    modal:SetAllPoints(window)
    modal:SetFrameLevel(window:GetFrameLevel() + 100)
    modal:EnableMouse(true)
    modal.dim = T.Solid(modal, "BACKGROUND", "black", T.alpha.modalDim)
    modal.dim:SetAllPoints()
    local panel = CreateFrame("Frame", nil, modal)
    panel:SetSize(M.modalW, M.modalH)
    panel:SetPoint("CENTER")
    panel.bg = T.Solid(panel, "BACKGROUND", "panel", 1)
    panel.bg:SetAllPoints()
    panel.border = T.Border(panel, "line")
    modal.message = W.Text(panel, "label", "fg")
    modal.message:SetPoint("TOPLEFT", panel, "TOPLEFT", M.rowInset, -M.rowInset)
    modal.message:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -M.rowInset, -M.rowInset)
    modal.message:SetWordWrap(true)
    modal.confirm = W.Button(panel, { label = "Reset", primary = true, onClick = function()
        local fn = modal.onConfirm
        modal:Hide()
        if fn then fn() end
    end })
    modal.confirm:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -M.rowInset, M.rowInset - 4)
    modal.cancel = W.Button(panel, { label = "Cancel", onClick = function() modal:Hide() end })
    modal.cancel:SetPoint("RIGHT", modal.confirm, "LEFT", -M.gap, 0)
    modal:Hide()
end

-- Shows a themed confirm dialog over `window`.
function W.Confirm(window, message, confirmLabel, onConfirm)
    if not modal then CreateModal(window) end
    modal.message:SetText(message)
    modal.confirm:SetLabel(confirmLabel or "Reset")
    modal.onConfirm = onConfirm
    modal:Show()
end

function W.HideModal()
    if modal then modal:Hide() end
end
