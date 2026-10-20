# MPlusAutoLFG - Development Backlog & Bug Tracker

This document tracks identified bugs, edge cases, and feature refinements to be addressed incrementally one by one.

---

## Active Backlog Items

### [x] Task 1: Fix Premade Groups Category Selection (Dungeons Tab Navigation)
* **Status:** Completed
* **Reported Behavior:** 
  Clicking "Start Queue" opens `LFGListFrame` and clicks "Start a Group", but only opens the Mythic+ dungeon creation form if the player had already manually clicked the **"Dungeons"** tab. If another category (e.g. Raids, Delves, Quests) was selected previously, it clicks "Start a Group" on whatever tab was preselected.
* **Investigation & Solution:**
  * In Blizzard's `Blizzard_LFGList` UI:
    * `CategoryButtons` contains the category buttons where Dungeons is Category `2` (`GROUP_FINDER_CATEGORY_ID_DUNGEONS`).
    * Blizzard's category selection and panel transitions are standard Lua (`LFGListCategorySelectionButton_OnClick`, `LFGListCategorySelection_SelectCategory`, `LFGListFrame_SetActivePanel`, `LFGListEntryCreationCancelButton_OnClick`), completely separate from protected C-functions like `C_LFGList.CreateListing`.
  * Implemented `SelectDungeonsCategoryAndStartGroup()`:
    1. If `LFGListFrame.EntryCreation` is open for a non-dungeon category, clicks `CancelButton` (or switches back to `CategorySelection`).
    2. If `LFGListFrame.SearchPanel` is open, clicks `BackButton` to return to `CategorySelection`.
    3. On `CategorySelection`, finds the button where `btn.categoryID == 2` and clicks it (falling back to `LFGListCategorySelection_SelectCategory`).
    4. Triggers `catSelection.StartGroupButton:Click()`.
    5. Blizzard automatically queries `C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()` and selects the keystone dungeon.
    6. Updated `SetDefaultListingPlaystyle()` to properly set `frame.generalPlaystyle = Enum.LFGEntryGeneralPlaystyle.FunRelaxed` (2), call `LFGListEntryCreation_OnPlayStyleSelectedInternal`, and update the dropdown widget and valid state so "Relaxed" is prefilled and the "List Group" button is ready to click.

---

### [x] Task 2: Remove Pause Queue Button & Simplify HUD Controls
* **Status:** Completed
* **Reported Behavior:**
  The "Pause Queue" button is unnecessary and clutters the interface. The addon only needs straightforward **Start Queue** and **Stop Queue / Delist** controls.
* **Changes Made:**
  1. Removed `f.pauseBtn` from [`UI.lua`](UI.lua).
  2. Resized `startBtn` to 312px width (`startBtn:SetSize(312, 24)`), centered at the bottom of the HUD window, matching `inviteBtn`.
  3. Removed the `PAUSED` state from [`Constants.lua`](Constants.lua), [`Core.lua`](Core.lua), [`UI.lua`](UI.lua), and [`README.md`](README.md).
  4. Removed the `/malfg pause` command and removed it from slash command help output.

---

### [x] Task 3: Real-Time Roster & Utility Requirement Updates on Leaver
* **Status:** Completed
* **Reported Behavior:**
  When a player leaves the group during assembly, the group requirements (Bloodlust, Combat Res, open slot counts) must immediately update on the HUD and re-evaluate the queue.
* **Changes Made:**
  1. Added member count change detection (`lastMemberCount`) in `Core:OnGroupRosterUpdated()`.
  2. If member count decreases, logs warning and immediately triggers `Core:UpdateUI()` to recalculate open slots, `BL [Need/Ready]`, and `CR [Need/Ready]`.
  3. Automatically triggers `Core:EvaluateQueue()` whenever member count is below 5 in active states (`LISTED` or `ASSEMBLING`), ensuring the queue selects a new FIFO applicant satisfying newly missing utility.
  4. Automatically transitions from `FULL` back to `ASSEMBLING` if a member leaves a full group before starting.

---

### [x] Task 4: Invite State Handling & Candidate Card Lock (Show "INVITED")
* **Status:** Completed
* **Reported Behavior:**
  Currently, clicking "CLICK TO INVITE" immediately clears or jumps. The addon should instead wait until the invitation is resolved (accepted, declined, or timed out). While waiting:
  * The candidate showcase card must remain locked on the invited candidate.
  * The button should show `INVITED` and be disabled.
  * Only after the candidate joins the group (`GROUP_ROSTER_UPDATE`) or declines/times out (`LFG_LIST_APPLICANT_UPDATED`) should the next qualified FIFO applicant be shown.
* **Changes Made:**
  1. Updated `UI:UpdateCandidateCard(candidate, isInvited)`: when `isInvited` is true, changes the button label to `"INVITED"` and disables it while keeping all candidate details locked in place.
  2. In `UI:OnInviteClicked`, immediately calls `UI:UpdateCandidateCard(candidate, true)` on successful invite dispatch.
  3. Added guard in `Core:EvaluateQueue()`: while an invitation is pending (`next(pendingInvites)`), evaluation holds off on showing new candidates.
  4. On `GROUP_ROSTER_UPDATE`: when the invited player joins the roster, `pendingInvites` clears, card resets, and queue evaluation resumes for the next slot.
  5. On `LFG_LIST_APPLICANT_UPDATED`: if declined, timed out, or cancelled, clears card and immediately re-evaluates the queue to find the next FIFO candidate.

---

### [x] Task 5: Replace Role Text (TANK/HEALER/DPS) with Spec Icons
* **Status:** Completed
* **Reported Behavior:**
  Instead of displaying raw text badges like `TANK`, `HEALER`, `DAMAGER`, display the candidate's specialization icon texture.
* **Changes Made:**
  1. Added `f.candSpecIcon` texture (20x20 with rounded Blizzard texcoord) in `candBox` in [`UI.lua`](UI.lua).
  2. Dynamically queries `GetSpecializationInfoByID(candidate.specID)` to set the spec icon texture.
  3. Formatted specialization text cleanly as `(Spec Class)` without raw role badges (`- TANK` / `- DAMAGER` / `- HEALER` removed).
  4. Automatically positions candidate name smoothly with or without icon, and clears icon on card reset.

---

### [x] Task 6: Replace Window Header Title with Addon Name
* **Status:** Completed
* **Reported Behavior:**
  The main HUD window title text currently displays `"Mythic+ Auto Matchmaker"`. It should be replaced with the official addon name (`"MPlusAutoLFG"`).
* **Changes Made:**
  1. Updated `f.TitleText:SetText(ns.ADDON_NAME or "MPlusAutoLFG")` in [`UI.lua`](UI.lua).

---

### [x] Task 7: Add 'List AutoLFG Group' Red Blizzard-Style Button to LFG Window
* **Status:** Completed
* **Reported Behavior / Feature Request:**
  Add a button near the Blizzard LFG window (positioned on top), styled as a simple red Blizzard-like button labeled `"List AutoLFG Group"`.
* **Changes Made:**
  1. Created `UI:CreateLFGTopButton()` in [`UI.lua`](UI.lua), parented directly to `PVEFrame` (the top-level Group Finder window).
  2. Anchored cleanly to the top-right border of the window (`BOTTOMRIGHT, PVEFrame, TOPRIGHT, -12, 1`) with dimensions `150x22`, using Blizzard's authentic `UIPanelButtonTemplate` (the classic red Blizzard panel button).
  3. Attached mouseover tooltip providing clear status inspection and guidance (`"Click to configure listing and start Mythic+ matchmaking. Pre-fills Playstyle (Relaxed) and required ilvl based on your keystone."`).
  4. Wired `OnClick` handler to invoke `Core:StartMatchmaking()` and display the AutoLFG HUD (`UI:Show()`), or toggle HUD visibility if already active.
  5. Handled Load-on-Demand (LoD) lifecycle in [`Core.lua`](Core.lua) and [`Services/LFGService.lua`](Services/LFGService.lua) via `ADDON_LOADED` (`Blizzard_GroupFinder`, `Blizzard_LFGList`, `Blizzard_PVEFrame`), `PLAYER_LOGIN`, and `OpenGroupFinder()`.
  6. Updated minimap button right-click handler to cleanly toggle start/stop queue matching the simplified FSM.

---

## Execution Order
We will address these one by one:
1. **Task 1:** Fix Premade Groups Category Selection (Dungeons Tab Navigation) - *Completed*.
2. **Task 2:** Remove Pause Queue Button & Simplify HUD Controls - *Completed*.
3. **Task 3:** Real-Time Roster & Utility Requirement Updates on Leaver - *Completed*.
4. **Task 4:** Invite State Handling & Candidate Card Lock (Show "INVITED") - *Completed*.
5. **Task 5:** Replace Role Text with Spec Icons - *Completed*.
6. **Task 6:** Replace Window Header Title with Addon Name - *Completed*.
7. **Task 7:** Add 'List AutoLFG Group' Red Blizzard-Style Button to LFG Window - *Completed*.
