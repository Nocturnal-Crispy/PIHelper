-- PIHelper.lua
-- Core: events, trinket scanning, macro building, slash command

local ADDON_NAME    = "PIHelper"
local MACRO_NAME    = "PI"
local MACRO_ICON    = "INV_MISC_QUESTIONMARK"
local TRINKET_SLOTS = { 13, 14 }

-- Shared with PITarget.lua via global
PIHelper_Trinkets = {}

local pendingMacroUpdate = false

local DEFAULTS = {
    target     = "",
    blacklist  = {},
    usePotion  = false,
    potionName = "",
}

-- ─── Trinket Scanning ─────────────────────────────────────────────────────────

local function ScanTrinkets()
    local found = {}
    for _, slot in ipairs(TRINKET_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            local spellName = GetItemSpell(itemID)
            if spellName then
                local itemName = GetItemInfo(itemID) or ("Item #" .. itemID)
                found[slot] = { itemID = itemID, name = itemName }
            end
        end
    end
    PIHelper_Trinkets = found
end

-- ─── Macro Builder ────────────────────────────────────────────────────────────

local function BuildMacroBody()
    local db    = PIHelperDB
    local lines = {}

    for _, slot in ipairs(TRINKET_SLOTS) do
        local t = PIHelper_Trinkets[slot]
        if t and not db.blacklist[t.itemID] then
            lines[#lines + 1] = "/use " .. slot
        end
    end

    if db.usePotion and db.potionName ~= "" then
        lines[#lines + 1] = "/use " .. db.potionName
    end

    local targetClause = ""
    if db.target ~= "" then
        targetClause = "[@" .. db.target .. ",exists,nodead]"
    end
    lines[#lines + 1] = "/cast [@mouseover,help,nodead]" .. targetClause .. "[] Power Infusion"

    return table.concat(lines, "\n")
end

-- ─── Macro Update ─────────────────────────────────────────────────────────────

function PIHelper_UpdateMacro()
    if InCombatLockdown() then
        pendingMacroUpdate = true
        return
    end

    pendingMacroUpdate = false
    local body = BuildMacroBody()
    local idx  = GetMacroIndexByName(MACRO_NAME)

    if idx > 0 then
        EditMacro(idx, MACRO_NAME, nil, body)
    else
        local newIdx = CreateMacro(MACRO_NAME, MACRO_ICON, body)
        if not newIdx then
            print("|cffff4444PIHelper:|r Could not create macro \"" .. MACRO_NAME ..
                  "\" — macro slots may be full.")
            return
        end
    end

    if PIHelperFrame and PIHelperFrame:IsShown() and PIHelper_RefreshGUI then
        PIHelper_RefreshGUI()
    end
end

-- ─── Event Handler ────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end

        if type(PIHelperDB) ~= "table" then PIHelperDB = {} end
        for k, v in pairs(DEFAULTS) do
            if PIHelperDB[k] == nil then PIHelperDB[k] = v end
        end
        if type(PIHelperDB.blacklist) ~= "table" then
            PIHelperDB.blacklist = {}
        end

        ScanTrinkets()
        PIHelper_UpdateMacro()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingMacroUpdate then
            PIHelper_UpdateMacro()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if arg1 == 13 or arg1 == 14 then
            ScanTrinkets()
            PIHelper_UpdateMacro()
            if PIHelperFrame and PIHelperFrame:IsShown() and PIHelper_RefreshGUI then
                PIHelper_RefreshGUI()
            end
        end
    end
end)

-- ─── Slash Commands ───────────────────────────────────────────────────────────

SLASH_PIH1 = "/pih"
SLASH_PIH2 = "/pihelper"
SlashCmdList["PIH"] = function()
    if UnitExists("target") and UnitIsPlayer("target") then
        local name = UnitName("target")
        PIHelperDB.target = name
        PIHelper_UpdateMacro()
        print("|cff00ccffPIHelper:|r PI target set to |cffffd700" .. name .. "|r")
    else
        if PIHelperFrame then
            if PIHelperFrame:IsShown() then
                PIHelperFrame:Hide()
            else
                if PIHelper_RefreshGUI then PIHelper_RefreshGUI() end
                PIHelperFrame:Show()
            end
        end
    end
end
