-- CDTrackerSlash.lua
-- "/pih cd ..." subcommands (spec 15.2). PIHelper.lua routes here.

local _, ns = ...

local CD = ns.CD
local Frames, Glow, Media = ns.CDFrames, ns.CDGlow, ns.CDMedia
local Plain = CD.Plain

local HI = "|cffffd700"
local R = "|r"

local USAGE = {
    "/pih cd - open CD tracker settings",
    "/pih cd on | off - enable or disable the tracker",
    "/pih cd status | test | frames | check",
    "/pih cd add <id> [raid|dungeon|focus] / remove <id> [raid|dungeon|focus]",
    "/pih cd unlock | lock - move the alert",
    "/pih cd export | import | minimap",
}

local function LibPresent(name)
    if not LibStub then return false end
    local ok, lib = pcall(LibStub, name, true)
    return ok and lib ~= nil
end

local function YesNo(v) return v and "yes" or "no" end

local function GateLine(g)
    local text = "PI gate: " .. HI .. g.reason .. R
    if type(g.remaining) == "number" and g.remaining > 0 then
        text = text .. " (" .. string.format("%.1f", g.remaining) .. "s)"
    end
    return text .. (g.allowed and " - showing" or " - hidden")
end

local function PrintStatus()
    local st = CD.GetState()
    CD.Print(CD.GetStatusLine() .. " - reason: " .. HI .. tostring(st.reason) .. R)
    CD.Print("Context: " .. HI .. (st.contextLabel or "none") .. R .. "  Candidates: " .. HI .. st.candidates .. R)
    CD.Print(GateLine(st.gate))
    local parts = {}
    for _, p in ipairs(Frames.GetProviderStats()) do
        if p.loaded then parts[#parts + 1] = p.label .. " " .. p.count end
    end
    CD.Print("Frames: " .. table.concat(parts, ", "))
    CD.Print(HI .. st.detectable .. "/" .. st.activeIDs .. R .. " buff IDs detectable right now")
    CD.Print("LibCustomGlow: " .. YesNo(Glow.LCGAvailable()) .. "  LibSharedMedia: " .. YesNo(Media.LSMAvailable())
        .. "  LibDataBroker: " .. YesNo(LibPresent("LibDataBroker-1.1") and LibPresent("LibDBIcon-1.0")))
end

local function PrintFrames()
    local byProvider, order = {}, {}
    for _, r in ipairs(Frames.ListResolved()) do
        if not byProvider[r.provider] then
            byProvider[r.provider] = {}
            order[#order + 1] = r.provider
        end
        table.insert(byProvider[r.provider], r.unit .. " -> " .. r.name)
    end
    if #order == 0 then CD.Print("No raid or party frames resolved.") return end
    for _, key in ipairs(order) do
        CD.Print(HI .. key .. R .. " (" .. #byProvider[key] .. ")")
        for _, line in ipairs(byProvider[key]) do CD.Print("  " .. line) end
    end
end

local function Secrecy(id)
    if not (C_Secrets and C_Secrets.GetSpellAuraSecrecy) then return "n/a" end
    local v = Plain(C_Secrets.GetSpellAuraSecrecy(id))
    return v == nil and "secret" or tostring(v)
end

local function PrintCheck()
    local list = CD.ActiveBuffList()
    CD.Print("Checking " .. #list .. " active buff IDs:")
    for _, id in ipairs(list) do
        local name = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(id))
        local exists = C_Spell and C_Spell.DoesSpellExist and Plain(C_Spell.DoesSpellExist(id))
        CD.Print(string.format("  %d %s - exists: %s, secrecy: %s%s", id, tostring(name or "?"),
            tostring(exists), Secrecy(id), CD.SpellIsSecret(id) and " (undetectable now)" or ""))
    end
end

local function ParseScope(word)
    if word == nil or word == "" then return "shared" end
    if word == "raid" or word == "dungeon" or word == "focus" then return word end
    return nil
end

local function CustomCommand(verb, args)
    local idText, ctxWord = args:match("^(%S*)%s*(%S*)")
    local scope = ParseScope(ctxWord and ctxWord:lower())
    if not scope then CD.PrintError("Context must be raid, dungeon or focus.") return end
    local fn = verb == "add" and CD.AddCustomID or CD.RemoveCustomID
    local ok, msg = fn(idText or "", scope)
    if ok then CD.Print(msg) else CD.PrintError(msg) end
end

local function SetEnabled(on)
    CD.ApplySettingsChange(function(c) c.enabled = on end)
    CD.Print("CD tracker " .. (on and "enabled." or "disabled."))
end

local function ToggleMinimap()
    CD.ApplySettingsChange(function(c) c.minimap.hide = not c.minimap.hide end)
    CD.Print("Minimap button " .. (CD.GetConfig().minimap.hide and "hidden." or "shown."))
end

local function RunTest()
    local n = CD.Test(10)
    CD.Print("Test highlight on " .. n .. " frame(s) for 10s.")
end

local function OpenPage(key, opts)
    if ns.UI then ns.UI.Open(key, opts) end
end

local COMMANDS = {
    [""] = function() if ns.UI then ns.UI.Toggle("cd_general") end end,
    on = function() SetEnabled(true) end,
    off = function() SetEnabled(false) end,
    status = PrintStatus,
    test = RunTest,
    frames = PrintFrames,
    check = PrintCheck,
    add = function(args) CustomCommand("add", args) end,
    remove = function(args) CustomCommand("remove", args) end,
    unlock = function() ns.CDAlert.Unlock() end,
    lock = function() ns.CDAlert.Lock() end,
    export = function() OpenPage("cd_profiles", { export = true }) end,
    import = function() OpenPage("cd_profiles") end,
    minimap = ToggleMinimap,
}

function CD.HandleSlash(rest)
    if not CD.GetConfig() then return end
    rest = type(rest) == "string" and rest or ""
    local word, args = rest:match("^%s*(%S*)%s*(.-)%s*$")
    local fn = COMMANDS[(word or ""):lower()]
    if fn then
        fn(args or "")
    else
        for _, line in ipairs(USAGE) do CD.Print(line) end
    end
end
