--[[
    MPlusAutoLFG - Matchmaking Assistant for Mythic+
    File: Core.lua
    Description: Finite State Machine (FSM), central Event Bus, roster management,
                 FIFO applicant orchestrator, leaver resilience, listing automation, and slash commands.
]]

local addonName, ns = ...

-- Local caching of high-frequency Lua built-ins
local pairs, ipairs, type, tonumber, tostring, select = pairs, ipairs, type, tonumber, tostring, select
local floor, max, min = math.floor, math.max, math.min
local format, wipe = string.format, table.wipe
local GetTime = GetTime

-------------------------------------------------------------------------------
-- Structured Logger
-------------------------------------------------------------------------------
local Logger = {}
ns.Logger = Logger

function Logger:Debug(category, msg, ...)
    if ns.IsDebugMode and ns.IsDebugMode() then
        local formatted = format(msg, ...)
        print(format("%s [%s] %s", ns.DEBUG_PREFIX, category or "INFO", formatted))
    end
end

function Logger:Info(category, msg, ...)
    local formatted = format(msg, ...)
    print(format("%s [%s] %s", ns.CHAT_PREFIX, category or "INFO", formatted))
end

function Logger:Warn(category, msg, ...)
    local formatted = format(msg, ...)
    print(format("|cffffcc00[MPlusAutoLFG WARN]|r [%s] %s", category or "WARN", formatted))
end

function Logger:Error(category, msg, ...)
    local formatted = format(msg, ...)
    print(format("|cffff2222[MPlusAutoLFG ERROR]|r [%s] %s", category or "ERROR", formatted))
end

-------------------------------------------------------------------------------
-- Central Event Bus
-------------------------------------------------------------------------------
local EventBus = {}
ns.EventBus = EventBus
local subscribers = {}

---Register a listener function for a domain event
---@param eventName string
---@param handler function
function EventBus:Register(eventName, handler)
    if type(handler) ~= "function" then return end
    subscribers[eventName] = subscribers[eventName] or {}
    table.insert(subscribers[eventName], handler)
end

---Trigger a domain event to all subscribers
---@param eventName string
---@param ... any
function EventBus:Trigger(eventName, ...)
    local list = subscribers[eventName]
    if list then
        for _, handler in ipairs(list) do
            local ok, err = pcall(handler, ...)
            if not ok then
                Logger:Error("EVENT", format("Error in handler for '%s': %s", eventName, tostring(err)))
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Addon Core & State Variables
-------------------------------------------------------------------------------
local Core = {}
ns.Core = Core

ns.CurrentState = ns.States.IDLE
local activeKeystone = {
    challengeMapID = 0,
    keystoneLevel = 0,
    dungeonName = "Unknown Dungeon",
    iconTexture = 525134,
    activityID = 0,
}

local pendingInvites = {} -- [applicantID] = candidate
local stopwatchStartTime = nil
local stopwatchElapsed = 0
local isStopwatchRunning = false
local currentTopCandidate = nil

-------------------------------------------------------------------------------
-- FSM State Manager
-------------------------------------------------------------------------------
---Transition addon FSM to a new state
---@param newState string
---@param reason string?
function Core:SetState(newState, reason)
    local oldState = ns.CurrentState
    if oldState == newState then return end

    ns.CurrentState = newState
    Logger:Debug("FSM", format("State Transition: %s -> %s (Reason: %s)", oldState, newState, reason or "None"))

    EventBus:Trigger("STATE_CHANGED", oldState, newState, reason)
    Core:UpdateUI()
end

---Retrieve current FSM state
---@return string
function Core:GetState()
    return ns.CurrentState
end

---Check if debug mode is active
---@return boolean
function ns.IsDebugMode()
    return (MPlusAutoLFGDB and MPlusAutoLFGDB.debug == true) or (ns.MockEngine and ns.MockEngine:IsEnabled())
end

-------------------------------------------------------------------------------
-- Stopwatch Lifecycle
-------------------------------------------------------------------------------
function Core:StartStopwatch()
    stopwatchStartTime = GetTime()
    stopwatchElapsed = 0
    isStopwatchRunning = true
end

function Core:StopStopwatch()
    if isStopwatchRunning and stopwatchStartTime then
        stopwatchElapsed = GetTime() - stopwatchStartTime
    end
    isStopwatchRunning = false
end

function Core:GetElapsedSeconds()
    if isStopwatchRunning and stopwatchStartTime then
        return GetTime() - stopwatchStartTime
    end
    return stopwatchElapsed
end

-------------------------------------------------------------------------------
-- Roster Context Builder & Slot Accounting
-------------------------------------------------------------------------------
---Scan real group members and merge with pending invited candidates
---@return table rosterContext
function Core:GetRosterContext()
    local members = {}
    local roles = { [ns.Roles.TANK] = 0, [ns.Roles.HEALER] = 0, [ns.Roles.DAMAGER] = 0 }
    local classes = {}
    local specs = {}
    local hasBL = false
    local hasCR = false

    -- 1. Scan Player
    local playerName = UnitName("player") or "Leader"
    local _, playerClass = UnitClass("player")
    playerClass = playerClass or "WARRIOR"

    local playerRole = UnitGroupRolesAssigned("player")
    if not playerRole or playerRole == "NONE" then
        -- Default to DAMAGER unless spec says otherwise
        playerRole = "DAMAGER"
    end

    table.insert(members, {
        name = playerName,
        class = playerClass,
        role = playerRole,
    })

    roles[playerRole] = (roles[playerRole] or 0) + 1
    classes[playerClass] = (classes[playerClass] or 0) + 1
    if ns.HasBloodlust(playerClass) then hasBL = true end
    if ns.HasCombatRes(playerClass) then hasCR = true end

    -- 2. Scan Party Members (party1 to party4)
    local numGroupMembers = GetNumGroupMembers()
    if numGroupMembers > 1 then
        for i = 1, numGroupMembers - 1 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local uName = UnitName(unit) or format("Member%d", i)
                local _, uClass = UnitClass(unit)
                uClass = uClass or "WARRIOR"
                local uRole = UnitGroupRolesAssigned(unit)
                if not uRole or uRole == "NONE" then
                    uRole = "DAMAGER"
                end

                table.insert(members, {
                    name = uName,
                    class = uClass,
                    role = uRole,
                })

                roles[uRole] = (roles[uRole] or 0) + 1
                classes[uClass] = (classes[uClass] or 0) + 1
                if ns.HasBloodlust(uClass) then hasBL = true end
                if ns.HasCombatRes(uClass) then hasCR = true end
            end
        end
    end

    -- 3. Merge Pending Invited Candidates (Reserved Slots)
    for _, pending in pairs(pendingInvites) do
        local pRole = pending.role or "DAMAGER"
        local pClass = pending.classFilename or "WARRIOR"
        local pSpec = pending.specID

        roles[pRole] = (roles[pRole] or 0) + 1
        classes[pClass] = (classes[pClass] or 0) + 1
        if pSpec and pSpec > 0 then
            specs[pSpec] = (specs[pSpec] or 0) + 1
        end

        if pending.hasBL then hasBL = true end
        if pending.hasCR then hasCR = true end
    end

    local totalCount = #members
    for _ in pairs(pendingInvites) do
        totalCount = totalCount + 1
    end

    local leaderIlvl = ns.LFGService:GetLeaderEquippedItemLevel()
    local targetKey = activeKeystone.keystoneLevel or 0
    local requiredIlvl = ns.LFGService:CalculateRequiredItemLevel(leaderIlvl, targetKey)

    return {
        members = members,
        roles = roles,
        classes = classes,
        specs = specs,
        hasBL = hasBL,
        hasCR = hasCR,
        totalCount = totalCount,
        leaderIlvl = leaderIlvl,
        targetKeyLevel = targetKey,
        requiredItemLevel = requiredIlvl,
        activityID = activeKeystone.activityID,
    }
end

-------------------------------------------------------------------------------
-- FIFO Applicant Evaluation & Matchmaking Engine
-------------------------------------------------------------------------------
---Strict FIFO candidate evaluation across the active applicant queue
function Core:EvaluateQueue()
    -- Guard: Only evaluate in active matchmaking states
    if ns.CurrentState == ns.States.IDLE or ns.CurrentState == ns.States.PAUSED or ns.CurrentState == ns.States.FULL then
        return
    end

    local rosterContext = self:GetRosterContext()
    local openSlots = ns.MAX_PARTY_SIZE - rosterContext.totalCount

    if openSlots <= 0 then
        -- Group is full or fully reserved
        self:SetState(ns.States.FULL, "Party full (5/5 slots filled/reserved)")
        ns.UI:ClearCandidateCard()
        return
    end

    local applicants = ns.LFGService:GetApplicants()
    if not applicants or #applicants == 0 then
        currentTopCandidate = nil
        ns.UI:ClearCandidateCard()
        return
    end

    local bestCandidate = nil

    -- Strict FIFO traversal (applicants array is pre-sorted ascending by applicantID)
    for _, applicantID in ipairs(applicants) do
        -- Skip candidates already invited and pending
        if not pendingInvites[applicantID] then
            local appInfo = ns.LFGService:GetApplicantInfo(applicantID)
            if appInfo and (appInfo.applicationStatus == "applied" or appInfo.applicationStatus == "none") then
                -- Single-member applicant evaluation
                local candidate = ns.LFGService:GetApplicantMemberInfo(applicantID, 1)
                if candidate then
                    -- Fetch real-time dungeon progress for active activity
                    local bestRunLevel, finishedSuccess, mapScore = ns.LFGService:GetApplicantDungeonScore(applicantID, 1, activeKeystone.activityID)
                    candidate.bestRunLevel = bestRunLevel
                    candidate.bestRunFinishedSuccess = finishedSuccess
                    if (not candidate.dungeonScore or candidate.dungeonScore == 0) and mapScore > 0 then
                        candidate.dungeonScore = mapScore
                    end

                    -- Run declarative pipeline validation
                    local isValid, rejectReason, validatorName = ns.ValidateCandidate(candidate, rosterContext)
                    if isValid then
                        bestCandidate = candidate
                        Logger:Debug("FIFO", format("Candidate '%s' (ID %d) passed all validation checks.", candidate.name, applicantID))
                        break -- FIFO: Select first qualifying candidate immediately!
                    else
                        Logger:Debug("REJECT", format("Applicant '%s' (ID %d) rejected by %s: %s", candidate.name, applicantID, validatorName or "Rule", rejectReason or "Failed"))
                    end
                end
            end
        end
    end

    currentTopCandidate = bestCandidate
    if bestCandidate then
        ns.UI:UpdateCandidateCard(bestCandidate)
        EventBus:Trigger("APPLICANT_QUALIFIED", bestCandidate)
    else
        ns.UI:ClearCandidateCard()
        EventBus:Trigger("QUEUE_EMPTY")
    end
end

-------------------------------------------------------------------------------
-- Candidate Invite & Leaver Resilience Handlers
-------------------------------------------------------------------------------
---Invoked when the player clicks "CLICK TO INVITE" on HUD
---@param candidate table
function ns.OnCandidateInvited(candidate)
    if not candidate or not candidate.applicantID then return end

    -- Reserve role and utility flags
    pendingInvites[candidate.applicantID] = candidate
    Logger:Info("QUEUE", format("Slot reserved for %s (%s). Awaiting player join...", candidate.name, candidate.role))

    Core:SetState(ns.States.ASSEMBLING, "Candidate invited")
    Core:UpdateUI()

    -- Re-evaluate queue for next open slot
    Core:EvaluateQueue()
end

---Handle applicant status changes (declined, timed out, accepted)
---@param applicantID number
function Core:OnApplicantUpdated(applicantID)
    if not applicantID then return end

    local appInfo = ns.LFGService:GetApplicantInfo(applicantID)
    local status = appInfo and appInfo.applicationStatus

    if pendingInvites[applicantID] then
        local pending = pendingInvites[applicantID]

        if status == "declined" or status == "timedout" or status == "cancelled" then
            -- Candidate declined or timed out: Immediately unlock reserved role and utility flags!
            pendingInvites[applicantID] = nil
            Logger:Warn("RESILIENCE", format("Invited candidate '%s' %s! Reserved %s slot & utility flags recovered.", pending.name, status, pending.role))
            
            EventBus:Trigger("ROSTER_SLOT_FREED", pending.role, pending.classFilename)
            Core:UpdateUI()
            Core:EvaluateQueue()
        elseif status == "inviteaccepted" then
            Logger:Info("RESILIENCE", format("Candidate '%s' accepted invitation!", pending.name))
        end
    end
end

---Handle group roster changes (members joining / leaving)
function Core:OnGroupRosterUpdated()
    local rosterContext = self:GetRosterContext()
    local memberCount = #rosterContext.members

    -- Check if any joined member matches a pending invite; if so, clear pending reservation
    for _, m in ipairs(rosterContext.members) do
        for appID, p in pairs(pendingInvites) do
            if m.name == p.name then
                pendingInvites[appID] = nil
                Logger:Debug("RESILIENCE", format("Pending candidate '%s' joined group roster.", m.name))
            end
        end
    end

    -- Full party reached: 5 members in group
    if memberCount >= ns.MAX_PARTY_SIZE then
        if ns.CurrentState ~= ns.States.FULL then
            self:SetState(ns.States.FULL, "Party reached 5/5 members")
            self:StopStopwatch()

            local elapsed = floor(self:GetElapsedSeconds())
            local mins = floor(elapsed / 60)
            local secs = elapsed % 60

            local names = {}
            for _, m in ipairs(rosterContext.members) do
                table.insert(names, format("%s (%s)", m.name, m.role))
            end

            Logger:Info("LIFECYCLE", format("Group fully assembled in %02d:%02d! Composition: %s", mins, secs, table.concat(names, ", ")))

            -- Automatically delist from Premade Groups
            if MPlusAutoLFGDB and MPlusAutoLFGDB.autoDelistOnFull then
                Logger:Info("LIFECYCLE", "Auto-delisting group from Premade Groups.")
                ns.LFGService:RemoveListing()
            end
        end
    elseif memberCount < ns.MAX_PARTY_SIZE and ns.CurrentState == ns.States.FULL then
        -- A member left a full group before dungeon started: Resume assembly!
        Logger:Warn("RESILIENCE", "Party member left full group! Returning to ASSEMBLING and resuming queue evaluation.")
        self:SetState(ns.States.ASSEMBLING, "Roster slot freed from leaver")
        self:EvaluateQueue()
    elseif ns.CurrentState == ns.States.LISTED and memberCount > 1 then
        self:SetState(ns.States.ASSEMBLING, "Group assembling")
    end

    Core:UpdateUI()
end

-------------------------------------------------------------------------------
-- Keystone & Listing Automation
-------------------------------------------------------------------------------
---Refresh active keystone details
function Core:RefreshKeystoneInfo()
    local cMapID, kLevel, dName, icon, actID = ns.LFGService:GetOwnedKeystoneInfo()
    activeKeystone.challengeMapID = cMapID
    activeKeystone.keystoneLevel = kLevel
    activeKeystone.dungeonName = dName
    activeKeystone.iconTexture = icon
    activeKeystone.activityID = actID
end

---Start automated matchmaking listing
function Core:StartMatchmaking()
    self:RefreshKeystoneInfo()

    if not activeKeystone.keystoneLevel or activeKeystone.keystoneLevel <= 0 then
        Logger:Warn("QUEUE", "No active Mythic Keystone found in inventory. Cannot create listing.")
        return
    end

    local leaderIlvl = ns.LFGService:GetLeaderEquippedItemLevel()
    local requiredIlvl = ns.LFGService:CalculateRequiredItemLevel(leaderIlvl, activeKeystone.keystoneLevel)
    local title = format(ns.DefaultConfig.listingTitleTemplate, activeKeystone.keystoneLevel)
    local desc = ns.DefaultConfig.listingDescTemplate

    Logger:Info("LISTING", format("Creating automated queue listing for %s +%d (Min ilvl: %d)...", activeKeystone.dungeonName, activeKeystone.keystoneLevel, requiredIlvl))

    local success = ns.LFGService:CreateListing(activeKeystone.activityID, requiredIlvl, title, desc)
    if success then
        self:StartStopwatch()
        local rosterContext = self:GetRosterContext()
        local nextState = (rosterContext.totalCount > 1) and ns.States.ASSEMBLING or ns.States.LISTED
        self:SetState(nextState, "Listing created")
        self:EvaluateQueue()
        ns.UI:Show()
    else
        Logger:Warn("LISTING", "Listing creation failed or requires manual click in Blizzard Group Finder.")
    end
end

---Pause or resume automated queue evaluation
function ns.TogglePause()
    if ns.CurrentState == ns.States.PAUSED then
        Core:SetState(ns.States.LISTED, "User resumed matchmaking")
        Logger:Info("QUEUE", "Queue matchmaking RESUMED.")
        Core:EvaluateQueue()
    else
        Core:SetState(ns.States.PAUSED, "User paused matchmaking")
        Logger:Info("QUEUE", "Queue matchmaking PAUSED.")
        ns.UI:ClearCandidateCard()
    end
end

-------------------------------------------------------------------------------
-- UI Synchronization
-------------------------------------------------------------------------------
function Core:UpdateUI()
    if not ns.UI then return end

    local rosterContext = self:GetRosterContext()
    local elapsed = self:GetElapsedSeconds()

    ns.UI:UpdateHeader(
        activeKeystone.challengeMapID,
        activeKeystone.keystoneLevel,
        activeKeystone.dungeonName,
        activeKeystone.iconTexture,
        ns.CurrentState,
        elapsed
    )

    ns.UI:UpdateRoster(rosterContext, pendingInvites)
end

-------------------------------------------------------------------------------
-- Event Orchestration Frame
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
eventFrame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_SLOTTED")

-- Periodic stopwatch and queue refresh ticker (every 1.0s)
local lastTick = 0
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    lastTick = lastTick + elapsed
    if lastTick >= 1.0 then
        lastTick = 0
        if isStopwatchRunning then
            Core:UpdateUI()
        end
    end
end)

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName or loadedName == "MPlusAutoLFG" or loadedName == "MPlus Auto LFG" then
            -- Initialize SavedVariables
            if not MPlusAutoLFGDB then
                MPlusAutoLFGDB = CopyTable(ns.DefaultConfig)
            end
            for k, v in pairs(ns.DefaultConfig) do
                if MPlusAutoLFGDB[k] == nil then
                    MPlusAutoLFGDB[k] = v
                end
            end
        end
    elseif event == "PLAYER_LOGIN" then
        ns.UI:Initialize()
        Core:RefreshKeystoneInfo()
        Core:UpdateUI()

        Logger:Info("CORE", format("v%s loaded. Type |cff00ff00/malfg|r to open HUD, |cff00ff00/malfg debug|r for dev mode.", ns.VERSION))
    elseif event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
        Core:EvaluateQueue()
        Core:UpdateUI()
    elseif event == "LFG_LIST_APPLICANT_UPDATED" then
        local applicantID = ...
        Core:OnApplicantUpdated(applicantID)
    elseif event == "GROUP_ROSTER_UPDATE" then
        Core:OnGroupRosterUpdated()
    elseif event == "CHALLENGE_MODE_KEYSTONE_SLOTTED" then
        Core:RefreshKeystoneInfo()
        Core:UpdateUI()
    end
end)

-- Wire internal EventBus triggers to Core handlers
EventBus:Register("LFG_LIST_APPLICANT_LIST_UPDATED", function()
    Core:EvaluateQueue()
    Core:UpdateUI()
end)

EventBus:Register("LFG_LIST_APPLICANT_UPDATED", function(applicantID)
    Core:OnApplicantUpdated(applicantID)
end)

EventBus:Register("GROUP_ROSTER_UPDATE", function()
    Core:OnGroupRosterUpdated()
end)

-------------------------------------------------------------------------------
-- Slash Commands & Dev Controls
-------------------------------------------------------------------------------
SLASH_MPLUSAUTOLFG1 = "/malfg"
SlashCmdList["MPLUSAUTOLFG"] = function(msg)
    msg = msg and string.lower(strtrim(msg)) or ""
    local cmd, arg = strsplit(" ", msg, 2)

    if cmd == "" then
        -- Toggle main HUD
        ns.UI:Toggle()
    elseif cmd == "debug" then
        if MPlusAutoLFGDB then
            MPlusAutoLFGDB.debug = not MPlusAutoLFGDB.debug
            if MPlusAutoLFGDB.debug then
                ns.MockEngine:Enable()
                Logger:Info("DEBUG", "|cff00ff00ENABLED|r. Offline testing and fixtures active.")
            else
                ns.MockEngine:Disable()
                Logger:Info("DEBUG", "|cffff4444DISABLED|r. Returned to live server mode.")
            end
        end
    elseif cmd == "sim" then
        if arg == "leaver" then
            -- Simulate invited candidate leaving
            ns.MockEngine:SimulateLeaver()
        else
            -- Simulate 5-10 synthetic applicants
            ns.MockEngine:SimulateQueueIngestion()
            Core:SetState(ns.States.LISTED, "Simulated queue populated")
            ns.UI:Show()
            Core:EvaluateQueue()
            Core:UpdateUI()
        end
    elseif cmd == "start" then
        Core:StartMatchmaking()
    elseif cmd == "pause" then
        ns.TogglePause()
    elseif cmd == "reset" then
        ns.MockEngine:Reset()
        wipe(pendingInvites)
        Core:StopStopwatch()
        Core:SetState(ns.States.IDLE, "Reset command issued")
        if MPlusAutoLFGDB then
            MPlusAutoLFGDB.framePosition = CopyTable(ns.DefaultConfig.framePosition)
        end
        ns.UI:ClearCandidateCard()
        Core:UpdateUI()
        Logger:Info("CORE", "Addon state, mock queue, and positions reset.")
    else
        Logger:Info("HELP", "Commands:")
        print("  |cff00ff00/malfg|r - Toggle main HUD")
        print("  |cff00ff00/malfg start|r - Start automated matchmaking queue")
        print("  |cff00ff00/malfg pause|r - Pause / resume queue")
        print("  |cff00ff00/malfg debug|r - Toggle Debug / Mock mode")
        print("  |cff00ff00/malfg sim|r - Ingest synthetic applicants into queue")
        print("  |cff00ff00/malfg sim leaver|r - Simulate candidate decline / leave")
        print("  |cff00ff00/malfg reset|r - Wipe mock queue and reset frames")
    end
end
