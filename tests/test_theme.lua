-- tests/test_theme.lua: theme tokens and UI static checks (spec 17.2).
local ns = ...
local Theme = ns.Theme

local UI_FILES = {
    "CDOptionsTracking.lua", "CDOptionsDisplay.lua", "UIWidgets.lua", "UIWidgetsMenu.lua", "UIWindow.lua", "PITarget.lua",
}
local BANNED_TEMPLATES = { "UIPanelButtonTemplate", "UICheckButtonTemplate", "BasicFrameTemplate", "InputBoxTemplate" }

local function InUnit(v) return type(v) == "number" and v >= 0 and v <= 1 end

local T = {}

T["theme loads without WoW globals"] = function(t)
    t.ok(type(Theme) == "table", "ns.Theme exists")
    t.eq(CreateFrame, nil, "no WoW stubs present")
end

T["colors in range"] = function(t)
    local n = 0
    for key, c in pairs(Theme.color) do
        n = n + 1
        t.ok(InUnit(c.r) and InUnit(c.g) and InUnit(c.b), "color " .. key)
    end
    t.ok(n >= 11, "all palette entries present")
    for _, key in ipairs({ "bg", "panel", "line", "fg", "muted", "accent", "accentSoft", "grey", "danger", "success", "black" }) do
        t.ok(Theme.color[key], "color " .. key)
    end
end

T["accent value"] = function(t)
    local a = Theme.color.accent
    t.eq(a.r, 0x00 / 255); t.eq(a.g, 0x91 / 255); t.eq(a.b, 0xED / 255)
end

T["alpha in range"] = function(t)
    for key, v in pairs(Theme.alpha) do t.ok(InUnit(v), "alpha " .. key) end
end

T["metrics and sizes positive"] = function(t)
    for key, v in pairs(Theme.metric) do t.ok(type(v) == "number" and v > 0, "metric " .. key) end
    for key, v in pairs(Theme.size) do t.ok(type(v) == "number" and v > 0, "size " .. key) end
    t.eq(Theme.metric.windowW, 760); t.eq(Theme.metric.windowH, 540)
end

T["fonts are stock"] = function(t)
    t.eq(Theme.font.heading, "Fonts\\FRIZQT__.TTF")
    t.eq(Theme.font.body, "Fonts\\ARIALN.TTF")
end

T["UI files use theme colors and no stock chrome"] = function(t)
    for _, f in ipairs(UI_FILES) do
        local src = t.readFile(f)
        t.ok(src, "read " .. f)
        t.eq(src:find("SetColorTexture%(%s*[%d%.%-]"), nil, f .. " numeric SetColorTexture")
        for _, name in ipairs(BANNED_TEMPLATES) do
            t.eq(src:find(name, 1, true), nil, f .. " uses " .. name)
        end
    end
end

return T
