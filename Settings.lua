--[[
    MPlusAutoLFG - Matchmaking Assistant for Mythic+
    File: Settings.lua
    Description: Native Blizzard Settings Menu integration using Settings.RegisterCanvasLayoutCategory.
                 Provides customizable rules for candidate key ranges, timed run requirements, and item levels.
]]

local addonName, ns = ...

local Settings = _G["Settings"]
local pairs, ipairs, tonumber, tostring, floor, max, min = pairs, ipairs, tonumber, tostring, math.floor, math.max, math.min
local format = string.format

local settingsCategory = nil

-------------------------------------------------------------------------------
-- Helper UI Component Builders
-------------------------------------------------------------------------------
local function CreateCheckbox(parent, labelText, tooltipText, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb.text:SetText(labelText)
    cb.text:SetFontObject("GameFontHighlight")
    cb:SetScript("OnClick", function(self)
        local val = self:GetChecked()
        setter(val)
    end)
    if tooltipText then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 0.82, 0)
            GameTooltip:AddLine(tooltipText, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    cb.Refresh = function(self)
        self:SetChecked(getter() == true)
    end
    return cb
end

local function CreateSlider(parent, labelText, minVal, maxVal, step, getter, setter, formatFunc, tooltipText)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(280)

    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))

    local title = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 6)
    title:SetText(labelText)
    slider.title = title

    local valueText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", 0, 6)
    slider.valueText = valueText

    if tooltipText then
        slider:EnableMouse(true)
        slider:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 0.82, 0)
            GameTooltip:AddLine(tooltipText, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        slider:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    slider:SetScript("OnValueChanged", function(self, val)
        val = floor(val + 0.5)
        setter(val)
        if formatFunc then
            self.valueText:SetText(formatFunc(val))
        else
            self.valueText:SetText(tostring(val))
        end
    end)

    slider.Refresh = function(self)
        local val = getter() or minVal
        self:SetValue(val)
        if formatFunc then
            self.valueText:SetText(formatFunc(val))
        else
            self.valueText:SetText(tostring(val))
        end
    end

    return slider
end

-------------------------------------------------------------------------------
-- Options Panel Initialization
-------------------------------------------------------------------------------
function ns.InitializeSettings()
    if settingsCategory then return end

    local panel = CreateFrame("Frame", "MPlusAutoLFGOptionsPanel", UIParent)
    panel.name = ns.ADDON_NAME

    -- Header Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText(format("|cff00b4ff%s|r Settings", ns.ADDON_NAME))

    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetText("Configure automated qualification rules, key level tolerances, and item level requirements.")

    local div = panel:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
    div:SetSize(580, 1)
    div:SetColorTexture(0.25, 0.25, 0.28, 0.8)

    local widgets = {}

    -- Section: Qualification Tiers Information
    local rulesHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rulesHeader:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, -14)
    rulesHeader:SetText("Matchmaking Rules & Qualification Tiers")

    local rulesDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rulesDesc:SetPoint("TOPLEFT", rulesHeader, "BOTTOMLEFT", 0, -6)
    rulesDesc:SetWidth(560)
    rulesDesc:SetJustifyH("LEFT")
    rulesDesc:SetText("MPlusAutoLFG uses a deterministic qualification pipeline tailored to keystone difficulty:\n\n" ..
        "• |cffffd100Keys up to +10:|r Open queue. No prior completed run of the dungeon is required.\n\n" ..
        "• |cffffd100Keys +11 to +15:|r Requires a completed timed run of at least [Key - 2] specifically for this dungeon (e.g. +9 for an 11, +13 for a 15).\n\n" ..
        "• |cffffd100Keys +16+:|r Requires a completed timed run of at least [Key - 1] specifically for this dungeon (e.g. +15 for a 16).\n\n" ..
        "• |cffffd100Higher Keys:|r Candidates with an equal or higher completed key for this dungeon always qualify.\n\n" ..
        "• |cffffd100Item Level:|r Must meet the item level requirement set in the Premade Groups listing.\n\n" ..
        "• |cffffd100Group Roles & Utility:|r Automatically guarantees 1 Tank, 1 Healer, 3 DPS, Bloodlust/Heroism, and Combat Resurrection before the group fills.")

    panel.Refresh = function()
        for _, w in ipairs(widgets) do
            if w.Refresh then w:Refresh() end
        end
    end

    panel:SetScript("OnShow", function(self)
        self:Refresh()
    end)

    -- Register with Blizzard Modern Settings Category (Dragonflight / TWW 10.0+ / 11.0+)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, ns.ADDON_NAME)
        Settings.RegisterAddOnCategory(cat)
        settingsCategory = cat
        ns.SettingsCategory = cat
    elseif InterfaceOptions_AddCategory then
        -- Legacy Fallback
        InterfaceOptions_AddCategory(panel)
        settingsCategory = panel
    end
end

---Open the Addon Settings Panel in Blizzard Options
function ns.OpenOptions()
    if not settingsCategory then
        ns.InitializeSettings()
    end

    if Settings and Settings.OpenToCategory and ns.SettingsCategory then
        local catID = ns.SettingsCategory.GetID and ns.SettingsCategory:GetID() or ns.SettingsCategory
        Settings.OpenToCategory(catID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory("MPlusAutoLFGOptionsPanel")
    end
end
