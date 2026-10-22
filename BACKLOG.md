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
  3. Automatically triggers `Core:EvaluateQueue()` whenever member count is below 5 in active states (`LISTED` or `ASSEMBLING`), ensuring the queue selects a new applicant satisfying newly missing utility.
  4. Automatically transitions from `FULL` back to `ASSEMBLING` if a member leaves a full group before starting.

---

### [x] Task 4: Invite State Handling & Candidate Card Lock (Show "INVITED")
* **Status:** Completed
* **Reported Behavior:**
  Currently, clicking "CLICK TO INVITE" immediately clears or jumps. The addon should instead wait until the invitation is resolved (accepted, declined, or timed out). While waiting:
  * The candidate showcase card must remain locked on the invited candidate.
  * The button should show `INVITED` and be disabled.
  * Only after the candidate joins the group (`GROUP_ROSTER_UPDATE`) or declines/times out (`LFG_LIST_APPLICANT_UPDATED`) should the next qualified applicant be shown.
* **Changes Made:**
  1. Updated `UI:UpdateCandidateCard(candidate, isInvited)`: when `isInvited` is true, changes the button label to `"INVITED"` and disables it while keeping all candidate details locked in place.
  2. In `UI:OnInviteClicked`, immediately calls `UI:UpdateCandidateCard(candidate, true)` on successful invite dispatch.
  3. Added guard in `Core:EvaluateQueue()`: while an invitation is pending (`next(pendingInvites)`), evaluation holds off on showing new candidates.
  4. On `GROUP_ROSTER_UPDATE`: when the invited player joins the roster, `pendingInvites` clears, card resets, and queue evaluation resumes for the next slot.
  5. On `LFG_LIST_APPLICANT_UPDATED`: if declined, timed out, or cancelled, clears card and immediately re-evaluates the queue to find the next candidate.

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

### [x] Task 8: Streamline HUD Actions - Unified Primary Button & Remove Delist
* **Status:** Completed
* **Reported Behavior / Feature Request:**
  1. Remove the "Start Queue" / "Stop Queue / Delist" button (`no 'delist' button as its not working`).
  2. Replace `"CLICK TO INVITE"` badge text with concise, standard `"Invite"`.
  3. Transform the primary action button into a unified contextual action:
     * When no group is listed (`IDLE` state): Displays **`"Open LFG Window"`** (enabled). Clicking it invokes `LFGService:OpenGroupFinder()`, opening the Premade Groups window and partially pre-filling the listing form (Category 2 Dungeons, Relaxed playstyle, keystone ilvl).
     * When group is listed / active (`LISTED`, `ASSEMBLING`):
       * Displays **`"Invite"`** (enabled) when a qualified candidate is present.
       * Displays **`"INVITED"`** (disabled) when an invitation is actively pending response.
       * Displays **`"Invite"`** (disabled) while awaiting qualified applicants.
  4. Refactor HUD bottom layout to cleanly host the single consolidated action button.
* **Changes Made:**
  1. Removed `startBtn` from [`UI.lua`](UI.lua).
  2. Consolidated bottom action into a single 322x30 button (`inviteBtn`).
  3. Wired dynamic contextual states: `"Open LFG Window"` when idle, `"Invite"` when candidate available, `"INVITED"` when invitation pending.
  4. Resized window from 310 to 296px height.

---

### [x] Task 9: HUD Window UI/UX Full Redesign
* **Status:** Completed
* **Goal:** Completely redesign the HUD interface to replace the outdated, clunky 2004-era stone dialog frame and tacky text dumps with a modern, sleek, ergonomic Dragonflight / The War Within (TWW) Mythic+ matchmaking HUD.
* **Changes Made:**
  1. Replaced `BasicFrameTemplateWithInset` and `InsetFrameTemplate` with a modern dark slate canvas (`Color(0.08, 0.08, 0.10, 0.95)`), flat header bar (`Color(0.05, 0.05, 0.07, 0.95)`), and razor-sharp 1px slate borders (`Color(0.22, 0.22, 0.26)`).
  2. Eliminated tacky `Utilities (4 open): BL [Need] • CR [Need]` text strings completely.
  3. Built an interactive **5-Slot Visual Party Roster** (`[Tank] [Healer] [DPS 1] [DPS 2] [DPS 3]`) using native Blizzard role icons:
     * When slot is filled: Displays full brightness with class-colored border and member tooltip.
     * When slot is open: Displays desaturated silhouette with open role tooltip.
  4. Redesigned candidate showcase card into a modern dark card panel with score tier colorization (`C_ChallengeMode.GetDungeonScoreRarityColor`), 28x28 spec icon, class-colored candidate name, and clean stat typography.
  5. Sized window compactly to 350x296 with centered 322x30 unified action button.

---

### [x] Task 10: Modern Blizzlike Overhaul, Rules Modes, Options Menu & Guards
* **Status:** Completed
* **Reported Requests:**
  1. Replace Unicode bullet `●` with a circular indicator texture (`Interface\Common\Indicator-Green`, `Yellow`, `Gray`, `Red`) because `●` renders as a missing glyph box in localized/custom fonts.
  2. Remove the clunky boxed roles block. Just draw 5 clean role icons side by side (`Tank`, `Healer`, `DPS`, `DPS`, `DPS`), full brightness when present, desaturated (alpha 0.35) when missing.
  3. Just write simple colored text for utilities: `BL` (green if ready, red if missing) and `CR` (green if ready, red if missing) without square red boxes or borders.
  4. Remove the word "FIFO" across all UI labels, comments, and documentation (`NEXT QUALIFIED APPLICANT`).
  5. Add an AddOn Options Menu in Blizzard's native Settings panel (`Settings.RegisterCanvasLayoutCategory` / `/aiko`-style options in `Game Menu -> Options -> AddOns -> MPlusAutoLFG`):
     - Sliders: Allowed Key Level Drop `[Key - X]` (0 to 5, default 2, clamped to min +2); Allowed Item Level Deficit (0 to 30, default 10).
     - Checkboxes: Require Timed Run (ignore depleted runs); Require Candidate ilvl >= Party Leader ilvl.
  6. Add HUD Mode Switcher button (`Default` vs `Custom Rules`) with an `[Options]` shortcut button.
  7. Party Leader & Mismatch Guards:
     - If not party leader: disable controls, show amber warning (`"Only party leader can manage matchmaking"`), handle `PARTY_LEADER_CHANGED` / `GROUP_ROSTER_UPDATE`.
     - If active listing in LFG differs from player's bag keystone: disable controls, show red warning (`"Listing Mismatch: Listed key != Bag key"`).
  8. Auto-Sync Active Listing: when a group is already listed in Premade Groups upon login or opening the HUD, automatically attach to it, sync keystone and dungeon details, and begin queue evaluation.
* **Changes Made:**
  1. Created [`Settings.lua`](Settings.lua) and registered it in [`MPlusAutoLFG.toc`](MPlusAutoLFG.toc).
  2. Implemented `LFGService:GetActiveListingDetails()` in [`Services/LFGService.lua`](Services/LFGService.lua).
  3. Updated `ns.CheckItemLevel` and `ns.CheckExperience` in [`Validation.lua`](Validation.lua) to support both `DEFAULT` and `CUSTOM` modes.
  4. Updated [`Core.lua`](Core.lua) with leader checking, mismatch detection, auto-syncing, and slash commands (`/malfg config`, `/malfg mode`).
  5. Completely rewrote [`UI.lua`](UI.lua) with native circular indicator textures, unboxed 5-slot role display, clean text BL/CR, rules mode switcher, options shortcut, warning banner, and safety guards.
  6. Verified 100% Lua 5.1 AST syntax validity with `luaparse` across all files.

---

### [x] Task 11: Real-Time Cancelled Applicant Eviction & Freshness Guards
* **Status:** Completed
* **Reported Behavior:**
  An applicant ("Соланс") whose application had been cancelled in Blizzard's Premade Groups window (`Canceled` in red) was still displayed on the `MPlusAutoLFG` HUD card as "NEXT QUALIFIED APPLICANT" with an active "Invite" button.
* **Root Cause:**
  1. `Core:OnApplicantUpdated(applicantID)` only processed candidates present in `pendingInvites`. When a showcased candidate who had not yet been invited cancelled, the event was ignored.
  2. `Core:EvaluateQueue()` accepted `appInfo.applicationStatus == "none"` in addition to `"applied"`.
  3. The 1.0s periodic ticker in `Core.lua` only called `Core:UpdateUI()`, never validating candidate freshness or re-evaluating the queue.
  4. `UI:OnInviteClicked` lacked a pre-flight status check before sending hardware invites.
* **Changes Made:**
  1. In `Core:OnApplicantUpdated`: added check for `currentTopCandidate`. If the updated applicant is currently showcased and their status is no longer `"applied"`, immediately clears `currentTopCandidate`, clears the card (`ns.UI:ClearCandidateCard()`), re-evaluates the queue, and refreshes the UI.
  2. In `Core:EvaluateQueue()`: strictly enforces `appInfo.applicationStatus == "applied"` and `not appInfo.isStale`, and skips any applicant with `pendingApplicationStatus == "cancelled" / "declined" / "timedout"`.
  3. In `Core.lua` periodic ticker: every 1.0s, checks if `currentTopCandidate` is still active (`"applied"` and not stale); if not, immediately clears and re-evaluates. If no candidate is showcased, re-evaluates the queue.
  4. In `UI:OnInviteClicked`: added real-time pre-flight validation preventing invites to candidates who are no longer active.
  5. Verified all Lua files pass Lua 5.1 AST syntax checks via `luaparse`.

---

### [x] Task 12: Comprehensive Bug & Corner Case Audit
* **Status:** Completed
* **Investigation & Fixes:**
  1. **Leader Item Level Field Name Mismatch**: `Validation.lua` looked for `rosterContext.leaderItemLevel`, but `Core:GetRosterContext()` returned `leaderIlvl`. The checkbox rule "Require Candidate ilvl >= Party Leader ilvl" never triggered because `leaderIlvl` evaluated to 0. Fixed by providing both `leaderIlvl` and `leaderItemLevel` in `Core:GetRosterContext()`, and checking both in `Validation.lua`.
  2. **Spec Name & Spec Icon Unpopulated**: `candidate.specName` and `candidate.specIcon` were never populated by `GetApplicantMemberInfo()`, causing the HUD candidate card to never show the spec icon and only display generic class names (`Mage` instead of `Fire Mage`). Fixed by resolving `specName` and `specIcon` from `GetSpecializationInfoByID(specID)` and `ns.Specializations`.
  3. **Multi-Member Applicant Groups (`numMembers > 1`)**: In solo queue matchmaking, inviting an applicant group only inspected member 1, and could invite 2–3 players at once, exceeding 5-man party limits and admitting unvalidated members. Fixed by guarding in `Core:EvaluateQueue()`: skip applicants if `numMembers > openSlots` or `numMembers > 1`.
  4. **Leader Spec Omitted from Duplicate Check**: `Core:GetRosterContext()` never added the player's own specialization to `rosterContext.specs`. On key levels < 15, duplicate spec checks permitted candidates with the same spec as the party leader. Fixed by adding player's active specialization from `GetSpecializationInfo(GetSpecialization())` to `specs`.
  5. **Raid Group State Handling (`IsInRaid()`)**: In a raid group, `UnitExists("party1")` fails, throwing off slot counts, and keystones cannot be slotted in raids. Fixed by guarding against `IsInRaid()` in `Core:IsLeader()`, `Core:EvaluateQueue()`, `UI:UpdateHeader()`, and `UI:OnInviteClicked()`, displaying a dedicated warning banner `"In Raid Group: Convert to 5-man Party"`.
  6. **Active Listing Manual Edit Synchronization**: When a leader edited their listing in Premade Groups while matchmaking was active, `Core:OnActiveEntryUpdated()` skipped `RefreshKeystoneInfo()` because state was not `IDLE`. Fixed by always calling `self:RefreshKeystoneInfo()` whenever an active entry update fires.
  7. **SavedVariables Deep Merge**: Shallow merge in `ADDON_LOADED` didn't populate missing nested keys in `customRules` from older versions and shared table references with `DefaultConfig`. Fixed by implementing recursive deep copy and merge in `Core.lua`.
  8. **Bag Keystone Map ID Lookup when `C_MythicPlus` returns 0**: If `C_MythicPlus.GetOwnedKeystoneChallengeMapID()` returned 0 before a dungeon run, `challengeMapID` stayed 0 even if `activityID` was known. Fixed by adding reverse lookup from `C_LFGList.GetActivityInfoTable(activityID)` to resolve map ID and dungeon name.

---

## Execution Order
All tasks 1 through 12 are completed and validated.
