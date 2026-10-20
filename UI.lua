--[[
    MPlusAutoLFG - Matchmaking Assistant for Mythic+
    File: UI.lua
    Description: Authentic Blizzard-native UI styling using BasicFrameTemplateWithInset,
                 InsetFrameTemplate, and UIPanelButtonTemplate. Zero custom flat/vibe-coded styling.
                 Group composition is omitted as party unit frames provide this natively.
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
-- Main Blizzard-Like Frame Creation
-------------------------------------------------------------------------------
function UI:CreateMainHUD()
    if mainFrame or _G["MPlusAutoLFGMainFrame"] then
        mainFrame = mainFrame or _G["MPlusAutoLFGMainFrame"]
        return mainFrame
    end

    -- Use native Blizzard BasicFrameTemplateWithInset for authentic look & feel
    local f = CreateFrame("Frame", "MPlusAutoLFGMainFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame = f
    f:SetSize(340, 310)
    f:SetFrameStrata("DIALOG")
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

    -- Window Title (native Blizzard TitleText from template)
    if f.TitleText then
        f.TitleText:SetText("Mythic+ Auto Matchmaker")
        f.TitleText:SetTextColor(1, 0.82, 0)
    end

    ---------------------------------------------------------------------------
    -- Top Section: Keystone Information, Matchmaking Status & Stopwatch
    ---------------------------------------------------------------------------
    local infoContainer = CreateFrame("Frame", nil, f)
    infoContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -28)
    infoContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -28)
    infoContainer:SetHeight(76)
    f.infoContainer = infoContainer

    -- Keystone Icon with standard Blizzard border
    local keyIcon = infoContainer:CreateTexture(nil, "ARTWORK")
    keyIcon:SetSize(36, 36)
    keyIcon:SetPoint("TOPLEFT", infoContainer, "TOPLEFT", 4, -4)
    keyIcon:SetTexture(525134) -- Default keystone icon
    f.keyIcon = keyIcon

    -- Dungeon Name & Key Level
    local dungeonText = infoContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dungeonText:SetPoint("TOPLEFT", keyIcon, "TOPRIGHT", 10, 0)
    dungeonText:SetText("No Keystone Found")
    f.dungeonText = dungeonText

    -- Required Item Level
    local ilvlText = infoContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ilvlText:SetPoint("TOPLEFT", dungeonText, "BOTTOMLEFT", 0, -2)
    ilvlText:SetText("Required ilvl: --")
    f.ilvlText = ilvlText

    -- Matchmaking State & Stopwatch row
    local statusText = infoContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("TOPLEFT", keyIcon, "BOTTOMLEFT", 0, -8)
    statusText:SetText("Status: |cff888888IDLE|r")
    f.statusText = statusText

    local timerText = infoContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerText:SetPoint("TOPRIGHT", infoContainer, "TOPRIGHT", -4, -4)
    timerText:SetText("00:00")
    f.timerText = timerText

    -- Missing Utility Summary Row
    local utilText = infoContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    utilText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -3)
    utilText:SetText("Utilities: BL |cffff4444[Need]|r  •  CR |cffff4444[Need]|r")
    f.utilText = utilText

    ---------------------------------------------------------------------------
    -- Middle Section: Next FIFO Applicant (Blizzard InsetFrameTemplate)
    ---------------------------------------------------------------------------
    local candBox = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
    candBox:SetPoint("TOPLEFT", infoContainer, "BOTTOMLEFT", 0, -6)
    candBox:SetPoint("TOPRIGHT", infoContainer, "BOTTOMRIGHT", 0, -6)
    candBox:SetHeight(102)
    f.candBox = candBox

    local boxHeader = candBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    boxHeader:SetPoint("TOPLEFT", candBox, "TOPLEFT", 10, -8)
    boxHeader:SetText("NEXT QUALIFIED FIFO APPLICANT")

    local candName = candBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    candName:SetPoint("TOPLEFT", boxHeader, "BOTTOMLEFT", 0, -4)
    candName:SetText("|cff888888Queue is empty|r")
    f.candName = candName

    local candSpec = candBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    candSpec:SetPoint("LEFT", candName, "RIGHT", 6, 0)
    candSpec:SetText("")
    f.candSpec = candSpec

    local candMetrics = candBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candMetrics:SetPoint("TOPLEFT", candName, "BOTTOMLEFT", 0, -4)
    candMetrics:SetText("Waiting for qualifying candidates in queue...")
    f.candMetrics = candMetrics

    local candExp = candBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candExp:SetPoint("TOPLEFT", candMetrics, "BOTTOMLEFT", 0, -3)
    candExp:SetText("")
    f.candExp = candExp

    ---------------------------------------------------------------------------
    -- Bottom Section: Default Blizzard Action Buttons (UIPanelButtonTemplate)
    ---------------------------------------------------------------------------
    -- Primary Invite Button using native UIPanelButtonTemplate & SecureActionButtonTemplate
    local inviteBtn = CreateFrame("Button", "MPlusAutoLFGInviteButton", f, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    f.inviteBtn = inviteBtn
    inviteBtn:SetSize(312, 30)
    inviteBtn:SetPoint("TOP", candBox, "BOTTOM", 0, -8)
    inviteBtn:SetText("CLICK TO INVITE")

    -- Mouse-click only (no spacebar or keybind exploits)
    inviteBtn:RegisterForClicks("LeftButtonUp")

    inviteBtn:SetScript("OnClick", function(self)
        if currentCandidate and currentCandidate.applicantID then
            UI:OnInviteClicked(currentCandidate)
        end
    end)
    inviteBtn:Disable()

    -- Secondary Control Buttons Row: [Start / Delist Queue] and [Pause / Resume]
    local startBtn = CreateFrame("Button", "MPlusAutoLFGStartButton", f, "UIPanelButtonTemplate")
    startBtn:SetSize(152, 24)
    startBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    startBtn:SetText("Start Queue")
    f.startBtn = startBtn

    startBtn:SetScript("OnClick", function()
        if ns.Core then
            if ns.LFGService:HasActiveListing() or ns.CurrentState == ns.States.LISTED or ns.CurrentState == ns.States.ASSEMBLING then
                ns.Core:StopMatchmaking()
            else
                ns.Core:StartMatchmaking()
            end
        end
    end)

    local pauseBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    pauseBtn:SetSize(152, 24)
    pauseBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
    pauseBtn:SetText("Pause Queue")
    f.pauseBtn = pauseBtn

    pauseBtn:SetScript("OnClick", function()
        if ns.TogglePause then
            ns.TogglePause()
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
        ns.Logger:Info("INVITE", format("Dispatching automated invite to '%s' (ID %d)...", candidate.name, candidate.applicantID))
    end

    local success = ns.LFGService:InviteApplicant(candidate.applicantID)
    if success then
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

---Update keystone header information, state badge, stopwatch, and controls
---@param challengeMapID number
---@param keyLevel number
---@param dungeonName string
---@param iconTexture number|string
---@param state string
---@param elapsedSeconds number
---@param requiredIlvl number
function UI:UpdateHeader(challengeMapID, keyLevel, dungeonName, iconTexture, state, elapsedSeconds, requiredIlvl)
    if not mainFrame then self:CreateMainHUD() end

    if dungeonName and dungeonName ~= "" then
        mainFrame.dungeonText:SetText(format("%s +%d", dungeonName, keyLevel or 0))
    else
        mainFrame.dungeonText:SetText("No Keystone Found")
    end

    if iconTexture then
        mainFrame.keyIcon:SetTexture(iconTexture)
    end

    if requiredIlvl and requiredIlvl > 0 then
        mainFrame.ilvlText:SetText(format("Required ilvl: |cffffffff%d|r", requiredIlvl))
    else
        mainFrame.ilvlText:SetText("Required ilvl: --")
    end

    -- Format stopwatch
    elapsedSeconds = floor(elapsedSeconds or 0)
    local mins = floor(elapsedSeconds / 60)
    local secs = elapsedSeconds % 60
    mainFrame.timerText:SetText(format("%02d:%02d", mins, secs))

    -- Format state badge with Blizzard font colors
    local stateFormatted = "|cff888888IDLE|r"
    if state == ns.States.LISTED then
        stateFormatted = "|cff00ff00LISTED (Scanning)|r"
    elseif state == ns.States.ASSEMBLING then
        stateFormatted = "|cffffff00ASSEMBLING|r"
    elseif state == ns.States.FULL then
        stateFormatted = "|cff00b4ffGROUP FULL|r"
    elseif state == ns.States.PAUSED then
        stateFormatted = "|cffff8800PAUSED|r"
    end
    mainFrame.statusText:SetText(format("Status: %s", stateFormatted))

    -- Update Start / Delist button label
    if ns.LFGService:HasActiveListing() or state == ns.States.LISTED or state == ns.States.ASSEMBLING then
        mainFrame.startBtn:SetText("Delist Group")
    else
        mainFrame.startBtn:SetText("Start Queue")
    end

    -- Update Pause / Resume button label
    if state == ns.States.PAUSED then
        mainFrame.pauseBtn:SetText("Resume Queue")
    else
        mainFrame.pauseBtn:SetText("Pause Queue")
    end
end

---Update Utility Requirement Status (Group composition display is intentionally omitted)
---@param rosterContext table
function UI:UpdateUtilityStatus(rosterContext)
    if not mainFrame then self:CreateMainHUD() end

    local blStr = rosterContext.hasBL and "|cff00ff00[Ready]|r" or "|cffff4444[Need]|r"
    local crStr = rosterContext.hasCR and "|cff00ff00[Ready]|r" or "|cffff4444[Need]|r"

    local openSlots = max(0, ns.MAX_PARTY_SIZE - (rosterContext.totalCount or 0))
    local slotStr = format("(%d open)", openSlots)

    mainFrame.utilText:SetText(format("Utilities %s: BL %s  •  CR %s", slotStr, blStr, crStr))
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
    mainFrame.candSpec:SetText(format("(%s %s - %s)", specName, candidate.localizedClass or candidate.classFilename, candidate.role))

    mainFrame.candMetrics:SetText(format("Item Level: |cffffffff%d|r   |   M+ Rating: |cffffffff%d|r", candidate.itemLevel or 0, candidate.dungeonScore or 0))

    local timedText = candidate.bestRunFinishedSuccess and "|cff00ff00Timed|r" or "|cffff4444Overtime|r"
    mainFrame.candExp:SetText(format("Best Run: |cffffffff+%d|r (%s)", candidate.bestRunLevel or 0, timedText))

    -- Enable Blizzard default invite button
    mainFrame.inviteBtn:SetText(format("CLICK TO INVITE: %s", candidate.name))
    mainFrame.inviteBtn:Enable()
end

---Clear candidate showcase card
function UI:ClearCandidateCard()
    if not mainFrame then return end
    currentCandidate = nil

    mainFrame.candName:SetText("|cff777777Queue searching...|r")
    mainFrame.candSpec:SetText("")
    mainFrame.candMetrics:SetText("No qualifying applicants currently in queue.")
    mainFrame.candExp:SetText("")

    mainFrame.inviteBtn:SetText("CLICK TO INVITE")
    mainFrame.inviteBtn:Disable()
end

-------------------------------------------------------------------------------
-- Native Minimap Button (Standard Blizzard Round Border)
-------------------------------------------------------------------------------
function UI:CreateMinimapButton()
    if minimapButton or _G["MPlusAutoLFGMinimapButton"] then
        minimapButton = minimapButton or _G["MPlusAutoLFGMinimapButton"]
        return minimapButton
    end

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
        GameTooltip:AddLine("MPlusAutoLFG", 1, 0.82, 0)
        local state = ns.CurrentState or "IDLE"
        GameTooltip:AddLine(format("Current State: |cffffffff%s|r", state), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Left-Click:|r Toggle Matchmaker Panel", 0.7, 0.7, 0.7)
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
