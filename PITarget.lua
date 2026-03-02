-- PITarget.lua
-- Settings GUI: trinket blacklist, potion toggle, macro preview

local FRAME_W  = 320
local FRAME_H  = 390
local TITLE_H  = 28   -- approx height of BasicFrameTemplate title bar
local PAD      = 10   -- left/right/bottom content padding

-- ─── Main Frame ───────────────────────────────────────────────────────────────
-- Use BasicFrameTemplate (no Inset child) and parent content directly to f.

local f = CreateFrame("Frame", "PIHelperFrame", UIParent, "BasicFrameTemplate")
f:SetSize(FRAME_W, FRAME_H)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetClampedToScreen(true)
f:Hide()

-- TitleText exists on BasicFrameTemplate but guard in case WoW changes it.
if f.TitleText then
    f.TitleText:SetText("PIHelper")
end

-- ─── Target Display ───────────────────────────────────────────────────────────

local targetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
targetLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(TITLE_H + 8))
targetLabel:SetText("Target: |cffaaaaaa(none set)|r")

local targetHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
targetHint:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -2)
targetHint:SetText("Target a player and use /pih to change")

-- ─── Trinket Section ──────────────────────────────────────────────────────────

local trinketHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
trinketHeader:SetPoint("TOPLEFT", targetHint, "BOTTOMLEFT", 0, -12)
trinketHeader:SetText("On-Use Trinkets:")
trinketHeader:SetTextColor(1, 0.82, 0)

-- Two rows, one per trinket slot (shown/hidden individually).
-- Labels created manually; don't rely on template internals.
local trinketRows = {}
for i, slot in ipairs({ 13, 14 }) do
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", -2, -((i - 1) * 26) - 4)
    cb:SetSize(24, 24)
    cb.slotID = slot

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)

    cb:SetScript("OnClick", function(self)
        local t = PIHelper_Trinkets[self.slotID]
        if not t then return end
        if self:GetChecked() then
            PIHelperDB.blacklist[t.itemID] = nil
        else
            PIHelperDB.blacklist[t.itemID] = true
        end
        PIHelper_UpdateMacro()
    end)

    trinketRows[slot] = { check = cb, label = lbl }
end

local noTrinketLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
noTrinketLabel:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", 4, -8)
noTrinketLabel:SetText("No on-use trinkets detected.")
noTrinketLabel:Hide()

-- ─── Potion Section ───────────────────────────────────────────────────────────
-- Fixed 66px below trinketHeader — room for 2 trinket rows (26px each) + gap.

local potionCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
potionCheck:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", -2, -66)
potionCheck:SetSize(24, 24)

local potionLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
potionLabel:SetPoint("LEFT", potionCheck, "RIGHT", 4, 0)
potionLabel:SetText("Use Combat Potion")

local potionInput = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
potionInput:SetSize(FRAME_W - 50, 22)
potionInput:SetPoint("TOPLEFT", potionCheck, "BOTTOMLEFT", 20, -2)
potionInput:SetAutoFocus(false)
potionInput:SetMaxLetters(100)
potionInput:Hide()

local function SavePotionName(self)
    PIHelperDB.potionName = self:GetText()
    PIHelper_UpdateMacro()
end

potionInput:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    SavePotionName(self)
end)
potionInput:SetScript("OnEditFocusLost", SavePotionName)

potionCheck:SetScript("OnClick", function(self)
    PIHelperDB.usePotion = self:GetChecked()
    potionInput:SetShown(PIHelperDB.usePotion)
    PIHelper_UpdateMacro()
end)

-- ─── Macro Preview ────────────────────────────────────────────────────────────
-- Fixed 130px below trinketHeader — clears trinkets + potion + input + gap.

local previewHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
previewHeader:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", 0, -130)
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
    for _, slot in ipairs({ 13, 14 }) do
        local row = trinketRows[slot]
        local t   = PIHelper_Trinkets[slot]
        if t then
            anyFound = true
            row.check:Show()
            row.label:Show()
            row.label:SetText(t.name .. " (slot " .. slot .. ")")
            row.check:SetChecked(not db.blacklist[t.itemID])
        else
            row.check:Hide()
            row.label:Hide()
        end
    end
    noTrinketLabel:SetShown(not anyFound)

    -- Potion
    potionCheck:SetChecked(db.usePotion)
    potionInput:SetShown(db.usePotion)
    potionInput:SetText(db.potionName or "")

    -- Macro preview
    local lines = {}
    for _, slot in ipairs({ 13, 14 }) do
        local t = PIHelper_Trinkets[slot]
        if t and not db.blacklist[t.itemID] then
            lines[#lines + 1] = "/use " .. slot
        end
    end
    if db.usePotion and db.potionName ~= "" then
        lines[#lines + 1] = "/use " .. db.potionName
    end
    local clause = (db.target ~= "") and ("[@" .. db.target .. ",exists,nodead]") or ""
    lines[#lines + 1] = "/cast [@mouseover,help,nodead]" .. clause .. "[] Power Infusion"
    previewText:SetText(table.concat(lines, "\n"))
end
