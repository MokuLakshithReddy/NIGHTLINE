# NIGHTLINE: LAST TRAIN — Development Progress

## Current Status Summary

- **Milestone 0 — Environment and Project Foundation:** **COMPLETE (Rojo 7.7.1 + Committed `package-lock.json` + Reproducible Toolchain Bootstrap + GitHub Actions CI)**
- **Milestone 1 — Train Hub and Round Foundation:** **COMPLETE (Issues 01–07 + Commit `81542c7` Remediation Fixes 1–7 Verified)**
- **Milestone 2 — Station 001 Physical Environment, Mission-Specific `ObjectiveService`, & Complete Round Lifecycle:** **COMPLETE (All 3 Missions Independently & Cooperatively Verified in Official Luau VM)**
- **Milestone 3 — The Hollow and Survival:** **INTERFACES PREPARED & VERIFIED (`MonsterConfig.lua` & `MonsterService.lua` — Active Autonomous Monster NPC Deferred Until Objective System Review)**
- **Milestone 4 — Rewards and Persistence:** **NOT STARTED**
- **Milestone 5 — Mobile UX, Art and Audio Polish:** **NOT STARTED**
- **Milestone 6 — Security, Performance and Multiplayer QA:** **NOT STARTED**
- **Milestone 7 — Closed Test and Public Launch Preparation:** **NOT STARTED**

---

## Completed Priorities in Current Iteration (`feat/objective-service-and-hollow-interfaces`)

### Priority 1 — Implemented Mission-Specific Objective Mechanics (`ObjectiveService.lua`, `ObjectiveConfig.lua`, `HubService.lua`, `InventoryService.lua`)
Replaced the generic shared progress counter with dedicated, server-validated multi-step mechanics for all three Station 001 missions:
1. **`RestorePower` (`requiredProgress = 3`):**
   - Placed three individual fuses (`FusePickup_01..03`) across the Main Concourse, Control Room, and Cargo Storage Bay, and three maintenance sockets (`FuseSocket_01..03`) in the Maintenance Room.
   - Picking up a fuse validates proximity (`<= 14` studs), marks that fuse collected, disables its pickup prompt, and adds `1` `"Fuse"` to the player's server inventory (`InventoryService:AddMissionItem`).
   - Installing into a maintenance socket requires carrying at least `1` `"Fuse"` (`MissingRequiredFuse` if 0), consumes `1` carried `"Fuse"`, marks that socket installed, and increments mission progress (`1/3 -> 2/3 -> 3/3`).
2. **`RecoverCargo` (`requiredProgress = 2`):**
   - Placed two sealed cargo containers (`CargoContainer_01..02`) in the Cargo Storage Bay and a platform drop point (`CargoDropPoint_01`) on the Station Platform.
   - Picking up a cargo container validates that the container has not already been collected (`CargoAlreadyCollected`) and that the player is not already carrying a heavy container (`AlreadyCarryingCargo`), then adds `1` `"CargoContainer"` to the player's server inventory.
   - Delivering at `CargoDropPoint_01` validates that the player is carrying a container (`MissingCarriedCargo`), consumes it, marks the container delivered, and increments mission progress (`1/2 -> 2/2`).
3. **`RepairSignal` (`requiredProgress = 3`):**
   - Placed three communication terminals (`SignalTerminal_01..03`) across the Control Room (`82, 3.0, -8` and `82, 3.0, 8`) and Main Concourse (`56, 3.0, 0`).
   - Activating each terminal validates proximity and non-duplicate state (`TerminalAlreadyActivated`) and increments mission progress (`1/3 -> 2/3 -> 3/3`).
4. **Cross-Mission Isolation & Carrier Recovery:**
   - Any interaction with an objective part belonging to a mission other than the active mission is rejected with `"MissionMismatch"` and never advances progress.
   - If a player carrying an uninstalled fuse or undelivered cargo container is eliminated or disconnects (`OnPlayerEliminatedOrRemoved`), their carried mission items are automatically restored to their Station 001 pickup parts so teammates can still complete the mission.

### Priority 2 — Extracted `ObjectiveService.lua` Architecture
- Extracted all mission state, node validation, carried-item checks, and round objective resets out of `RoundService.lua` into `/roblox/ServerScriptService/Services/ObjectiveService.lua`.
- Kept `RoundService.lua` responsible for round orchestration (`WAITING`, `INTERMISSION`, `BOARDING`, `TRAVEL`, `EXPLORATION`, `EXTRACTION`, `RETURN`, `RESULTS`) while delegating objective initialization, interaction handling, carrier elimination recovery, and round cleanup to `ObjectiveService`.

### Priority 3 — Complete Regression Testing Across All Three Missions
- Verified `RestorePower`, `RecoverCargo`, and `RepairSignal` independently and cooperatively inside the official Luau VM (`luau 0.746`) via `src/engine/luauVmRunner.ts`:
  - Correct objective selection (`SelectMissionForRound`).
  - Cross-mission interactions rejected (`MissionMismatch`).
  - Duplicate fuse/cargo/terminal interactions rejected (`FuseAlreadyCollected`, `SocketAlreadyInstalled`, `CargoAlreadyCollected`, `AlreadyCarryingCargo`, `TerminalAlreadyActivated`).
  - Missing item installations/deliveries rejected (`MissingRequiredFuse`, `MissingCarriedCargo`).
  - Remote distance abuse rejected (`OutOfRange` beyond `14.0` studs).
  - Cooperative multi-player collection, carry, installation/delivery, and carrier elimination item recovery verified.
  - Clean objective reset between rounds verified on `CleanupRound()`.

### Priority 4 — Prepared Server-Side Interfaces for The Hollow (`MonsterService.lua`, `MonsterConfig.lua`)
- Implemented and tested the six required server-side interfaces for **The Hollow** without spawning an autonomous monster NPC during mission verification:
  1. **Player Detection:** Sight range (`48.0` studs), FOV cone (`110°`), proximity awareness (`11.0` studs), wall line-of-sight (`HubService:IsPathWalkable`), hiding spot immunity, and threat scoring.
  2. **Noise Events:** Server-trusted noise emission (`EmitNoiseEvent`), expiration pruning, and strongest stimulus selection (`SelectStrongestNoiseStimulus`).
  3. **Monster State Management:** Validated state machine (`INACTIVE`, `PATROL`, `INVESTIGATE`, `CHASE`, `SEARCH`, `RETURN`).
  4. **Station Navigation:** 8-node Station 001 waypoint graph and BFS route computation (`ComputeWaypointRoute`).
  5. **Hiding Locations:** 6 physical Station 001 hiding lockers (`HidingLocker_01..06`) with enter/exit toggling and single-occupant enforcement (`HidingSpotOccupied`).
  6. **Player Elimination Hook:** `CanEliminateTarget` and `ExecuteValidatedElimination` validating attack range (`6.5` studs), cooldown (`2.0s`), wall line-of-sight (`BlockedByWall`), and non-hidden status (`TargetHidden`) before delegating to `RoundService:EliminatePlayer`.
