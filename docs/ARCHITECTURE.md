# NIGHTLINE: LAST TRAIN — System Architecture

## 1. Authority Boundary Principle

The server owns all authoritative gameplay state:
- Round state machine, phase countdown timers, state-aware respawning, elimination, and physical extraction zone validation (`RoundService`)
- Explicit 1..6 spawn-slot allocation (`AllocateSpawnSlot` / `ReleaseSpawnSlot`), Train Hub geometry, Recovery Bay berths, and physical `ExtractionPlatformZone` (`HubService`)
- Server-validated sprint state (`RequestSprint`), `Humanoid.WalkSpeed` assignment, server teleport grace windows, and periodic speed/teleport anomaly rubberbanding (`MovementService`)
- Player equipment slots and mission item counts (`InventoryService`)
- ProximityPrompt validation and distance/cooldown checks (`InteractionService` + `SecurityService`)

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
4. `HubService:Init()` + `HubService:SetMovementService(MovementService)` (builds `Workspace/World/Hub/Train`, 6 `HubSpawn` pads, 6 `EliminatedRecoveryBerth` pads, and `ExtractionPlatformZone`)
5. `InventoryService:Init({ remotes, securityService })`
6. `RoundService:Init({ remotes, securityService, hubService, inventoryService, movementService })`
7. `InteractionService:Init({ securityService, inventoryService, roundService })`
8. `:Start()` is called in the same order.

---

## 3. Resolved Architecture & Security Hardening (Issues 01–07)

1. **Issue 01 — Player-State-Aware Respawning & Elimination (`RoundService.lua`, `HubService.lua`):**
   - `CharacterAdded` calls `RoundService:HandleCharacterAdded(player, character)` instead of unconditionally spawning in the Hub.
   - Connects `Humanoid.Died` on the server to `RoundService:EliminatePlayer(player, "Died")`.
   - Players who die during an active expedition (`TRAVEL`, `EXPLORATION`, `EXTRACTION`) are marked `ELIMINATED` and respawn into the isolated **Hub Recovery Bay** (`EliminatedRecoveryBerth_01..06`, `Z = 36..38`) so they cannot re-enter the active station until the round ends.
   - Surviving `IN_EXPEDITION` players whose character loads during `EXPLORATION` or `EXTRACTION` spawn at the active station platform (`SpawnPlayerInActiveStation`).
2. **Issue 02 — Explicit 1..6 Spawn-Slot Allocation (`HubService.lua`, `RoundService.lua`):**
   - `HubService:AllocateSpawnSlot(userId)` assigns the lowest available slot index (`1..6`) and records ownership in `_allocatedSlots` and `_playerSlots`.
   - `HubService:ReleaseSpawnSlot(userId)` frees the slot on `Players.PlayerRemoving`, preventing new joiners from colliding with occupied slots when an earlier player disconnects.
3. **Issue 03 — Server-Authoritative Sprint & Movement Validation (`MovementService.lua`, `InputController.lua`):**
   - Removed client-side `Humanoid.WalkSpeed` mutation from `InputController.lua`; sprinting now fires `Remotes.RequestSprint:FireServer(wantsSprint)`.
   - `MovementService:HandleSprintRequest` validates player instance, boolean payload, rate limit, alive state, and non-eliminated status before setting `Humanoid.WalkSpeed` (`22` sprint / `14` walk) on the server.
   - `MovementService:ValidatePlayerMovement` runs every `0.25s` and rubberbands characters back to their last valid server position if horizontal displacement exceeds `(SPRINT_SPEED + MOVEMENT_SPEED_TOLERANCE) * dt`, while honoring a `1.0s` grace window on server-initiated teleports (`NotifyServerTeleport`).
4. **Issue 04 — Physical Extraction Platform Zone Validation (`HubService.lua`, `RoundService.lua`, `InteractionService.lua`):**
   - Created physical `ExtractionPlatformZone` part (`Position = (15, 2.5, -8)`, `Size = (8, 8, 18)`, tagged `NightlineExtractionZone`, radius `13.0` studs) with an `ExtractionPlatformPrompt`.
   - `RoundService:TryExtractPlayer(player)` and `_enterReturnPhase()` verify via `HubService:IsPlayerInExtractionZone(player)` that the player is alive (`Health > 0`) and physically inside the extraction zone (`horizontalDist <= 13.0` studs).
   - Active expedition players still outside the extraction zone when the `EXTRACTION` timer expires are marked `ELIMINATED` (left behind) and moved to the Recovery Bay.

---

## 4. Networking Contract (`RemotesRegistry.lua`)

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
