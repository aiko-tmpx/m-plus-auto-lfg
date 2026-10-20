--[[
    MPlusAutoLFG - Matchmaking Assistant for Mythic+
    File: MockEngine.lua
    Description: Synthetic queue generator, realistic test fixtures, and offline debug harness.
                 Provides a complete mock implementation of LFGService for rapid local testing.
]]

local addonName, ns = ...

-- Local caching of high-frequency Lua built-ins
local pairs, ipairs, type, tonumber, tostring = pairs, ipairs, type, tonumber, tostring
local floor, max, min, random = math.floor, math.max, math.min, math.random
local tinsert, tremove, wipe, sort = table.insert, table.remove, table.wipe, table.sort
local format = string.format

-------------------------------------------------------------------------------
-- MockEngine Declaration
-------------------------------------------------------------------------------
local MockEngine = {}
ns.MockEngine = MockEngine

-- Internal state
local isEnabled = false
local mockApplicantCounter = 200
local mockApplicants = {}
local mockApplicantOrder = {}
local mockListingActive = false
local mockListingData = {}
local mockKeystoneData = {
    challengeMapID = 501,
    keystoneLevel = 15,
    dungeonName = "The Stonevault",
    icon = 525134,
    activityID = 1001,
}
local mockLeaderIlvl = 635

-------------------------------------------------------------------------------
-- Realistic Test Fixtures
-------------------------------------------------------------------------------
-- 1. High-score DPS missing Bloodlust (Rogue, 2850 score, +16 timed)
local FIXTURE_ROGUE_NO_BL = {
    name = "Valeera",
    classFilename = "ROGUE",
    specID = 261, -- Subtlety
    role = "DAMAGER",
    itemLevel = 636,
    dungeonScore = 2850,
    bestRunLevel = 16,
    bestRunFinishedSuccess = true,
    hasBL = false,
    hasCR = false,
}

-- 2. Undergeared Tank (ilvl 605 < required 625 on key +15)
local FIXTURE_UNDERGEARED_TANK = {
    name = "Baine",
    classFilename = "WARRIOR",
    specID = 73, -- Protection
    role = "TANK",
    itemLevel = 605,
    dungeonScore = 2100,
    bestRunLevel = 14,
    bestRunFinishedSuccess = true,
    hasBL = false,
    hasCR = false,
}

-- 3. Applicant with timed run 3 levels lower (+12 timed on a +15 key, needs >= 13)
local FIXTURE_LOW_EXP_HEALER = {
    name = "Anduin",
    classFilename = "PRIEST",
    specID = 257, -- Holy
    role = "HEALER",
    itemLevel = 630,
    dungeonScore = 2250,
    bestRunLevel = 12,
    bestRunFinishedSuccess = true,
    hasBL = false,
    hasCR = false,
}

-- 4. Valid Mage offering BL with valid key experience (+15 timed)
local FIXTURE_VALID_MAGE_BL = {
    name = "Jaina",
    classFilename = "MAGE",
    specID = 64, -- Frost
    role = "DAMAGER",
    itemLevel = 633,
    dungeonScore = 2680,
    bestRunLevel = 15,
    bestRunFinishedSuccess = true,
    hasBL = true,
    hasCR = false,
}

-- 5. Duplicate specialization collision (Frost Mage applying when Frost Mage exists)
local FIXTURE_DUPLICATE_SPEC_MAGE = {
    name = "Khadgar",
    classFilename = "MAGE",
    specID = 64, -- Frost
    role = "DAMAGER",
    itemLevel = 640,
    dungeonScore = 2920,
    bestRunLevel = 17,
    bestRunFinishedSuccess = true,
    hasBL = true,
    hasCR = false,
}

-- 6. Valid Tank with Combat Res (Blood DK)
local FIXTURE_VALID_TANK_CR = {
    name = "Bolvar",
    classFilename = "DEATHKNIGHT",
    specID = 250, -- Blood
    role = "TANK",
    itemLevel = 635,
    dungeonScore = 2710,
    bestRunLevel = 15,
    bestRunFinishedSuccess = true,
    hasBL = false,
    hasCR = true,
}

-- 7. Valid Healer with Combat Res (Resto Druid)
local FIXTURE_VALID_HEALER_CR = {
    name = "Malfurion",
    classFilename = "DRUID",
    specID = 105, -- Restoration
    role = "HEALER",
    itemLevel = 634,
    dungeonScore = 2690,
    bestRunLevel = 15,
    bestRunFinishedSuccess = true,
    hasBL = false,
    hasCR = true,
}

-------------------------------------------------------------------------------
-- Initialization & Control
-------------------------------------------------------------------------------
---Enable the Mock Engine and hook LFGService
function MockEngine:Enable()
    isEnabled = true
    ns.LFGService:SetMockEngine(self)
    mockListingActive = true
    mockListingData = {
        activityID = mockKeystoneData.activityID,
        requiredIlvl = ns.LFGService:CalculateRequiredItemLevel(mockLeaderIlvl, mockKeystoneData.keystoneLevel),
        title = format(ns.DefaultConfig.listingTitleTemplate, mockKeystoneData.keystoneLevel),
        description = ns.DefaultConfig.listingDescTemplate,
    }
    if ns.Logger then
        ns.Logger:Info("MOCK", "Mock Engine ENABLED. Real server calls are safely intercepted.")
    end
end

---Disable Mock Engine and revert LFGService to live Blizzard client
function MockEngine:Disable()
    isEnabled = false
    ns.LFGService:SetMockEngine(nil)
    self:Reset()
    if ns.Logger then
        ns.Logger:Info("MOCK", "Mock Engine DISABLED. Addon returned to live client mode.")
    end
end

---Check if mock engine is enabled
---@return boolean
function MockEngine:IsEnabled()
    return isEnabled
end

---Reset mock data and queue
function MockEngine:Reset()
    wipe(mockApplicants)
    wipe(mockApplicantOrder)
    mockApplicantCounter = 200
    mockListingActive = false
    wipe(mockListingData)
    if ns.Logger then
        ns.Logger:Debug("MOCK", "Mock data and queue wiped.")
    end
end

-------------------------------------------------------------------------------
-- Mock LFGService Adapter Implementations
-------------------------------------------------------------------------------
function MockEngine:GetOwnedKeystoneInfo()
    return mockKeystoneData.challengeMapID,
           mockKeystoneData.keystoneLevel,
           mockKeystoneData.dungeonName,
           mockKeystoneData.icon,
           mockKeystoneData.activityID
end

function MockEngine:GetLeaderEquippedItemLevel()
    return mockLeaderIlvl
end

function MockEngine:CreateListing(activityID, requiredIlvl, title, description)
    mockListingActive = true
    mockListingData = {
        activityID = activityID,
        requiredIlvl = requiredIlvl,
        title = title,
        description = description,
    }
    return true
end

function MockEngine:UpdateListing(activityID, requiredIlvl)
    if mockListingActive then
        mockListingData.activityID = activityID
        mockListingData.requiredIlvl = requiredIlvl
        return true
    end
    return false
end

function MockEngine:RemoveListing()
    mockListingActive = false
    wipe(mockListingData)
    return true
end

function MockEngine:HasActiveListing()
    return mockListingActive
end

function MockEngine:GetActiveListingInfo()
    if mockListingActive then
        return {
            activityID = mockListingData.activityID,
            requiredItemLevel = mockListingData.requiredIlvl,
            name = mockListingData.title,
            comment = mockListingData.description,
        }
    end
    return nil
end

function MockEngine:GetApplicants()
    local result = {}
    for _, appID in ipairs(mockApplicantOrder) do
        if mockApplicants[appID] and mockApplicants[appID].status == "applied" then
            tinsert(result, appID)
        end
    end
    return result
end

function MockEngine:GetApplicantInfo(applicantID)
    local app = mockApplicants[applicantID]
    if not app then return nil end

    return {
        applicantID = applicantID,
        applicationStatus = app.status or "applied",
        numMembers = 1,
        isNew = false,
        comment = app.comment or "",
        displayDuration = 10,
    }
end

function MockEngine:GetApplicantMemberInfo(applicantID, memberIndex)
    local app = mockApplicants[applicantID]
    if not app or not app.member then return nil end

    local m = app.member
    local classInfo = ns.Classes[m.classFilename]
    local localizedClass = classInfo and classInfo.name or m.classFilename

    return {
        applicantID     = applicantID,
        memberIdx       = memberIndex or 1,
        name            = m.name,
        classFilename   = m.classFilename,
        localizedClass  = localizedClass,
        specID          = m.specID,
        role            = m.role,
        itemLevel       = m.itemLevel,
        dungeonScore    = m.dungeonScore,
        bestRunLevel    = m.bestRunLevel,
        bestRunFinishedSuccess = m.bestRunFinishedSuccess,
        hasBL           = m.hasBL,
        hasCR           = m.hasCR,
    }
end

function MockEngine:GetApplicantDungeonScore(applicantID, memberIndex, activityID)
    local app = mockApplicants[applicantID]
    if not app or not app.member then
        return 0, false, 0, ""
    end

    local m = app.member
    return m.bestRunLevel or 0, m.bestRunFinishedSuccess == true, m.dungeonScore or 0, mockKeystoneData.dungeonName
end

function MockEngine:InviteApplicant(applicantID)
    local app = mockApplicants[applicantID]
    if not app then return false end

    app.status = "invited"
    if ns.Logger then
        ns.Logger:Info("MOCK", format("Applicant '%s' (ID %d) INVITED successfully.", app.member.name, applicantID))
    end

    -- Trigger domain event
    if ns.EventBus then
        ns.EventBus:Trigger("LFG_LIST_APPLICANT_UPDATED", applicantID)
    end
    return true
end

function MockEngine:DeclineApplicant(applicantID)
    local app = mockApplicants[applicantID]
    if not app then return false end

    app.status = "declined"
    if ns.Logger then
        ns.Logger:Info("MOCK", format("Applicant '%s' (ID %d) DECLINED.", app.member.name, applicantID))
    end

    if ns.EventBus then
        ns.EventBus:Trigger("LFG_LIST_APPLICANT_UPDATED", applicantID)
    end
    return true
end

-------------------------------------------------------------------------------
-- Synthetic Applicant Queue Ingestion
-------------------------------------------------------------------------------
---Add a single candidate into the mock queue
---@param template table
---@return number applicantID
function MockEngine:AddMockApplicant(template)
    mockApplicantCounter = mockApplicantCounter + 1
    local applicantID = mockApplicantCounter

    local cand = {
        name                   = template.name or format("Player%d", applicantID),
        classFilename          = template.classFilename or "WARRIOR",
        specID                 = template.specID or 71,
        role                   = template.role or "DAMAGER",
        itemLevel              = template.itemLevel or 630,
        dungeonScore           = template.dungeonScore or 2500,
        bestRunLevel           = template.bestRunLevel or 15,
        bestRunFinishedSuccess = (template.bestRunFinishedSuccess ~= false),
        hasBL                  = ns.HasBloodlust(template.classFilename),
        hasCR                  = ns.HasCombatRes(template.classFilename),
    }

    mockApplicants[applicantID] = {
        applicantID = applicantID,
        status = "applied",
        member = cand,
    }
    tinsert(mockApplicantOrder, applicantID)

    return applicantID
end

---Ingest 5-10 synthetic applicants (fixtures + random) into the queue
function MockEngine:SimulateQueueIngestion()
    if not isEnabled then
        self:Enable()
    end

    -- Clear previous queue
    wipe(mockApplicants)
    wipe(mockApplicantOrder)

    if ns.Logger then
        ns.Logger:Info("SIM", "Ingesting 7 realistic synthetic applicants into queue...")
    end

    -- Ingest the core test fixtures in FIFO order:
    -- 1. High-score DPS missing BL (Valeera)
    self:AddMockApplicant(FIXTURE_ROGUE_NO_BL)
    -- 2. Undergeared Tank (Baine)
    self:AddMockApplicant(FIXTURE_UNDERGEARED_TANK)
    -- 3. Low-experience Healer (Anduin)
    self:AddMockApplicant(FIXTURE_LOW_EXP_HEALER)
    -- 4. Valid Mage with BL and timed +15 (Jaina)
    self:AddMockApplicant(FIXTURE_VALID_MAGE_BL)
    -- 5. Duplicate Spec Frost Mage (Khadgar)
    self:AddMockApplicant(FIXTURE_DUPLICATE_SPEC_MAGE)
    -- 6. Valid Tank with CR (Bolvar)
    self:AddMockApplicant(FIXTURE_VALID_TANK_CR)
    -- 7. Valid Healer with CR (Malfurion)
    self:AddMockApplicant(FIXTURE_VALID_HEALER_CR)

    -- Dispatch Blizzard applicant list updated event
    if ns.EventBus then
        ns.EventBus:Trigger("LFG_LIST_APPLICANT_LIST_UPDATED")
    end
end

---Simulate an invited candidate dropping/declining or leaving group
function MockEngine:SimulateLeaver()
    if not isEnabled then
        if ns.Logger then
            ns.Logger:Warn("SIM", "Enable mock mode first with '/malfg debug'.")
        end
        return
    end

    -- Find an applicant that was invited
    local targetID = nil
    for _, appID in ipairs(mockApplicantOrder) do
        local app = mockApplicants[appID]
        if app and app.status == "invited" then
            targetID = appID
            break
        end
    end

    if not targetID then
        if ns.Logger then
            ns.Logger:Warn("SIM", "No invited candidate found in mock state to drop.")
        end
        return
    end

    local app = mockApplicants[targetID]
    app.status = "declined"

    if ns.Logger then
        ns.Logger:Warn("SIM", format("Candidate '%s' declined / left group! Triggering slot & utility recovery...", app.member.name))
    end

    -- Notify Core of applicant update and roster update
    if ns.EventBus then
        ns.EventBus:Trigger("LFG_LIST_APPLICANT_UPDATED", targetID)
        ns.EventBus:Trigger("GROUP_ROSTER_UPDATE")
    end
end
