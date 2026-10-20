--[[
    MPlusAutoLFG - Matchmaking Assistant for Mythic+
    File: UI.lua
    Description: 100% Native WoW UI implementation. Floating HUD, party status badges,
                 candidate showcase card, SecureActionButtonTemplate invite button, and native minimap button.
]]

local addonName, ns = ...

-- Local caching of high-frequency Lua built-ins
local pairs, ipairs, type, tonumber, tostring = pairs, ipairs, type, tonumber, tostring
local floor, max, min, sin, cos, rad, deg, atan2 = math.floor, math.max, math.min, math.sin, math.cos, math.rad, math.deg, math.atan2
local format = string.format

-------------------------------------------------------------------------------
-- UI Module Declaration
-------------------------------------------------------------------------------
local UI = {}
ns.UI = UI

local mainFrame = nil
local minimapButton = nil
local currentCandidate = nil

-------------------------------------------------------------------------------
-- Native Backdrop Helper (Retail BackdropTemplate Safe)
-------------------------------------------------------------------------------
local TOOLTIP_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

local CARD_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

-------------------------------------------------------------------------------
-- Main Floating HUD Frame Creation
-------------------------------------------------------------------------------
function UI:CreateMainHUD()
    if mainFrame then return mainFrame end

    local f = CreateFrame("Frame", "MPlusAutoLFGMainFrame", UIParent, "BackdropTemplate")
    mainFrame = f
    f:SetSize(360, 340)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    -- Set position from SavedVariables or default
    local pos = (MPlusAutoLFGDB and MPlusAutoLFGDB.framePosition) or ns.DefaultConfig.framePosition
    f:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 100)

    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if MPlusAutoLFGDB then
            MPlusAutoLFGDB.framePosition = { point = point, relativePoint = relPoint, x = floor(x), y = floor(y) }
        end
    end)

    -- Native Backdrop Styling
    f:SetBackdrop(TOOLTIP_BACKDROP)
    f:SetBackdropColor(0.06, 0.08, 0.12, 0.94)
    f:SetBackdropBorderColor(0.35, 0.40, 0.50, 0.8)

    ---------------------------------------------------------------------------
    -- Top Title / Drag Bar
    ---------------------------------------------------------------------------
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    titleBar:SetHeight(26)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 6, 0)
    titleText:SetText("|cff00b4ffMPlusAutoLFG|r")

    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 4, 0)
    closeBtn:SetSize(24, 24)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    ---------------------------------------------------------------------------
    -- Keystone Info & Stopwatch Header
    ---------------------------------------------------------------------------
    local headerFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    headerFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 4, -4)
    headerFrame:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -4, -4)
    headerFrame:SetHeight(54)
    headerFrame:SetBackdrop(CARD_BACKDROP)
    headerFrame:SetBackdropColor(0.04, 0.05, 0.07, 0.8)
    headerFrame:SetBackdropBorderColor(0.2, 0.25, 0.35, 0.6)
    f.headerFrame = headerFrame

    -- Keystone Icon
    local keyIcon = headerFrame:CreateTexture(nil, "ARTWORK")
    keyIcon:SetSize(38, 38)
    keyIcon:SetPoint("LEFT", headerFrame, "LEFT", 8, 0)
    keyIcon:SetTexture(525134) -- Default keystone icon
    f.keyIcon = keyIcon

    -- Dungeon Title & Key Level
    local dungeonText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dungeonText:SetPoint("TOPLEFT", keyIcon, "TOPRIGHT", 10, -2)
    dungeonText:SetText("No Keystone Detected")
    f.dungeonText = dungeonText

    -- Status Badge / FSM State
    local statusText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", keyIcon, "BOTTOMRIGHT", 10, 4)
    statusText:SetText("|cff888888State: IDLE|r")
    f.statusText = statusText

    -- Elapsed Stopwatch Timer
    local timerText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timerText:SetPoint("RIGHT", headerFrame, "RIGHT", -12, 0)
    timerText:SetText("00:00")
    timerText:SetTextColor(0.9, 0.9, 0.9, 1)
    f.timerText = timerText

    ---------------------------------------------------------------------------
    -- Party Status & Utility Badges
    ---------------------------------------------------------------------------
    local rosterFrame = CreateFrame("Frame", nil, f)
    rosterFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -8)
    rosterFrame:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -8)
    rosterFrame:SetHeight(52)
    f.rosterFrame = rosterFrame

    -- 5 Role Badges: Tank, Healer, DPS1, DPS2, DPS3
    f.roleBadges = {}
    local badgeLabels = { "T", "H", "DPS", "DPS", "DPS" }
    local badgeRoles = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }
    local badgeWidth = 48
    local badgeSpacing = 6

    for i = 1, 5 do
        local badge = CreateFrame("Frame", nil, rosterFrame, "BackdropTemplate")
        badge:SetSize(badgeWidth, 34)
        badge:SetPoint("TOPLEFT", rosterFrame, "TOPLEFT", 6 + (i - 1) * (badgeWidth + badgeSpacing), 0)
        badge:SetBackdrop(CARD_BACKDROP)
        badge:SetBackdropColor(0.1, 0.12, 0.15, 0.9)
        badge:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

        local roleLbl = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        roleLbl:SetPoint("TOP", badge, "TOP", 0, -4)
        roleLbl:SetText(badgeLabels[i])

        local nameLbl = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLbl:SetPoint("BOTTOM", badge, "BOTTOM", 0, 4)
        nameLbl:SetText("Empty")
        nameLbl:SetWidth(44)
        nameLbl:SetWordWrap(false)

        badge.roleLbl = roleLbl
        badge.nameLbl = nameLbl
        badge.expectedRole = badgeRoles[i]
        f.roleBadges[i] = badge
    end

    -- Utility Badges: BL & CR indicators
    local utilFrame = CreateFrame("Frame", nil, rosterFrame)
    utilFrame:SetPoint("TOPLEFT", rosterFrame, "BOTTOMLEFT", 6, 2)
    utilFrame:SetPoint("TOPRIGHT", rosterFrame, "BOTTOMRIGHT", -6, 2)
    utilFrame:SetHeight(18)

    local blStatus = utilFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    blStatus:SetPoint("LEFT", utilFrame, "LEFT", 10, 0)
    blStatus:SetText("BL: |cffff4444[NEED]|r")
    f.blStatus = blStatus

    local crStatus = utilFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    crStatus:SetPoint("RIGHT", utilFrame, "RIGHT", -10, 0)
    crStatus:SetText("CR: |cffff4444[NEED]|r")
    f.crStatus = crStatus

    ---------------------------------------------------------------------------
    -- Candidate Showcase Card
    ---------------------------------------------------------------------------
    local card = CreateFrame("Frame", nil, f, "BackdropTemplate")
    card:SetPoint("TOPLEFT", rosterFrame, "BOTTOMLEFT", 4, -20)
    card:SetPoint("TOPRIGHT", rosterFrame, "BOTTOMRIGHT", -4, -20)
    card:SetHeight(82)
    card:SetBackdrop(CARD_BACKDROP)
    card:SetBackdropColor(0.04, 0.05, 0.07, 0.85)
    card:SetBackdropBorderColor(0.25, 0.3, 0.4, 0.7)
    f.candidateCard = card

    local cardHeader = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cardHeader:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -6)
    cardHeader:SetText("NEXT QUALIFIED FIFO APPLICANT")

    local candName = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    candName:SetPoint("TOPLEFT", cardHeader, "BOTTOMLEFT", 0, -4)
    candName:SetText("|cff888888Queue is empty|r")
    f.candName = candName

    local candSpec = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    candSpec:SetPoint("LEFT", candName, "RIGHT", 8, 0)
    candSpec:SetText("")
    f.candSpec = candSpec

    local candMetrics = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candMetrics:SetPoint("TOPLEFT", candName, "BOTTOMLEFT", 0, -4)
    candMetrics:SetText("Waiting for matching applicants to enter queue...")
    f.candMetrics = candMetrics

    local candExp = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candExp:SetPoint("TOPLEFT", candMetrics, "BOTTOMLEFT", 0, -3)
    candExp:SetText("")
    f.candExp = candExp

    ---------------------------------------------------------------------------
    -- Action Element: SecureActionButtonTemplate "CLICK TO INVITE" Button
    ---------------------------------------------------------------------------
    -- Must inherit SecureActionButtonTemplate to comply with Blizzard hardware event requirements
    local inviteBtn = CreateFrame("Button", "MPlusAutoLFGInviteButton", f, "SecureActionButtonTemplate, BackdropTemplate")
    f.inviteBtn = inviteBtn
    inviteBtn:SetSize(260, 36)
    inviteBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    inviteBtn:SetBackdrop(CARD_BACKDROP)
    inviteBtn:SetBackdropColor(0.12, 0.14, 0.18, 0.95)
    inviteBtn:SetBackdropBorderColor(0.4, 0.45, 0.55, 0.9)

    -- Mouse-click only (no spacebar/keybind overrides)
    inviteBtn:RegisterForClicks("LeftButtonUp")

    local btnText = inviteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
    btnText:SetPoint("CENTER", inviteBtn, "CENTER", 0, 0)
    btnText:SetText("AWAITING CANDIDATE")
    inviteBtn.btnText = btnText

    inviteBtn:SetScript("OnClick", function(self)
        if currentCandidate and currentCandidate.applicantID then
            UI:OnInviteClicked(currentCandidate)
        end
    end)

    f:Hide()
    return f
end

-------------------------------------------------------------------------------
-- UI State & Presentation Updaters
-------------------------------------------------------------------------------
---Handle click on the Invite Button
---@param candidate table
function UI:OnInviteClicked(candidate)
    if not candidate or not candidate.applicantID then return end

    if ns.Logger then
        ns.Logger:Info("INVITE", format("Dispatching automated invite to candidate '%s' (ID %d)...", candidate.name, candidate.applicantID))
    end

    local success = ns.LFGService:InviteApplicant(candidate.applicantID)
    if success then
        -- Notify core that candidate was invited
        if ns.OnCandidateInvited then
            ns.OnCandidateInvited(candidate)
        end
        UI:ClearCandidateCard()
    else
        if ns.Logger then
            ns.Logger:Warn("INVITE", format("Could not invite applicant %d (protected hardware event required).", candidate.applicantID))
        end
    end
end

---Update keystone header information, state badge, and stopwatch
---@param challengeMapID number
---@param keyLevel number
---@param dungeonName string
---@param iconTexture number|string
---@param state string
---@param elapsedSeconds number
function UI:UpdateHeader(challengeMapID, keyLevel, dungeonName, iconTexture, state, elapsedSeconds)
    if not mainFrame then self:CreateMainHUD() end

    if dungeonName and dungeonName ~= "" then
        mainFrame.dungeonText:SetText(format("%s +%d", dungeonName, keyLevel or 0))
    else
        mainFrame.dungeonText:SetText("No Keystone")
    end

    if iconTexture then
        mainFrame.keyIcon:SetTexture(iconTexture)
    end

    -- Format stopwatch
    elapsedSeconds = floor(elapsedSeconds or 0)
    local mins = floor(elapsedSeconds / 60)
    local secs = elapsedSeconds % 60
    mainFrame.timerText:SetText(format("%02d:%02d", mins, secs))

    -- Format state badge
    local stateColor = "|cff888888"
    if state == ns.States.LISTED then
        stateColor = "|cff00ff00"
    elseif state == ns.States.ASSEMBLING then
        stateColor = "|cffffff00"
    elseif state == ns.States.FULL then
        stateColor = "|cff00b4ff"
    elseif state == ns.States.PAUSED then
        stateColor = "|cffff8800"
    end
    mainFrame.statusText:SetText(format("State: %s[%s]|r", stateColor, state or "IDLE"))
end

---Update Party Status Badges and Utility Status
---@param rosterContext table
---@param pendingInvites table
function UI:UpdateRoster(rosterContext, pendingInvites)
    if not mainFrame then self:CreateMainHUD() end

    local members = rosterContext.members or {}
    local pending = pendingInvites or {}

    -- Group roles: 1 Tank, 1 Healer, 3 DPS
    -- Fill badges sequentially matching role types
    local tanks = {}
    local healers = {}
    local dps = {}

    -- Collect joined members
    for _, m in ipairs(members) do
        if m.role == "TANK" then
            tinsert(tanks, { name = m.name, class = m.class, state = "FILLED" })
        elseif m.role == "HEALER" then
            tinsert(healers, { name = m.name, class = m.class, state = "FILLED" })
        else
            tinsert(dps, { name = m.name, class = m.class, state = "FILLED" })
        end
    end

    -- Collect pending invited candidates
    for _, p in pairs(pending) do
        if p.role == "TANK" then
            tinsert(tanks, { name = p.name, class = p.classFilename, state = "PENDING" })
        elseif p.role == "HEALER" then
            tinsert(healers, { name = p.name, class = p.classFilename, state = "PENDING" })
        else
            tinsert(dps, { name = p.name, class = p.classFilename, state = "PENDING" })
        end
    end

    -- Map to the 5 role badges
    local slots = {
        tanks[1],
        healers[1],
        dps[1],
        dps[2],
        dps[3],
    }

    for i = 1, 5 do
        local badge = mainFrame.roleBadges[i]
        local slotData = slots[i]

        if slotData then
            local r, g, b = ns.GetClassColor(slotData.class)
            if slotData.state == "FILLED" then
                badge:SetBackdropColor(r * 0.25, g * 0.25, b * 0.25, 0.9)
                badge:SetBackdropBorderColor(r, g, b, 1)
                badge.nameLbl:SetText(slotData.name)
                badge.nameLbl:SetTextColor(r, g, b, 1)
            else -- PENDING
                badge:SetBackdropColor(0.25, 0.2, 0.05, 0.9)
                badge:SetBackdropBorderColor(1.0, 0.75, 0.1, 0.9)
                badge.nameLbl:SetText("Invited")
                badge.nameLbl:SetTextColor(1.0, 0.8, 0.2, 1)
            end
        else
            -- Empty slot
            badge:SetBackdropColor(0.08, 0.1, 0.12, 0.8)
            badge:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)
            badge.nameLbl:SetText("Open")
            badge.nameLbl:SetTextColor(0.5, 0.5, 0.5, 1)
        end
    end

    -- Update Utility Indicators
    if rosterContext.hasBL then
        mainFrame.blStatus:SetText("BL: |cff00ff00[READY]|r")
    else
        mainFrame.blStatus:SetText("BL: |cffff4444[NEED]|r")
    end

    if rosterContext.hasCR then
        mainFrame.crStatus:SetText("CR: |cff00ff00[READY]|r")
    else
        mainFrame.crStatus:SetText("CR: |cffff4444[NEED]|r")
    end
end

---Display top FIFO candidate in Showcase Card and activate Invite Button
---@param candidate table|nil
function UI:UpdateCandidateCard(candidate)
    if not mainFrame then self:CreateMainHUD() end

    currentCandidate = candidate

    if not candidate then
        self:ClearCandidateCard()
        return
    end

    local r, g, b = ns.GetClassColor(candidate.classFilename)
    mainFrame.candName:SetText(candidate.name)
    mainFrame.candName:SetTextColor(r, g, b, 1)

    local specInfo = ns.GetSpecInfo(candidate.specID)
    local specName = specInfo and specInfo.name or candidate.role
    mainFrame.candSpec:SetText(format("(%s %s)", specName, candidate.localizedClass or candidate.classFilename))

    mainFrame.candMetrics:SetText(format("Item Level: |cffffffff%d|r   |   M+ Score: |cffffffff%d|r", candidate.itemLevel or 0, candidate.dungeonScore or 0))

    local timedText = candidate.bestRunFinishedSuccess and "|cff00ff00Timed|r" or "|cffff4444Overtime|r"
    mainFrame.candExp:SetText(format("Best Run for Dungeon: |cffffffff+%d|r (%s)", candidate.bestRunLevel or 0, timedText))

    -- Highlight card border
    mainFrame.candidateCard:SetBackdropBorderColor(0.0, 0.8, 1.0, 0.9)

    -- Activate Prominent "CLICK TO INVITE" Button
    mainFrame.inviteBtn:SetBackdropColor(0.08, 0.35, 0.15, 0.95)
    mainFrame.inviteBtn:SetBackdropBorderColor(0.2, 0.9, 0.3, 1)
    mainFrame.inviteBtn.btnText:SetText("|cffffffffCLICK TO INVITE|r")
    mainFrame.inviteBtn:Enable()
end

---Clear candidate showcase card
function UI:ClearCandidateCard()
    if not mainFrame then return end
    currentCandidate = nil

    mainFrame.candName:SetText("|cff777777Queue scanning...|r")
    mainFrame.candSpec:SetText("")
    mainFrame.candMetrics:SetText("No qualifying applicants currently in queue.")
    mainFrame.candExp:SetText("")
    mainFrame.candidateCard:SetBackdropBorderColor(0.25, 0.3, 0.4, 0.7)

    -- Dim the invite button
    mainFrame.inviteBtn:SetBackdropColor(0.12, 0.14, 0.18, 0.9)
    mainFrame.inviteBtn:SetBackdropBorderColor(0.3, 0.35, 0.4, 0.6)
    mainFrame.inviteBtn.btnText:SetText("|cff777777AWAITING APPLICANTS|r")
    mainFrame.inviteBtn:Disable()
end

-------------------------------------------------------------------------------
-- Native Minimap Button
-------------------------------------------------------------------------------
function UI:CreateMinimapButton()
    if minimapButton then return minimapButton end

    local btn = CreateFrame("Button", "MPlusAutoLFGMinimapButton", Minimap)
    minimapButton = btn
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-Button-Highlight")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetTexture(525134) -- Mythic Keystone Texture
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    -- Dragging around Minimap circumference
    local function UpdatePosition()
        local angle = (MPlusAutoLFGDB and MPlusAutoLFGDB.minimap and MPlusAutoLFGDB.minimap.angle) or 220
        local radius = 80
        local x = cos(rad(angle)) * radius
        local y = sin(rad(angle)) * radius
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    btn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = deg(atan2(cy - my, cx - mx))
            if angle < 0 then angle = angle + 360 end
            if MPlusAutoLFGDB then
                MPlusAutoLFGDB.minimap = MPlusAutoLFGDB.minimap or {}
                MPlusAutoLFGDB.minimap.angle = angle
            end
            UpdatePosition()
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            UI:Toggle()
        elseif button == "RightButton" then
            if ns.TogglePause then
                ns.TogglePause()
            end
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff00b4ffMPlusAutoLFG|r", 1, 1, 1)
        local state = ns.CurrentState or "IDLE"
        GameTooltip:AddLine(format("Current State: |cffffffff%s|r", state), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Left-Click:|r Toggle HUD", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cff00ff00Right-Click:|r Pause / Resume queue", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdatePosition()
    return btn
end

-------------------------------------------------------------------------------
-- HUD Visibility Controls
-------------------------------------------------------------------------------
function UI:Show()
    if not mainFrame then self:CreateMainHUD() end
    mainFrame:Show()
end

function UI:Hide()
    if mainFrame then mainFrame:Hide() end
end

function UI:Toggle()
    if not mainFrame then self:CreateMainHUD() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

function UI:Initialize()
    self:CreateMainHUD()
    self:CreateMinimapButton()
end
