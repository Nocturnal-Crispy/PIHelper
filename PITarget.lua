-- PITarget.lua
-- The "PI Macro" settings page: PI target, on-use trinket toggles, combat
-- potion, Vampiric Embrace and a live macro preview. Every control writes the
-- same PIHelperDB keys and calls PIHelper_UpdateMacro() exactly as the
-- original stand-alone window did.

local _, ns = ...

local T = ns.Theme
local M = T.metric
local W = ns.Widgets

local POTION_OPTIONS = {
    "Draught of Rampant Abandon",
    "Potion of Zealotry",
    "Potion of Recklessness",
    "Light's Potential",
}

-- Re-syncs the preview and dependent rows after a change made on this page.
local function RefreshPage()
    if PIHelper_RefreshGUI then PIHelper_RefreshGUI() end
end

local function PotionItems()
    local items = {}
    for i, name in ipairs(POTION_OPTIONS) do items[i] = { value = name, label = name } end
    return items
end

-- --- Sections ----------------------------------------------------------------

local function BuildTarget(page, st)
    st:Section("Target")
    local setBtn = W.Button(page.content, { label = "Set from Target", primary = true, onClick = function()
        PIHelper_SetTargetFromUnit()
    end })
    local clearBtn = W.Button(page.content, { label = "Clear", onClick = function()
        PIHelperDB.target = ""
        PIHelper_UpdateMacro()
        if PIHelper_RefreshGUI then PIHelper_RefreshGUI() end
    end })
    local holder = CreateFrame("Frame", nil, page.content)
    holder:SetSize(setBtn:GetWidth() + M.gap + clearBtn:GetWidth(), M.buttonH)
    setBtn:SetParent(holder); clearBtn:SetParent(holder)
    clearBtn:SetPoint("RIGHT", holder, "RIGHT")
    setBtn:SetPoint("RIGHT", clearBtn, "LEFT", -M.gap, 0)
    page.targetName = W.Text(holder, "label", "fg")
    page.targetName:SetPoint("RIGHT", setBtn, "LEFT", -2 * M.gap, 0)
    st:Row("PI target", "Target a player and type /pih to change.", holder)
end

local function TrinketToggle(slot)
    return {
        get = function()
            local t = PIHelper_Trinkets[slot]
            return t ~= nil and PIHelperDB.trinketEnabled[t.itemID] ~= false
        end,
        set = function(value)
            local t = PIHelper_Trinkets[slot]
            if not t then return end
            PIHelperDB.trinketEnabled[t.itemID] = value and true or false
            PIHelper_UpdateMacro()
            RefreshPage()
        end,
    }
end

local function BuildTrinkets(page, st)
    st:Section("On-use trinkets", { label = "Scan", onClick = function()
        PIHelper_ScanTrinkets()
        if PIHelper_RefreshGUI then PIHelper_RefreshGUI() end
    end })
    page.trinketRows = {}
    for _, slot in ipairs(PIHelper_TRINKET_SLOTS) do
        local row = st:Row("", nil, W.Toggle(page.content, TrinketToggle(slot)))
        row.slot = slot
        page.trinketRows[#page.trinketRows + 1] = row
    end
    page.noTrinkets = st:Note("No on-use trinkets detected.")
end

local function BuildPotion(page, st)
    st:Section("Combat potion")
    page.potionToggle = st:Row("Use combat potion", nil, W.Toggle(page.content, {
        get = function() return PIHelperDB.usePotion end,
        set = function(value)
            PIHelperDB.usePotion = value
            -- Only default to the first option when no potion was ever chosen;
            -- re-enabling must not overwrite a saved selection.
            if PIHelperDB.usePotion and PIHelperDB.potionName == "" then
                PIHelperDB.potionName = POTION_OPTIONS[1]
            end
            PIHelper_UpdateMacro()
            RefreshPage()
        end,
    }))
    page.potionRow = st:Row("Potion", nil, W.Dropdown(page.content, {
        items = PotionItems,
        get = function() return PIHelperDB.potionName end,
        set = function(name)
            PIHelperDB.potionName = name
            PIHelper_UpdateMacro()
            RefreshPage()
        end,
    }))
end

local function BuildExtras(page, st)
    st:Section("Extras")
    page.veRow = st:Row("Use Vampiric Embrace", nil, W.Toggle(page.content, {
        get = function() return PIHelperDB.useVampiricEmbrace end,
        set = function(value)
            PIHelperDB.useVampiricEmbrace = value and true or false
            PIHelper_UpdateMacro()
            RefreshPage()
        end,
    }))
end

local function BuildPreview(page, st)
    st:Section("Macro preview")
    local box = CreateFrame("Frame", nil, page.content)
    box:SetHeight(M.previewH)
    local inner = CreateFrame("Frame", nil, box)
    inner:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -M.gap)
    inner:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -M.rowInset, 0)
    T.Solid(inner, "BACKGROUND", "panel", 1):SetAllPoints()
    T.Border(inner, "line")
    local text = inner:CreateFontString(nil, "OVERLAY")
    text:SetFont(T.font.body, T.size.preview, "")
    T.SetTextColor(text, "fg")
    text:SetPoint("TOPLEFT", inner, "TOPLEFT", M.gap, -M.gap)
    text:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -M.gap, M.gap)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    page.preview = text
    st:Add(box)
end

-- --- Page --------------------------------------------------------------------

local function Build(content, page)
    local st = W.Stack(content)
    page.stack = st
    BuildTarget(page, st)
    BuildTrinkets(page, st)
    BuildPotion(page, st)
    BuildExtras(page, st)
    BuildPreview(page, st)
end

local function RefreshTarget(page)
    local name = PIHelperDB.target
    if name ~= "" then
        page.targetName:SetText(name)
        T.SetTextColor(page.targetName, "fg")
    else
        page.targetName:SetText("(none set)")
        T.SetTextColor(page.targetName, "muted")
    end
end

local function RefreshTrinkets(page)
    local anyFound = false
    for _, row in ipairs(page.trinketRows) do
        local t = PIHelper_Trinkets[row.slot]
        row:SetShown(t ~= nil)
        if t then
            anyFound = true
            row:SetLabel(t.name .. " (slot " .. row.slot .. ")")
        end
    end
    page.noTrinkets:SetShown(not anyFound)
end

local function Refresh(_, page)
    RefreshTarget(page)
    RefreshTrinkets(page)
    page.stack:Refresh()
    page.potionRow:SetEnabled(PIHelperDB.usePotion and true or false)
    page.preview:SetText(PIHelper_BuildMacroBody())
    page.stack:Reflow()
end

ns.UI.RegisterPage({
    key = "pi_macro", group = "POWER INFUSION", label = "PI Macro", order = 1,
    title = "PI Macro", subtitle = "Power Infusion macro, trinkets, potion and target.",
    build = Build, refresh = Refresh,
})
