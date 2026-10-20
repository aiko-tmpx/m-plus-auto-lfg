# MPlusAutoLFG

[![WoW Retail](https://img.shields.io/badge/World%20of%20Warcraft-Retail%20%2F%20Midnight-orange.svg)](https://worldofwarcraft.blizzard.com)
[![Lua 5.1](https://img.shields.io/badge/Language-Lua%205.1-blue.svg)](https://www.lua.org)
[![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero%20(100%25%20Native)-green.svg)]()

**MPlusAutoLFG** is an automated, fair matchmaking assistant engineered for a **"Solo Queue"** style of play in Mythic+. Instead of arbitrary manual cherry-picking and gatekeeping, the addon simulates an automatic dungeon finder queue: it invites the first eligible applicant (**FIFO**) based on strict, deterministic mechanical rules.

---

## Key Highlights & Architectural Principles

- **Zero External Dependencies**: 100% native World of Warcraft Lua & XML APIs (`BackdropTemplate`, `NineSlice`, native event handlers, native minimap button). No Ace3, LibDataBroker, or LibDBIcon overhead.
- **Blizzard Protected API Compliance**: Calling `C_LFGList.InviteApplicant(applicantID)` requires an explicit hardware event. The addon implements a dedicated on-screen `SecureActionButtonTemplate` button labeled **"CLICK TO INVITE"** (strictly mouse-click driven, no spacebar or keybind exploits).
- **Declarative Validation Pipeline (Chain of Responsibility)**: Isolated, pure validator rules in `Validation.lua` (`CheckRoleSlot`, `CheckItemLevel`, `CheckExperience`, `CheckDuplicates`, `CheckUtilities`).
- **Data Access Layer & Adapter Pattern**: `LFGService.lua` abstracts Blizzard's `C_LFGList`, `C_MythicPlus`, and `C_ChallengeMode` APIs, enabling clean runtime mocking and dependency injection.
- **Leaver / Decline Resilience**: Real-time tracking of `LFG_LIST_APPLICANT_UPDATED` and `GROUP_ROSTER_UPDATE`. If an invited or joined candidate declines or leaves before the dungeon starts, their reserved slot and utility flags (BL/CR) unlock immediately, resuming automated FIFO evaluation.
- **Offline Simulation & Dev Harness**: Built-in `MockEngine.lua` with 7 realistic test fixtures to test all edge cases without live applicants.

---

## Matchmaking Rules & Candidate Validation

Applicants are evaluated strictly in **FIFO order** (by ascending queue entry time / `applicantID`):

### 1. Group Roles & Target Composition
- Target team: **1 Tank, 1 Healer, 3 DPS**.
- Applicants whose role is already filled or currently reserved by an invited candidate are skipped.

### 2. Dynamic Item Level Gatekeeper
Calculated dynamically from the party leader's equipped average item level (`GetAverageItemLevel()`):
- **Key Level $\ge$ 18**: Leader ilvl $- 5$
- **Key Level 15 to 17**: Leader ilvl $- 10$
- **Key Level 12 to 14**: Leader ilvl $- 15$
- **Key Level $<$ 12**: Leader ilvl $- 35$

Passed directly to native listing creation (`requiredItemLevel`) and verified in Lua as a double-check.

### 3. Dungeon Experience Threshold
Evaluates applicant's best run on the exact dungeon of the active keystone:
- **Target Key Level $\le$ 15**: Must have completed the exact same dungeon at $\ge (\text{Target Key} - 2)$ **within timer**.
- **Target Key Level $>$ 15**: Must have completed the exact same dungeon at $\ge (\text{Target Key} - 1)$ **within timer**.
- **Keys $\ge$ Target Key Level**: Strictly valid (retries, score upgrades, farm).

### 4. Class & Spec Duplicate Restrictions
- **Target Key Level $<$ 15**: Duplicate classes are permitted provided their specializations differ. Duplicate specializations are rejected.
- **Target Key Level $\ge$ 15**: Duplicate classes are strictly prohibited across the entire group.

### 5. Utility Requirements (Bloodlust & Combat Resurrection)
- **Mandatory Requirements**: At least 1 Bloodlust / Heroism provider and at least 1 Combat Resurrection provider per group.
  - **BL Classes**: Mage, Shaman, Hunter, Evoker.
  - **CR Classes**: Death Knight, Druid, Warlock, Paladin.
- **Dynamic Lock Rule**: If the number of remaining open slots equals the number of missing mandatory utilities (e.g., 1 slot left and group has no BL), all applicants unable to satisfy the missing utility are rejected.

---

## Finite State Machine (FSM)

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> LISTED: Start Matchmaking (/malfg start)
    LISTED --> ASSEMBLING: Candidate Invited / Member Joins
    ASSEMBLING --> ASSEMBLING: Candidate Leaves / Declines (Slot Recovered)
    ASSEMBLING --> FULL: 5/5 Members Filled (Auto-delist)
    FULL --> ASSEMBLING: Member Leaves Before Run
    LISTED --> PAUSED: /malfg pause
    ASSEMBLING --> PAUSED: /malfg pause
    PAUSED --> LISTED: Resume Matchmaking
    FULL --> IDLE: Reset / Run Completed
```

- **`IDLE`**: Matchmaking inactive.
- **`LISTED`**: Premade group listed in LFG, 0 pending invites, scanning applicants.
- **`ASSEMBLING`**: 1–4 members or pending invites; actively evaluating and inviting candidates.
- **`FULL`**: 5/5 members. Internal stopwatch stops, group automatically delists from LFG, and formation stats are logged.
- **`PAUSED`**: Matchmaking paused by leader.

---

## File Structure

```
MPlusAutoLFG/
├── MPlusAutoLFG.toc         # TOC file with Midnight/Retail interface version & SavedVariables
├── Constants.lua            # Utility tables, class IDs, spec IDs, and role definitions
├── Services/
│   └── LFGService.lua       # Data Access Layer / Blizzard API adapter
├── Validation.lua           # Declarative Validation Pipeline (Chain of Responsibility)
├── UI.lua                   # Authentic Blizzard UI (BasicFrameTemplateWithInset & UIPanelButtonTemplate)
├── Core.lua                 # FSM orchestrator, event bus, roster tracking & slash commands
└── README.md                # Project documentation
```

---

## Slash Commands & Controls

| Command | Description |
| :--- | :--- |
| `/malfg` | Toggle main floating HUD window |
| `/malfg start` | Read active keystone, calculate dynamic ilvl, and create automated LFG listing |
| `/malfg pause` | Pause or resume automated queue evaluation |
| `/malfg debug` | Toggle verbose applicant evaluation chat logs |
| `/malfg reset` | Reset queue state, pending invites, and restore frame positions |

---

## Installation & Live Usage

1. Copy the `MPlusAutoLFG` folder to:
   `World of Warcraft\_retail_\Interface\AddOns\MPlusAutoLFG\`
2. Launch or reload World of Warcraft (`/reload`).
3. Type `/malfg` in chat or click the Minimap button to toggle the HUD.
4. **Testing with Real Premade Groups**:
   - Turn on verbose debugging: `/malfg debug`
   - Click **"Start Queue"** (or list your keystone in the native Premade Groups UI).
   - As players apply, `MPlusAutoLFG` prints every candidate evaluation to chat (`[FIFO]`, `[REJECT]`), showing why applicants pass or fail rules in real time.
   - Click the prominent Blizzard-native **"CLICK TO INVITE"** button to invite the top qualified applicant.
