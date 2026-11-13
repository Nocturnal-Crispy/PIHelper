-- CDOptionsTracking.lua
-- CD tracker settings pages: General, Contexts, Buffs, Players.
-- Every write goes through ns.CD (ApplySettingsChange or its helpers); the
-- config table is re-read inside each callback because import/reset replace it.

local _, ns = ...

local T = ns.Theme
local M = T.metric
local W = ns.Widgets
local Data = ns.CDData

local GROUP = "CD TRACKER"

local function Cfg() return ns.CD.GetConfig() end
local function Apply(fn) ns.CD.ApplySettingsChange(fn) end

local REASONS = {
    disabled = "Disabled", not_priest = "Not a priest", not_healer_spec = "Not a healer spec",
    aura_api_missing = "Aura API missing", loading = "Loading",
}

-- Header pill shared by the CD pages.
local function StatusPill()
    local s = ns.CD.GetState()
    if s.running then return "Active - " .. (s.contextLabel or "no context"), true end
    return "Inactive - " .. (REASONS[s.reason] or tostring(s.reason)), false
end

local function Toggle(content, get, set)
    return W.Toggle(content, { get = get, set = set })
end

local function KeyToggle(content, key)
    return Toggle(content, function() return Cfg()[key] end,
        function(v) Apply(function(c) c[key] = v end) end)
end

local function Items(pairsList)
    local out = {}
    for i = 1, #pairsList, 2 do out[#out + 1] = { value = pairsList[i], label = pairsList[i + 1] } end
    return out
end

local function RefreshStack(page)
    page.stack:Refresh()
    page.stack:Reflow()
end

-- --- General -----------------------------------------------------------------

local function BuildGeneral(content, page)
    local st = W.Stack(content)
    page.stack = st
    st:Section("Tracker")
    st:Row("Enabled", "Highlight raid frames when DPS players use major cooldowns.", KeyToggle(content, "enabled"))
    st:Row("Healer specs only (Holy/Discipline)", "Run only as a Holy or Discipline Priest.",
        KeyToggle(content, "healerSpecsOnly"))
    st:Row("Load on all classes", "Run on any class and spec.", KeyToggle(content, "loadOnAllClasses"))
    st:Section("Power Infusion")
    st:Row("Only when PI is available", "Show highlights only while Power Infusion is ready.",
        KeyToggle(content, "requirePIReady"))
    st:Row("Grace window", "Seconds before PI is ready to start showing highlights.", W.Slider(content, {
        min = 0, max = 30, step = 1,
        get = function() return Cfg().graceSeconds end,
        set = function(v) Apply(function(c) c.graceSeconds = v end) end,
    }))
    st:Section("Minimap")
    st:Row("Show minimap button", nil, Toggle(content, function() return not Cfg().minimap.hide end,
        function(v) Apply(function(c) c.minimap.hide = not v end) end))
end

-- --- Contexts ----------------------------------------------------------------

local CONTEXT_ITEMS = Items({ "raid", "Raid", "dungeon", "Dungeon", "focus", "Focus" })
local GLOW_ITEMS = Items({ "pixel", "Pixel", "proc", "Proc", "border", "Border", "countdown", "Countdown", "fill", "Fill" })
local DURATION_ITEMS = Items({ "none", "None", "frame", "Frame", "alert", "Alert", "both", "Both" })
local TRACK_ITEMS = Items({ "all", "All DPS", "list", "Listed only" })

local function CtxToggle(content, page, key)
    return Toggle(content, function() return Cfg().contexts[page.ctx][key] end,
        function(v) Apply(function(c) c.contexts[page.ctx][key] = v end) end)
end

local function CtxSetter(page, key)
    return function(v) Apply(function(c) c.contexts[page.ctx][key] = v end) end
end

local function CtxGetter(page, key)
    return function() return Cfg().contexts[page.ctx][key] end
end

local function BuildContexts(content, page)
    page.ctx = "raid"
    local st = W.Stack(content)
    page.stack = st
    st:Row("Context", "Focus watches your focus target and pauses Raid/Dungeon tracking.",
        W.Segmented(content, { items = CONTEXT_ITEMS, width = 3 * M.buttonW,
            get = function() return page.ctx end,
            set = function(v) page.ctx = v; ns.UI.Refresh() end }))
    st:Section("Settings")
    st:Row("Enabled", nil, CtxToggle(content, page, "enabled"))
    page.trackRow = st:Row("Track", "Listed only: just the players on the Players page.", W.Segmented(content, {
        items = TRACK_ITEMS, width = 2 * M.buttonW + 20,
        get = function()
            local c = Cfg().contexts[page.ctx]
            return c.trackMode
        end,
        set = CtxSetter(page, "trackMode") }))
    st:Row("Glow style", nil, W.Dropdown(content, { items = function() return GLOW_ITEMS end,
        get = CtxGetter(page, "glowStyle"), set = CtxSetter(page, "glowStyle") }))
    st:Row("Glow color", nil, W.Swatch(content, {
        get = function()
            local col = Cfg().contexts[page.ctx].glowColor
            return col.r, col.g, col.b, col.a
        end,
        set = function(r, g, b, a)
            Apply(function(c) c.contexts[page.ctx].glowColor = { r = r, g = g, b = b, a = a or 1 } end)
        end }))
    st:Row("Duration text", "Show remaining time on the frame, the alert, or both.", W.Segmented(content, {
        items = DURATION_ITEMS, width = 4 * 64,
        get = CtxGetter(page, "durationText"), set = CtxSetter(page, "durationText") }))
    st:Row("Show alert", "On-screen icon and name for the newest highlight.", CtxToggle(content, page, "showAlert"))
    st:Row("Play sound", "When a highlight starts (at most every 2 seconds).", CtxToggle(content, page, "playSound"))
    st:Row("Test", "Fake 10 second highlight on your own frame.", W.Button(content, {
        label = "Test", onClick = function() ns.CD.Test(10, page.ctx) end }))
end

local function RefreshContexts(_, page)
    page.trackRow:SetShown(page.ctx ~= "focus")
    RefreshStack(page)
end

-- --- Buffs -------------------------------------------------------------------

local SCOPE_ITEMS = Items({ "shared", "Shared", "raid", "Raid", "dungeon", "Dungeon", "focus", "Focus" })

local function ScopeBuffs(page) return ns.CD.BuffsFor(page.scope) end

local function ListEnabled(page)
    if page.scope == "shared" then return true end
    return Cfg().contexts[page.scope].useOwnBuffs
end

local function SpellRowLabel(id)
    return ns.CD.SpellName(id) .. " (" .. id .. ")"
end

local function BuildClassSections(content, page, st)
    for _, entry in ipairs(Data.CATALOG) do
        page.listItems[#page.listItems + 1] = st:Section(entry.label)
        if #entry.spells == 0 then
            page.listItems[#page.listItems + 1] = st:Note("No reliable caster buff to track.")
        end
        for _, spell in ipairs(entry.spells) do
            local id = spell.id
            local row = st:Row(SpellRowLabel(id), nil, Toggle(content,
                function() return not ScopeBuffs(page).disabled[id] end,
                function(v) ns.CD.SetBuffEnabled(page.scope, id, v) end))
            row.spellID = id
            page.spellRows[#page.spellRows + 1] = row
            page.listItems[#page.listItems + 1] = row
        end
    end
end

local function CustomRow(page)
    return function(container)
        local row = W.Row(container, "", nil)
        row:SetControl(W.Button(row, { label = "Remove", onClick = function()
            local ok, msg = ns.CD.RemoveCustomID(row.spellID, page.scope)
            page.customError:SetText(ok and "" or msg, "danger")
        end }))
        return row
    end
end

local function BuildCustom(content, page, st)
    page.listItems[#page.listItems + 1] = st:Section("Custom IDs")
    local edit = W.EditBox(content, { width = M.dropdownW, maxLetters = 12 })
    local function Add()
        local ok, msg = ns.CD.AddCustomID(edit:GetText() or "", page.scope)
        if ok then edit:SetText("") end
        page.customError:SetText(msg, ok and "success" or "danger")
    end
    edit:SetScript("OnEnterPressed", function(self) Add(); self:ClearFocus() end)
    local addBtn = W.Button(content, { label = "Add", primary = true, onClick = Add })
    local holder = CreateFrame("Frame", nil, content)
    holder:SetSize(M.dropdownW + M.gap + addBtn:GetWidth(), M.editH)
    edit:SetParent(holder); addBtn:SetParent(holder)
    addBtn:SetPoint("RIGHT", holder, "RIGHT")
    edit:SetPoint("RIGHT", addBtn, "LEFT", -M.gap, 0)
    function holder:SetEnabled(on)
        W.SetFrameEnabled(edit, on)
        addBtn:SetEnabled(on)
    end
    page.listItems[#page.listItems + 1] = st:Row("Spell ID", "Any buff your group members gain.", holder)
    page.customError = st:Note("", "danger")
    page.listItems[#page.listItems + 1] = page.customError
    local container = st:Container()
    page.listItems[#page.listItems + 1] = container
    page.customPool = W.RowPool(container, CustomRow(page))
end

local function BuildBuffs(content, page)
    page.scope = "shared"
    page.spellRows, page.listItems = {}, {}
    local st = W.Stack(content)
    page.stack = st
    st:Row("Scope", "Shared buffs apply to every context without its own list.", W.Segmented(content, {
        items = SCOPE_ITEMS, width = 4 * 76,
        get = function() return page.scope end,
        set = function(v) page.scope = v; page.customError:SetText(""); ns.UI.Refresh() end }))
    page.ownRow = st:Row("Use separate buffs", "Give this context its own buff list.", Toggle(content,
        function() return page.scope ~= "shared" and Cfg().contexts[page.scope].useOwnBuffs end,
        function(v) ns.CD.SetUseOwnBuffs(page.scope, v) end))
    page.listItems[#page.listItems + 1] = st:Row("Include combat potions", "Light's Potential, Recklessness, Zealotry, Rampant Abandon.",
        Toggle(content, function() return ScopeBuffs(page).potions end,
            function(v) ns.CD.SetPotions(page.scope, v) end))
    BuildCustom(content, page, st)
    BuildClassSections(content, page, st)
end

local function RefreshCustom(page)
    local list = ScopeBuffs(page).custom
    for i, id in ipairs(list) do
        local row = page.customPool:Get(i)
        row.spellID = id
        row:SetLabel(SpellRowLabel(id))
    end
    page.customPool:Finish(#list)
end

local function RefreshBuffs(_, page)
    page.ownRow:SetShown(page.scope ~= "shared")
    for _, row in ipairs(page.spellRows) do row:SetLabel(SpellRowLabel(row.spellID)) end
    RefreshCustom(page)
    RefreshStack(page)
    local on = ListEnabled(page)
    for _, item in ipairs(page.listItems) do
        if item.SetEnabled then item:SetEnabled(on) else item:SetAlpha(on and 1 or T.alpha.dim) end
    end
    for _, row in ipairs(page.customPool.rows) do row:SetEnabled(on) end
end

-- --- Players -----------------------------------------------------------------

local function PlayerRow(container)
    local row = W.Row(container, "", nil)
    row:SetControl(W.Button(row, { label = "Remove", onClick = function()
        ns.CD.RemoveTrackedPlayer(row.playerName)
    end }))
    return row
end

local function BuildPlayers(content, page)
    local st = W.Stack(content)
    page.stack = st
    st:Section("Tracked players")
    local edit = W.EditBox(content, { width = M.dropdownW, maxLetters = 64 })
    local function Report(ok, err)
        page.error:SetText(ok and "" or err, "danger")
        if ok then edit:SetText("") end
    end
    local function AddTyped() Report(ns.CD.AddTrackedPlayer(edit:GetText() or "")) end
    edit:SetScript("OnEnterPressed", function(self) AddTyped(); self:ClearFocus() end)
    local addBtn = W.Button(content, { label = "Add", primary = true, onClick = AddTyped })
    local targetBtn = W.Button(content, { label = "Add Target", onClick = function()
        Report(ns.CD.AddTrackedPlayerFromTarget())
    end })
    local holder = CreateFrame("Frame", nil, content)
    holder:SetSize(M.dropdownW + addBtn:GetWidth() + targetBtn:GetWidth() + 2 * M.gap, M.editH)
    for _, f in ipairs({ edit, addBtn, targetBtn }) do f:SetParent(holder) end
    targetBtn:SetPoint("RIGHT", holder, "RIGHT")
    addBtn:SetPoint("RIGHT", targetBtn, "LEFT", -M.gap, 0)
    edit:SetPoint("RIGHT", addBtn, "LEFT", -M.gap, 0)
    st:Row("Add player", "Name or Name-Realm. Listed players are tracked even as tanks or healers.", holder)
    page.error = st:Note("", "danger")
    page.empty = st:Note("No players listed.")
    page.pool = W.RowPool(st:Container(), PlayerRow)
end

local function RefreshPlayers(_, page)
    local list = Cfg().trackedPlayers
    for i, name in ipairs(list) do
        local row = page.pool:Get(i)
        row.playerName = name
        row:SetLabel(name)
    end
    page.pool:Finish(#list)
    page.empty:SetShown(#list == 0)
    page.stack:Reflow()
end

-- --- Registration ------------------------------------------------------------

local function Register(key, label, order, subtitle, build, refresh, pill)
    ns.UI.RegisterPage({
        key = key, group = GROUP, label = label, order = order, title = label, subtitle = subtitle,
        build = build, refresh = refresh or function(_, page) RefreshStack(page) end, pill = pill,
    })
end

Register("cd_general", "General", 1, "When the CD tracker runs and the PI-ready gate.", BuildGeneral, nil, StatusPill)
Register("cd_contexts", "Contexts", 2, "Separate settings for Raid, Dungeon and Focus.", BuildContexts, RefreshContexts)
Register("cd_buffs", "Buffs", 3, "Which cooldown buffs trigger a highlight.", BuildBuffs, RefreshBuffs)
Register("cd_players", "Players", 4, "Players to track regardless of role.", BuildPlayers, RefreshPlayers)
