--[[
    MPlusAutoLFG - Matchmaking Assistant for Mythic+
    File: Validation.lua
    Description: Declarative Validation Pipeline (Chain of Responsibility) for candidate applicants.
                 Pure filtering functions ensuring strict, deterministic, and fair matchmaking.
]]

local addonName, ns = ...

-- Local caching of high-frequency Lua built-ins
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local floor, max, min = math.floor, math.max, math.min
local format = string.format
local tinsert, tremove = table.insert, table.remove

-------------------------------------------------------------------------------
-- Pure Validator Rules (Chain of Responsibility)
-------------------------------------------------------------------------------

---Rule 1: Group Roles Allocation
---Ensures candidate does not exceed the target composition: 1 Tank, 1 Healer, 3 DPS.
---@param candidate table
---@param rosterContext table
---@return boolean passed, string? reason
function ns.CheckRoleSlot(candidate, rosterContext)
    local role = candidate.role
    if not role or role == "NOROLE" then
        return false, "Applicant has no assigned role"
    end

    local currentRoles = rosterContext.roles or {}
    if role == ns.Roles.TANK then
        local currentTanks = currentRoles[ns.Roles.TANK] or 0
        if currentTanks >= ns.TargetComposition[ns.Roles.TANK] then
            return false, "Tank role slot is already filled or reserved"
        end
    elseif role == ns.Roles.HEALER then
        local currentHealers = currentRoles[ns.Roles.HEALER] or 0
        if currentHealers >= ns.TargetComposition[ns.Roles.HEALER] then
            return false, "Healer role slot is already filled or reserved"
        end
    elseif role == ns.Roles.DAMAGER then
        local currentDPS = currentRoles[ns.Roles.DAMAGER] or 0
        if currentDPS >= ns.TargetComposition[ns.Roles.DAMAGER] then
            return false, "DPS role slots are already filled or reserved"
        end
    else
        return false, format("Unknown role '%s'", tostring(role))
    end

    return true, nil
end

---Rule 2: Item Level Gatekeeper
---Validates applicant item level against the required item level threshold.
---@param candidate table
---@param rosterContext table
---@return boolean passed, string? reason
function ns.CheckItemLevel(candidate, rosterContext)
    local requiredIlvl = rosterContext.requiredItemLevel or 0
    local applicantIlvl = candidate.itemLevel or 0

    if applicantIlvl < requiredIlvl then
        return false, format("Item level %d is below required threshold (%d)", applicantIlvl, requiredIlvl)
    end

    return true, nil
end

---Rule 3: Dungeon Experience Threshold
---Automated qualification tiers:
---  * Before +10 (Keys <= 10): No prior completed run required (open queue).
---  * Keys 11 to 15: Requires [Key - 2] completed timed for this specific dungeon.
---  * Keys 16+: Requires [Key - 1] completed timed for this specific dungeon.
---  * Optional (disabled by default): Applicants with equal or higher keys (bestRun >= targetKey) qualify even if untimed.
---@param candidate table
---@param rosterContext table
---@return boolean passed, string? reason
function ns.CheckExperience(candidate, rosterContext)
    local targetKey = rosterContext.targetKeyLevel or 0
    local bestRun = candidate.bestRunLevel or 0
    local timed = candidate.bestRunFinishedSuccess == true

    -- Keys <= 10: Open queue — no prior completed run required
    if targetKey <= 10 then
        return true, nil
    end

    -- Option: Auto-qualify equal and higher key applicants (disabled by default)
    local qualifyEqualOrHigher = (MPlusAutoLFGDB and MPlusAutoLFGDB.qualifyEqualOrHigher) == true
    if qualifyEqualOrHigher and bestRun >= targetKey then
        return true, nil
    end

    -- Keys 11 to 15: [Key - 2] timed is required
    -- Keys 16+: [Key - 1] timed is required
    local drop = (targetKey <= 15) and 2 or 1
    local minRequiredLevel = max(2, targetKey - drop)

    if bestRun < minRequiredLevel then
        return false, format("Best run (+%d) is below required tier (+%d) for key +%d", bestRun, minRequiredLevel, targetKey)
    end

    if not timed then
        return false, format("Best run (+%d) was not completed within the timer", bestRun)
    end

    return true, nil
end

---Rule 4: Class & Spec Duplicate Restrictions
---Keys < 10: Duplicate specs and classes are allowed (low/leveling/casual keys).
---Keys 10 to 14: Same classes are allowed if specializations differ. Duplicate specs are rejected.
---Keys >= 15: Duplicate classes are strictly prohibited across the entire group.
---@param candidate table
---@param rosterContext table
---@return boolean passed, string? reason
function ns.CheckDuplicates(candidate, rosterContext)
    local targetKey = rosterContext.targetKeyLevel or 0
    local classFilename = candidate.classFilename
    local specID = candidate.specID

    local rosterClasses = rosterContext.classes or {}
    local rosterSpecs = rosterContext.specs or {}

    if targetKey >= 15 then
        -- Strict class exclusivity on keys 15 and above
        if rosterClasses[classFilename] and rosterClasses[classFilename] > 0 then
            return false, format("Duplicate class '%s' is prohibited on key levels >= 15", classFilename)
        end
    elseif targetKey >= 10 then
        -- Keys 10 to 14 allow same class if different specs
        if specID and specID > 0 and rosterSpecs[specID] and rosterSpecs[specID] > 0 then
            local specInfo = ns.GetSpecInfo(specID)
            local specName = specInfo and specInfo.name or format("Spec %d", specID)
            return false, format("Duplicate specialization '%s' is rejected on key levels >= 10", specName)
        end
    end

    return true, nil
end

---Rule 5: Utility Requirements (Bloodlust & Combat Resurrection)
---Group must have at least 1 BL and at least 1 CR.
---Dynamic lock: If remaining open slots equal the number of missing utilities,
---reject applicants who cannot provide the missing utility.
---@param candidate table
---@param rosterContext table
---@return boolean passed, string? reason
function ns.CheckUtilities(candidate, rosterContext)
    local totalInGroup = rosterContext.totalCount or 0
    local openSlots = max(0, ns.MAX_PARTY_SIZE - totalInGroup)

    local hasBL = rosterContext.hasBL == true
    local hasCR = rosterContext.hasCR == true

    local missingBL = not hasBL
    local missingCR = not hasCR
    local missingCount = (missingBL and 1 or 0) + (missingCR and 1 or 0)

    -- If all mandatory utilities are already satisfied, any class utility is valid
    if missingCount == 0 then
        return true, nil
    end

    -- If no slots left, let role checker handle it
    if openSlots <= 0 then
        return true, nil
    end

    local candBL = candidate.hasBL == true
    local candCR = candidate.hasCR == true

    -- Scenario A: Only 1 slot remaining
    if openSlots == 1 then
        if missingCount == 1 then
            if missingBL and not candBL then
                return false, "Final slot locked: group requires Bloodlust / Heroism"
            end
            if missingCR and not candCR then
                return false, "Final slot locked: group requires Combat Resurrection"
            end
        elseif missingCount == 2 then
            -- 1 slot left and both missing: candidate must provide at least one
            if not (candBL or candCR) then
                return false, "Final slot locked: candidate provides neither missing utility (BL or CR)"
            end
        end
        return true, nil
    end

    -- Scenario B: 2 slots remaining and 2 utilities missing
    -- Every applicant admitted to these remaining 2 slots MUST bring at least one missing utility
    if openSlots == 2 and missingCount == 2 then
        if not (candBL or candCR) then
            return false, "Remaining 2 slots locked: applicant must provide missing utility (BL or CR)"
        end
        return true, nil
    end

    -- If openSlots > missingCount, group has room for flexibility
    return true, nil
end

-------------------------------------------------------------------------------
-- Declarative Pipeline Registry & Orchestrator
-------------------------------------------------------------------------------
ns.ValidationPipeline = {
    { name = "CheckRoleSlot",    fn = ns.CheckRoleSlot },
    { name = "CheckItemLevel",   fn = ns.CheckItemLevel },
    { name = "CheckExperience",  fn = ns.CheckExperience },
    { name = "CheckDuplicates",  fn = ns.CheckDuplicates },
    { name = "CheckUtilities",   fn = ns.CheckUtilities },
}

---Execute the declarative validation pipeline against a candidate
---@param candidate table
---@param rosterContext table
---@return boolean isValid, string? rejectReason, string? failedValidator
function ns.ValidateCandidate(candidate, rosterContext)
    if not candidate then
        return false, "Candidate data is nil", "Internal"
    end
    if not rosterContext then
        return false, "Roster context is nil", "Internal"
    end

    for _, step in ipairs(ns.ValidationPipeline) do
        local passed, reason = step.fn(candidate, rosterContext)
        if not passed then
            return false, reason or "Validation failed", step.name
        end
    end

    return true, nil, nil
end

---Add a custom validator rule to the pipeline
---@param name string
---@param validatorFn function
---@param index number|nil
function ns.AddValidator(name, validatorFn, index)
    if type(validatorFn) ~= "function" then return end
    local entry = { name = name or "CustomRule", fn = validatorFn }
    if index and index <= #ns.ValidationPipeline then
        tinsert(ns.ValidationPipeline, index, entry)
    else
        tinsert(ns.ValidationPipeline, entry)
    end
end

---Remove a validator rule from the pipeline by function or name
---@param identifier function|string
function ns.RemoveValidator(identifier)
    for i = #ns.ValidationPipeline, 1, -1 do
        local entry = ns.ValidationPipeline[i]
        if entry.fn == identifier or entry.name == identifier then
            tremove(ns.ValidationPipeline, i)
        end
    end
end
