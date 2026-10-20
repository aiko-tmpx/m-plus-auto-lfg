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

### [ ] Task 3: Real-Time Roster & Utility Requirement Updates on Leaver
* **Reported Behavior:**
  When a player leaves the group during assembly, the group requirements (Bloodlust, Combat Res, open slot counts) must immediately update on the HUD and re-evaluate the queue.
* **Technical Details:**
  * When `GROUP_ROSTER_UPDATE` fires or when someone drops:
    * Rescan current party members via `GetNumGroupMembers()`, `UnitClass`, `UnitGroupRolesAssigned`.
    * Recompute `hasBL`, `hasCR`, and remaining open slots.
    * Update `f.utilText` on the HUD immediately to reflect changes (e.g. `BL [Need]`, `CR [Ready]`, `(2 open)`).
    * Re-run `Core:EvaluateQueue()` so the FIFO candidate pipeline adapts to the freed slot and missing utility requirements.
* **Action Items:**
  1. Ensure `Core:OnGroupRosterUpdated()` calls `Core:UpdateUI()` immediately upon any member count reduction.
  2. Verify that leavers release their reserved utility flags and role slots instantly.
  3. Trigger queue re-evaluation without requiring manual intervention.

---

### [ ] Task 4: Invite State Handling & Candidate Card Lock (Show "INVITED")
* **Reported Behavior:**
  Currently, clicking "CLICK TO INVITE" immediately clears or jumps. The addon should instead wait until the invitation is resolved (accepted, declined, or timed out). While waiting:
  * The candidate showcase card must remain locked on the invited candidate.
  * The button should show `INVITED` (or `INVITED - AWAITING RESPONSE`) and be disabled.
  * Only after the candidate joins the group (`GROUP_ROSTER_UPDATE`) or declines/times out (`LFG_LIST_APPLICANT_UPDATED`) should the next qualified FIFO applicant be shown.
* **Action Items:**
  1. Add an `isInvited` state to `UI:UpdateCandidateCard(candidate, isInvited)`.
  2. When "CLICK TO INVITE" is pressed:
     - Set button text to `"INVITED"` and disable it.
     - Keep candidate name, spec icon, and details visible on the card.
  3. Listen to `LFG_LIST_APPLICANT_UPDATED` and `GROUP_ROSTER_UPDATE`:
     - If candidate joins (`inviteaccepted` / roster member match): clear card, trigger next queue evaluation.
     - If candidate declines / times out (`declined` / `timedout`): log warning, release slot, evaluate next FIFO candidate.

---

### [ ] Task 5: Replace Role Text (TANK/HEALER/DPS) with Spec Icons
* **Reported Behavior:**
  Instead of displaying raw text badges like `TANK`, `HEALER`, `DAMAGER`, display the candidate's specialization icon texture.
* **Technical Details:**
  * `GetSpecializationInfoByID(specID)` returns `id, name, description, icon, role, primaryStat`.
  * Candidate info table in `LFGService:GetApplicantMemberInfo` contains `specID`.
  * If `specID` is valid (> 0), retrieve its icon: `local _, _, _, specIcon = GetSpecializationInfoByID(specID)`.
  * Render this icon next to the candidate's name or on a dedicated spec icon texture widget in `candBox`.
* **Action Items:**
  1. Add a dedicated `specIcon` texture widget to `candBox` in [`UI.lua`](UI.lua).
  2. In `UI:UpdateCandidateCard(candidate)`, look up the specialization icon and set it on the texture.
  3. Remove redundant text role indicators.

---

### [ ] Task 6: Replace Window Header Title with Addon Name
* **Reported Behavior:**
  The main HUD window title text currently displays `"Mythic+ Auto Matchmaker"`. It should be replaced with the official addon name (`"MPlusAutoLFG"`).
* **Technical Details:**
  * In `UI.lua`, line 63 sets `f.TitleText:SetText("Mythic+ Auto Matchmaker")`.
* **Action Items:**
  1. In [`UI.lua`](UI.lua), update `f.TitleText:SetText("MPlusAutoLFG")` (or use `addonName`).

---

### [ ] Task 7: Add 'List AutoLFG Group' Red Blizzard-Style Button to LFG Window
* **Reported Behavior / Feature Request:**
  Add a button near the Blizzard LFG window (positioned on top), styled as a simple red Blizzard-like button labeled `"List AutoLFG Group"`.
* **Technical Details:**
  * Target parent: `LFGListFrame` / `PVEFrame` (anchored to top/top-right of the window).
  * Visual style: Blizzard `UIPanelButtonTemplate` with red accent styling / text.
  * Functionality: Provides quick one-click access directly from the native Blizzard Group Finder frame to start the MPlusAutoLFG workflow.
* **Action Items:**
  1. Create and anchor the button to `LFGListFrame` (or `PVEFrame`).
  2. Apply Blizzard-authentic red styling and text `"List AutoLFG Group"`.
  3. Hook button `OnClick` to invoke `Core:StartMatchmaking()`.
  4. Ensure button visibility toggles appropriately with `LFGListFrame` / `PVEFrame`.

---

## Execution Order
We will address these one by one:
1. **Task 1:** Fix Premade Groups Category Selection (Dungeons Tab Navigation) - *Completed*.
2. **Task 2:** Remove Pause Queue Button & Simplify HUD Controls.
3. **Task 3:** Real-Time Roster & Utility Requirement Updates on Leaver.
4. **Task 4:** Invite State Handling & Candidate Card Lock (Show "INVITED").
5. **Task 5:** Replace Role Text with Spec Icons.
6. **Task 6:** Replace Window Header Title with Addon Name.
7. **Task 7:** Add 'List AutoLFG Group' Red Blizzard-Style Button to LFG Window.
