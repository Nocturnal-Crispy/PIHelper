-- PIHelper.lua
-- Core: events, trinket scanning, macro building, slash command

local ADDON_NAME    = "PIHelper"
local MACRO_NAME    = "PI"
local MACRO_ICON    = "INV_MISC_QUESTIONMARK"
local TRINKET_SLOTS = { 13, 14 }

-- Shared with PITarget.lua via global
PIHelper_Trinkets = {}

local pendingMacroUpdate = false
local pendingItemIDs    = {}
local frame  -- forward declaration; assigned below before any events fire

local DEFAULTS = {
    target         = "",
    trinketEnabled = {},
    usePotion      = false,
    potionName     = "",
}

-- ─── Trinket Scanning ─────────────────────────────────────────────────────────

local function ScanTrinkets()
    local found = {}
    pendingItemIDs = {}
    for _, slot in ipairs(TRINKET_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            local spellName = GetItemSpell(itemID)
            if spellName then
                local itemName = GetItemInfo(itemID) or ("Item #" .. itemID)
                found[slot] = { itemID = itemID, name = itemName }
            else
                -- Item data not in cache yet; request it so GET_ITEM_INFO_RECEIVED fires
                GetItemInfo(itemID)
                pendingItemIDs[itemID] = true
            end
        end
    end
    PIHelper_Trinkets = found

    -- Keep GET_ITEM_INFO_RECEIVED registered iff we have pending items
    if next(pendingItemIDs) then
        frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

-- ─── Macro Builder ────────────────────────────────────────────────────────────

local function BuildMacroBody()
    local db    = PIHelperDB
    local lines = {}

    for _, slot in ipairs(TRINKET_SLOTS) do
        local t = PIHelper_Trinkets[slot]
        if t and db.trinketEnabled[t.itemID] ~= false then
            lines[#lines + 1] = "/use " .. slot
        end
    end

    if db.usePotion and db.potionName ~= "" then
        lines[#lines + 1] = "/use Fleeting " .. db.potionName
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

frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
-- GET_ITEM_INFO_RECEIVED is registered/unregistered dynamically by ScanTrinkets()

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end

        if type(PIHelperDB) ~= "table" then PIHelperDB = {} end
        for k, v in pairs(DEFAULTS) do
            if PIHelperDB[k] == nil then PIHelperDB[k] = v end
        end
        if type(PIHelperDB.trinketEnabled) ~= "table" then
            PIHelperDB.trinketEnabled = {}
        end

        ScanTrinkets()
        PIHelper_UpdateMacro()

    elseif event == "PLAYER_LOGIN" then
        -- Item data is more likely cached by login; retry scan in case ADDON_LOADED was too early
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

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- arg1 is itemID (number)
        if pendingItemIDs[arg1] then
            -- Re-scan now that this item's data is available; ScanTrinkets manages (un)registration
            ScanTrinkets()
            PIHelper_UpdateMacro()
            if PIHelperFrame and PIHelperFrame:IsShown() and PIHelper_RefreshGUI then
                PIHelper_RefreshGUI()
            end
        end
    end
end)

-- ─── Slash Commands ───────────────────────────────────────────────────────────

local function PrintStatus()
    local p = "|cff00ccffPIHelper:|r "
    print(p .. "=== Status ===")
    print(p .. "Addon loaded: |cff00ff00yes|r")

    local dbOk = type(PIHelperDB) == "table"
    print(p .. "SavedVariables: " .. (dbOk and "|cff00ff00loaded|r" or "|cffff4444missing|r"))

    local _, class = UnitClass("player")
    local _, spec  = GetSpecializationInfo(GetSpecialization() or 0)
    print(p .. "Class: |cffffd700" .. (class or "?") .. "|r  Spec: |cffffd700" .. (spec or "?") .. "|r")

    local target = (dbOk and PIHelperDB.target ~= "") and PIHelperDB.target or "(none)"
    print(p .. "PI target: |cffffd700" .. target .. "|r")

    print(p .. "In combat: " .. (InCombatLockdown() and "|cffff4444yes|r" or "|cff00ff00no|r"))
    print(p .. "Pending macro update: " .. (pendingMacroUpdate and "|cffffff00yes|r" or "|cff00ff00no|r"))

    local idx = GetMacroIndexByName(MACRO_NAME)
    print(p .. "Macro \"" .. MACRO_NAME .. "\": " .. (idx > 0 and "|cff00ff00exists (slot " .. idx .. ")|r" or "|cffff4444not found|r"))

    local tCount = 0
    for _ in pairs(PIHelper_Trinkets) do tCount = tCount + 1 end
    print(p .. "On-use trinkets found: |cffffd700" .. tCount .. "|r")
end

SLASH_PIH1 = "/pih"
SLASH_PIH2 = "/pihelper"
SlashCmdList["PIH"] = function(msg)
    local cmd = msg and msg:lower():match("^%s*(%S+)") or ""

    if cmd == "status" then
        PrintStatus()
        return
    end

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
