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
    elseif (not challengeMapID or challengeMapID == 0) and activityID and activityID > 0 then
        if C_LFGList and C_LFGList.GetActivityInfoTable then
            local actInfo = C_LFGList.GetActivityInfoTable(activityID)
            if actInfo then
                if actInfo.mapID and actInfo.mapID > 0 then
                    challengeMapID = actInfo.mapID
                end
                if actInfo.fullName and actInfo.fullName ~= "" and dungeonName == "Unknown Dungeon" then
                    dungeonName = actInfo.fullName
                end
            end
        end
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
---Helper to switch LFGListFrame to CategorySelection, select Dungeons (category 2), and start group
---@return boolean isDungeonCategoryReady
local function SelectDungeonsCategoryAndStartGroup()
    if not LFGListFrame then return false end

    local DUNGEON_CATEGORY_ID = _G["GROUP_FINDER_CATEGORY_ID_DUNGEONS"] or 2

    -- 1. If currently inside EntryCreation for a NON-dungeon category, cancel back to CategorySelection
    if LFGListFrame.EntryCreation and LFGListFrame.EntryCreation:IsShown() then
        if LFGListFrame.EntryCreation.selectedCategory == DUNGEON_CATEGORY_ID then
            -- Already on Dungeons EntryCreation form!
            return true
        else
            if LFGListFrame.EntryCreation.CancelButton and LFGListFrame.EntryCreation.CancelButton.Click then
                pcall(LFGListFrame.EntryCreation.CancelButton.Click, LFGListFrame.EntryCreation.CancelButton)
            elseif LFGListFrame_SetActivePanel and LFGListFrame.CategorySelection then
                pcall(LFGListFrame_SetActivePanel, LFGListFrame, LFGListFrame.CategorySelection)
            end
        end
    end

    -- 2. If currently inside SearchPanel, return back to CategorySelection
    if LFGListFrame.SearchPanel and LFGListFrame.SearchPanel:IsShown() then
        if LFGListFrame.SearchPanel.BackButton and LFGListFrame.SearchPanel.BackButton.Click then
            pcall(LFGListFrame.SearchPanel.BackButton.Click, LFGListFrame.SearchPanel.BackButton)
        elseif LFGListFrame_SetActivePanel and LFGListFrame.CategorySelection then
            pcall(LFGListFrame_SetActivePanel, LFGListFrame, LFGListFrame.CategorySelection)
        end
    end

    -- 3. If CategorySelection is not the active panel, activate it (if not already listed in LFG)
    if LFGListFrame.CategorySelection and not LFGListFrame.CategorySelection:IsShown() then
        if LFGListFrame_SetActivePanel and not (C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()) then
            pcall(LFGListFrame_SetActivePanel, LFGListFrame, LFGListFrame.CategorySelection)
        end
    end

    -- 4. Select Dungeons (Category 2) on CategorySelection
    local catSelection = LFGListFrame.CategorySelection
    if catSelection and catSelection:IsShown() then
        -- Refresh category buttons if available
        if LFGListCategorySelection_UpdateCategoryButtons then
            pcall(LFGListCategorySelection_UpdateCategoryButtons, catSelection)
        end

        -- Find the Dungeons button in CategoryButtons (categoryID == 2)
        local dungeonBtn = nil
        if catSelection.CategoryButtons then
            for _, btn in ipairs(catSelection.CategoryButtons) do
                if btn and btn.categoryID == DUNGEON_CATEGORY_ID then
                    dungeonBtn = btn
                    break
                end
            end
        end

        if dungeonBtn and dungeonBtn.Click then
            pcall(dungeonBtn.Click, dungeonBtn)
        elseif LFGListCategorySelection_SelectCategory then
            pcall(LFGListCategorySelection_SelectCategory, catSelection, DUNGEON_CATEGORY_ID, 0)
        end

        -- Clear auto create mode if present
        if LFGListEntryCreation_ClearAutoCreateMode and LFGListFrame.EntryCreation then
            pcall(LFGListEntryCreation_ClearAutoCreateMode, LFGListFrame.EntryCreation)
        end

        -- 5. Click "Start a Group"
        if catSelection.StartGroupButton and catSelection.StartGroupButton:IsEnabled() then
            pcall(catSelection.StartGroupButton.Click, catSelection.StartGroupButton)
            return true
        end
    end

    return false
end

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

    -- Ensure LFG top button is created on PVEFrame
    if ns.UI and ns.UI.CreateLFGTopButton then
        ns.UI:CreateLFGTopButton()
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

    -- 4. Explicitly ensure Category 2 (Dungeons) is selected and "Start a Group" is clicked
    SelectDungeonsCategoryAndStartGroup()

    -- 5. Hook and set default listing parameters (Playstyle "Relaxed", ilvl, title)
    self:HookEntryCreation()
    self:SetDefaultListingPlaystyle()

    -- Multiple frame ticks to ensure category selection and fields populate after Blizzard's layout updates
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            local frame = LFGListFrame and LFGListFrame.EntryCreation
            local DUNGEON_CATEGORY_ID = _G["GROUP_FINDER_CATEGORY_ID_DUNGEONS"] or 2
            if not (frame and frame:IsShown() and frame.selectedCategory == DUNGEON_CATEGORY_ID) then
                SelectDungeonsCategoryAndStartGroup()
            end
            self:SetDefaultListingPlaystyle()
        end)
        C_Timer.After(0.15, function()
            local frame = LFGListFrame and LFGListFrame.EntryCreation
            local DUNGEON_CATEGORY_ID = _G["GROUP_FINDER_CATEGORY_ID_DUNGEONS"] or 2
            if not (frame and frame:IsShown() and frame.selectedCategory == DUNGEON_CATEGORY_ID) then
                SelectDungeonsCategoryAndStartGroup()
            end
            self:SetDefaultListingPlaystyle()
        end)
    end
end

---Pre-populate and enforce "Relaxed" playstyle on Blizzard's Premade Group listing form
function LFGService:SetDefaultListingPlaystyle()
    local frame = LFGListFrame and LFGListFrame.EntryCreation
    if not frame then return end

    -- Playstyle enum ID for Casual / Relaxed:
    -- In Enum.LFGEntryGeneralPlaystyle: 1 = Learning, 2 = FunRelaxed ("Relaxed"), 3 = FunSerious, 4 = Expert
    local generalPlaystyle = (Enum and Enum.LFGEntryGeneralPlaystyle and Enum.LFGEntryGeneralPlaystyle.FunRelaxed) or 2
    local legacyPlaystyle = (Enum and Enum.LFGEntryPlaystyle and (Enum.LFGEntryPlaystyle.Casual or Enum.LFGEntryPlaystyle.Relaxed)) or 2

    local playstyleText = _G["GROUP_FINDER_GENERAL_PLAYSTYLE2"] or "Relaxed"

    -- 1. Set internal playstyle variables on EntryCreation frame
    -- NOTE: Do NOT call LFGListEntryCreation_SetTitleFromActivityInfo, C_LFGList.SetEntryTitle,
    -- or LFGListEntryCreation_OnPlayStyleSelectedInternal here; SetEntryTitle is a protected
    -- Blizzard C-function that throws ADDON_ACTION_BLOCKED if invoked from third-party code.
    -- Blizzard's native untainted StartGroupButton handler automatically populates the keystone title.
    frame.generalPlaystyle = generalPlaystyle
    frame.selectedPlaystyle = legacyPlaystyle

    -- 2. Target the dropdown widget and update its display state / text
    local dropdown = frame.PlayStyleDropdown or frame.PlaystyleDropdown or frame.playStyleDropdown
    if dropdown then
        dropdown.selectedPlaystyle = generalPlaystyle

        -- Modern 11.0+ DropdownButton API
        if dropdown.SetText then
            pcall(dropdown.SetText, dropdown, playstyleText)
        end
        if dropdown.SetDefaultText then
            pcall(dropdown.SetDefaultText, dropdown, playstyleText)
        end
        if dropdown.GenerateMenu then
            pcall(dropdown.GenerateMenu, dropdown)
        end
        if dropdown.UpdateSelections then
            pcall(dropdown.UpdateSelections, dropdown)
        end
        if dropdown.Text and dropdown.Text.SetText then
            pcall(dropdown.Text.SetText, dropdown.Text, playstyleText)
        end

        -- Legacy UIDropDownMenu API fallback
        if UIDropDownMenu_SetSelectedValue then
            pcall(UIDropDownMenu_SetSelectedValue, dropdown, generalPlaystyle)
        end
        if UIDropDownMenu_SetText then
            pcall(UIDropDownMenu_SetText, dropdown, playstyleText)
        end
    end

    -- 3. Pre-fill minimum item level based on keystone level and leader ilvl
    local _, kLevel = self:GetOwnedKeystoneInfo()
    if kLevel and kLevel > 0 and frame.ItemLevel and frame.ItemLevel.EditBox then
        local currentIlvl = tonumber(frame.ItemLevel.EditBox:GetText()) or 0
        if currentIlvl <= 0 then
            local leaderIlvl = self:GetLeaderEquippedItemLevel()
            local reqIlvl = self:CalculateRequiredItemLevel(leaderIlvl, kLevel)
            pcall(frame.ItemLevel.EditBox.SetText, frame.ItemLevel.EditBox, tostring(reqIlvl))
        end
    end

    -- 4. Trigger Blizzard's entry validation so the List Group button refreshes
    if LFGListEntryCreation_UpdateValidState then
        pcall(LFGListEntryCreation_UpdateValidState, frame)
    end
end

---Hook Blizzard's EntryCreation frame to auto-apply defaults on display
function LFGService:HookEntryCreation()
    local frame = LFGListFrame and LFGListFrame.EntryCreation
    if frame and not frame.mplusAutoLFGHooked then
        frame.mplusAutoLFGHooked = true

        frame:HookScript("OnShow", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.02, function()
                    LFGService:SetDefaultListingPlaystyle()
                end)
                C_Timer.After(0.1, function()
                    LFGService:SetDefaultListingPlaystyle()
                end)
            else
                LFGService:SetDefaultListingPlaystyle()
            end
        end)
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

---Get parsed details about the active listing
---@return boolean hasListing, number challengeMapID, number keystoneLevel, string dungeonName, number|string iconTexture, number requiredIlvl, number activityID
---Get parsed details about the active listing
---@return boolean hasListing, number challengeMapID, number keystoneLevel, string dungeonName, number|string iconTexture, boolean isMythicPlus, number activityID, string groupTitle
function LFGService:GetActiveListingDetails()
    if not self:HasActiveListing() then
        return false, 0, 0, "", 525134, false, 0, ""
    end

    local entryInfo = self:GetActiveListingInfo()
    if not entryInfo then
        return false, 0, 0, "", 525134, false, 0, ""
    end

    local activityID = entryInfo.activityID or 0
    if (not activityID or activityID == 0) and entryInfo.activityIDs and entryInfo.activityIDs[1] then
        activityID = entryInfo.activityIDs[1]
    end

    local isMythicPlus = false
    local dungeonName = "Unknown Dungeon"
    local challengeMapID = 0
    local iconTexture = 525134
    local keyLevel = 0
    local groupTitle = entryInfo.name or ""
    local requiredIlvl = entryInfo.requiredItemLevel or 0

    -- Extract clean dungeon name from activity metadata
    if activityID > 0 and C_LFGList.GetActivityInfoTable then
        local actInfo = C_LFGList.GetActivityInfoTable(activityID)
        if actInfo then
            isMythicPlus = (actInfo.isMythicPlusActivity == true)

            if actInfo.groupID and C_LFGList.GetActivityGroupInfo then
                local groupName = C_LFGList.GetActivityGroupInfo(actInfo.groupID)
                if groupName and groupName ~= "" then
                    dungeonName = groupName
                end
            end
            if dungeonName == "Unknown Dungeon" and actInfo.fullName then
                dungeonName = actInfo.fullName:gsub("%s*%(.*%)", "")
            end
        end
    end

    -- Icon is always standard Mythic Keystone icon (525134) - never use dungeon art
    iconTexture = 525134

    -- Parse key level strictly from group title (entryInfo.name)
    keyLevel = self:ParseKeyLevelFromTitle(groupTitle)

    return true, challengeMapID, keyLevel, dungeonName, iconTexture, isMythicPlus, activityID, groupTitle, requiredIlvl
end

---Parse Mythic+ keystone level from listing title string
---Enforces valid range [2, 50], rejects conflicting or invalid numbers (e.g. "+1", "+1 wer 3", "+10 +12")
---@param title string
---@return number keyLevel (0 if unparseable or invalid)
function LFGService:ParseKeyLevelFromTitle(title)
    if not title or type(title) ~= "string" or title == "" then
        return 0
    end

    -- 1. Explicit plus numbers: "+12", "+ 12", "12+", "12 +"
    local plusMatches = {}
    for numStr in title:gmatch("%+%s*(%d+)") do
        table.insert(plusMatches, tonumber(numStr))
    end
    for numStr in title:gmatch("(%d+)%s*%+") do
        table.insert(plusMatches, tonumber(numStr))
    end

    if #plusMatches > 0 then
        local firstPlus = plusMatches[1]
        for i = 2, #plusMatches do
            if plusMatches[i] ~= firstPlus then
                return 0 -- Conflicting plus numbers (e.g. "+10 +12")
            end
        end

        -- Key must be within valid range: 2 to 50 (e.g. "+1", "+0", "+55" are invalid)
        if firstPlus < 2 or firstPlus > 50 then
            return 0
        end

        -- Check for other contradictory standalone numbers (e.g. "+12 wer 15")
        for numStr in title:gmatch("%f[%d](%d+)%f[%D]") do
            local n = tonumber(numStr)
            if n and n ~= firstPlus then
                local isScoreOrIlvl = title:match(numStr .. "%s*[kK]")
                    or title:match(numStr .. "%s*[iI][lL]")
                    or title:match("[iI][lL]%s*" .. numStr)
                    or (n > 50)
                local isChest = title:match(numStr .. "%s*[cC][hH][eE][sS][tT]")
                if not isScoreOrIlvl and not isChest then
                    return 0 -- Contradictory number found
                end
            end
        end

        return firstPlus
    end

    -- 2. Standalone numbers without plus (e.g. "12 chill", "Den 12")
    local candidateNumbers = {}
    for numStr in title:gmatch("%f[%d](%d+)%f[%D]") do
        local n = tonumber(numStr)
        if n then
            local isScoreOrIlvl = title:match(numStr .. "%s*[kK]")
                or title:match(numStr .. "%s*[iI][lL]")
                or title:match("[iI][lL]%s*" .. numStr)
                or (n > 50)
            if not isScoreOrIlvl then
                table.insert(candidateNumbers, n)
            end
        end
    end

    if #candidateNumbers == 1 then
        local n = candidateNumbers[1]
        if n >= 2 and n <= 50 then
            return n
        end
    end

    return 0
end

-------------------------------------------------------------------------------
-- Applicants Data Access & Queue Retrieval
-------------------------------------------------------------------------------
---Retrieve list of all applicant IDs in order (ascending applicantID)
---@return table applicantsArray
function LFGService:GetApplicants()
    if not C_LFGList or not C_LFGList.GetApplicants then
        return {}
    end

    local applicants = C_LFGList.GetApplicants() or {}
    
    -- Ensure deterministic ordering by ascending applicant ID
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

    local specName = nil
    local specIcon = nil
    if specID and specID > 0 then
        if GetSpecializationInfoByID then
            local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
            specName = sName
            specIcon = sIcon
        end
        if not specName and ns.Specializations and ns.Specializations[specID] then
            specName = ns.Specializations[specID].name
        end
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
        specName        = specName,
        specIcon        = specIcon,
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
