# MPlusAutoLFG - Development Backlog & Bug Tracker

This document tracks identified bugs, edge cases, and feature refinements to be addressed incrementally one by one.

---

## Active Backlog Items

### [ ] Task 1: Fix Premade Groups Category Selection (Dungeons Tab Navigation)
* **Reported Behavior:** 
  Clicking "Start Queue" opens `LFGListFrame` and clicks "Start a Group", but only opens the Mythic+ dungeon creation form if the player had already manually clicked the **"Dungeons"** tab. If another category (e.g. Raids, Delves, Quests) was selected previously, it clicks "Start a Group" on whatever tab was preselected.
* **Investigation & Technical Details:**
  * In Blizzard's `Blizzard_LFGList` UI:
    * `LFGListFrame.CategorySelection` lists available categories via `CategoryButtons` (`1` = Quests, `2` = Dungeons, `3` = Raids, `4` = Arena, `114` = Delves).
    * Category selection is managed by `LFGListCategorySelection_SelectCategory(LFGListFrame.CategorySelection, 2, 0)`.
    * Alternatively, each button in `LFGListFrame.CategorySelection.CategoryButtons` has `.categoryID == 2`. Calling `btn:Click()` selects Dungeons natively.
    * In `LFGListFrame.EntryCreation`, activity selection can be mapped directly to the keystone's `activityID` via `C_LFGList.GetActivityInfoTable(activityID)` or `LFGListEntryCreation_Select(LFGListFrame.EntryCreation, nil, nil, nil, activityID)` if not tainted.
* **Action Items:**
  1. Inspect `LFGListFrame.CategorySelection` when opening the group finder.
  2. Explicitly select Category `2` (`LFGListCategorySelection_SelectCategory` or clicking the Dungeons button) before triggering `StartGroupButton:Click()`.
  3. Verify whether selecting the category causes taint or if simulating the native button click is untainted.

---

### [ ] Task 2: Remove Pause Queue Button & Simplify HUD Controls
* **Reported Behavior:**
  The "Pause Queue" button is unnecessary and clutters the interface. The addon only needs straightforward **Start Queue** and **Stop Queue / Delist** controls.
* **Action Items:**
  1. Remove `f.pauseBtn` from [`UI.lua`](UI.lua).
  2. Expand `startBtn` to span the full bottom row width (or center it cleanly with standard Blizzard `UIPanelButtonTemplate` sizing).
  3. Remove the `PAUSED` state from [`Constants.lua`](Constants.lua) and [`Core.lua`](Core.lua) (or simplify FSM to `IDLE`, `LISTED`, `ASSEMBLING`, `FULL`).
  4. Remove `/malfg pause` slash command and clean up help text.

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

## Execution Order
We will address these one by one:
1. **Task 1:** Fix Premade Groups Category Selection (Dungeons Tab Navigation).
2. **Task 2:** Remove Pause Queue Button & Simplify HUD Controls.
3. **Task 3:** Real-Time Roster & Utility Requirement Updates on Leaver.
4. **Task 4:** Invite State Handling & Candidate Card Lock (Show "INVITED").
5. **Task 5:** Replace Role Text with Spec Icons.
