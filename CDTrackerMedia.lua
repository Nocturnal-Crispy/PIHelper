-- CDTrackerMedia.lua
-- Fonts and sounds for tracker text and alerts: stock built-ins plus anything
-- registered with LibSharedMedia-3.0 (optional, never bundled). Lists are
-- rebuilt on every call so media registered late (e.g. by BigWigs) appears.

local _, ns = ...

local Media = {}
ns.CDMedia = Media

local BUILTIN_FONTS = {
    { name = "Friz Quadrata TT", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",     path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus",         path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri",           path = "Fonts\\SKURRI.TTF" },
}

-- Sound kits are resolved lazily: SOUNDKIT entries may be missing.
local BUILTIN_SOUNDS = {
    { name = "Raid Warning", kit = "RAID_WARNING" },
    { name = "Ready Check",  kit = "READY_CHECK" },
    { name = "Alarm Clock",  kit = "ALARM_CLOCK_WARNING_3" },
    { name = "Map Ping",     kit = "MAP_PING" },
}

local function LSM()
    if not LibStub then return nil end
    local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok then return lib end
    return nil
end

function Media.LSMAvailable()
    return LSM() ~= nil
end

local function SoundKit(entry)
    return SOUNDKIT and SOUNDKIT[entry.kit] or nil
end

local function BuiltinSounds()
    local out = {}
    for _, s in ipairs(BUILTIN_SOUNDS) do
        if SoundKit(s) then out[#out + 1] = s end
    end
    return out
end

-- Built-ins first, then LSM:List(kind), de-duplicated.
local function BuildList(builtins, kind)
    local names, seen = {}, {}
    for _, e in ipairs(builtins) do
        names[#names + 1] = e.name
        seen[e.name] = true
    end
    local lib = LSM()
    if lib then
        local ok, list = pcall(lib.List, lib, kind)
        if ok and type(list) == "table" then
            for _, name in ipairs(list) do
                if type(name) == "string" and not seen[name] then
                    names[#names + 1] = name
                    seen[name] = true
                end
            end
        end
    end
    return names
end

function Media.ListFonts()
    return BuildList(BUILTIN_FONTS, "font")
end

function Media.ListSounds()
    return BuildList(BuiltinSounds(), "sound")
end

local function FindBuiltin(list, name)
    for _, e in ipairs(list) do
        if e.name == name then return e end
    end
    return nil
end

local function FetchLSM(kind, name)
    local lib = LSM()
    if not lib or type(name) ~= "string" then return nil end
    local ok, path = pcall(lib.Fetch, lib, kind, name, true)
    if ok and path then return path end
    return nil
end

-- Resolution: built-in, then LSM, then the first built-in. The saved name is
-- never rewritten, so media that loads later is picked up again.
function Media.FetchFont(name)
    local b = FindBuiltin(BUILTIN_FONTS, name)
    if b then return b.path end
    return FetchLSM("font", name) or BUILTIN_FONTS[1].path
end

function Media.PlaySound(name)
    local b = FindBuiltin(BUILTIN_SOUNDS, name)
    if b and SoundKit(b) then
        PlaySound(SoundKit(b), "Master")
        return
    end
    local path = FetchLSM("sound", name)
    if path then
        PlaySoundFile(path, "Master")
        return
    end
    local first = BuiltinSounds()[1]
    if first then PlaySound(SoundKit(first), "Master") end
end
