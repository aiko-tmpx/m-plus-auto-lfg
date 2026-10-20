--[[
    MPlusAutoLFG - Matchmaking Assistant for Mythic+
    File: Services/LFGService.lua
    Description: Data Access Layer and adapter facade over Blizzard's C_LFGList, C_MythicPlus,
                 and C_ChallengeMode APIs. 100% native client calls.
]]

local addonName, ns = ...

-- Local caching of high-frequency Lua built-ins
local pairs, ipairs, type, tonumber, select = pairs, ipairs, type, tonumber, select
local floor, max, min = math.floor, math.max, math.min
local sort = table.sort
local format = string.format

-------------------------------------------------------------------------------
-- LFGService Declaration
-------------------------------------------------------------------------------
local LFGService = {}
ns.LFGService = LFGService

-------------------------------------------------------------------------------
-- Keystone & Activity Information
-------------------------------------------------------------------------------
---Retrieve owned Mythic Keystone information
---@return number challengeMapID, number keystoneLevel, string dungeonName, number|string iconTexture, number activityID
function LFGService:GetOwnedKeystoneInfo()
    local activityID, groupID, keystoneLevel
    if C_LFGList and C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel then
        activityID, groupID, keystoneLevel = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
    end

    local challengeMapID = 0
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
        challengeMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0
    end

    if (not keystoneLevel or keystoneLevel == 0) and C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel then
        keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel() or 0
    end

    local dungeonName = "Unknown Dungeon"
    local iconTexture = 525134 -- Default Mythic Keystone icon

    if challengeMapID and challengeMapID > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(challengeMapID)
        if name and name ~= "" then
            dungeonName = name
        end
        if texture then
            iconTexture = texture
        end
    end

    -- If activityID was not returned directly, resolve from challengeMapID or available activities
    if (not activityID or activityID == 0) and challengeMapID and challengeMapID > 0 then
        activityID = self:FindActivityIDForMap(challengeMapID)
    end

    return challengeMapID, keystoneLevel or 0, dungeonName, iconTexture, activityID or 0
end

---Helper to find LFG activityID matching a Challenge Map ID
---@param challengeMapID number
---@return number activityID
function LFGService:FindActivityIDForMap(challengeMapID)
    if not C_LFGList or not C_LFGList.GetAvailableActivities then
        return 0
    end

    -- Category 2 is typically Dungeons in Premade Groups
    local activities = C_LFGList.GetAvailableActivities(2) or {}
    for _, actID in ipairs(activities) do
        local info = C_LFGList.GetActivityInfoTable and C_LFGList.GetActivityInfoTable(actID)
        if info and (info.isMythicPlusActivity or info.isMythicActivity) then
            if info.mapID == challengeMapID or (info.groupFinderActivityGroupID and info.groupFinderActivityGroupID == challengeMapID) then
                return actID
            end
        end
    end

    return 0
end

-------------------------------------------------------------------------------
-- Dynamic Item Level Calculation
-------------------------------------------------------------------------------
---Retrieve party leader's equipped average item level
---@return number
function LFGService:GetLeaderEquippedItemLevel()
    if GetAverageItemLevel then
        local _, equippedIlvl = GetAverageItemLevel()
        return floor(equippedIlvl or 0)
    end
    return 0
end

---Calculate minimum required item level based on leader ilvl and key level
---@param leaderIlvl number
---@param keyLevel number
---@return number requiredIlvl
function LFGService:CalculateRequiredItemLevel(leaderIlvl, keyLevel)
    leaderIlvl = floor(leaderIlvl or 0)
    keyLevel = tonumber(keyLevel) or 0

    local offset = -35
    for _, rule in ipairs(ns.IlvlThresholdOffsets) do
        if keyLevel >= rule.minKey and keyLevel <= rule.maxKey then
            offset = rule.offset
            break
        end
    end

    local required = leaderIlvl + offset
    return max(0, required)
end

-------------------------------------------------------------------------------
-- LFG Listing Management
-------------------------------------------------------------------------------
---Open Blizzard's native Premade Groups frame cleanly without taint
function LFGService:OpenGroupFinder()
    -- 1. Try Blizzard's dedicated LFG opener (handles tabs, frames, and subpanels natively)
    if LFGListUtil_OpenBestWindow then
        pcall(LFGListUtil_OpenBestWindow)
    end

    -- 2. Ensure PVEFrame is open and displaying the Group Finder panel
    if PVEFrame then
        if not PVEFrame:IsShown() then
            if ShowUIPanel then
                pcall(ShowUIPanel, PVEFrame)
            else
                pcall(PVEFrame.Show, PVEFrame)
            end
        end

        local stub = _G["LFGListPVEStub"]
        if stub and PVEFrame_ShowFrame then
            pcall(PVEFrame_ShowFrame, "GroupFinderFrame", stub)
        elseif stub and PVEFrame_ToggleFrame then
            pcall(PVEFrame_ToggleFrame, "GroupFinderFrame", stub)
        end
    elseif ToggleLFDParentFrame then
        pcall(ToggleLFDParentFrame)
    end

    -- 3. If GroupFinderFrame has group buttons, click Premade Groups button
    if GroupFinderFrame and GroupFinderFrame.groupButtons then
        for _, btn in ipairs(GroupFinderFrame.groupButtons) do
            if btn and (btn.tooltip == LFGLIST_NAME or (btn.GetText and btn:GetText() and btn:GetText():find("Premade"))) then
                pcall(btn.Click, btn)
                break
            end
        end
    end

    -- 4. If CategorySelection is visible, automatically click "Start a Group"
    if LFGListFrame and LFGListFrame.CategorySelection and LFGListFrame.CategorySelection:IsShown() then
        if LFGListFrame.CategorySelection.StartGroupButton and LFGListFrame.CategorySelection.StartGroupButton:IsEnabled() then
            pcall(LFGListFrame.CategorySelection.StartGroupButton.Click, LFGListFrame.CategorySelection.StartGroupButton)
        end
    end

    -- 5. If EntryCreation is visible, prefill recommended item level
    if LFGListFrame and LFGListFrame.EntryCreation and LFGListFrame.EntryCreation:IsShown() then
        local kMapID, kLevel = self:GetOwnedKeystoneInfo()
        if kLevel and kLevel > 0 then
            local leaderIlvl = self:GetLeaderEquippedItemLevel()
            local reqIlvl = self:CalculateRequiredItemLevel(leaderIlvl, kLevel)
            if LFGListFrame.EntryCreation.ItemLevel and LFGListFrame.EntryCreation.ItemLevel.EditBox then
                pcall(LFGListFrame.EntryCreation.ItemLevel.EditBox.SetText, LFGListFrame.EntryCreation.ItemLevel.EditBox, tostring(reqIlvl))
            end
        end
    end
end

---Check if group currently has an active listing, or open Group Finder frame
---@return boolean isAlreadyActive
function LFGService:CreateListing()
    if self:HasActiveListing() then
        return true
    end

    self:OpenGroupFinder()
    return false
end

---Update existing active listing
---@param activityID number
---@param requiredIlvl number
---@return boolean
function LFGService:UpdateListing(activityID, requiredIlvl)
    return self:HasActiveListing()
end

---Handle request to remove listing (opens Group Finder to allow manual delisting)
---@return boolean
function LFGService:RemoveListing()
    self:OpenGroupFinder()
    return true
end

---Check if group currently has an active LFG listing
---@return boolean
function LFGService:HasActiveListing()
    if C_LFGList and C_LFGList.HasActiveEntryInfo then
        return C_LFGList.HasActiveEntryInfo() == true
    end
    return false
end

---Get details about the active listing
---@return table|nil
function LFGService:GetActiveListingInfo()
    if C_LFGList and C_LFGList.GetActiveEntryInfo then
        return C_LFGList.GetActiveEntryInfo()
    end
    return nil
end

-------------------------------------------------------------------------------
-- Applicants Data Access & FIFO Retrieval
-------------------------------------------------------------------------------
---Retrieve list of all applicant IDs in strict FIFO order (ascending applicantID)
---@return table applicantsArray
function LFGService:GetApplicants()
    if not C_LFGList or not C_LFGList.GetApplicants then
        return {}
    end

    local applicants = C_LFGList.GetApplicants() or {}
    
    -- Ensure deterministic FIFO ordering by ascending applicant ID
    sort(applicants, function(a, b)
        return a < b
    end)

    return applicants
end

---Retrieve basic applicant group metadata
---@param applicantID number
---@return table|nil
function LFGService:GetApplicantInfo(applicantID)
    if not C_LFGList or not C_LFGList.GetApplicantInfo then
        return nil
    end

    return C_LFGList.GetApplicantInfo(applicantID)
end

---Retrieve detailed member info for an applicant
---@param applicantID number
---@param memberIndex number
---@return table|nil candidateInfo
function LFGService:GetApplicantMemberInfo(applicantID, memberIndex)
    if not C_LFGList or not C_LFGList.GetApplicantMemberInfo then
        return nil
    end

    local name, classFilename, localizedClass, level, itemLevel, honorLevel,
          tank, healer, damage, assignedRole, relationship, dungeonScore,
          pvpItemLevel, specID = C_LFGList.GetApplicantMemberInfo(applicantID, memberIndex)

    if not name or name == "" then
        return nil
    end

    classFilename = classFilename or "WARRIOR"
    assignedRole = assignedRole or (tank and "TANK") or (healer and "HEALER") or "DAMAGER"
    itemLevel = floor(itemLevel or 0)
    dungeonScore = floor(dungeonScore or 0)

    -- If specID is not returned directly by client API, fallback to 0
    if not specID or specID == 0 then
        specID = 0
    end

    local hasBL = ns.HasBloodlust(classFilename)
    local hasCR = ns.HasCombatRes(classFilename)

    return {
        applicantID     = applicantID,
        memberIdx       = memberIndex,
        name            = name,
        classFilename   = classFilename,
        localizedClass  = localizedClass or classFilename,
        specID          = specID,
        role            = assignedRole,
        itemLevel       = itemLevel,
        dungeonScore    = dungeonScore,
        hasBL           = hasBL,
        hasCR           = hasCR,
    }
end

---Retrieve dungeon score and best run progression for an applicant
---@param applicantID number
---@param memberIndex number
---@param activityID number
---@return number bestRunLevel, boolean finishedSuccess, number mapScore, string mapName
function LFGService:GetApplicantDungeonScore(applicantID, memberIndex, activityID)
    if not C_LFGList then
        return 0, false, 0, ""
    end

    -- Real-time Blizzard API for dungeon score on listing activity
    local scoreFunc = C_LFGList.GetApplicantDungeonScoreForListing or C_LFGList.GetApplicantDungeonScoreForActivity
    if scoreFunc then
        local scoreInfo = scoreFunc(applicantID, memberIndex, activityID)
        if scoreInfo then
            local bestRunLevel = tonumber(scoreInfo.bestRunLevel) or 0
            local finishedSuccess = scoreInfo.finishedSuccess == true
            local mapScore = tonumber(scoreInfo.mapScore) or 0
            local mapName = scoreInfo.mapName or ""
            return bestRunLevel, finishedSuccess, mapScore, mapName
        end
    end

    return 0, false, 0, ""
end

-------------------------------------------------------------------------------
-- Invitations & Moderation
-------------------------------------------------------------------------------
---Send an invite to an applicant group (requires hardware event on live client)
---@param applicantID number
---@return boolean success
function LFGService:InviteApplicant(applicantID)
    if C_LFGList and C_LFGList.InviteApplicant then
        local ok, err = pcall(C_LFGList.InviteApplicant, applicantID)
        return ok
    end
    return false
end

---Decline an applicant
---@param applicantID number
---@return boolean success
function LFGService:DeclineApplicant(applicantID)
    if C_LFGList and C_LFGList.DeclineApplicant then
        local ok, err = pcall(C_LFGList.DeclineApplicant, applicantID)
        return ok
    end
    return false
end
