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
local pcall = pcall

local PREFIX = "|cffff00ff[MPlus-PROBE]|r"

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
local function RunParserSuite(rawTitle)
    local results = {}

    local titleStr = tostring(rawTitle or "")
    local titleLen = #titleStr
    local hexDump = StringToHex(titleStr)

    -- Method 1: Raw Direct Pattern (%+ *(%d+) and (%d+) *%+)
    local m1 = titleStr:match("%+%s*(%d+)") or titleStr:match("(%d+)%s*%+")
    results["1. Raw Pattern"] = m1 and tonumber(m1) or "nil"

    -- Method 2: Stripped Blizzard UI Markup (|c, |r, |H, |T, |A)
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
        -- e.g. "+2" or "2+"
        local num = token:match("^%+(%d+)$") or token:match("^(%d+)%+$")
        if num then
            m3 = tonumber(num)
            break
        end
        -- e.g. "+" followed by "2" in next token
        if token == "+" and tokens[idx + 1] and tokens[idx + 1]:match("^%d+$") then
            m3 = tonumber(tokens[idx + 1])
            break
        end
    end
    results["3. Token-Split"] = m3 or "nil"

    -- Method 4: Scan ALL numbers found in the entire string
    local allNums = {}
    for n in titleStr:gmatch("(%d+)") do
        table.insert(allNums, tonumber(n))
    end
    results["4. All Digits In Title"] = #allNums > 0 and table.concat(allNums, ", ") or "none"

    -- Method 5: Sanitize Unicode / Non-ASCII (replace non-ASCII bytes > 127)
    local asciiOnly = titleStr:gsub("[\128-\255]", " ")
    local m5 = asciiOnly:match("%+%s*(%d+)") or asciiOnly:match("(%d+)%s*%+")
    results["5. Non-ASCII Stripped"] = m5 and tonumber(m5) or "nil"

    return {
        raw = titleStr,
        len = titleLen,
        hex = hexDump,
        results = results,
    }
end

-------------------------------------------------------------------------------
-- Print Diagnostics to Chat
-------------------------------------------------------------------------------
local function PrintReport(sourceTag, suiteResult, extraInfo)
    print(string.format("%s ================= %s =================", PREFIX, sourceTag))
    print(string.format("%s |cffffff00Raw Title:|r '%s' (len: %d bytes)", PREFIX, suiteResult.raw, suiteResult.len))
    print(string.format("%s |cffaaaaaaHex Bytes:|r %s", PREFIX, suiteResult.hex))

    if extraInfo then
        for k, v in pairs(extraInfo) do
            print(string.format("%s |cff00b4ff%s:|r %s", PREFIX, k, tostring(v)))
        end
    end

    print(string.format("%s |cff00ff00Parsing Methods Comparison:|r", PREFIX))
    for name, val in pairs(suiteResult.results) do
        print(string.format("%s   * %s: |cffffffff%s|r", PREFIX, name, tostring(val)))
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
            ["activityID"] = entryInfo.activityID or "nil",
            ["comment"] = entryInfo.comment ~= "" and entryInfo.comment or "(empty)",
            ["requiredItemLevel"] = entryInfo.requiredItemLevel or 0,
            ["duration"] = entryInfo.duration or 0,
            ["autoAccept"] = tostring(entryInfo.autoAccept),
            ["privateGroup"] = tostring(entryInfo.privateGroup),
        }

        -- Also probe Blizzard's live EditBox if the EntryCreation UI is visible
        if LFGListFrame and LFGListFrame.EntryCreation and LFGListFrame.EntryCreation.Name then
            local editBoxText = LFGListFrame.EntryCreation.Name:GetText()
            extra["UI EditBox.Name"] = string.format("'%s'", tostring(editBoxText or ""))
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

print(string.format("%s Standalone Debug Watcher loaded. Queuing in LFG will dump raw titles & 5 parser methods. Type |cff00ff00/malfgtest <text>|r to test any string manually.", PREFIX))
