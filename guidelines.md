# MPlusAutoLFG - Engineering Guidelines & Architectural Reference

This document serves as the persistent architectural reference, source-of-truth guide, and engineering manual for the `MPlusAutoLFG` codebase.

---

## 1. Primary Source of Truth: `Gethe/wow-ui-source`

All implementation decisions, UI template usages, FrameXML interactions, and Blizzard API signatures in this project are anchored to the official extracted World of Warcraft interface source code mirrored at:

* **Repository:** [https://github.com/Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source)
* **Primary Target Branch:** `live` (Modern Retail / The War Within / Midnight)

### Key Files in `wow-ui-source` for this Project
1. **`Interface/FrameXML/LFGList.lua` & `LFGList.xml`**:
   - Manages Premade Groups (`LFGListFrame`).
   - `LFGListFrame.CategorySelection`: Category buttons (`1` = Quests, `2` = Dungeons, `3` = Raids, `4` = Arena, `114` = Delves), `LFGListCategorySelection_SelectCategory(self, categoryID, baseFilter)`, and `LFGListCategorySelectionStartGroupButton_OnClick(self)`.
   - `LFGListFrame.EntryCreation`: Listing creation dialog containing `self.Name` (Title), `self.Description.EditBox`, `self.ItemLevel.EditBox`, `self.selectedPlaystyle`, and `self.PlayStyleDropdown`.
   - `LFGListFrame.ApplicationViewer`: Applicant queue management and applicant row invite triggers.
2. **`Interface/FrameXML/PVEFrame.lua` & `PVEFrame.xml`**:
   - Core PvE frame container (`PVEFrame`), `GroupFinderFrame`, and `PVEFrame_ShowFrame(sideFrameName, selectionFrame)`.
   - **Critical Rule:** `selectionFrame` must be a frame object (e.g. `_G["LFGListPVEStub"]`), never a string.
3. **`Interface/FrameXML/SecureTemplates.lua`**:
   - Implementation of `SecureActionButtonTemplate`.
   - **Critical Rule:** General UI buttons (like Start Queue, Toggle, Delist) must NEVER inherit `SecureActionButtonTemplate`. Inheriting it without setting explicit secure attributes (`type`, `macrotext`) causes Blizzard's secure click handler to swallow user input and ignore `SetScript("OnClick")`.
4. **`Interface/AddOns/Blizzard_APIDocumentationGenerated/`**:
   - Machine-generated documentation of C-APIs: `C_LFGList`, `C_MythicPlus`, and `C_ChallengeMode`.
5. **Modern Dropdown & Menu Architecture**:
   - Dropdown elements in modern retail utilize `WowStyle1DropdownTemplate` and `MenuUtil` / `DropdownButton`. Methods like `:SetSelectedValue()`, `:SetSelection()`, and `:SetText()` update dropdown states.

---

## 2. Blizzard Security Model & Protected APIs

Blizzard enforces strict boundaries on Premade Groups (`C_LFGList`) to combat automated listing spam:

### Forbidden Addon Calls (Instant `ADDON_ACTION_BLOCKED`)
* `C_LFGList.CreateListing(...)`: Protected C-function. Calling it directly from third-party addon code throws `ADDON_ACTION_BLOCKED: AddOn 'MPlusAutoLFG' tried to call the protected function 'UNKNOWN()'`.
* `C_LFGList.RemoveListing()`: Protected C-function. Cannot be called programmatically by third-party addons without secure execution.
* `C_LFGList.ClearCreationTextFields()` & `C_LFGList.SetEntryTitle(...)`: Tainted C-helpers.

### Compliant Listing Workflow
1. When starting matchmaking:
   - Check `C_LFGList.HasActiveEntryInfo()`. If the group is already listed, attach immediately.
   - If not listed, open Blizzard's native Group Finder (`LFGListUtil_OpenBestWindow` / `PVEFrame_ShowFrame("GroupFinderFrame", _G["LFGListPVEStub"])`).
   - Automatically select Category 2 (Dungeons) and navigate to `LFGListFrame.EntryCreation`.
   - Pre-populate Title, recommended Item Level, and enforce Playstyle "Relaxed" (`selectedPlaystyle = 2`).
   - The user clicks Blizzard's native "List Group" button (untainted execution).
2. Listen to `LFG_LIST_ACTIVE_ENTRY_UPDATE`:
   - The moment the listing goes live, `MPlusAutoLFG` detects it, starts the queue stopwatch, and begins automated FIFO candidate evaluation.

### Hardware-Protected Invitations
* `C_LFGList.InviteApplicant(applicantID)` is protected and requires an explicit hardware event.
* The addon provides a dedicated native button (`MPlusAutoLFGInviteButton`) inheriting `SecureActionButtonTemplate` and `UIPanelButtonTemplate`, registered for mouse clicks (`LeftButtonUp`) with no keybind exploits.

---

## 3. UI Guidelines & Blizzard-Native Aesthetic

* **Strictly Native Blizzard UI:**
  - Standard frame template: `BasicFrameTemplateWithInset`.
  - Content containers: `InsetFrameTemplate`.
  - Interactive buttons: `UIPanelButtonTemplate`.
  - Zero external libraries (no Ace3, LibDBIcon, etc.).
  - Avoid custom "vibe-coded" flat widgets or non-Blizzard textures.
* **No Redundant Group Composition:**
  - Party composition is intentionally omitted from the HUD (unit frames already show this natively).
* **Clear Role/Spec Representation:**
  - Display native specialization icon textures (`GetSpecializationInfoByID`) rather than cluttered raw text badges.
* **Single-State Controls:**
  - Keep button controls concise (Start Queue / Delist Group), avoiding unnecessary pause buttons.

---

## 4. Matchmaking Pipeline & Experience Thresholds

Candidate evaluation is structured as a pure Chain of Responsibility (`Validation.lua`):
1. **`CheckRoleSlot`**: Target comp 1 Tank, 1 Healer, 3 DPS. Skip filled/reserved roles.
2. **`CheckItemLevel`**: Enforces leader ilvl dynamic floor offset:
   - Key $\ge 18$: Leader ilvl $- 5$
   - Key $15-17$: Leader ilvl $- 10$
   - Key $12-14$: Leader ilvl $- 15$
   - Key $< 12$: Leader ilvl $- 35$
3. **`CheckExperience`**:
   - **Keys $\le +10$**: No experience required (open to all).
   - **Keys $+11$ to $+15$**: Timed completion at $\ge (\text{Target Key} - 2)$.
   - **Keys $> +15$**: Timed completion at $\ge (\text{Target Key} - 1)$.
   - **Keys $\ge$ Target Key**: Strictly valid.
4. **`CheckDuplicates`**:
   - Key $< 15$: Same class allowed if specs differ; duplicate specs rejected.
   - Key $\ge 15$: Duplicate classes strictly prohibited.
5. **`CheckUtilities`**:
   - Mandatory 1 Bloodlust (Mage, Shaman, Hunter, Evoker) and 1 Combat Res (DK, Druid, Warlock, Paladin).
   - Dynamic Lock: If remaining open slots equal missing mandatory utilities, reject applicants lacking the required utility.

---

## 5. Roster Tracking & Leaver Resilience

* On `GROUP_ROSTER_UPDATE`, rescan group members (`GetNumGroupMembers()`, `UnitClass`, `UnitGroupRolesAssigned`).
* Recompute missing utility flags and update HUD badges immediately.
* If a player leaves during assembly, immediately unlock their role/utility slot and re-trigger FIFO candidate evaluation.

---

## 6. Development & Git Workflow Discipline

* **Mandatory Commits:** Commit to Git immediately after each set of code changes.
* **Syntax Verification:** Always run lexical block validation (`node check_lua.js`) before committing to verify zero unclosed tokens or mismatched blocks.
* **Backlog Driven:** Track identified bugs and features in [`BACKLOG.md`](BACKLOG.md) and implement them incrementally one by one.
