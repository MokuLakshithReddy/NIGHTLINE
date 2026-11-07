# NIGHTLINE: LAST TRAIN — System Architecture

## 1. Authority Boundary Principle

The server owns all authoritative gameplay state:
- Round state machine, phase countdown timers, station objective progress, state-aware respawning, elimination, and physical extraction zone validation (`RoundService`)
- Explicit 1..6 spawn-slot allocation (`AllocateSpawnSlot` / `ReleaseSpawnSlot`), Train Hub geometry, openable train-to-station bulkhead doors (`SetStationDoorsOpen`), Recovery Bay berths, physical Station 001 environment (`BuildStation001Environment`), and floor/wall walkability verification (`HubService`)
- Server-validated sprint state (`RequestSprint`), `Humanoid.WalkSpeed` assignment, server teleport grace windows, and periodic 3D speed/teleport anomaly rubberbanding (`MovementService`)
- Player equipment slots and mission item counts (`InventoryService`)
- ProximityPrompt validation and distance/cooldown checks for Hub terminals, Station 001 objective nodes, and the Extraction Platform (`InteractionService` + `SecurityService`)

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
6. `RoundService:Init({ remotes, securityService, hubService, inventoryService, movementService })`
7. `InteractionService:Init({ securityService, inventoryService, roundService })`
8. `:Start()` is called in the same order.

---

## 3. Station 001 Physical Environment Architecture (`HubService.lua`)

`HubService:BuildStation001Environment()` constructs `Station001_ForgottenTerminal` inside `Workspace.World.Runtime.ActiveStation` with continuous, gap-free `CanCollide = true`, `Anchored = true` floor geometry at `Y = 0` (`Size.Y = 1.5`, top surface `Y = 0.75`):

| Floor / Structure Part | World Bounds (`X`, `Z`) | Size (`X, Y, Z`) | Collision & Purpose |
| --- | --- | --- | --- |
| `TrainFloor` | `X = -11 .. 11`, `Z = -42 .. 42` | `(22, 1.5, 84)` | `CanCollide = true` — Train carriage interior deck |
| `TrainToStationBridge` | `X = 9 .. 13`, `Z = -42 .. 42` | `(4, 1.5, 84)` | `CanCollide = true` — Overlaps `TrainFloor` (`X = 9..11`) and `StationPlatformFloor` (`X = 11..13`) so there is zero gap between the train and station |
| `StationPlatformFloor` | `X = 11 .. 29`, `Z = -42 .. 42` | `(18, 1.5, 84)` | `CanCollide = true` — Main boarding & arrival platform alongside the train |
| `MainConcourseFloor` | `X = 29 .. 65`, `Z = -42 .. 42` | `(36, 1.5, 84)` | `CanCollide = true` — Central Forgotten Terminal concourse |
| `MaintenanceRoomFloor` | `X = 33 .. 61`, `Z = -66 .. -42` | `(28, 1.5, 24)` | `CanCollide = true` — North wing housing `ObjectiveNode_01_Maintenance` (`RestorePower`) |
| `ControlRoomFloor` | `X = 65 .. 89`, `Z = -18 .. 18` | `(24, 1.5, 36)` | `CanCollide = true` — East wing housing `ObjectiveNode_02_Control` (`RepairSignal`) |
| `CargoStorageFloor` | `X = 33 .. 61`, `Z = 42 .. 66` | `(28, 1.5, 24)` | `CanCollide = true` — South wing housing `ObjectiveNode_03_Cargo` (`RecoverCargo`) |
| `StationEntrySpawn_01..06` | `X = 15..21`, `Z = 18..30`, `Y = 0.85` | `(4, 0.2, 4)` | `CanCollide = true`, `Anchored = true` — Six arrival spawn pads supported by `StationPlatformFloor`, minimum `26.02` studs outside `ExtractionPlatformZone` |
| `ExtractionPlatformDeck` & `ExtractionPlatformZone` | `X = 16`, `Z = -8` | Deck `(10, 0.2, 16)` (`CanCollide = true`), Zone `(10, 8, 16)` (`CanCollide = false`) | Accessible boarding deck and trigger volume (`NightlineExtractionZone`, radius `10.0` studs) |
| `Door_ExtractionHatch` & `Door_ArrivalHatch` | `X = 10.5`, `Z = -8` & `Z = 24` | `(1, 9, 8)` | Controlled by `HubService:SetStationDoorsOpen(isOpen)` — closed (`CanCollide = true`) during Hub/Travel/Return, open (`CanCollide = false`, retracted) during `EXPLORATION` and `EXTRACTION` |

---

## 4. Resolved Architecture & Security Hardening

1. **Player-State-Aware Respawning & Fresh-Character Elimination (`RoundService.lua`, `HubService.lua`):**
   - `Humanoid.Died` calls `RoundService:EliminatePlayer(player, "CharacterDied", false)` which marks the player `ELIMINATED` without mutating `Humanoid.Health` or calling `PivotTo` on the dead character.
   - When the fresh character spawns via `player.CharacterAdded`, `RoundService:HandleCharacterAdded(player, character)` routes `ELIMINATED` players to the isolated **Hub Recovery Bay** (`EliminatedRecoveryBerth_01..06`, `Z = 35..38`), `IN_EXPEDITION` players during `EXPLORATION`/`EXTRACTION` to `SpawnPlayerInActiveStation`, and `HUB_WAITING` players to `SpawnPlayerInHub`.
   - If all active expedition players are eliminated during `TRAVEL`, `EXPLORATION`, or `EXTRACTION`, the round terminates immediately into `RETURN` (`lastOutcome = "FAILED"`).
2. **Explicit 1..6 Spawn-Slot Allocation (`HubService.lua`, `RoundService.lua`):**
   - `HubService:AllocateSpawnSlot(userId)` assigns the lowest available slot (`1..6`) and `ReleaseSpawnSlot(userId)` frees it on disconnect.
3. **Server-Authoritative Sprint & 3D Movement Validation (`MovementService.lua`, `InputController.lua`):**
   - Client sprinting sends `RequestSprint` to the server; `MovementService:ValidatePlayerMovement` validates both horizontal speed and vertical jump/fall bounds every `0.25s` while honoring server-authorized teleports (`NotifyServerTeleport`).
4. **Physical Extraction Platform Zone Validation (`HubService.lua`, `RoundService.lua`, `InteractionService.lua`):**
   - `RoundService:TryExtractPlayer(player)` and `_enterReturnPhase()` verify via `HubService:IsPlayerInExtractionZone(player)` that the player is alive (`Health > 0`) and physically inside `ExtractionPlatformZone` (`(16, 3.0, -8)`, radius `10.0` studs) while standing on supported floor geometry.

---

## 5. Networking Contract (`RemotesRegistry.lua`)

| RemoteEvent | Direction | Validation & Purpose |
| --- | --- | --- |
| `RoundStateChanged` | Server → All Clients | Broadcasts `RoundStatePayload` (including `lastOutcome: "PENDING" \| "SUCCESS" \| "FAILED"`) on every state transition. |
| `ObjectiveUpdated` | Server → All Clients | Broadcasts `ObjectivePayload` (id, title, progress, requiredProgress, isComplete). |
| `PlayerStatusUpdated` | Server → All Clients | Broadcasts array of `PlayerStatusSummary` records for the crew roster UI. |
| `InventoryUpdated` | Server → Owning Client | Syncs the player's 2 equipment slots (`Flashlight`, `Flare`) and mission items. |
| `Notification` | Server → Client(s) | Sends structured toast messages (`Info`, `Warning`, `Success`, `Danger`). |
| `RequestEquipment` | Client → Server | Validated by `SecurityService` (rate limit, cooldown, integer slot `1..2`, allowlisted item ID, and Hub preparation phase). |
| `RequestDestinationVote` | Client → Server | Validated by `SecurityService` (rate limit, string length, allowlisted `Station001`, and voting phase). |
| `RequestSprint` | Client → Server | Validated by `MovementService` + `SecurityService` (boolean payload, rate limit, alive character, non-eliminated status). |
