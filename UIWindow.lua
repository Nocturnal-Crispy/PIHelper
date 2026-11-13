-- UIWindow.lua
-- The unified flat-dark settings window (PIHelperFrame): sidebar navigation,
-- page header, scrolling content pane, page registry and the PIHelperTooltip.
-- Also defines the legacy globals PIHelper.lua relies on:
--   PIHelper_RefreshGUI(), PIHelper_RestoreFramePosition()

local _, ns = ...

local T = ns.Theme
local M = T.metric
local W = ns.Widgets

local UI = {}
ns.UI = UI

local GROUPS = {
    { key = "POWER INFUSION", crumb = "Power Infusion" },
    { key = "CD TRACKER",     crumb = "CD Tracker" },
}
local FIRST_PAGE = "pi_macro"
local CONTENT_W = M.windowW - M.sidebarW - M.contentX - M.contentRight

local pages, pageByKey = {}, {}
local current, pendingOpts
local chrome -- built on first show
local refreshing = false

-- --- Window frame (created at load, hidden) ----------------------------------

local f = CreateFrame("Frame", "PIHelperFrame", UIParent)
f:SetSize(M.windowW, M.windowH)
f:SetPoint("CENTER")
f:SetFrameStrata("HIGH")
f:SetToplevel(true)
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:Hide()

-- Let ESC close the window (and not fall through to the game menu).
tinsert(UISpecialFrames, "PIHelperFrame")

local function SavePosition()
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    PIHelperDB.framePos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function MakeDragHandle(handle)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() f:StartMoving() end)
    handle:SetScript("OnDragStop", SavePosition)
end

-- Restore last-dragged position. Called from PIHelper.lua's ADDON_LOADED
-- handler once PIHelperDB exists. relativeTo is always UIParent.
function PIHelper_RestoreFramePosition()
    local p = PIHelperDB and PIHelperDB.framePos
    if type(p) ~= "table" or type(p.point) ~= "string" then return end
    f:ClearAllPoints()
    f:SetPoint(p.point, UIParent, p.relPoint or p.point, tonumber(p.x) or 0, tonumber(p.y) or 0)
end

-- --- Tooltip -----------------------------------------------------------------

local tip

local function CreateTooltip()
    tip = CreateFrame("Frame", "PIHelperTooltip", UIParent)
    tip:SetFrameStrata("TOOLTIP")
    tip:SetWidth(M.tooltipW)
    tip.bg = T.Solid(tip, "BACKGROUND", "panel", T.alpha.tooltip)
    tip.bg:SetAllPoints()
    tip.border = T.Border(tip, "line")
    tip.title = T.Font(tip, "tooltipTitle", "accent", true)
    tip.title:SetPoint("TOPLEFT", M.tooltipPad, -M.tooltipPad)
    tip.title:SetWidth(M.tooltipW - 2 * M.tooltipPad)
    tip.title:SetJustifyH("LEFT")
    tip.body = T.Font(tip, "tooltipBody", "fg")
    tip.body:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, -4)
    tip.body:SetWidth(M.tooltipW - 2 * M.tooltipPad)
    tip.body:SetJustifyH("LEFT")
    tip.body:SetWordWrap(true)
    tip:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 16, y / s - 12)
    end)
    tip:Hide()
end

function UI.ShowTooltip(_, title, body)
    if not tip then CreateTooltip() end
    tip.title:SetText(title or "")
    tip.body:SetText(body or "")
    local h = 2 * M.tooltipPad + tip.title:GetStringHeight()
    if body and body ~= "" then h = h + 4 + tip.body:GetStringHeight() end
    tip:SetHeight(h)
    tip:Show()
end

function UI.HideTooltip()
    if tip then tip:Hide() end
end

-- --- Sidebar navigation ------------------------------------------------------

local function TrackerOff()
    return ns.CD and ns.CD.GetState and not ns.CD.GetState().running
end

local function PaintNav(item)
    local selected = item.page.key == current
    item.fill:SetShown(selected)
    item.marker:SetShown(selected)
    local key = selected and "accentSoft" or (item.hovered and "fg" or "muted")
    T.SetTextColor(item.text, key)
    local off = item.page.group == "CD TRACKER" and TrackerOff()
    item:SetAlpha(off and T.alpha.navOff or 1)
end

local function PaintAllNav()
    for _, item in ipairs(chrome.navItems) do PaintNav(item) end
end

local function NavItem(parent, page, y)
    local item = CreateFrame("Button", nil, parent)
    item.page = page
    item:SetHeight(M.navRowH)
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", M.navInset, y)
    item:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -M.navInset, y)
    item.fill = T.Solid(item, "BACKGROUND", "accent", T.alpha.navFill)
    item.fill:SetAllPoints()
    item.marker = T.Solid(item, "ARTWORK", "accent", 1)
    item.marker:SetWidth(M.navMarkerW)
    item.marker:SetPoint("TOPLEFT"); item.marker:SetPoint("BOTTOMLEFT")
    item.text = T.Font(item, "navText", "muted")
    item.text:SetPoint("LEFT", item, "LEFT", M.navTextX - M.navInset, 0)
    item.text:SetText(page.label)
    item:SetScript("OnEnter", function(self) self.hovered = true; PaintNav(self) end)
    item:SetScript("OnLeave", function(self) self.hovered = false; PaintNav(self) end)
    item:SetScript("OnClick", function() UI.Open(page.key) end)
    return item
end

local function SortedPages()
    local groupIndex = {}
    for i, g in ipairs(GROUPS) do groupIndex[g.key] = i end
    local list = {}
    for _, p in ipairs(pages) do list[#list + 1] = p end
    table.sort(list, function(a, b)
        local ga, gb = groupIndex[a.group] or 99, groupIndex[b.group] or 99
        if ga ~= gb then return ga < gb end
        return (a.order or 0) < (b.order or 0)
    end)
    return list
end

local function BuildNav(sidebar)
    chrome.navItems = {}
    local y = -(M.brandH + 12)
    local lastGroup
    for _, page in ipairs(SortedPages()) do
        if page.group ~= lastGroup then
            if lastGroup then y = y - 8 end
            local label = T.Font(sidebar, "groupLabel", "muted")
            label:SetPoint("TOPLEFT", sidebar, "TOPLEFT", M.groupX, y - 8)
            label:SetText(string.upper(page.group))
            y = y - M.groupStep
            lastGroup = page.group
        end
        chrome.navItems[#chrome.navItems + 1] = NavItem(sidebar, page, y)
        y = y - M.navRowH
    end
end

local function AddonVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and get("PIHelper", "Version")
    return v and ("v" .. v) or ""
end

local function BuildSidebar()
    local sb = CreateFrame("Frame", nil, f)
    sb:SetPoint("TOPLEFT"); sb:SetPoint("BOTTOMLEFT")
    sb:SetWidth(M.sidebarW)
    T.Solid(sb, "BACKGROUND", "bg", 1):SetAllPoints()
    local shade = T.Solid(sb, "BACKGROUND", "black", T.alpha.sidebarShade)
    shade:SetDrawLayer("BACKGROUND", 1)
    shade:SetAllPoints()
    local edge = T.Hairline(sb, "line", 1, "V")
    edge:SetPoint("TOPRIGHT"); edge:SetPoint("BOTTOMRIGHT")

    local brand = CreateFrame("Frame", nil, sb)
    brand:SetPoint("TOPLEFT"); brand:SetPoint("TOPRIGHT")
    brand:SetHeight(M.brandH)
    MakeDragHandle(brand)
    local name = T.Font(brand, "brand", "fg", true)
    name:SetPoint("LEFT", brand, "LEFT", M.groupX, 7)
    name:SetText("PIHelper")
    local ver = T.Font(brand, "version", "muted")
    ver:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    ver:SetText(AddonVersion())
    local rule = T.Hairline(brand, "line", 1)
    rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
    BuildNav(sb)
    return sb
end

-- --- Header and content ------------------------------------------------------

local function BuildHeader(pane)
    local h = CreateFrame("Frame", nil, pane)
    h:SetPoint("TOPLEFT"); h:SetPoint("TOPRIGHT")
    h:SetHeight(M.headerH)
    MakeDragHandle(h)
    h.crumb = T.Font(h, "crumb", "muted")
    h.crumb:SetPoint("TOPLEFT", h, "TOPLEFT", M.contentX, -12)
    h.title = T.Font(h, "title", "fg", true)
    h.title:SetPoint("TOPLEFT", h, "TOPLEFT", M.contentX, -30)
    h.subtitle = T.Font(h, "subtitle", "muted")
    h.subtitle:SetPoint("TOPLEFT", h, "TOPLEFT", M.contentX, -56)
    h.pill = W.Pill(h)
    h.pill:SetPoint("RIGHT", h, "RIGHT", -(M.contentRight + M.closeSize), 0)
    h.pill:Hide()
    local rule = T.Hairline(h, "line", 1)
    rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
    return h
end

local function BuildCloseButton()
    local b = CreateFrame("Button", nil, f)
    b:SetSize(M.closeSize, M.closeSize)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    b:SetFrameLevel(f:GetFrameLevel() + 20)
    b.text = T.Font(b, "button", "muted", true)
    b.text:SetPoint("CENTER")
    b.text:SetText("X")
    b:SetScript("OnEnter", function(self) T.SetTextColor(self.text, "fg") end)
    b:SetScript("OnLeave", function(self) T.SetTextColor(self.text, "muted") end)
    b:SetScript("OnClick", function() f:Hide() end)
end

local function BuildChrome()
    chrome = {}
    T.EnsureScaleWatcher()
    T.Shadow(f)
    T.Solid(f, "BACKGROUND", "bg", T.alpha.window):SetAllPoints()
    chrome.border = T.Border(f, "line")
    chrome.sidebar = BuildSidebar()

    local pane = CreateFrame("Frame", nil, f)
    pane:SetPoint("TOPLEFT", f, "TOPLEFT", M.sidebarW, 0)
    pane:SetPoint("BOTTOMRIGHT")
    chrome.header = BuildHeader(pane)

    local sf = CreateFrame("ScrollFrame", nil, pane)
    sf:SetPoint("TOPLEFT", pane, "TOPLEFT", M.contentX, -(M.headerH + 8))
    sf:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -M.contentRight, 12)
    chrome.scroll = sf
    chrome.bar = W.SlimScroll(sf)
    BuildCloseButton()
end

local function UpdateHeader(page)
    local h = chrome.header
    local crumb = page.group
    for _, g in ipairs(GROUPS) do
        if g.key == page.group then crumb = g.crumb end
    end
    h.crumb:SetText(crumb .. " / " .. page.label)
    h.title:SetText(page.title or page.label)
    h.subtitle:SetText(page.subtitle or "")
    if page.pill then
        local text, active = page.pill()
        h.pill:SetState(text, active)
        h.pill:Show()
    else
        h.pill:Hide()
    end
end

local function EnsureBuilt(page)
    if page.content then return end
    local content = CreateFrame("Frame", nil, chrome.scroll)
    content:SetSize(CONTENT_W, 1)
    page.content = content
    page.build(content, page)
end

local function RefreshPage(page, opts)
    if page.refresh then page.refresh(page.content, page, opts) end
    UpdateHeader(page)
    if chrome.bar.Update then chrome.bar.Update() end
end

local function ShowPage(key, opts)
    local page = pageByKey[key] or pageByKey[FIRST_PAGE] or pages[1]
    if not page then return end
    local prev = current and pageByKey[current]
    if prev and prev ~= page and prev.content then prev.content:Hide() end
    current = page.key
    EnsureBuilt(page)
    chrome.scroll:SetScrollChild(page.content)
    page.content:Show()
    chrome.scroll:SetVerticalScroll(0)
    W.CloseMenu()
    RefreshPage(page, opts)
    PaintAllNav()
end

f:SetScript("OnShow", function()
    if not chrome then BuildChrome() end
    local opts = pendingOpts
    pendingOpts = nil
    ShowPage(current or FIRST_PAGE, opts)
end)

f:SetScript("OnHide", function()
    W.CloseMenu()
    W.HideModal()
    UI.HideTooltip()
    if ns.CDAlert then ns.CDAlert.Lock() end
end)

-- --- Public API --------------------------------------------------------------

-- def = { key, group, label, order, title, subtitle, build(content, page),
--         refresh(content, page, opts), pill() -> text, active }
function UI.RegisterPage(def)
    assert(type(def.key) == "string" and not pageByKey[def.key], "duplicate or missing page key")
    pages[#pages + 1] = def
    pageByKey[def.key] = def
end

function UI.Open(key, opts)
    if not pageByKey[key] then return end
    if f:IsShown() and chrome then
        ShowPage(key, opts)
    else
        current = key
        pendingOpts = opts
        f:Show()
    end
end

function UI.Toggle(key)
    if f:IsShown() and current == key then
        f:Hide()
    else
        UI.Open(key)
    end
end

-- Refreshes the sidebar states and the visible page. Cheap no-op when hidden.
function UI.Refresh()
    if refreshing or not chrome or not f:IsShown() then return end
    refreshing = true
    local page = current and pageByKey[current]
    if page and page.content then
        local ok, err = pcall(RefreshPage, page)
        if not ok then geterrorhandler()(err) end
    end
    PaintAllNav()
    refreshing = false
end

function UI.IsShown() return f:IsShown() end
function UI.CurrentPage() return current end
function UI.Window() return f end

-- Legacy contract used by PIHelper.lua.
function PIHelper_RefreshGUI()
    UI.Refresh()
end
