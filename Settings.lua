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

    -- Section 1: Rules Mode (Default vs Custom)
    local modeHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeHeader:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, -14)
    modeHeader:SetText("Matchmaking Rules Mode")

    local modeDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeDesc:SetPoint("TOPLEFT", modeHeader, "BOTTOMLEFT", 0, -4)
    modeDesc:SetText("Choose between smart automated tiers or your own custom qualification rules:")

    local modeToggle = CreateCheckbox(panel, "Use Custom Rules (Enable sliders below)",
        "When unchecked, Default mode is active:\n* Keys +2 to +6: Open to all applicants.\n* Keys +7 to +11: Requires [Key - 2] completed.\n* Keys +12+: Requires [Key - 1] completed (timed).\n\nWhen checked, the custom sliders below are strictly enforced.",
        function() return (MPlusAutoLFGDB and MPlusAutoLFGDB.rulesMode) == "CUSTOM" end,
        function(val)
            if MPlusAutoLFGDB then
                MPlusAutoLFGDB.rulesMode = val and "CUSTOM" or "DEFAULT"
            end
            if ns.UI and ns.UI.UpdateModeButton then ns.UI:UpdateModeButton() end
            if ns.Core and ns.Core.EvaluateQueue then ns.Core:EvaluateQueue() end
        end
    )
    modeToggle:SetPoint("TOPLEFT", modeDesc, "BOTTOMLEFT", 0, -8)
    table.insert(widgets, modeToggle)

    -- Section 2: Custom Key Range Options
    local keyHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyHeader:SetPoint("TOPLEFT", modeToggle, "BOTTOMLEFT", 0, -20)
    keyHeader:SetText("Custom Key Level Qualification Rules")

    local keySlider = CreateSlider(panel, "Allowed Key Level Drop", 0, 5, 1,
        function() return (MPlusAutoLFGDB and MPlusAutoLFGDB.customRules and MPlusAutoLFGDB.customRules.keyDropTolerance) or 2 end,
        function(val)
            if MPlusAutoLFGDB and MPlusAutoLFGDB.customRules then
                MPlusAutoLFGDB.customRules.keyDropTolerance = val
            end
            if ns.Core and ns.Core.EvaluateQueue then ns.Core:EvaluateQueue() end
        end,
        function(val) return format("[Key - %d] (Min: +2)", val) end,
        "Specifies how many levels below the listed keystone a candidate's best run can be.\n\nExample for a +10 keystone:\n• Drop 0: Candidate must have timed a +10 or higher.\n• Drop 1: Candidate must have timed at least a +9.\n• Drop 2: Candidate must have timed at least a +8.\n\nNote: Timed runs are always required by default. Candidates with equal or higher keys for this dungeon always qualify."
    )
    keySlider:SetPoint("TOPLEFT", keyHeader, "BOTTOMLEFT", 0, -28)
    table.insert(widgets, keySlider)

    local uncompletedCheckbox = CreateCheckbox(panel, "Only applicants who haven't completed this dungeon",
        "When checked, only candidates who have NEVER completed this dungeon (best run level is 0) will qualify.\n\nIdeal for bonus crests, valorstone farming, or first-time rating gain groups.",
        function() return (MPlusAutoLFGDB and MPlusAutoLFGDB.customRules and MPlusAutoLFGDB.customRules.onlyUncompletedDungeon) == true end,
        function(val)
            if MPlusAutoLFGDB and MPlusAutoLFGDB.customRules then
                MPlusAutoLFGDB.customRules.onlyUncompletedDungeon = val
            end
            if ns.Core and ns.Core.EvaluateQueue then ns.Core:EvaluateQueue() end
        end
    )
    uncompletedCheckbox:SetPoint("TOPLEFT", keySlider, "BOTTOMLEFT", 0, -22)
    table.insert(widgets, uncompletedCheckbox)

    -- Section 3: Item Level Options
    local ilvlHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ilvlHeader:SetPoint("TOPLEFT", uncompletedCheckbox, "BOTTOMLEFT", 0, -20)
    ilvlHeader:SetText("Custom Item Level Requirements")

    local ilvlSlider = CreateSlider(panel, "Allowed Item Level Deficit", 0, 30, 1,
        function() return (MPlusAutoLFGDB and MPlusAutoLFGDB.customRules and MPlusAutoLFGDB.customRules.ilvlDeficit) or 10 end,
        function(val)
            if MPlusAutoLFGDB and MPlusAutoLFGDB.customRules then
                MPlusAutoLFGDB.customRules.ilvlDeficit = val
            end
            if ns.Core and ns.Core.EvaluateQueue then ns.Core:EvaluateQueue() end
        end,
        function(val) return format("-%d ilvl from recommendation", val) end,
        "Specifies how far below Blizzard's recommended minimum item level an applicant is allowed to be.\n\nExample for a dungeon recommending 610 ilvl:\n• Deficit 0: Must be 610+ ilvl.\n• Deficit 10: Candidates with 600+ ilvl qualify.\n• Deficit 20: Candidates with 590+ ilvl qualify."
    )
    ilvlSlider:SetPoint("TOPLEFT", ilvlHeader, "BOTTOMLEFT", 0, -28)
    table.insert(widgets, ilvlSlider)

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
