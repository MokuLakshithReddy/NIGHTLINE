# NIGHTLINE: LAST TRAIN — System Architecture

## 1. Authority Boundary Principle

The server owns all authoritative gameplay state:
- Round state machine, phase countdown timers, state-aware respawning, elimination, and physical extraction zone validation (`RoundService`)
- Mission-specific objective selection, multi-step interaction validation (`RestorePower`, `RecoverCargo`, `RepairSignal`), cross-mission rejection, anti-duplication, carrier elimination item recovery, and between-round objective reset (`ObjectiveService`)
- Prepared server-side interfaces for **The Hollow** — player detection (sight range, FOV cone, wall line-of-sight, hiding spot immunity), noise event stimuli, monster state machine transitions, Station 001 waypoint navigation graph & BFS routing, hiding locker occupancy, and validated player elimination (`MonsterService`)
- Explicit 1..6 spawn-slot allocation (`AllocateSpawnSlot` / `ReleaseSpawnSlot`), Train Hub geometry, openable train-to-station bulkhead doors (`SetStationDoorsOpen`), Recovery Bay berths, physical Station 001 environment (`BuildStation001Environment`), and floor/wall walkability verification (`HubService`)
- Server-validated sprint state (`RequestSprint`), `Humanoid.WalkSpeed` assignment, server teleport grace windows, and periodic 3D speed/teleport anomaly rubberbanding (`MovementService`)
- Player 2-slot equipment loadouts and carried mission items (`"Fuse"`, `"CargoContainer"`) (`InventoryService`)
- ProximityPrompt validation and distance/cooldown checks for Hub terminals, Station 001 objective nodes, hiding lockers, and the Extraction Platform (`InteractionService` + `SecurityService`)

The client owns only:
- Input bindings across Keyboard/Mouse, Touch, and Gamepad (`InputController`) — sends `RequestSprint` to the server and never mutates `Humanoid.WalkSpeed` locally
- Responsive ScreenGui display and countdown interpolation (`UIController`)
- Local `ProximityPrompt` highlight affordances (`InteractionController`)

---

## 2. Service & Controller Lifecycle

All server services (`ServerScriptService/Services/*`) and client controllers (`StarterPlayerScripts/Controllers/*`) are standard Luau `ModuleScript`s implementing a two-stage lifecycle:

1. **`Init(dependencies)`**: Synchronous internal state reset, Workspace folder/geometry setup, and dependency injection. Must not yield or fire network traffic to uninitialized peers.
2. **`Start()`**: Connects `RemoteEvent` listeners, `Players.PlayerAdded`/`PlayerRemoving` hooks, `ProximityPromptService` events, and spawns the authoritative state loop.

### Server Bootstrap Order (`Bootstrap.server.lua`)
1. `RemotesRegistry.InitializeServerRemotes()` creates all 8 `RemoteEvent` instances inside `ReplicatedStorage/Remotes`.
2. `SecurityService:Init()`
3. `MovementService:Init({ remotes, securityService })`
4. `HubService:Init()` + `HubService:SetMovementService(MovementService)` (builds `Workspace/World/Hub/Train`, segmented right wall with bulkhead doors, 6 `HubSpawn` pads, 6 `EliminatedRecoveryBerth` pads, and physical `Station001_ForgottenTerminal` inside `Workspace/World/Runtime/ActiveStation`)
5. `InventoryService:Init({ remotes, securityService })`
6. `ObjectiveService:Init({ remotes, securityService, hubService, inventoryService })`
7. `MonsterService:Init({ securityService, hubService })`
8. `RoundService:Init({ remotes, securityService, hubService, inventoryService, movementService, objectiveService, monsterService })`
9.Cross-service wiring (`MovementService:SetRoundService`, `InventoryService:SetRoundService`, `ObjectiveService:SetRoundService`, `ObjectiveService:SetMonsterService`, `MonsterService:SetRoundService`)
10. `InteractionService:Init({ securityService, inventoryService, roundService, objectiveService, monsterService })`
11. `:Start()` is called in the same dependency order.

---

## 3. Mission-Specific Objective Architecture (`ObjectiveService.lua`)

Objective mechanics are extracted into `ObjectiveService.lua` so `RoundService.lua` remains focused on round orchestration:

| Mission ID | Required Progress | Station 001 Physical Parts | Authoritative Server Validation Rules (`ObjectiveService.lua`) |
| --- | --- | --- | --- |
| `RestorePower` | `3` | `FusePickup_01..03` (`NightlineFusePickup`) + `FuseSocket_01..03` (`NightlineFuseSocket`) | Players locate and pick up 3 individual fuses (`InventoryService:AddMissionItem(player, "Fuse", 1)`). Installing into a maintenance socket requires `GetMissionItemCount(player, "Fuse") >= 1`, consumes 1 carried fuse, marks that socket installed, and increments progress `1/3 -> 2/3 -> 3/3`. |
| `RecoverCargo` | `2` | `CargoContainer_01..02` (`NightlineCargoPickup`) + `CargoDropPoint_01` (`NightlineCargoDropPoint`) | Players locate 2 sealed cargo containers (`InventoryService:AddMissionItem(player, "CargoContainer", 1)`). Each player can carry at most 1 heavy cargo container at a time (`AlreadyCarryingCargo`). Delivering at `CargoDropPoint_01` requires carrying a container (`MissingCarriedCargo`), consumes it, marks the container delivered, and increments progress `1/2 -> 2/2`. |
| `RepairSignal` | `3` | `SignalTerminal_01..03` (`NightlineSignalTerminal`) | Players activate 3 communication terminals across the Control Room and Main Concourse. Each terminal can only be activated once (`TerminalAlreadyActivated`), advancing progress `1/3 -> 2/3 -> 3/3`. |

- **Cross-Mission Isolation:** Interacting with any objective node whose `MissionId` does not match `ObjectiveService:GetActiveMissionId()` is immediately rejected with `"MissionMismatch"` and never advances progress.
- **Carrier Elimination & Disconnect Recovery (`OnPlayerEliminatedOrRemoved`):** If a player carrying an uninstalled fuse or undelivered cargo container is eliminated or disconnects, `ObjectiveService` restores those items back to their Station 001 pickup parts (`Collected = false`, `ProximityPrompt.Enabled = true`) so surviving teammates are never soft-locked out of completing the mission.

---

## 4. Prepared Server-Side Interfaces for The Hollow (`MonsterService.lua` & `MonsterConfig.lua`)

Per project instructions, the active autonomous monster NPC is not spawned until the objective system is verified. `MonsterService.lua` and `MonsterConfig.lua` provide the complete, server-authoritative interfaces for Milestone 3:

1. **Monster State Management:** Validated state machine (`INACTIVE`, `PATROL`, `INVESTIGATE`, `CHASE`, `SEARCH`, `RETURN`) enforcing `MonsterConfig.ValidStateTransitions`.
2. **Noise Events:** Server-trusted noise stimulus emission (`EmitNoiseEvent`) for `Walk`, `Sprint`, `ObjectiveInteraction`, `FlareDistraction`, and `DoorTransit`, automatic expiration pruning (`PruneExpiredNoiseEvents`), and distance-weighted stimulus selection (`SelectStrongestNoiseStimulus`).
3. **Player Detection:** `EvaluatePlayerDetection` and `ScanForTargets` check `IN_EXPEDITION` status, living character state, hiding spot immunity (`IsPlayerHidden`), proximity awareness (`11.0` studs) or sight cone (`48.0` studs, `110°` FOV), and unobstructed wall line-of-sight (`HubService:IsPathWalkable`).
4. **Station Navigation:** 8-waypoint Station 001 navigation graph (`WP_PlatformNorth`, `WP_PlatformSouth`, `WP_ConcourseNorth`, `WP_ConcourseCenter`, `WP_ConcourseSouth`, `WP_Maintenance`, `WP_Control`, `WP_Cargo`) with `FindNearestWaypoint` and shortest-path BFS `ComputeWaypointRoute`.
5. **Hiding Locations:** 6 physical Station 001 hiding lockers (`HidingLocker_01..06`, tagged `NightlineHidingSpot`) supporting `EnterHidingSpot`, `ExitHidingSpot`, `HandleHidingSpotInteraction`, and single-occupant enforcement (`HidingSpotOccupied`).
6. **Player Elimination Hook:** `CanEliminateTarget` and `ExecuteValidatedElimination` verify attack range (`<= 6.5` studs), attack cooldown (`2.0s`), non-hidden status (`TargetHidden`), and wall line-of-sight (`BlockedByWall`) before delegating to `RoundService:EliminatePlayer`.

---

## 5. Networking Contract (`RemotesRegistry.lua`)

| RemoteEvent | Direction | Validation & Purpose |
| --- | --- | --- |
| `RoundStateChanged` | Server → All Clients | Broadcasts `RoundStatePayload` (including `lastOutcome: "PENDING" \| "SUCCESS" \| "FAILED"`) on every state transition. |
| `ObjectiveUpdated` | Server → All Clients | Broadcasts `ObjectivePayload` (id, title, progress, requiredProgress, isComplete). |
| `PlayerStatusUpdated` | Server → All Clients | Broadcasts array of `PlayerStatusSummary` records for the crew roster UI. |
| `InventoryUpdated` | Server → Owning Client | Syncs the player's 2 equipment slots (`Flashlight`, `Flare`) and carried mission items (`Fuse`, `CargoContainer`). |
| `Notification` | Server → Client(s) | Sends structured toast messages (`Info`, `Warning`, `Success`, `Danger`). |
| `RequestEquipment` | Client → Server | Validated by `SecurityService` (rate limit, cooldown, integer slot `1..2`, allowlisted item ID, and Hub preparation phase). |
| `RequestDestinationVote` | Client → Server | Validated by `SecurityService` (rate limit, string length, allowlisted `Station001`, and voting phase). |
| `RequestSprint` | Client → Server | Validated by `MovementService` + `SecurityService` (boolean payload, rate limit, alive character, non-eliminated status). |
