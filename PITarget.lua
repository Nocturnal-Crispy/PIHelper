-- PITarget.lua
-- Settings GUI: trinket toggles, potion toggle, macro preview

local FRAME_W  = 320
local FRAME_H  = 590
local TITLE_H  = 28   -- approx height of BasicFrameTemplate title bar
local PAD      = 10   -- left/right/bottom content padding

-- Layout cursor constants — each section advances cursorY by its own row
-- count, so adding/removing rows (e.g. POTION_OPTIONS entries) never requires
-- hand-recalculating the offsets of sections below it.
local ROW_H         = 24  -- checkbox / radio row height+spacing
local TRINKET_ROW_H = 26  -- trinket row height+spacing
local SECTION_GAP   = 14  -- vertical gap between sections

-- ─── Main Frame ───────────────────────────────────────────────────────────────

local f = CreateFrame("Frame", "PIHelperFrame", UIParent, "BasicFrameTemplate")
f:SetSize(FRAME_W, FRAME_H)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    PIHelperDB.framePos = { point = point, relPoint = relPoint, x = x, y = y }
end)
f:SetClampedToScreen(true)
f:Hide()

-- Let ESC close the frame (and not fall through to the game menu).
tinsert(UISpecialFrames, "PIHelperFrame")

if f.TitleText then
    f.TitleText:SetText("PIHelper")
end

-- Restore last-dragged position. Called from PIHelper.lua's ADDON_LOADED
-- handler once PIHelperDB is guaranteed to exist.
function PIHelper_RestoreFramePosition()
    local p = PIHelperDB and PIHelperDB.framePos
    if not p then return end
    f:ClearAllPoints()
    -- Assumes relativeTo is always UIParent (true for this frame).
    -- If that changes, save/restore relativeTo too.
    f:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
end

-- ─── Target Display ───────────────────────────────────────────────────────────

local targetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
targetLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(TITLE_H + 8))
targetLabel:SetText("Target: |cffaaaaaa(none set)|r")

local targetHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
targetHint:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -2)
targetHint:SetText("Target a player and use /pih to change")

local setTargetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
setTargetBtn:SetSize(112, 22)
setTargetBtn:SetPoint("TOPLEFT", targetHint, "BOTTOMLEFT", 0, -8)
setTargetBtn:SetText("Set from Target")
setTargetBtn:SetScript("OnClick", function()
    PIHelper_SetTargetFromUnit()
end)

local clearTargetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
clearTargetBtn:SetSize(60, 22)
clearTargetBtn:SetPoint("LEFT", setTargetBtn, "RIGHT", 6, 0)
clearTargetBtn:SetText("Clear")
clearTargetBtn:SetScript("OnClick", function()
    PIHelperDB.target = ""
    PIHelper_UpdateMacro()
    if PIHelper_RefreshGUI then PIHelper_RefreshGUI() end
end)

-- ─── Trinket Section ──────────────────────────────────────────────────────────

local trinketHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
trinketHeader:SetPoint("TOPLEFT", setTargetBtn, "BOTTOMLEFT", 0, -12)
trinketHeader:SetText("On-Use Trinkets:")
trinketHeader:SetTextColor(1, 0.82, 0)

-- Manual rescan — trinkets are sometimes not yet cached right after login.
local scanTrinketsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
scanTrinketsBtn:SetSize(56, 20)
scanTrinketsBtn:SetPoint("LEFT", trinketHeader, "RIGHT", 8, 0)
scanTrinketsBtn:SetText("Scan")
scanTrinketsBtn:SetScript("OnClick", function()
    PIHelper_ScanTrinkets()
end)

local cursorY = 0 -- offset (negative) from trinketHeader:BOTTOMLEFT for the next section

-- PIHelper_TRINKET_SLOTS is defined in PIHelper.lua (loads first per toc order).
local trinketRows = {}
for i, slot in ipairs(PIHelper_TRINKET_SLOTS) do
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", -2, cursorY - ((i - 1) * TRINKET_ROW_H) - 4)
    cb:SetSize(24, 24)
    cb.slotID = slot

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)

    cb:SetScript("OnClick", function(self)
        local t = PIHelper_Trinkets[self.slotID]
        if not t then return end
        PIHelperDB.trinketEnabled[t.itemID] = self:GetChecked() and true or false
        PIHelper_UpdateMacro()
    end)

    trinketRows[slot] = { check = cb, label = lbl }
end
cursorY = cursorY - (#PIHelper_TRINKET_SLOTS * TRINKET_ROW_H) - SECTION_GAP

local noTrinketLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
noTrinketLabel:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", 4, -8)
noTrinketLabel:SetText("No on-use trinkets detected.")
noTrinketLabel:Hide()

-- ─── Potion Section ───────────────────────────────────────────────────────────

local POTION_OPTIONS = {
    "Draught of Rampant Abandon",
    "Potion of Zealotry",
    "Potion of Recklessness",
    "Light's Potential",
}

local potionCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
potionCheck:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", -2, cursorY)
potionCheck:SetSize(24, 24)
cursorY = cursorY - ROW_H

local potionLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
potionLabel:SetPoint("LEFT", potionCheck, "RIGHT", 4, 0)
potionLabel:SetText("Use Combat Potion")

-- Radio buttons — one per potion option, shown when potionCheck is enabled.
local potionRadios = {}
for i, name in ipairs(POTION_OPTIONS) do
    local rb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    rb:SetPoint("TOPLEFT", potionCheck, "BOTTOMLEFT", 20, -((i - 1) * ROW_H) - 4)
    rb:SetSize(20, 20)
    rb.potionName = name

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", rb, "RIGHT", 4, 0)
    lbl:SetText(name)

    rb:SetScript("OnClick", function(self)
        for _, r in ipairs(potionRadios) do
            r.button:SetChecked(r.button == self)
        end
        PIHelperDB.potionName = self.potionName
        PIHelper_UpdateMacro()
    end)

    rb:Hide()
    lbl:Hide()

    potionRadios[i] = { button = rb, label = lbl }
end
cursorY = cursorY - (#POTION_OPTIONS * ROW_H) - SECTION_GAP

local function SetPotionRadiosShown(shown)
    for _, r in ipairs(potionRadios) do
        r.button:SetShown(shown)
        r.label:SetShown(shown)
    end
end

potionCheck:SetScript("OnClick", function(self)
    PIHelperDB.usePotion = self:GetChecked()
    SetPotionRadiosShown(PIHelperDB.usePotion)
    -- Only default to the first option when truly no potion has ever been chosen.
    -- Do NOT auto-select when disabling then re-enabling — that would silently
    -- overwrite a previously saved selection with POTION_OPTIONS[1].
    if PIHelperDB.usePotion and PIHelperDB.potionName == "" then
        PIHelperDB.potionName = POTION_OPTIONS[1]
        for _, r in ipairs(potionRadios) do
            r.button:SetChecked(r.button.potionName == PIHelperDB.potionName)
        end
    end
    PIHelper_UpdateMacro()
end)

-- ─── Vampiric Embrace Section ─────────────────────────────────────────────────

local vampiricEmbraceCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
vampiricEmbraceCheck:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", -2, cursorY)
vampiricEmbraceCheck:SetSize(24, 24)
cursorY = cursorY - ROW_H - SECTION_GAP

local vampiricEmbraceLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
vampiricEmbraceLabel:SetPoint("LEFT", vampiricEmbraceCheck, "RIGHT", 4, 0)
vampiricEmbraceLabel:SetText("Use Vampiric Embrace")

vampiricEmbraceCheck:SetScript("OnClick", function(self)
    PIHelperDB.useVampiricEmbrace = self:GetChecked() and true or false
    PIHelper_UpdateMacro()
end)

-- ─── Macro Preview ────────────────────────────────────────────────────────────

local previewHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
previewHeader:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", 0, cursorY)
previewHeader:SetText("Macro Preview:")
previewHeader:SetTextColor(0.6, 0.6, 0.6)

local previewBox = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
previewBox:SetPoint("TOPLEFT", previewHeader, "BOTTOMLEFT", -2, -4)
previewBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)

local previewText = previewBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
previewText:SetPoint("TOPLEFT", previewBox, "TOPLEFT", 8, -8)
previewText:SetPoint("BOTTOMRIGHT", previewBox, "BOTTOMRIGHT", -8, 8)
previewText:SetJustifyH("LEFT")
previewText:SetJustifyV("TOP")
previewText:SetWordWrap(true)

-- ─── Refresh (called from PIHelper.lua) ───────────────────────────────────────

function PIHelper_RefreshGUI()
    local db = PIHelperDB

    -- Target label
    if db.target ~= "" then
        targetLabel:SetText("Target: |cffffd700" .. db.target .. "|r")
    else
        targetLabel:SetText("Target: |cffaaaaaa(none set)|r")
    end

    -- Trinket rows
    local anyFound = false
    for _, slot in ipairs(PIHelper_TRINKET_SLOTS) do
        local row = trinketRows[slot]
        local t   = PIHelper_Trinkets[slot]
        if t then
            anyFound = true
            row.check:Show()
            row.label:Show()
            row.label:SetText(t.name .. " (slot " .. slot .. ")")
            row.check:SetChecked(db.trinketEnabled[t.itemID] ~= false)
        else
            row.check:Hide()
            row.label:Hide()
        end
    end
    noTrinketLabel:SetShown(not anyFound)

    -- Potion
    potionCheck:SetChecked(db.usePotion)
    SetPotionRadiosShown(db.usePotion)
    for _, r in ipairs(potionRadios) do
        r.button:SetChecked(r.button.potionName == db.potionName)
    end

    -- Vampiric Embrace
    vampiricEmbraceCheck:SetChecked(db.useVampiricEmbrace)

    -- Macro preview — single source of truth via PIHelper_BuildMacroBody()
    previewText:SetText(PIHelper_BuildMacroBody())
end
