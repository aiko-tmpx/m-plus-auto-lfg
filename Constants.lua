--[[
    MPlusAutoLFG - Matchmaking Assistant for Mythic+
    File: Constants.lua
    Description: Global constants, class/spec mappings, utility sets, role definitions, and default configuration.
]]

local addonName, ns = ...

-- Local caching of high-frequency Lua built-ins
local pairs, ipairs, type, tonumber, tostring = pairs, ipairs, type, tonumber, tostring
local floor, max, min = math.floor, math.max, math.min
local format = string.format

-------------------------------------------------------------------------------
-- Addon Metadata
-------------------------------------------------------------------------------
ns.ADDON_NAME = "MPlusAutoLFG"
ns.VERSION = "1.0.0"
ns.CHAT_PREFIX = "|cff00b4ff[MPlusAutoLFG]|r"
ns.DEBUG_PREFIX = "|cffff8800[MPlusAutoLFG DEBUG]|r"

-------------------------------------------------------------------------------
-- Finite State Machine (FSM) States
-------------------------------------------------------------------------------
ns.States = {
    IDLE       = "IDLE",       -- Not actively listing or searching
    LISTED     = "LISTED",     -- Group listed in LFG, 0 pending invites, waiting/scanning
    ASSEMBLING = "ASSEMBLING", -- Group actively assembling (1-4 members or pending invites)
    FULL       = "FULL",       -- Group reached 5/5 members, auto-delisting completed
}

-------------------------------------------------------------------------------
-- Roles and Target Group Composition
-------------------------------------------------------------------------------
ns.Roles = {
    TANK    = "TANK",
    HEALER  = "HEALER",
    DAMAGER = "DAMAGER",
}

ns.TargetComposition = {
    [ns.Roles.TANK]    = 1,
    [ns.Roles.HEALER]  = 1,
    [ns.Roles.DAMAGER] = 3,
}

ns.MAX_PARTY_SIZE = 5

-------------------------------------------------------------------------------
-- Utility Providers (Bloodlust & Combat Resurrection)
-------------------------------------------------------------------------------
-- Mandatory utilities required per Mythic+ run
ns.Utilities = {
    BLOODLUST = "BLOODLUST",
    COMBAT_RES = "COMBAT_RES",
}

-- Classes capable of casting Bloodlust / Heroism / Time Warp / Fury of the Aspects
ns.BloodlustClasses = {
    ["MAGE"]   = true,
    ["SHAMAN"] = true,
    ["HUNTER"] = true,
    ["EVOKER"] = true,
}

-- Classes capable of casting Combat Resurrection
ns.CombatResClasses = {
    ["DEATHKNIGHT"] = true,
    ["DRUID"]       = true,
    ["WARLOCK"]     = true,
    ["PALADIN"]     = true,
}

-------------------------------------------------------------------------------
-- Class Definitions & Identifiers
-------------------------------------------------------------------------------
ns.Classes = {
    WARRIOR     = { id = 1,  token = "WARRIOR",     name = "Warrior",     color = { r = 0.78, g = 0.61, b = 0.43 } },
    PALADIN     = { id = 2,  token = "PALADIN",     name = "Paladin",     color = { r = 0.96, g = 0.55, b = 0.73 } },
    HUNTER      = { id = 3,  token = "HUNTER",      name = "Hunter",      color = { r = 0.67, g = 0.83, b = 0.45 } },
    ROGUE       = { id = 4,  token = "ROGUE",       name = "Rogue",       color = { r = 1.00, g = 0.96, b = 0.41 } },
    PRIEST      = { id = 5,  token = "PRIEST",      name = "Priest",      color = { r = 1.00, g = 1.00, b = 1.00 } },
    DEATHKNIGHT = { id = 6,  token = "DEATHKNIGHT", name = "Death Knight",color = { r = 0.77, g = 0.12, b = 0.23 } },
    SHAMAN      = { id = 7,  token = "SHAMAN",      name = "Shaman",      color = { r = 0.00, g = 0.44, b = 0.87 } },
    MAGE        = { id = 8,  token = "MAGE",        name = "Mage",        color = { r = 0.25, g = 0.78, b = 0.92 } },
    WARLOCK     = { id = 9,  token = "WARLOCK",     name = "Warlock",     color = { r = 0.53, g = 0.53, b = 0.93 } },
    MONK        = { id = 10, token = "MONK",        name = "Monk",        color = { r = 0.00, g = 1.00, b = 0.59 } },
    DRUID       = { id = 11, token = "DRUID",       name = "Druid",       color = { r = 1.00, g = 0.49, b = 0.04 } },
    DEMONHUNTER = { id = 12, token = "DEMONHUNTER", name = "Demon Hunter",color = { r = 0.64, g = 0.19, b = 0.79 } },
    EVOKER      = { id = 13, token = "EVOKER",      name = "Evoker",      color = { r = 0.20, g = 0.58, b = 0.50 } },
}

-------------------------------------------------------------------------------
-- Specializations Mapping (Spec ID -> Name, Role, Class)
-------------------------------------------------------------------------------
ns.Specializations = {
    -- Warrior
    [71]   = { name = "Arms",            role = "DAMAGER", class = "WARRIOR" },
    [72]   = { name = "Fury",            role = "DAMAGER", class = "WARRIOR" },
    [73]   = { name = "Protection",      role = "TANK",    class = "WARRIOR" },
    -- Paladin
    [65]   = { name = "Holy",            role = "HEALER",  class = "PALADIN" },
    [66]   = { name = "Protection",      role = "TANK",    class = "PALADIN" },
    [70]   = { name = "Retribution",     role = "DAMAGER", class = "PALADIN" },
    -- Hunter
    [253]  = { name = "Beast Mastery",   role = "DAMAGER", class = "HUNTER" },
    [254]  = { name = "Marksmanship",    role = "DAMAGER", class = "HUNTER" },
    [255]  = { name = "Survival",        role = "DAMAGER", class = "HUNTER" },
    -- Rogue
    [259]  = { name = "Assassination",   role = "DAMAGER", class = "ROGUE" },
    [260]  = { name = "Outlaw",          role = "DAMAGER", class = "ROGUE" },
    [261]  = { name = "Subtlety",        role = "DAMAGER", class = "ROGUE" },
    -- Priest
    [256]  = { name = "Discipline",      role = "HEALER",  class = "PRIEST" },
    [257]  = { name = "Holy",            role = "HEALER",  class = "PRIEST" },
    [258]  = { name = "Shadow",          role = "DAMAGER", class = "PRIEST" },
    -- Death Knight
    [250]  = { name = "Blood",           role = "TANK",    class = "DEATHKNIGHT" },
    [251]  = { name = "Frost",           role = "DAMAGER", class = "DEATHKNIGHT" },
    [252]  = { name = "Unholy",          role = "DAMAGER", class = "DEATHKNIGHT" },
    -- Shaman
    [262]  = { name = "Elemental",       role = "DAMAGER", class = "SHAMAN" },
    [263]  = { name = "Enhancement",     role = "DAMAGER", class = "SHAMAN" },
    [264]  = { name = "Restoration",     role = "HEALER",  class = "SHAMAN" },
    -- Mage
    [62]   = { name = "Arcane",          role = "DAMAGER", class = "MAGE" },
    [63]   = { name = "Fire",            role = "DAMAGER", class = "MAGE" },
    [64]   = { name = "Frost",           role = "DAMAGER", class = "MAGE" },
    -- Warlock
    [265]  = { name = "Affliction",      role = "DAMAGER", class = "WARLOCK" },
    [266]  = { name = "Demonology",      role = "DAMAGER", class = "WARLOCK" },
    [267]  = { name = "Destruction",     role = "DAMAGER", class = "WARLOCK" },
    -- Monk
    [268]  = { name = "Brewmaster",      role = "TANK",    class = "MONK" },
    [270]  = { name = "Mistweaver",      role = "HEALER",  class = "MONK" },
    [269]  = { name = "Windwalker",      role = "DAMAGER", class = "MONK" },
    -- Druid
    [102]  = { name = "Balance",         role = "DAMAGER", class = "DRUID" },
    [103]  = { name = "Feral",           role = "DAMAGER", class = "DRUID" },
    [104]  = { name = "Guardian",        role = "TANK",    class = "DRUID" },
    [105]  = { name = "Restoration",     role = "HEALER",  class = "DRUID" },
    -- Demon Hunter
    [577]  = { name = "Havoc",           role = "DAMAGER", class = "DEMONHUNTER" },
    [581]  = { name = "Vengeance",       role = "TANK",    class = "DEMONHUNTER" },
    -- Evoker
    [1467] = { name = "Devastation",     role = "DAMAGER", class = "EVOKER" },
    [1468] = { name = "Preservation",    role = "HEALER",  class = "EVOKER" },
    [1473] = { name = "Augmentation",    role = "DAMAGER", class = "EVOKER" },
}

-------------------------------------------------------------------------------
-- Dynamic Item Level Calculation Rules
-------------------------------------------------------------------------------
-- Key Level >= 18: Leader ilvl - 5
-- Key Level 15 to 17: Leader ilvl - 10
-- Key Level 12 to 14: Leader ilvl - 15
-- Key Level < 12: Leader ilvl - 35
ns.IlvlThresholdOffsets = {
    { minKey = 18, maxKey = 999, offset = -5 },
    { minKey = 15, maxKey = 17,  offset = -10 },
    { minKey = 12, maxKey = 14,  offset = -15 },
    { minKey = 0,  maxKey = 11,  offset = -35 },
}

-------------------------------------------------------------------------------
-- Default Addon Configuration
-------------------------------------------------------------------------------
ns.DefaultConfig = {
    debug = false,
    autoDelistOnFull = true,
    qualifyEqualOrHigher = false, -- Disabled by default: allow candidates who already timed equal or higher keys to qualify
    rulesMode = "DEFAULT", -- "DEFAULT" (auto-tiered) or "CUSTOM" (user rules)
    customRules = {
        keyDropTolerance = 2,           -- Allowed key difference [TargetKey - X] (clamped to +2)
        requireTimedRun = true,         -- Timed runs required by default
        ilvlDeficit = 10,               -- Allowed item level deficit below key recommendation
        onlyUncompletedDungeon = false, -- Only invite candidates who haven't completed this dungeon
    },
    minimap = {
        hide = false,
        angle = 220,
    },
    framePosition = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 100,
    },
    listingTitleTemplate = "MPlusAutoLFG: +%d",
    listingDescTemplate = "MPlusAutoLFG auto-matching queue. Invites are automated in queue order: 1 BL, 1 CR, verified experience. Fast formation.",
}

-------------------------------------------------------------------------------
-- Helper Utility Functions
-------------------------------------------------------------------------------
---Check if a class provides Bloodlust
---@param classFilename string
---@return boolean
function ns.HasBloodlust(classFilename)
    return ns.BloodlustClasses[classFilename] == true
end

---Check if a class provides Combat Resurrection
---@param classFilename string
---@return boolean
function ns.HasCombatRes(classFilename)
    return ns.CombatResClasses[classFilename] == true
end

---Retrieve class display color
---@param classFilename string
---@return number r, number g, number b, string hex
function ns.GetClassColor(classFilename)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if c then
        return c.r, c.g, c.b, c.colorStr or format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    local fallback = ns.Classes[classFilename] and ns.Classes[classFilename].color
    if fallback then
        return fallback.r, fallback.g, fallback.b, format("ff%02x%02x%02x", fallback.r * 255, fallback.g * 255, fallback.b * 255)
    end
    return 1, 1, 1, "ffffffff"
end

---Retrieve specialization information by ID
---@param specID number
---@return table|nil
function ns.GetSpecInfo(specID)
    if not specID or specID == 0 then return nil end
    return ns.Specializations[specID]
end
