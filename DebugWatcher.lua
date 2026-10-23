--[[
    MPlusAutoLFG - Standalone Deep Diagnostics & Parser Watcher
    File: DebugWatcher.lua
    Purpose: Isolated diagnostic probe that logs all LFG events, raw title payloads,
             byte-level representations, and evaluates multiple parsing algorithms simultaneously.
             Does NOT alter or touch core addon tables or logic.
]]

local addonName, ns = ...

local print = print
local string = string
local tostring = tostring
local tonumber = tonumber
local type = type
local table = table
local ipairs = ipairs
local pairs = pairs
local pcall = pcall

local PREFIX = "|cffff00ff[MPlus-PROBE]|r"

-------------------------------------------------------------------------------
-- Hidden Widgets for C-String Token Resolution
-------------------------------------------------------------------------------
local hiddenEditBox = CreateFrame("EditBox")
hiddenEditBox:Hide()

local hiddenFontString = UIParent:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
hiddenFontString:Hide()

-------------------------------------------------------------------------------
-- Helper: Hex / Byte Representation
-------------------------------------------------------------------------------
local function StringToHex(str)
    if not str or type(str) ~= "string" then return "nil" end
    local bytes = {}
    for i = 1, math.min(#str, 64) do
        table.insert(bytes, string.format("%02X", string.byte(str, i)))
    end
    if #str > 64 then
        table.insert(bytes, "..")
    end
    return table.concat(bytes, " ")
end

-------------------------------------------------------------------------------
-- Multi-Method Parsing Suite
-------------------------------------------------------------------------------
local function ParseSingleString(titleStr)
    local results = {}
    titleStr = tostring(titleStr or "")

    -- Method 1: Raw Direct Pattern (%+ *(%d+) and (%d+) *%+)
    local m1 = titleStr:match("%+%s*(%d+)") or titleStr:match("(%d+)%s*%+")
    results["1. Raw Pattern"] = m1 and tonumber(m1) or "nil"

    -- Method 2: Stripped Blizzard UI Markup (|c, |r, |H, |T, |A, |K)
    local clean2 = titleStr:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    clean2 = clean2:gsub("|H.-|h(.-)|h", "%1")
    clean2 = clean2:gsub("|T.-|t", "")
    clean2 = clean2:gsub("|A.-|a", "")
    local m2 = clean2:match("%+%s*(%d+)") or clean2:match("(%d+)%s*%+")
    results["2. Markup-Stripped"] = m2 and tonumber(m2) or "nil"

    -- Method 3: Whitespace Token Split (look for "+2", "2+", "+ 2")
    local tokens = {}
    for token in titleStr:gmatch("%S+") do
        table.insert(tokens, token)
    end
    local m3 = nil
    for idx, token in ipairs(tokens) do
        local num = token:match("^%+(%d+)$") or token:match("^(%d+)%+$")
        if num then
            m3 = tonumber(num)
            break
        end
        if token == "+" and tokens[idx + 1] and tokens[idx + 1]:match("^%d+$") then
            m3 = tonumber(tokens[idx + 1])
            break
        end
    end
    results["3. Token-Split"] = m3 or "nil"

    -- Method 4: Scan ALL numbers found in the string
    local allNums = {}
    for n in titleStr:gmatch("(%d+)") do
        table.insert(allNums, tonumber(n))
    end
    results["4. All Digits"] = #allNums > 0 and table.concat(allNums, ", ") or "none"

    return results
end

local function RunParserSuite(rawTitle)
    local titleStr = tostring(rawTitle or "")
    local titleLen = #titleStr
    local hexDump = StringToHex(titleStr)

    -- Attempt decoding through Hidden EditBox
    local editBoxDecoded = nil
    pcall(function()
        hiddenEditBox:SetText(titleStr)
        editBoxDecoded = hiddenEditBox:GetText()
    end)

    -- Attempt decoding through Hidden FontString
    local fsDecoded = nil
    pcall(function()
        hiddenFontString:SetText(titleStr)
        fsDecoded = hiddenFontString:GetText()
    end)

    return {
        raw = titleStr,
        len = titleLen,
        hex = hexDump,
        editBoxDecoded = editBoxDecoded,
        fsDecoded = fsDecoded,
        rawResults = ParseSingleString(titleStr),
        editBoxResults = editBoxDecoded and ParseSingleString(editBoxDecoded) or nil,
    }
end

-------------------------------------------------------------------------------
-- Print Diagnostics to Chat
-------------------------------------------------------------------------------
local function PrintReport(sourceTag, suiteResult, extraInfo)
    print(string.format("%s ================= %s =================", PREFIX, sourceTag))
    print(string.format("%s |cffffff00Raw Title:|r '%s' (len: %d bytes)", PREFIX, suiteResult.raw, suiteResult.len))
    print(string.format("%s |cffaaaaaaHex Bytes:|r %s", PREFIX, suiteResult.hex))

    -- Print Decoded Probe Results
    if suiteResult.editBoxDecoded then
        local ebHex = StringToHex(suiteResult.editBoxDecoded)
        print(string.format("%s |cff00ff00[RESOLVER] Hidden EditBox:|r '%s' (len: %d, hex: %s)",
            PREFIX, suiteResult.editBoxDecoded, #suiteResult.editBoxDecoded, ebHex))
    end
    if suiteResult.fsDecoded then
        local fsHex = StringToHex(suiteResult.fsDecoded)
        print(string.format("%s |cff00ff00[RESOLVER] Hidden FontString:|r '%s' (len: %d, hex: %s)",
            PREFIX, suiteResult.fsDecoded, #suiteResult.fsDecoded, fsHex))
    end

    if extraInfo then
        for k, v in pairs(extraInfo) do
            print(string.format("%s |cff00b4ff%s:|r %s", PREFIX, k, tostring(v)))
        end
    end

    print(string.format("%s |cffff8800Raw Parsing Results:|r", PREFIX))
    for name, val in pairs(suiteResult.rawResults) do
        print(string.format("%s   * %s: |cffffffff%s|r", PREFIX, name, tostring(val)))
    end

    if suiteResult.editBoxResults then
        print(string.format("%s |cff00ff00EditBox-Decoded Parsing Results:|r", PREFIX))
        for name, val in pairs(suiteResult.editBoxResults) do
            print(string.format("%s   * %s: |cffffffff%s|r", PREFIX, name, tostring(val)))
        end
    end

    print(string.format("%s ==================================================", PREFIX))
end

-------------------------------------------------------------------------------
-- Isolated Event Probe Frame
-------------------------------------------------------------------------------
local probeFrame = CreateFrame("Frame", "MPlusAutoLFG_DebugWatcherFrame")
probeFrame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
probeFrame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_SLOTTED")

probeFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        local hasEntry = C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()
        if not hasEntry then
            return
        end

        local entryInfo = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
        if not entryInfo then
            print(string.format("%s Event: %s | HasActiveEntry=true, but entryInfo is nil!", PREFIX, event))
            return
        end

        local groupTitle = entryInfo.name or ""
        local extra = {
            ["requiredItemLevel"] = entryInfo.requiredItemLevel or 0,
            ["duration"] = entryInfo.duration or 0,
            ["activityID"] = entryInfo.activityID or "nil",
        }

        if entryInfo.activityIDs and #entryInfo.activityIDs > 0 then
            extra["activityIDs[1]"] = entryInfo.activityIDs[1]
        end

        -- Check live Blizzard EditBox
        if LFGListFrame and LFGListFrame.EntryCreation and LFGListFrame.EntryCreation.Name then
            local ebText = LFGListFrame.EntryCreation.Name:GetText()
            extra["Live Blizzard EditBox.Name"] = string.format("'%s' (hex: %s)", tostring(ebText or ""), StringToHex(ebText or ""))
        end

        -- Check live Blizzard ApplicationViewer header
        if LFGListFrame and LFGListFrame.ApplicationViewer then
            local viewer = LFGListFrame.ApplicationViewer
            if viewer.EntryName and viewer.EntryName.GetText then
                local vn = viewer.EntryName:GetText()
                extra["ApplicationViewer.EntryName"] = string.format("'%s' (hex: %s)", tostring(vn or ""), StringToHex(vn or ""))
            end
            if viewer.Name and viewer.Name.GetText then
                local vn = viewer.Name:GetText()
                extra["ApplicationViewer.Name"] = string.format("'%s' (hex: %s)", tostring(vn or ""), StringToHex(vn or ""))
            end
        end

        local report = RunParserSuite(groupTitle)
        PrintReport(event, report, extra)

    elseif event == "CHALLENGE_MODE_KEYSTONE_SLOTTED" then
        print(string.format("%s Event: %s fired (Keystone placed in font)", PREFIX, event))
    end
end)

-------------------------------------------------------------------------------
-- Manual Testing Slash Command: /malfgtest <any text>
-------------------------------------------------------------------------------
SLASH_MALFGTEST1 = "/malfgtest"
SLASH_MALFGTEST2 = "/malfgparse"
SlashCmdList["MALFGTEST"] = function(msg)
    msg = msg or ""
    local suite = RunParserSuite(msg)
    PrintReport("MANUAL /malfgtest PROBE", suite, {
        ["Input Length"] = #msg,
    })
end

print(string.format("%s Standalone Debug Watcher v2 loaded. Type |cff00ff00/malfgtest <text>|r to test any string manually.", PREFIX))
