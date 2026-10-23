--[[
    MPlusAutoLFG - Matchmaking Assistant for Mythic+
    File: UI.lua
    Description: Modern Blizzard Dragonflight / The War Within (TWW) HUD styling.
                 Uses native indicator textures, unboxed 5-role party layout, clean text utilities (BL / CR),
                 rules mode toggle, native settings integration, and streamlined candidate showcase.
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
-- Micro Role Atlases & Class Color Helpers (Matches Blizzard LFG Design)
-------------------------------------------------------------------------------
local ROLE_MICRO_ATLAS = {
    TANK = "groupfinder-icon-role-micro-tank",
    HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps"
}

local ROLE_FALLBACK_COORDS = {
    TANK = { 0, 0.28125, 0.328125, 0.625 },
    HEALER = { 0.296875, 0.578125, 0, 0.296875 },
    DAMAGER = { 0.265625, 0.546875, 0.328125, 0.625 }
}

local function GetClassColorRGB(classFilename)
    if not classFilename then return 0.5, 0.5, 0.5 end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local colorObj = C_ClassColor.GetClassColor(classFilename)
        if colorObj then
            return colorObj.r, colorObj.g, colorObj.b
        end
    end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename] then
        local c = RAID_CLASS_COLORS[classFilename]
        return c.r, c.g, c.b
    end
    return 0.5, 0.5, 0.5
end

local function ApplyRoleIcon(texture, role, isDesaturated, alpha)
    local atlas = ROLE_MICRO_ATLAS[role]
    local success = false
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
        success = true
    end
    if not success then
        texture:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        local c = ROLE_FALLBACK_COORDS[role] or ROLE_FALLBACK_COORDS.DAMAGER
        texture:SetTexCoord(c[1], c[2], c[3], c[4])
    end
    texture:SetDesaturated(isDesaturated == true)
    texture:SetAlpha(alpha or 1.0)
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
    f:SetSize(350, 256)
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
    -- Top Section: Keystone Information, Status & Elapsed Stopwatch
    ---------------------------------------------------------------------------
    local keyIcon = f:CreateTexture(nil, "ARTWORK")
    keyIcon:SetSize(36, 36)
    keyIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
    keyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    keyIcon:SetTexture(525134) -- Default keystone icon
    f.keyIcon = keyIcon

    local timerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timerText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -34)
    timerText:SetText("00:00")
    f.timerText = timerText

    -- Modern circular indicator texture (avoids font-dependent glyph issues)
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPRIGHT", timerText, "BOTTOMRIGHT", 0, -3)
    statusText:SetText("|cff888888IDLE|r")
    f.statusText = statusText

    local statusIcon = f:CreateTexture(nil, "OVERLAY")
    statusIcon:SetSize(12, 12)
    statusIcon:SetPoint("RIGHT", statusText, "LEFT", -4, 0)
    statusIcon:SetTexture("Interface\\Common\\Indicator-Gray")
    f.statusIcon = statusIcon

    local dungeonText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dungeonText:SetPoint("LEFT", keyIcon, "RIGHT", 10, 0)
    dungeonText:SetWidth(168)
    dungeonText:SetJustifyH("LEFT")
    dungeonText:SetWordWrap(false)
    dungeonText:SetText("No Keystone Found")
    f.dungeonText = dungeonText

    -- Section divider 1
    local div1 = f:CreateTexture(nil, "ARTWORK")
    div1:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -76)
    div1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -76)
    div1:SetHeight(1)
    div1:SetColorTexture(0.18, 0.18, 0.22, 0.6)

    ---------------------------------------------------------------------------
    -- Middle Section A: Blizzard-Style 5 Member Circular Slots & Utilities
    ---------------------------------------------------------------------------
    f.roleSlots = {}
    for i = 1, 5 do
        local slot = CreateFrame("Frame", nil, f)
        slot:SetSize(22, 22)
        slot:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (i - 1) * 25, -82)

        -- Circular background disc
        local circle = slot:CreateTexture(nil, "BACKGROUND")
        circle:SetAllPoints(slot)
        circle:SetColorTexture(0.12, 0.12, 0.15, 0.65)

        -- Mask texture for circular cutout
        local mask = slot:CreateMaskTexture()
        mask:SetAllPoints(circle)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        circle:AddMaskTexture(mask)
        slot.circle = circle
        slot.mask = mask

        -- Centered micro role icon
        local roleIcon = slot:CreateTexture(nil, "ARTWORK")
        roleIcon:SetSize(14, 14)
        roleIcon:SetPoint("CENTER", slot, "CENTER", 0, 0)
        ApplyRoleIcon(roleIcon, "DAMAGER", true, 0.25)
        slot.roleIcon = roleIcon

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

    -- Clean Text Utilities: Bloodlust (BL) and Combat Res (CR)
    local blFrame = CreateFrame("Frame", nil, f)
    blFrame:SetSize(28, 20)
    blFrame:SetPoint("LEFT", f, "TOPLEFT", 144, -92)

    local blText = blFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    blText:SetAllPoints(blFrame)
    blText:SetText("|cffff4444BL|r")
    blFrame.text = blText
    blFrame.tooltip = "Bloodlust / Heroism: Needed"

    blFrame:EnableMouse(true)
    blFrame:SetScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip)
            GameTooltip:Show()
        end
    end)
    blFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    f.blFrame = blFrame

    local crFrame = CreateFrame("Frame", nil, f)
    crFrame:SetSize(28, 20)
    crFrame:SetPoint("LEFT", blFrame, "RIGHT", 8, 0)

    local crText = crFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    crText:SetAllPoints(crFrame)
    crText:SetText("|cffff4444CR|r")
    crFrame.text = crText
    crFrame.tooltip = "Combat Resurrection: Needed"

    crFrame:EnableMouse(true)
    crFrame:SetScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip)
            GameTooltip:Show()
        end
    end)
    crFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    f.crFrame = crFrame

    -- Options Shortcut Button (Right side of the utilities row)
    local configBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    configBtn:SetSize(68, 20)
    configBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -83)
    configBtn:SetText("Options")
    f.configBtn = configBtn

    configBtn:SetScript("OnClick", function()
        if ns.OpenOptions then
            ns.OpenOptions()
        end
    end)
    configBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("MPlusAutoLFG Settings", 1, 0.82, 0)
        GameTooltip:AddLine("Click to open configuration panel in Game Menu -> Options.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    configBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Section divider 2
    local div2 = f:CreateTexture(nil, "ARTWORK")
    div2:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -110)
    div2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -110)
    div2:SetHeight(1)
    div2:SetColorTexture(0.18, 0.18, 0.22, 0.6)

    ---------------------------------------------------------------------------
    -- Middle Section C: Next Qualified Applicant Showcase Card
    ---------------------------------------------------------------------------
    local candBox = CreateFrame("Frame", nil, f)
    candBox:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -116)
    candBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -116)
    candBox:SetHeight(94)
    f.candBox = candBox

    local candBg = candBox:CreateTexture(nil, "BACKGROUND")
    candBg:SetAllPoints(candBox)
    candBg:SetColorTexture(0.04, 0.04, 0.06, 0.85)

    CreateBorder(candBox, 0.20, 0.20, 0.24, 0.8)

    local boxHeader = candBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    boxHeader:SetPoint("TOPLEFT", candBox, "TOPLEFT", 10, -7)
    boxHeader:SetText("NEXT QUALIFIED APPLICANT")
    f.boxHeader = boxHeader

    local candSpecIcon = candBox:CreateTexture(nil, "OVERLAY")
    candSpecIcon:SetSize(28, 28)
    candSpecIcon:SetPoint("TOPLEFT", boxHeader, "BOTTOMLEFT", 0, -4)
    candSpecIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    candSpecIcon:Hide()
    f.candSpecIcon = candSpecIcon

    local candName = candBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    candName:SetPoint("TOPLEFT", boxHeader, "BOTTOMLEFT", 0, -5)
    candName:SetText("|cff888888Queue searching...|r")
    f.candName = candName

    local candSpec = candBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candSpec:SetPoint("LEFT", candName, "RIGHT", 6, 0)
    candSpec:SetText("")
    f.candSpec = candSpec

    local candMetrics = candBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    candMetrics:SetPoint("TOPLEFT", candName, "BOTTOMLEFT", 0, -4)
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
        if ns.Core and not ns.Core:IsLeader() then
            return
        end
        if ns.ActiveKeystone and ns.LFGService and ns.LFGService:HasActiveListing() and not ns.ActiveKeystone.isValidKey then
            return
        end

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
-- Action Button Click Dispatcher
-------------------------------------------------------------------------------
function UI:OnInviteClicked(candidate)
    if not candidate or not candidate.applicantID then return end

    if IsInRaid and IsInRaid() then
        return
    end
    if ns.Core and not ns.Core:IsLeader() then
        return
    end
    if ns.ActiveKeystone and ns.LFGService and ns.LFGService:HasActiveListing() and not ns.ActiveKeystone.isValidKey then
        return
    end

    -- Pre-flight verification: Ensure candidate is still actively applied before sending invite
    local appInfo = ns.LFGService:GetApplicantInfo(candidate.applicantID)
    if not appInfo or appInfo.applicationStatus ~= "applied" or appInfo.isStale then
        if ns.Logger and ns.Logger.Warn then
            ns.Logger:Warn("QUEUE", format("Cannot invite '%s': Application is no longer active (%s).", candidate.name or "Applicant", (appInfo and appInfo.applicationStatus) or "cancelled"))
        end
        UI:ClearCandidateCard()
        if ns.Core then
            ns.Core:EvaluateQueue()
            ns.Core:UpdateUI()
        end
        return
    end

    local ok = ns.LFGService:InviteApplicant(candidate.applicantID)
    if ok then
        if ns.OnCandidateInvited then
            ns.OnCandidateInvited(candidate)
        end
        UI:UpdateCandidateCard(candidate, true)
    end
end

-------------------------------------------------------------------------------
-- Header & Status Updater
-------------------------------------------------------------------------------
function UI:UpdateHeader(challengeMapID, keystoneLevel, dungeonName, iconTexture, currentState, elapsed, displayTitle, isMPlusQueue, isValidKey)
    if not mainFrame then self:CreateMainHUD() end
    local f = mainFrame
    if not f then return end

    -- Always draw standard Mythic Keystone icon (525134) - never use dungeon art
    f.keyIcon:SetTexture(525134)

    -- Draw ONLY title string as requested (e.g. "+45 relaxed", "+2")
    if displayTitle and displayTitle ~= "" then
        f.dungeonText:SetText(displayTitle)
    else
        f.dungeonText:SetText("No Keystone Found")
    end

    -- Update elapsed timer
    if elapsed and elapsed > 0 then
        local mins = floor(elapsed / 60)
        local secs = floor(elapsed % 60)
        f.timerText:SetText(format("%02d:%02d", mins, secs))
    else
        f.timerText:SetText("00:00")
    end

    local isRaid = IsInRaid and IsInRaid()
    local isLeader = true
    if ns.Core and ns.Core.IsLeader then
        isLeader = ns.Core:IsLeader()
    end
    local hasListing = ns.LFGService and ns.LFGService:HasActiveListing()
    local state = currentState or ns.CurrentState or (ns.States and ns.States.IDLE) or "IDLE"

    -- 1. Listing exists in M+ but key level is unparsed or invalid (e.g. "+1 wer 3", "chill run") -> DISABLE WINDOW
    if hasListing and isMPlusQueue and not isValidKey then
        f.keyIcon:SetDesaturated(true)
        f.keyIcon:SetAlpha(0.35)
        f.statusIcon:SetTexture("Interface\\Common\\Indicator-Gray")
        f.statusText:SetText("|cffff4444Invalid Key|r")

        if f.candBox then f.candBox:SetAlpha(0.40) end

        f.inviteBtn:Disable()
        f.inviteBtn:SetText("Invalid Key Level")
    elseif hasListing and isMPlusQueue == false then
        -- 2. Non-M+ Listing
        f.keyIcon:SetDesaturated(true)
        f.keyIcon:SetAlpha(0.35)
        f.statusIcon:SetTexture("Interface\\Common\\Indicator-Gray")
        f.statusText:SetText("|cffff8800Not M+|r")

        if f.candBox then f.candBox:SetAlpha(0.40) end

        f.inviteBtn:Disable()
        f.inviteBtn:SetText("Not an M+ Queue")
    else
        -- 3. Valid M+ listing or idle
        f.keyIcon:SetDesaturated(false)
        f.keyIcon:SetAlpha(1.0)
        if f.candBox then f.candBox:SetAlpha(1.0) end

        if ns.States and state == ns.States.LISTED then
            f.statusIcon:SetTexture("Interface\\Common\\Indicator-Green")
            f.statusText:SetText("|cff00ff00Scanning Queue|r")
        elseif ns.States and state == ns.States.ASSEMBLING then
            f.statusIcon:SetTexture("Interface\\Common\\Indicator-Yellow")
            f.statusText:SetText("|cffffff00Assembling|r")
        elseif ns.States and state == ns.States.FULL then
            f.statusIcon:SetTexture("Interface\\Common\\Indicator-Green")
            f.statusText:SetText("|cff00ff00Group Full|r")
        else
            f.statusIcon:SetTexture("Interface\\Common\\Indicator-Gray")
            f.statusText:SetText("|cff888888IDLE|r")
        end

        if not currentCandidate then
            if isRaid then
                f.inviteBtn:Disable()
                f.inviteBtn:SetText("Raid Group")
            elseif not isLeader then
                f.inviteBtn:Disable()
                f.inviteBtn:SetText("Leader Only")
            elseif not hasListing and (ns.States and state == ns.States.IDLE) then
                f.inviteBtn:Enable()
                f.inviteBtn:SetText("Open LFG Window")
            else
                f.inviteBtn:Disable()
                f.inviteBtn:SetText("Invite")
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Party Roster & Utilities (BL / CR) Updater
-------------------------------------------------------------------------------
function UI:UpdateUtilityStatus(rosterContext)
    if not mainFrame then self:CreateMainHUD() end
    local f = mainFrame
    if not f or not rosterContext then return end

    -- Group members by role
    local tanks = {}
    local healers = {}
    local dps = {}

    if rosterContext.members then
        for _, m in ipairs(rosterContext.members) do
            if m.role == "TANK" then
                table.insert(tanks, m)
            elseif m.role == "HEALER" then
                table.insert(healers, m)
            else
                table.insert(dps, m)
            end
        end
    end

    local totalTanks = (rosterContext.roles and rosterContext.roles["TANK"]) or #tanks
    local totalHealers = (rosterContext.roles and rosterContext.roles["HEALER"]) or #healers
    local totalDPS = (rosterContext.roles and rosterContext.roles["DAMAGER"]) or #dps

    -- If listed in M+ but key level is unparsed/invalid, dim roles and utilities
    local hasListing = ns.LFGService and ns.LFGService:HasActiveListing()
    local isMPlus = ns.ActiveKeystone and ns.ActiveKeystone.isMPlusQueue
    local isValidKey = ns.ActiveKeystone and ns.ActiveKeystone.isValidKey

    if hasListing and isMPlus and not isValidKey then
        for i = 1, 5 do
            local slot = f.roleSlots[i]
            if slot then
                slot.circle:SetColorTexture(0.08, 0.08, 0.10, 0.5)
                local defaultRole = (i == 1 and "TANK") or (i == 2 and "HEALER") or "DAMAGER"
                ApplyRoleIcon(slot.roleIcon, defaultRole, true, 0.15)
                slot.tooltipText = "Matchmaking Disabled (Invalid Key Level)"
            end
        end
        f.blFrame.text:SetText("|cff666666BL|r")
        f.blFrame.tooltip = "Bloodlust / Heroism: Matchmaking Disabled"
        f.crFrame.text:SetText("|cff666666CR|r")
        f.crFrame.tooltip = "Combat Resurrection: Matchmaking Disabled"
        return
    end

    -- Dynamically assemble 5 slots matching Blizzard Group Finder:
    -- 1. Existing members (Tanks -> Healers -> DPS)
    -- 2. Pending invited candidates
    -- 3. Needed missing roles (Tanks -> Healers -> DPS)
    local slotEntries = {}

    for _, m in ipairs(tanks) do
        table.insert(slotEntries, {
            type = "MEMBER",
            role = "TANK",
            name = m.name,
            class = m.class,
            tooltip = format("Tank: %s (%s)", m.name, m.class or "Tank")
        })
    end
    for _, m in ipairs(healers) do
        table.insert(slotEntries, {
            type = "MEMBER",
            role = "HEALER",
            name = m.name,
            class = m.class,
            tooltip = format("Healer: %s (%s)", m.name, m.class or "Healer")
        })
    end
    for _, m in ipairs(dps) do
        table.insert(slotEntries, {
            type = "MEMBER",
            role = "DAMAGER",
            name = m.name,
            class = m.class,
            tooltip = format("DPS: %s (%s)", m.name, m.class or "DPS")
        })
    end

    if rosterContext.pending then
        for _, p in ipairs(rosterContext.pending) do
            if #slotEntries < 5 then
                local roleStr = (p.role == "TANK" and "Tank") or (p.role == "HEALER" and "Healer") or "DPS"
                table.insert(slotEntries, {
                    type = "PENDING",
                    role = p.role or "DAMAGER",
                    name = p.name,
                    class = p.class,
                    tooltip = format("%s: %s (Reserved - Invited)", roleStr, p.name or "Applicant")
                })
            end
        end
    end

    local neededTanks = max(0, 1 - totalTanks)
    local neededHealers = max(0, 1 - totalHealers)
    local neededDPS = max(0, 3 - totalDPS)

    for i = 1, neededTanks do
        if #slotEntries < 5 then
            table.insert(slotEntries, { type = "NEEDED", role = "TANK", tooltip = "Tank: Needed" })
        end
    end
    for i = 1, neededHealers do
        if #slotEntries < 5 then
            table.insert(slotEntries, { type = "NEEDED", role = "HEALER", tooltip = "Healer: Needed" })
        end
    end
    for i = 1, neededDPS do
        if #slotEntries < 5 then
            table.insert(slotEntries, { type = "NEEDED", role = "DAMAGER", tooltip = "DPS: Needed" })
        end
    end

    while #slotEntries < 5 do
        table.insert(slotEntries, { type = "NEEDED", role = "DAMAGER", tooltip = "DPS: Needed" })
    end

    for i = 1, 5 do
        local slot = f.roleSlots[i]
        local entry = slotEntries[i]
        if slot and entry then
            slot.tooltipText = entry.tooltip

            if entry.type == "MEMBER" then
                local cr, cg, cb = GetClassColorRGB(entry.class)
                slot.circle:SetColorTexture(cr, cg, cb, 1.0)
                ApplyRoleIcon(slot.roleIcon, entry.role, false, 1.0)
            elseif entry.type == "PENDING" then
                local cr, cg, cb = GetClassColorRGB(entry.class)
                slot.circle:SetColorTexture(cr * 0.7, cg * 0.7, cb * 0.7, 0.75)
                ApplyRoleIcon(slot.roleIcon, entry.role, false, 0.75)
            else
                slot.circle:SetColorTexture(0.12, 0.12, 0.15, 0.65)
                ApplyRoleIcon(slot.roleIcon, entry.role, true, 0.25)
            end
        end
    end

    -- Utility text: Bloodlust (BL)
    if rosterContext.hasBL then
        f.blFrame.text:SetText("|cff00ff00BL|r")
        f.blFrame.tooltip = "Bloodlust / Heroism: In Party"
    else
        f.blFrame.text:SetText("|cffff4444BL|r")
        f.blFrame.tooltip = "Bloodlust / Heroism: Needed"
    end

    -- Utility text: Combat Resurrection (CR)
    if rosterContext.hasCR then
        f.crFrame.text:SetText("|cff00ff00CR|r")
        f.crFrame.tooltip = "Combat Resurrection: In Party"
    else
        f.crFrame.text:SetText("|cffff4444CR|r")
        f.crFrame.tooltip = "Combat Resurrection: Needed"
    end
end

-------------------------------------------------------------------------------
-- Candidate Showcase Card Updater
-------------------------------------------------------------------------------
function UI:UpdateCandidateCard(candidate, isInvited)
    if not mainFrame then self:CreateMainHUD() end
    local f = mainFrame
    if not f then return end

    currentCandidate = candidate
    if not candidate then
        self:ClearCandidateCard()
        return
    end

    local isLeader = (not ns.Core or not ns.Core.IsLeader) or ns.Core:IsLeader()

    -- Display candidate information
    local classColor = RAID_CLASS_COLORS[candidate.classFilename]
    local colorHex = classColor and classColor.colorStr or "ffffffff"
    local nameText = format("|c%s%s|r", colorHex, candidate.name or "Applicant")
    f.candName:SetText(nameText)

    local specText = ""
    if candidate.specName and candidate.specName ~= "" then
        specText = format("%s %s", candidate.specName, candidate.localizedClass or candidate.classFilename or "")
    else
        specText = format("%s", candidate.localizedClass or candidate.classFilename or candidate.role or "")
    end
    f.candSpec:SetText(specText)

    -- Spec Icon
    if candidate.specIcon and candidate.specIcon > 0 then
        f.candSpecIcon:SetTexture(candidate.specIcon)
        f.candSpecIcon:SetDesaturated(false)
        f.candSpecIcon:SetAlpha(1.0)
        f.candSpecIcon:Show()
        f.candName:SetPoint("TOPLEFT", f.candSpecIcon, "TOPRIGHT", 8, 2)
    else
        f.candSpecIcon:Hide()
        f.candName:SetPoint("TOPLEFT", f.boxHeader, "BOTTOMLEFT", 0, -5)
    end

    -- M+ Score rarity coloring
    local score = candidate.dungeonScore or candidate.overallScore or 0
    local scoreColor = "ffffffff"
    if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
        local colorObj = C_ChallengeMode.GetDungeonScoreRarityColor(score)
        if colorObj and colorObj.GenerateHexColor then
            scoreColor = colorObj:GenerateHexColor()
        elseif colorObj and colorObj.r then
            scoreColor = format("ff%02x%02x%02x", colorObj.r * 255, colorObj.g * 255, colorObj.b * 255)
        end
    else
        if score >= 2500 then scoreColor = "ffff8000"
        elseif score >= 2000 then scoreColor = "ffa335ee"
        elseif score >= 1500 then scoreColor = "ff0070dd"
        elseif score >= 1000 then scoreColor = "ff1eff00"
        end
    end

    local ilvl = candidate.itemLevel and floor(candidate.itemLevel) or 0
    f.candMetrics:SetText(format("Rating: |c%s%d|r   •   ilvl: |cffffffff%d|r", scoreColor, score, ilvl))

    -- Dungeon Experience
    local bestLevel = candidate.bestRunLevel or 0
    if bestLevel > 0 then
        local timedStr = candidate.bestRunFinishedSuccess and "|cff00ff00Timed|r" or "|cffff4444Overtime (Depleted)|r"
        f.candExp:SetText(format("Best Run: +%d %s", bestLevel, timedStr))
    else
        f.candExp:SetText("Best Run: |cff888888No record for this dungeon|r")
    end

    -- Primary action button state
    local isRaid = IsInRaid and IsInRaid()
    if isRaid then
        f.inviteBtn:Disable()
        f.inviteBtn:SetText("Raid Group")
    elseif not isLeader then
        f.inviteBtn:Disable()
        f.inviteBtn:SetText("Leader Only")
    elseif isInvited then
        f.inviteBtn:Disable()
        f.inviteBtn:SetText("INVITED")
    else
        f.inviteBtn:Enable()
        f.inviteBtn:SetText("Invite")
    end
end

-------------------------------------------------------------------------------
-- Reset Candidate Showcase Card
-------------------------------------------------------------------------------
function UI:ClearCandidateCard()
    currentCandidate = nil
    if not mainFrame then return end
    local f = mainFrame

    f.candSpecIcon:Hide()
    f.candName:SetPoint("TOPLEFT", f.boxHeader, "BOTTOMLEFT", 0, -5)
    f.candSpec:SetText("")
    f.candExp:SetText("")

    local hasListing = ns.LFGService and ns.LFGService:HasActiveListing()
    local isMPlus = ns.ActiveKeystone and ns.ActiveKeystone.isMPlusQueue
    local isValidKey = ns.ActiveKeystone and ns.ActiveKeystone.isValidKey

    if hasListing and isMPlus and not isValidKey then
        f.candName:SetText("|cffff4444Unparsed Key Level|r")
        f.candMetrics:SetText("Listing title must specify a valid key (e.g. +12).")
        f.inviteBtn:Disable()
        f.inviteBtn:SetText("Invalid Key Level")
        return
    end

    f.candName:SetText("|cff888888Queue searching...|r")
    f.candMetrics:SetText("No qualifying applicants currently in queue.")

    local isRaid = IsInRaid and IsInRaid()
    local isLeader = (not ns.Core or not ns.Core.IsLeader) or ns.Core:IsLeader()

    if isRaid then
        f.inviteBtn:Disable()
        f.inviteBtn:SetText("Raid Group")
    elseif not isLeader then
        f.inviteBtn:Disable()
        f.inviteBtn:SetText("Leader Only")
    elseif not hasListing and (ns.CurrentState == ns.States.IDLE) then
        f.inviteBtn:Enable()
        f.inviteBtn:SetText("Open LFG Window")
    else
        f.inviteBtn:Disable()
        f.inviteBtn:SetText("Invite")
    end
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
    if ns.Core and ns.Core.RefreshKeystoneInfo then
        ns.Core:RefreshKeystoneInfo()
    end
    if ns.Core and ns.Core.UpdateUI then
        ns.Core:UpdateUI()
    end
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
        self:Show()
    end
end

function UI:Initialize()
    self:CreateMainHUD()
    self:CreateMinimapButton()
    self:CreateLFGTopButton()
end
