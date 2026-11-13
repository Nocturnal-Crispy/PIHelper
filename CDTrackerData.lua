-- CDTrackerData.lua
-- Pure data for the CD tracker: default buff catalog, potions and constants.
-- No WoW API calls; loaded headless by tests/run.lua.

local _, ns = ...

local Data = {}

Data.PI_SPELL_ID = 10060

Data.HEALER_SPEC_IDS = { [256] = true, [257] = true }

Data.CONTEXTS = { "raid", "dungeon", "focus" }

Data.CONTEXT_LABELS = { raid = "Raid", dungeon = "Dungeon", focus = "Focus" }

-- Ordered list of classes. `name` is only a fallback; the UI prefers the
-- client's spell name.
Data.CATALOG = {
    { class = "DEATHKNIGHT", label = "Death Knight", spells = {
        { id = 51271,  name = "Pillar of Frost" },
        { id = 47568,  name = "Empower Rune Weapon" },
        { id = 152279, name = "Breath of Sindragosa" },
        { id = 207289, name = "Unholy Assault" },
    } },
    { class = "DEMONHUNTER", label = "Demon Hunter", spells = {
        { id = 162264, name = "Metamorphosis" },
    } },
    { class = "DRUID", label = "Druid", spells = {
        { id = 194223, name = "Celestial Alignment" },
        { id = 102560, name = "Incarnation: Chosen of Elune" },
        { id = 106951, name = "Berserk" },
        { id = 102543, name = "Incarnation: Avatar of Ashamane" },
    } },
    { class = "EVOKER", label = "Evoker", spells = {
        { id = 375087, name = "Dragonrage" },
    } },
    { class = "HUNTER", label = "Hunter", spells = {
        { id = 19574,  name = "Bestial Wrath" },
        { id = 359844, name = "Call of the Wild" },
        { id = 288613, name = "Trueshot" },
        { id = 360952, name = "Coordinated Assault" },
    } },
    { class = "MAGE", label = "Mage", spells = {
        { id = 365362, name = "Arcane Surge" },
        { id = 190319, name = "Combustion" },
        { id = 12472,  name = "Icy Veins" },
    } },
    { class = "MONK", label = "Monk", spells = {
        { id = 137639, name = "Storm, Earth, and Fire" },
    } },
    { class = "PALADIN", label = "Paladin", spells = {
        { id = 31884,  name = "Avenging Wrath" },
        { id = 231895, name = "Crusade" },
    } },
    { class = "PRIEST", label = "Priest", spells = {
        { id = 194249, name = "Voidform" },
        { id = 391109, name = "Dark Ascension" },
    } },
    { class = "ROGUE", label = "Rogue", spells = {
        { id = 13750,  name = "Adrenaline Rush" },
        { id = 121471, name = "Shadow Blades" },
    } },
    { class = "SHAMAN", label = "Shaman", spells = {
        { id = 114050, name = "Ascendance (Elemental)" },
        { id = 114051, name = "Ascendance (Enhancement)" },
        { id = 384352, name = "Doom Winds" },
    } },
    { class = "WARRIOR", label = "Warrior", spells = {
        { id = 107574, name = "Avatar" },
        { id = 1719,   name = "Recklessness" },
    } },
    -- No reliable caster buff for Warlock cooldowns; listed so the UI can say so.
    { class = "WARLOCK", label = "Warlock", spells = {} },
}

-- Off by default; toggled as a group.
Data.POTIONS = {
    { id = 1236616, name = "Light's Potential" },
    { id = 1236994, name = "Potion of Recklessness" },
    { id = 1238443, name = "Potion of Zealotry" },
    { id = 1236998, name = "Draught of Rampant Abandon" },
}

ns.CDData = Data
