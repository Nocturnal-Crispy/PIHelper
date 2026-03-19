-- PITarget.lua
-- Settings GUI: trinket toggles, potion toggle, macro preview

local FRAME_W  = 320
local FRAME_H  = 560
local TITLE_H  = 28   -- approx height of BasicFrameTemplate title bar
local PAD      = 10   -- left/right/bottom content padding

-- ─── Main Frame ───────────────────────────────────────────────────────────────

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
        PIHelperDB.trinketEnabled[t.itemID] = self:GetChecked() and true or false
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

local POTION_OPTIONS = {
    "Draught of Rampant Abandon",
    "Potion of Zealotry",
    "Potion of Recklessness",
    "Light's Potential",
}

local potionCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
potionCheck:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", -2, -66)
potionCheck:SetSize(24, 24)

local potionLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
potionLabel:SetPoint("LEFT", potionCheck, "RIGHT", 4, 0)
potionLabel:SetText("Use Combat Potion")

-- Radio buttons — one per potion option, shown when potionCheck is enabled.
local potionRadios = {}
for i, name in ipairs(POTION_OPTIONS) do
    local rb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    rb:SetPoint("TOPLEFT", potionCheck, "BOTTOMLEFT", 20, -((i - 1) * 24) - 4)
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

local function SetPotionRadiosShown(shown)
    for _, r in ipairs(potionRadios) do
        r.button:SetShown(shown)
        r.label:SetShown(shown)
    end
end

potionCheck:SetScript("OnClick", function(self)
    PIHelperDB.usePotion = self:GetChecked()
    SetPotionRadiosShown(PIHelperDB.usePotion)
    if PIHelperDB.usePotion and PIHelperDB.potionName == "" then
        PIHelperDB.potionName = POTION_OPTIONS[1]
    end
    PIHelper_UpdateMacro()
end)

-- ─── Macro Preview ────────────────────────────────────────────────────────────
-- 295px below trinketHeader — clears trinkets (66) + potion check (24) +
-- 8 radio rows (192) + gaps (13).

local previewHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
previewHeader:SetPoint("TOPLEFT", trinketHeader, "BOTTOMLEFT", 0, -295)
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

    -- Macro preview
    local lines = {}
    for _, slot in ipairs({ 13, 14 }) do
        local t = PIHelper_Trinkets[slot]
        if t and db.trinketEnabled[t.itemID] ~= false then
            lines[#lines + 1] = "/use " .. slot
        end
    end
    if db.usePotion and db.potionName ~= "" then
        lines[#lines + 1] = "/use " .. db.potionName
        lines[#lines + 1] = "/use Fleeting" .. db.potionName
    end
    local clause = (db.target ~= "") and ("[@" .. db.target .. ",exists,nodead]") or ""
    lines[#lines + 1] = "/cast [@mouseover,help,nodead]" .. clause .. "[] Power Infusion"
    previewText:SetText(table.concat(lines, "\n"))
end
