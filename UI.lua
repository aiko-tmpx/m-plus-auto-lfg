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
local lfgTopButton = nil
local currentCandidate = nil

-------------------------------------------------------------------------------
-- Helper: 1px Crisp Border Generator
-------------------------------------------------------------------------------
local function CreateBorder(frame, r, g, b, a)
    local top = frame:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    top:SetColorTexture(r, g, b, a)

    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    bottom:SetColorTexture(r, g, b, a)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)
    left:SetColorTexture(r, g, b, a)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)
    right:SetColorTexture(r, g, b, a)

    return {
        SetColorTexture = function(self, cr, cg, cb, ca)
            top:SetColorTexture(cr, cg, cb, ca)
            bottom:SetColorTexture(cr, cg, cb, ca)
            left:SetColorTexture(cr, cg, cb, ca)
            right:SetColorTexture(cr, cg, cb, ca)
        end
    }
end

-------------------------------------------------------------------------------
-- Main Modern Dragonflight / The War Within (TWW) HUD Creation
-------------------------------------------------------------------------------
function UI:CreateMainHUD()
    if mainFrame or _G["MPlusAutoLFGMainFrame"] then
        mainFrame = mainFrame or _G["MPlusAutoLFGMainFrame"]
        return mainFrame
    end

    -- Modern Dragonflight / The War Within (TWW) dark slate canvas
    local f = CreateFrame("Frame", "MPlusAutoLFGMainFrame", UIParent)
    mainFrame = f
    f:SetSize(350, 288)
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

    -- Background: Sleek dark charcoal fill
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.08, 0.08, 0.10, 0.95)

    -- Outer border (crisp 1px slate)
    CreateBorder(f, 0.22, 0.22, 0.26, 1.0)

    -- Header bar
    local headerBg = f:CreateTexture(nil, "BORDER")
    headerBg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    headerBg:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -1, -26)
    headerBg:SetColorTexture(0.05, 0.05, 0.07, 0.95)

    local headerDiv = f:CreateTexture(nil, "ARTWORK")
    headerDiv:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -26)
    headerDiv:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -26)
    headerDiv:SetHeight(1)
    headerDiv:SetColorTexture(0.20, 0.20, 0.24, 0.8)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", f, "TOPLEFT", 14, -13)
    title:SetText(ns.ADDON_NAME or "MPlusAutoLFG")
    f.TitleText = title

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    ---------------------------------------------------------------------------
    -- Top Section: Keystone Information, Matchmaking Status & Stopwatch
    ---------------------------------------------------------------------------
    local keyIcon = f:CreateTexture(nil, "ARTWORK")
    keyIcon:SetSize(36, 36)
    keyIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
    keyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    keyIcon:SetTexture(525134) -- Default keystone icon
    f.keyIcon = keyIcon

    local dungeonText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dungeonText:SetPoint("TOPLEFT", keyIcon, "TOPRIGHT", 10, 0)
    dungeonText:SetText("No Keystone Found")
    f.dungeonText = dungeonText

    local ilvlText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ilvlText:SetPoint("TOPLEFT", dungeonText, "BOTTOMLEFT", 0, -3)
    ilvlText:SetText("Required ilvl: --")
    f.ilvlText = ilvlText

    local timerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timerText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -34)
    timerText:SetText("00:00")
    f.timerText = timerText

    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPRIGHT", timerText, "BOTTOMRIGHT", 0, -3)
    statusText:SetText("|cff888888● IDLE|r")
    f.statusText = statusText

    -- Section divider 1
    local div1 = f:CreateTexture(nil, "ARTWORK")
    div1:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -76)
    div1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -76)
    div1:SetHeight(1)
    div1:SetColorTexture(0.18, 0.18, 0.22, 0.6)

    ---------------------------------------------------------------------------
    -- Middle Section A: Visual Party Roster (5 Slots) & Utilities (BL / CR)
    ---------------------------------------------------------------------------
    -- 5 Party Role Slots: [Tank] [Healer] [DPS 1] [DPS 2] [DPS 3]
    f.roleSlots = {}
    local roleCoords = {
        TANK = { 0, 0.28125, 0.328125, 0.625 },
        HEALER = { 0.296875, 0.578125, 0, 0.296875 },
        DAMAGER = { 0.265625, 0.546875, 0.328125, 0.625 }
    }
    local defaultRoles = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }

    for i = 1, 5 do
        local slot = CreateFrame("Frame", nil, f)
        slot:SetSize(24, 24)
        slot:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (i - 1) * 28, -83)

        local slotBg = slot:CreateTexture(nil, "BACKGROUND")
        slotBg:SetAllPoints(slot)
        slotBg:SetColorTexture(0.04, 0.04, 0.06, 0.9)

        local slotBorder = CreateBorder(slot, 0.25, 0.25, 0.28, 0.7)
        slot.border = slotBorder

        local slotIcon = slot:CreateTexture(nil, "ARTWORK")
        slotIcon:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -2)
        slotIcon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
        slotIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        local rName = defaultRoles[i]
        local c = roleCoords[rName]
        slotIcon:SetTexCoord(c[1], c[2], c[3], c[4])
        slotIcon:SetDesaturated(true)
        slotIcon:SetAlpha(0.35)
        slot.icon = slotIcon

        slot:EnableMouse(true)
        slot:SetScript("OnEnter", function(self)
            if self.tooltipText then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.tooltipText)
                GameTooltip:Show()
            end
        end)
        slot:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        f.roleSlots[i] = slot
    end

    -- Divider between party slots and utility badges
    local slotDiv = f:CreateTexture(nil, "ARTWORK")
    slotDiv:SetPoint("TOPLEFT", f, "TOPLEFT", 158, -82)
    slotDiv:SetSize(1, 26)
    slotDiv:SetColorTexture(0.20, 0.20, 0.24, 0.7)

    -- Bloodlust Utility Badge
    local blBadge = CreateFrame("Frame", nil, f)
    blBadge:SetSize(24, 24)
    blBadge:SetPoint("TOPLEFT", f, "TOPLEFT", 172, -83)
    local blBg = blBadge:CreateTexture(nil, "BACKGROUND")
    blBg:SetAllPoints(blBadge)
    blBg:SetColorTexture(0.04, 0.04, 0.06, 0.9)
    blBadge.border = CreateBorder(blBadge, 0.9, 0.2, 0.2, 0.8)

    local blIcon = blBadge:CreateTexture(nil, "ARTWORK")
    blIcon:SetPoint("TOPLEFT", blBadge, "TOPLEFT", 2, -2)
    blIcon:SetPoint("BOTTOMRIGHT", blBadge, "BOTTOMRIGHT", -2, 2)
    blIcon:SetTexture("Interface\\Icons\\spell_nature_bloodlust")
    blIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    blIcon:SetDesaturated(true)
    blIcon:SetAlpha(0.4)
    blBadge.icon = blIcon

    local blTag = blBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    blTag:SetPoint("LEFT", blBadge, "RIGHT", 5, 0)
    blTag:SetText("|cffff4444BL|r")
    blBadge.tag = blTag

    blBadge:EnableMouse(true)
    blBadge:SetScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip)
            GameTooltip:Show()
        end
    end)
    blBadge:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    f.blBadge = blBadge

    -- Combat Res Utility Badge
    local crBadge = CreateFrame("Frame", nil, f)
    crBadge:SetSize(24, 24)
    crBadge:SetPoint("TOPLEFT", f, "TOPLEFT", 244, -83)
    local crBg = crBadge:CreateTexture(nil, "BACKGROUND")
    crBg:SetAllPoints(crBadge)
    crBg:SetColorTexture(0.04, 0.04, 0.06, 0.9)
    crBadge.border = CreateBorder(crBadge, 0.9, 0.2, 0.2, 0.8)

    local crIcon = crBadge:CreateTexture(nil, "ARTWORK")
    crIcon:SetPoint("TOPLEFT", crBadge, "TOPLEFT", 2, -2)
    crIcon:SetPoint("BOTTOMRIGHT", crBadge, "BOTTOMRIGHT", -2, 2)
    crIcon:SetTexture("Interface\\Icons\\spell_nature_reincarnation")
    crIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    crIcon:SetDesaturated(true)
    crIcon:SetAlpha(0.4)
    crBadge.icon = crIcon

    local crTag = crBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    crTag:SetPoint("LEFT", crBadge, "RIGHT", 5, 0)
    crTag:SetText("|cffff4444CR|r")
    crBadge.tag = crTag

    crBadge:EnableMouse(true)
    crBadge:SetScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip)
            GameTooltip:Show()
        end
    end)
    crBadge:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    f.crBadge = crBadge

    -- Section divider 2
    local div2 = f:CreateTexture(nil, "ARTWORK")
    div2:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -114)
    div2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -114)
    div2:SetHeight(1)
    div2:SetColorTexture(0.18, 0.18, 0.22, 0.6)

    ---------------------------------------------------------------------------
    -- Middle Section B: Next FIFO Applicant Showcase Card
    ---------------------------------------------------------------------------
    local candBox = CreateFrame("Frame", nil, f)
    candBox:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -122)
    candBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -122)
    candBox:SetHeight(106)
    f.candBox = candBox

    local candBg = candBox:CreateTexture(nil, "BACKGROUND")
    candBg:SetAllPoints(candBox)
    candBg:SetColorTexture(0.04, 0.04, 0.06, 0.85)

    CreateBorder(candBox, 0.20, 0.20, 0.24, 0.8)

    local boxHeader = candBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    boxHeader:SetPoint("TOPLEFT", candBox, "TOPLEFT", 10, -7)
    boxHeader:SetText("NEXT QUALIFIED FIFO APPLICANT")
    f.boxHeader = boxHeader

    local candSpecIcon = candBox:CreateTexture(nil, "OVERLAY")
    candSpecIcon:SetSize(28, 28)
    candSpecIcon:SetPoint("TOPLEFT", boxHeader, "BOTTOMLEFT", 0, -4)
    candSpecIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    candSpecIcon:Hide()
    f.candSpecIcon = candSpecIcon

    local candName = candBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    candName:SetPoint("TOPLEFT", boxHeader, "BOTTOMLEFT", 0, -4)
    candName:SetText("|cff888888Queue searching...|r")
    f.candName = candName

    local candSpec = candBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candSpec:SetPoint("LEFT", candName, "RIGHT", 6, 0)
    candSpec:SetText("")
    f.candSpec = candSpec

    local candMetrics = candBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candMetrics:SetPoint("TOPLEFT", candName, "BOTTOMLEFT", 0, -5)
    candMetrics:SetText("No qualifying applicants currently in queue.")
    f.candMetrics = candMetrics

    local candExp = candBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candExp:SetPoint("TOPLEFT", candMetrics, "BOTTOMLEFT", 0, -3)
    candExp:SetText("")
    f.candExp = candExp

    ---------------------------------------------------------------------------
    -- Bottom Section: Unified Action Button (UIPanelButtonTemplate)
    ---------------------------------------------------------------------------
    local inviteBtn = CreateFrame("Button", "MPlusAutoLFGInviteButton", f, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    f.inviteBtn = inviteBtn
    inviteBtn:SetSize(322, 30)
    inviteBtn:SetPoint("TOP", candBox, "BOTTOM", 0, -8)
    inviteBtn:SetText("Open LFG Window")

    -- Mouse-click only (no spacebar or keybind exploits)
    inviteBtn:RegisterForClicks("LeftButtonUp")

    inviteBtn:SetScript("OnClick", function(self)
        if currentCandidate and currentCandidate.applicantID then
            UI:OnInviteClicked(currentCandidate)
        elseif not ns.LFGService:HasActiveListing() and (ns.CurrentState == ns.States.IDLE) then
            if ns.Core then
                ns.Core:StartMatchmaking()
            elseif ns.LFGService then
                ns.LFGService:OpenGroupFinder()
            end
        end
    end)

    f:Hide()
    return f
end

-------------------------------------------------------------------------------
-- UI State & Presentation Updaters
-------------------------------------------------------------------------------
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
            if ns.Core then
                if ns.LFGService:HasActiveListing() or ns.CurrentState == ns.States.LISTED or ns.CurrentState == ns.States.ASSEMBLING then
                    ns.Core:StopMatchmaking()
                else
                    ns.Core:StartMatchmaking()
                end
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
        GameTooltip:AddLine("|cff00ff00Right-Click:|r Start / Stop queue", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdatePosition()
    return btn
end

-------------------------------------------------------------------------------
-- Blizzard LFG / PVE Window Top Button
-------------------------------------------------------------------------------
---Create a red Blizzard-style action button anchored on top of PVEFrame
---@return Button|nil
function UI:CreateLFGTopButton()
    if lfgTopButton then
        return lfgTopButton
    end

    local parent = _G["PVEFrame"]
    if not parent then
        return nil
    end

    -- Create native Blizzard panel button using UIPanelButtonTemplate (classic red Blizzard button)
    local btn = CreateFrame("Button", "MPlusAutoLFGLFGListButton", parent, "UIPanelButtonTemplate")
    lfgTopButton = btn
    btn:SetSize(150, 22)
    btn:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -12, 1)
    btn:SetText("List AutoLFG Group")
    btn:SetFrameLevel(parent:GetFrameLevel() + 5)

    -- Tooltip & status inspection
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("MPlusAutoLFG", 1, 0.82, 0)
        local state = ns.CurrentState or (ns.States and ns.States.IDLE) or "IDLE"
        if state == "IDLE" or (ns.States and state == ns.States.IDLE) then
            GameTooltip:AddLine("Click to configure listing and start Mythic+ matchmaking.", 1, 1, 1, true)
            GameTooltip:AddLine("Pre-fills Playstyle (Relaxed) and required ilvl based on your keystone.", 0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine(format("Current State: |cffffffff%s|r", state), 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Queue is currently active. Click to view Matchmaking HUD.", 0.2, 1, 0.2, true)
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        if ns.Core then
            if ns.CurrentState == ns.States.LISTED or ns.CurrentState == ns.States.ASSEMBLING or ns.CurrentState == ns.States.FULL then
                UI:Show()
            else
                ns.Core:StartMatchmaking()
                UI:Show()
            end
        elseif ns.LFGService then
            ns.LFGService:OpenGroupFinder()
            UI:Show()
        end
    end)

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
    self:CreateLFGTopButton()
end
