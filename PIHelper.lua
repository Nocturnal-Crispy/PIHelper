-- PIHelper.lua
-- Core: events, trinket scanning, macro building, slash command

local ADDON_NAME    = "PIHelper"
local MACRO_NAME    = "PI"
local MACRO_ICON    = "INV_MISC_QUESTIONMARK"

-- Shared with PITarget.lua via global (single definition, no manual sync)
PIHelper_TRINKET_SLOTS = { 13, 14 }

-- Item APIs moved into the C_Item namespace; the bare globals were removed in 12.0.
-- Fall back to the old globals so the addon still works on pre-12.0 clients.
local GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local GetItemInfo  = (C_Item and C_Item.GetItemInfo)  or GetItemInfo

-- Shared with PITarget.lua via global
PIHelper_Trinkets = {}

local pendingMacroUpdate = false
local frame  -- forward declaration; assigned below before any events fire

local DEFAULTS = {
    target             = "",
    trinketEnabled     = {},
    usePotion          = false,
    potionName         = "",
    useVampiricEmbrace = false,
}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- Refresh the GUI only when it is open; avoids nil-checks scattered everywhere.
local function RefreshGUIIfVisible()
    if PIHelperFrame and PIHelperFrame:IsShown() and PIHelper_RefreshGUI then
        PIHelper_RefreshGUI()
    end
end

-- Full rescan + macro rebuild + optional GUI refresh in one call.
local function RescanAndUpdate()
    ScanTrinkets()
    PIHelper_UpdateMacro()
    RefreshGUIIfVisible()
end

-- ─── Trinket Scanning ─────────────────────────────────────────────────────────

function ScanTrinkets()
    local found = {}
    for _, slot in ipairs(PIHelper_TRINKET_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            -- pcall isolates per slot: one bad item can't blank the entire scan.
            local ok, spellName = pcall(GetItemSpell, itemID)
            if not ok then
                print("|cffff4444PIHelper:|r trinket scan error on item " .. itemID .. ": " .. tostring(spellName))
            elseif spellName then
                local itemName = GetItemInfo(itemID) or ("Item #" .. itemID)
                found[slot] = { itemID = itemID, name = itemName }
            elseif not C_Item.IsItemDataCachedByID(itemID) then
                -- Item data not cached yet; retry once the server sends it.
                -- ContinueOnItemLoad also fires immediately if data arrives first,
                -- so there is no stuck-pending race condition.
                Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
                    RescanAndUpdate()
                end)
            end
            -- else: cached, no use-spell — not an on-use trinket, nothing to retry.
        end
    end
    PIHelper_Trinkets = found
end

-- Exposed for the GUI's "Scan" button.
function PIHelper_ScanTrinkets()
    local count = 0
    RescanAndUpdate()
    for _ in pairs(PIHelper_Trinkets) do count = count + 1 end
    print("|cff00ccffPIHelper:|r Trinket scan complete — |cffffd700" .. count .. "|r on-use trinket(s) found.")
end

-- ─── Potion Resolution ────────────────────────────────────────────────────────

-- Returns "Fleeting <name>" when the player has that item in their bags,
-- otherwise returns the base name. Single /use line in the macro covers both cases.
local function ResolvePotionName(baseName)
    local fleetingName = "Fleeting " .. baseName
    if (GetItemCount(fleetingName) or 0) > 0 then
        return fleetingName
    end
    return baseName
end

-- ─── Macro Builder ────────────────────────────────────────────────────────────

-- Exported so PITarget.lua can use it for the live preview — single source of truth.
function PIHelper_BuildMacroBody()
    local db    = PIHelperDB
    local lines = {}

    -- Potion first: WoW only allows one item use per macro click. Putting the
    -- potion before trinkets ensures it fires when available (typically the
    -- opener). Trinkets fire on subsequent presses once the potion is on CD.
    if db.usePotion and db.potionName ~= "" then
        lines[#lines + 1] = "/use " .. ResolvePotionName(db.potionName)
    end

    for _, slot in ipairs(PIHelper_TRINKET_SLOTS) do
        local t = PIHelper_Trinkets[slot]
        if t and db.trinketEnabled[t.itemID] ~= false then
            lines[#lines + 1] = "/use " .. slot
        end
    end

    if db.useVampiricEmbrace then
        lines[#lines + 1] = "/cast Vampiric Embrace"
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
    local body = PIHelper_BuildMacroBody()
    local idx  = GetMacroIndexByName(MACRO_NAME)

    if idx > 0 then
        -- Skip the write when nothing changed to avoid unnecessary SavedVariables churn
        -- (BAG_UPDATE fires frequently; most ticks the body is identical).
        if GetMacroBody(idx) == body then return end
        EditMacro(idx, MACRO_NAME, nil, body)
    else
        local newIdx = CreateMacro(MACRO_NAME, MACRO_ICON, body)
        if not newIdx then
            print("|cffff4444PIHelper:|r Could not create macro \"" .. MACRO_NAME ..
                  "\" — macro slots may be full.")
            return
        end
    end

    RefreshGUIIfVisible()
end

-- ─── Event Handler ────────────────────────────────────────────────────────────

frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("BAG_UPDATE")

local eventHandlers = {
    ADDON_LOADED = function(arg1)
        if arg1 ~= ADDON_NAME then return end

        if type(PIHelperDB) ~= "table" then PIHelperDB = {} end

        -- Deep-copy scalar defaults; always assign a fresh table for trinketEnabled
        -- so DEFAULTS never shares a reference with PIHelperDB (mutations would
        -- otherwise corrupt the defaults for any subsequent DB rebuild).
        for k, v in pairs(DEFAULTS) do
            if PIHelperDB[k] == nil then
                PIHelperDB[k] = (type(v) == "table") and {} or v
            end
        end
        if type(PIHelperDB.trinketEnabled) ~= "table" then
            PIHelperDB.trinketEnabled = {}
        end

        -- Guard: usePotion=true with no potionName (e.g. crash prevented SavedVariables
        -- write) would silently produce no potion line in the macro.
        if PIHelperDB.usePotion and PIHelperDB.potionName == "" then
            PIHelperDB.usePotion = false
        end

        if PIHelper_RestoreFramePosition then PIHelper_RestoreFramePosition() end

        ScanTrinkets()
        PIHelper_UpdateMacro()
    end,

    PLAYER_LOGIN = function()
        -- Item data is more likely cached by login; retry scan in case ADDON_LOADED was too early.
        RescanAndUpdate()
    end,

    PLAYER_REGEN_ENABLED = function()
        if pendingMacroUpdate then
            PIHelper_UpdateMacro()
        end
    end,

    PLAYER_EQUIPMENT_CHANGED = function(arg1)
        if arg1 == 13 or arg1 == 14 then
            RescanAndUpdate()
        end
    end,

    BAG_UPDATE = function()
        -- Re-resolve Fleeting vs. regular potion whenever bags change.
        -- Skip-identical check in PIHelper_UpdateMacro keeps this free when nothing changed.
        PIHelper_UpdateMacro()
    end,
}

frame:SetScript("OnEvent", function(_, event, arg1)
    local handler = eventHandlers[event]
    if handler then handler(arg1) end
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

    if dbOk and PIHelperDB.usePotion and PIHelperDB.potionName ~= "" then
        local resolved = ResolvePotionName(PIHelperDB.potionName)
        print(p .. "Potion: |cffffd700" .. resolved .. "|r" ..
              (resolved ~= PIHelperDB.potionName and " |cff00ff00(Fleeting in bags)|r" or " |cffaaaaaa(regular — no Fleeting in bags)|r"))
    end
end

-- Shared by the /pih slash command and the GUI's "Set from Target" button.
-- Uses GetUnitName(unit, true) so cross-realm targets (M+/pug raids) are stored
-- as "Name-Realm" and still resolve in the macro.
function PIHelper_SetTargetFromUnit()
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        print("|cffff4444PIHelper:|r No valid target.")
        return false
    end

    local name = GetUnitName("target", true)
    PIHelperDB.target = name
    PIHelper_UpdateMacro()
    print("|cff00ccffPIHelper:|r PI target set to |cffffd700" .. name .. "|r")

    RefreshGUIIfVisible()
    return true
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
        PIHelper_SetTargetFromUnit()
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
