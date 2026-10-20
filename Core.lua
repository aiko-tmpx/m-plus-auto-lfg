--[[
    MPlusAutoLFG - Matchmaking Assistant for Mythic+
    File: Core.lua
    Description: Finite State Machine (FSM), central Event Bus, roster management,
                 applicant orchestrator, leaver resilience, listing automation, and slash commands.
]]

local addonName, ns = ...

-- Guard against multiple addon instances loading simultaneously (e.g. dual directory/junction loading)
if _G["MPlusAutoLFG_CoreLoaded"] then
    return
end
_G["MPlusAutoLFG_CoreLoaded"] = true

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
local lastMemberCount = 1

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
    return MPlusAutoLFGDB and MPlusAutoLFGDB.debug == true
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
-- Applicant Evaluation & Matchmaking Engine
-------------------------------------------------------------------------------
---Candidate evaluation across the active applicant queue
function Core:EvaluateQueue()
    -- Guard: Only evaluate in active matchmaking states
    if ns.CurrentState == ns.States.IDLE or ns.CurrentState == ns.States.FULL then
        return
    end

    -- Guard: Only party leader can evaluate and invite
    if not self:IsLeader() then
        return
    end

    -- Guard: Keystone mismatch halts automated candidate display
    if self.isKeystoneMismatch then
        return
    end

    -- Guard: If an invitation is currently pending, keep card locked on the invited candidate
    if next(pendingInvites) then
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

    -- Queue order traversal (applicants array is pre-sorted ascending by applicantID)
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

                    Logger:Debug("QUEUE", format("Evaluating applicant '%s' (%s %s, ilvl %d, M+ Score %d, best run +%d%s)...",
                        candidate.name, candidate.role, candidate.localizedClass or candidate.classFilename,
                        candidate.itemLevel or 0, candidate.dungeonScore or 0, candidate.bestRunLevel or 0,
                        candidate.bestRunFinishedSuccess and " Timed" or " Overtime"))

                    -- Run declarative pipeline validation
                    local isValid, rejectReason, validatorName = ns.ValidateCandidate(candidate, rosterContext)
                    if isValid then
                        bestCandidate = candidate
                        Logger:Debug("QUEUE", format("Candidate '%s' (ID %d) passed all validation checks.", candidate.name, applicantID))
                        break -- Select first qualifying candidate immediately
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
    -- Card remains locked on the invited candidate showing "INVITED" until resolved
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
            
            ns.UI:ClearCandidateCard()
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
                if ns.UI then
                    ns.UI:ClearCandidateCard()
                end
            end
        end
    end

    -- Member leaver detection & state adaptation
    if lastMemberCount and memberCount < lastMemberCount then
        Logger:Warn("RESILIENCE", format("Group roster decreased from %d to %d members! Re-evaluating requirements and queue...", lastMemberCount, memberCount))
        if ns.CurrentState == ns.States.FULL then
            self:SetState(ns.States.ASSEMBLING, "Roster slot freed from leaver")
        elseif memberCount == 1 and not next(pendingInvites) then
            if ns.CurrentState == ns.States.ASSEMBLING then
                self:SetState(ns.States.LISTED, "Roster reduced to solo leader")
            end
        end
    end
    lastMemberCount = memberCount

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
        end
    elseif ns.CurrentState == ns.States.LISTED and memberCount > 1 then
        self:SetState(ns.States.ASSEMBLING, "Group assembling")
    end

    -- Immediately refresh UI for updated utilities (BL/CR) and open slot counts
    Core:UpdateUI()

    -- Automatically re-evaluate queue whenever in active matchmaking and not full
    if memberCount < ns.MAX_PARTY_SIZE and (ns.CurrentState == ns.States.LISTED or ns.CurrentState == ns.States.ASSEMBLING) then
        self:EvaluateQueue()
    end
end

-------------------------------------------------------------------------------
-- Keystone & Listing Automation
-------------------------------------------------------------------------------
---Check if local player is the party leader
---@return boolean
function Core:IsLeader()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") == true
end

---Refresh active keystone details and sync with active Premade Groups listing
function Core:RefreshKeystoneInfo()
    local bagMapID, bagKeyLevel, bagDungeonName, bagIcon, bagActID = ns.LFGService:GetOwnedKeystoneInfo()
    local hasListing, listMapID, listKeyLevel, listDungeonName, listIcon, listReqIlvl, listActID = ns.LFGService:GetActiveListingDetails()

    if hasListing then
        activeKeystone.challengeMapID = listMapID > 0 and listMapID or bagMapID
        activeKeystone.keystoneLevel = listKeyLevel > 0 and listKeyLevel or bagKeyLevel
        activeKeystone.dungeonName = (listDungeonName and listDungeonName ~= "" and listDungeonName ~= "Unknown Dungeon") and listDungeonName or bagDungeonName
        activeKeystone.iconTexture = listIcon or bagIcon
        activeKeystone.activityID = listActID > 0 and listActID or bagActID
        activeKeystone.requiredItemLevel = listReqIlvl

        -- Check keystone mismatch (listed key differs from bag key)
        if bagKeyLevel > 0 and listKeyLevel > 0 and bagKeyLevel ~= listKeyLevel then
            self.isKeystoneMismatch = true
            self.mismatchReason = format("Listed key (+%d) != Bag key (+%d)", listKeyLevel, bagKeyLevel)
        elseif bagMapID > 0 and listMapID > 0 and bagMapID ~= listMapID then
            self.isKeystoneMismatch = true
            self.mismatchReason = format("Listed dungeon != Bag dungeon")
        else
            self.isKeystoneMismatch = false
            self.mismatchReason = nil
        end

        -- Auto-attach if idle
        if ns.CurrentState == ns.States.IDLE then
            self:StartStopwatch()
            local rosterContext = self:GetRosterContext()
            local nextState = (rosterContext.totalCount > 1) and ns.States.ASSEMBLING or ns.States.LISTED
            self:SetState(nextState, "Attached to active Premade Groups listing")
            self:EvaluateQueue()
        end
    else
        activeKeystone.challengeMapID = bagMapID
        activeKeystone.keystoneLevel = bagKeyLevel
        activeKeystone.dungeonName = bagDungeonName
        activeKeystone.iconTexture = bagIcon
        activeKeystone.activityID = bagActID
        self.isKeystoneMismatch = false
        self.mismatchReason = nil
    end
end

---Start automated matchmaking listing
function Core:StartMatchmaking()
    if not self:IsLeader() then
        Logger:Warn("ROSTER", "Only the party leader can start matchmaking.")
        return
    end

    self:RefreshKeystoneInfo()

    if self.isKeystoneMismatch then
        Logger:Warn("LISTING", format("Cannot start matchmaking: %s.", self.mismatchReason or "Keystone mismatch"))
        return
    end

    -- 1. If group is already listed in Premade Groups, attach immediately
    if ns.LFGService:HasActiveListing() then
        self:StartStopwatch()
        local rosterContext = self:GetRosterContext()
        local nextState = (rosterContext.totalCount > 1) and ns.States.ASSEMBLING or ns.States.LISTED
        self:SetState(nextState, "Attached to active Premade Groups listing")
        self:EvaluateQueue()
        self:UpdateUI()
        local dName = (activeKeystone.dungeonName and activeKeystone.dungeonName ~= "Unknown Dungeon") and activeKeystone.dungeonName or "Dungeon"
        local kLvl = (activeKeystone.keystoneLevel and activeKeystone.keystoneLevel > 0) and ("+" .. activeKeystone.keystoneLevel) or ""
        Logger:Info("QUEUE", format("Connected to active Premade Groups listing for %s %s. Monitoring applicants (Debug: %s)...", dName, kLvl, ns.IsDebugMode() and "|cff00ff00ON|r" or "OFF"))
        return
    end

    -- 2. Not yet listed: Open Blizzard's Premade Groups frame cleanly
    ns.LFGService:OpenGroupFinder()

    local leaderIlvl = ns.LFGService:GetLeaderEquippedItemLevel()
    local keyLvl = activeKeystone.keystoneLevel or 0
    local requiredIlvl = ns.LFGService:CalculateRequiredItemLevel(leaderIlvl, keyLvl)

    if keyLvl > 0 then
        Logger:Info("LISTING", format("Opened Premade Groups for %s +%d (Recommended min ilvl: %d). Select Title, Playstyle, Difficulty and click 'List Group' to activate auto-matchmaking.", activeKeystone.dungeonName, keyLvl, requiredIlvl))
    else
        Logger:Info("LISTING", format("Opened Premade Groups (Leader ilvl: %d). Select your activity, title, playstyle, and difficulty, then click 'List Group' to activate auto-matchmaking.", leaderIlvl))
    end
end

---Stop active matchmaking listing and reset queue state
function Core:StopMatchmaking()
    self:StopStopwatch()
    wipe(pendingInvites)
    self:SetState(ns.States.IDLE, "Matchmaking stopped by user")
    ns.UI:ClearCandidateCard()
    self:UpdateUI()
    ns.LFGService:OpenGroupFinder()
    Logger:Info("LISTING", "Matchmaking stopped. Opened Premade Groups to delist if desired.")
end

---Handle Blizzard LFG_LIST_ACTIVE_ENTRY_UPDATE
function Core:OnActiveEntryUpdated()
    if ns.LFGService:HasActiveListing() then
        if ns.CurrentState == ns.States.IDLE then
            self:StartStopwatch()
            local rosterContext = self:GetRosterContext()
            local nextState = (rosterContext.totalCount > 1) and ns.States.ASSEMBLING or ns.States.LISTED
            self:SetState(nextState, "Active Premade Group listing detected")
            Logger:Info("QUEUE", format("Active Premade Group listing detected! Matchmaking active (Debug: %s).", ns.IsDebugMode() and "|cff00ff00ON|r" or "OFF"))
            self:EvaluateQueue()
            self:UpdateUI()
        end
    else
        if ns.CurrentState == ns.States.LISTED or ns.CurrentState == ns.States.ASSEMBLING then
            self:SetState(ns.States.IDLE, "Premade Group listing was removed")
            self:StopStopwatch()
            wipe(pendingInvites)
            ns.UI:ClearCandidateCard()
            self:UpdateUI()
            Logger:Info("QUEUE", "Premade Group listing delisted.")
        end
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
        elapsed,
        rosterContext.requiredItemLevel
    )

    ns.UI:UpdateUtilityStatus(rosterContext)
end

-------------------------------------------------------------------------------
-- Event Orchestration Frame
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
eventFrame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED")
eventFrame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
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
        if loadedName == addonName or loadedName == "MPlusAutoLFG" then
            -- Initialize SavedVariables
            if not MPlusAutoLFGDB then
                MPlusAutoLFGDB = CopyTable(ns.DefaultConfig)
            end
            for k, v in pairs(ns.DefaultConfig) do
                if MPlusAutoLFGDB[k] == nil then
                    MPlusAutoLFGDB[k] = v
                end
            end
            if ns.InitializeSettings then
                ns.InitializeSettings()
            end
        elseif loadedName == "Blizzard_LFGList" or loadedName == "Blizzard_GroupFinder" or loadedName == "Blizzard_PVEFrame" then
            if ns.LFGService and ns.LFGService.HookEntryCreation then
                ns.LFGService:HookEntryCreation()
            end
            if ns.UI and ns.UI.CreateLFGTopButton then
                ns.UI:CreateLFGTopButton()
            end
        end
    elseif event == "PLAYER_LOGIN" then
        if ns.InitializeSettings then
            ns.InitializeSettings()
        end
        ns.UI:Initialize()
        Core:RefreshKeystoneInfo()
        Core:UpdateUI()

        if ns.LFGService and ns.LFGService.HookEntryCreation then
            ns.LFGService:HookEntryCreation()
        end

        local debugStatus = (MPlusAutoLFGDB and MPlusAutoLFGDB.debug) and "|cff00ff00ON|r" or "OFF"
        Logger:Info("CORE", format("v%s loaded. Type |cff00ff00/malfg|r to open HUD, |cff00ff00/malfg config|r for options.", ns.VERSION))
    elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        Core:OnActiveEntryUpdated()
    elseif event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
        Core:EvaluateQueue()
        Core:UpdateUI()
    elseif event == "LFG_LIST_APPLICANT_UPDATED" then
        local applicantID = ...
        Core:OnApplicantUpdated(applicantID)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not Core:IsLeader() then
            if ns.CurrentState == ns.States.LISTED or ns.CurrentState == ns.States.ASSEMBLING then
                Core:StopMatchmaking()
                Logger:Warn("ROSTER", "Lost party leadership. Matchmaking stopped.")
            end
        end
        Core:OnGroupRosterUpdated()
    elseif event == "PARTY_LEADER_CHANGED" then
        if not Core:IsLeader() then
            if ns.CurrentState == ns.States.LISTED or ns.CurrentState == ns.States.ASSEMBLING then
                Core:StopMatchmaking()
                Logger:Warn("ROSTER", "Lost party leadership. Matchmaking stopped.")
            end
        end
        Core:UpdateUI()
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
    elseif cmd == "config" or cmd == "options" or cmd == "opt" then
        if ns.OpenOptions then
            ns.OpenOptions()
        end
    elseif cmd == "mode" then
        if MPlusAutoLFGDB then
            MPlusAutoLFGDB.rulesMode = (MPlusAutoLFGDB.rulesMode == "CUSTOM") and "DEFAULT" or "CUSTOM"
            Logger:Info("RULES", format("Rules mode switched to: |cffffffff%s|r", MPlusAutoLFGDB.rulesMode))
            if ns.UI and ns.UI.UpdateModeButton then ns.UI:UpdateModeButton() end
            Core:EvaluateQueue()
            Core:UpdateUI()
        end
    elseif cmd == "debug" then
        if MPlusAutoLFGDB then
            MPlusAutoLFGDB.debug = not MPlusAutoLFGDB.debug
            if MPlusAutoLFGDB.debug then
                Logger:Info("DEBUG", "|cff00ff00ENABLED|r. Real-time applicant validation logs will be printed to chat.")
            else
                Logger:Info("DEBUG", "|cffff4444DISABLED|r. Verbose applicant evaluation logs silenced.")
            end
        end
    elseif cmd == "start" then
        Core:StartMatchmaking()
    elseif cmd == "reset" then
        wipe(pendingInvites)
        Core:StopStopwatch()
        Core:RefreshKeystoneInfo()
        Core:SetState(ns.States.IDLE, "Reset command issued")
        if MPlusAutoLFGDB then
            MPlusAutoLFGDB.framePosition = CopyTable(ns.DefaultConfig.framePosition)
        end
        ns.UI:ClearCandidateCard()
        Core:UpdateUI()
        Logger:Info("CORE", "Addon state, invites, and positions reset.")
    else
        Logger:Info("HELP", "Commands:")
        print("  |cff00ff00/malfg|r - Toggle main HUD")
        print("  |cff00ff00/malfg config|r - Open AddOn Settings menu")
        print("  |cff00ff00/malfg mode|r - Toggle Rules Mode (Default vs Custom)")
        print("  |cff00ff00/malfg start|r - Start automated matchmaking queue")
        print("  |cff00ff00/malfg debug|r - Toggle verbose candidate evaluation logs")
        print("  |cff00ff00/malfg reset|r - Reset queue state, pending invites, and HUD position")
    end
end

