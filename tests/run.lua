-- tests/run.lua
-- Minimal headless test runner (Lua 5.1 / LuaJIT). Run from the repo root:
--   lua tests/run.lua      or      luajit tests/run.lua
-- Loads the pure addon modules with no WoW stubs, then disables every code
-- loading function so nothing under test can execute strings or files.

local loadfile = loadfile
local MODULES = { "CDTrackerData.lua", "CDTrackerCore.lua", "CDTrackerSerialize.lua", "UITheme.lua" }
local TESTS = {
    "tests/test_core.lua", "tests/test_gate.lua", "tests/test_buffs.lua",
    "tests/test_migrate.lua", "tests/test_serialize.lua", "tests/test_theme.lua",
}

local ns = {}
local loadErrors = {}

for _, f in ipairs(MODULES) do
    local chunk, err = loadfile(f)
    if chunk then
        local ok, rerr = pcall(chunk, "PIHelper", ns)
        if not ok then loadErrors[#loadErrors + 1] = f .. ": " .. tostring(rerr) end
    else
        loadErrors[#loadErrors + 1] = f .. ": " .. tostring(err)
    end
end

-- Compile the test files before the loaders are disabled.
local suites = {}
for _, f in ipairs(TESTS) do
    local chunk, err = loadfile(f)
    suites[#suites + 1] = { file = f, chunk = chunk, err = err }
end

local function Blocked(name)
    return function() error(name .. " is disabled in tests", 2) end
end
for _, name in ipairs({ "load", "loadstring", "loadfile", "dofile", "setfenv" }) do
    if _G[name] ~= nil then _G[name] = Blocked(name) end
end

-- --- Assertions --------------------------------------------------------------

local function Show(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

local function DeepEqual(a, b, path)
    if type(a) ~= type(b) then return false, path .. ": " .. Show(a) .. " vs " .. Show(b) end
    if type(a) ~= "table" then
        if a == b then return true end
        return false, path .. ": " .. Show(a) .. " vs " .. Show(b)
    end
    for k, v in pairs(a) do
        local ok, why = DeepEqual(v, b[k], path .. "." .. tostring(k))
        if not ok then return false, why end
    end
    for k, v in pairs(b) do
        if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing vs " .. Show(v) end
    end
    return true
end

local t = {}
function t.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "expected " .. Show(expected) .. ", got " .. Show(actual), 2)
    end
end
function t.ok(v, msg)
    if not v then error(msg or "expected truthy value", 2) end
end
function t.deepEq(actual, expected, msg)
    local ok, why = DeepEqual(actual, expected, "")
    if not ok then error((msg and (msg .. ": ") or "") .. "tables differ at " .. why, 2) end
end
function t.fails(fn, msg)
    if pcall(fn) then error(msg or "expected an error", 2) end
end
t.ns = ns
t.readFile = function(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
end

-- --- Run ---------------------------------------------------------------------

local passed, failed = 0, 0
local function Failure(where, msg)
    failed = failed + 1
    print("FAIL " .. where .. ": " .. tostring(msg))
end

for _, e in ipairs(loadErrors) do Failure("load", e) end

for _, suite in ipairs(suites) do
    if not suite.chunk then
        Failure(suite.file, suite.err)
    else
        local ok, cases = pcall(suite.chunk, ns)
        if not ok or type(cases) ~= "table" then
            Failure(suite.file, ok and "did not return a table" or cases)
        else
            local names = {}
            for name in pairs(cases) do names[#names + 1] = name end
            table.sort(names)
            for _, name in ipairs(names) do
                local okc, err = pcall(cases[name], t)
                if okc then passed = passed + 1 else Failure(suite.file .. " :: " .. name, err) end
            end
        end
    end
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
