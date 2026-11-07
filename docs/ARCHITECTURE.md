# NIGHTLINE: LAST TRAIN — System Architecture

## 1. Authority Boundary Principle

The server owns all authoritative gameplay state:
- Round state machine and phase countdown timers (`RoundService`)
- Crew roster, boarding readiness, and late-joiner isolation (`RoundService`)
- Player equipment slots and mission item counts (`InventoryService`)
- ProximityPrompt validation and distance/cooldown checks (`InteractionService` + `SecurityService`)
- Procedural Train Hub construction and runtime station cleanup (`HubService`)

The client owns only:
- Input bindings across Keyboard/Mouse, Touch, and Gamepad (`InputController`)
- Responsive ScreenGui display and countdown interpolation (`UIController`)
- Local `ProximityPrompt` highlight affordances (`InteractionController`)

---

## 2. Service & Controller Lifecycle

All server services (`ServerScriptService/Services/*`) and client controllers (`StarterPlayerScripts/Controllers/*`) are standard Luau `ModuleScript`s implementing a two-stage lifecycle:

1. **`Init(dependencies)`**: Synchronous internal state reset, Workspace folder/geometry setup, and dependency injection. Must not yield or fire network traffic to uninitialized peers.
2. **`Start()`**: Connects `RemoteEvent` listeners, `Players.PlayerAdded`/`PlayerRemoving` hooks, `ProximityPromptService` events, and spawns the authoritative state loop.

### Server Bootstrap Order (`Bootstrap.server.lua`)
1. `RemotesRegistry.InitializeServerRemotes()` creates all 7 `RemoteEvent` instances inside `ReplicatedStorage/Remotes`.
2. `SecurityService:Init()`
3. `HubService:Init()` (builds `Workspace/World/Hub/Train` and `Workspace/World/Hub/Spawns`)
4. `InventoryService:Init({ remotes, securityService })`
5. `RoundService:Init({ remotes, securityService, hubService, inventoryService })`
6. `InteractionService:Init({ securityService, inventoryService, roundService })`
7. `:Start()` is called in the same order.

---

## 3. Round State Machine (`RoundService.lua`)

| State | Default Duration | Authoritative Server Behaviour |
| --- | --- | --- |
| `WAITING` | Indefinite (`0s`) | Holds in Hub until `>= GameConfig.MIN_CREW_TO_START` (1) players are present. |
| `INTERMISSION` | `15s` | Increments round counter, selects next mission template, resets crew status to `HUB_WAITING`, opens destination voting and equipment preparation. |
| `BOARDING` | `45s` | Marks present hub crew as `BOARDED` (while allowing players to toggle readiness at the Boarding Gate) and broadcasts mission briefing. |
| `TRAVEL` | `20s` | Locks active expedition crew (`IN_EXPEDITION`), moves departing crew to the forward boarding bay, isolates late joiners in `HUB_WAITING`. |
| `EXPLORATION` | `180s` | Active station phase (Milestone 1 foundation runs the timer and tracks crew presence; Milestone 2 hooks `StationService` and `ObjectiveService` here). |
| `EXTRACTION` | `60s` | Broadcasts departure warning and tracks extraction window. |
| `RETURN` | `20s` | Resolves surviving expedition players as `EXTRACTED` and transitions back toward the Train Hub. |
| `RESULTS` | `30s` | Displays expedition outcome, then invokes `CleanupRound()` via `Janitor` before returning to `INTERMISSION` or `WAITING`. |

### Late-Join & Disconnect Safety
- **Late Joiners:** Any player joining during `TRAVEL`, `EXPLORATION`, `EXTRACTION`, `RETURN`, or `RESULTS` is registered with status `HUB_WAITING`, spawned inside the safe Train Hub, and excluded from `_activeExpeditionUserIds` until the next `INTERMISSION`.
- **All-Crew Disconnect:** If all players in `_activeExpeditionUserIds` leave during an active expedition, `RoundService` immediately invokes `CleanupRound()` and transitions safely to `WAITING`.

---

## 4. Networking Contract (`RemotesRegistry.lua`)

| RemoteEvent | Direction | Validation & Purpose |
| --- | --- | --- |
| `RoundStateChanged` | Server → All Clients | Broadcasts `RoundStatePayload` on every state transition and vote update. |
| `ObjectiveUpdated` | Server → All Clients | Broadcasts `ObjectivePayload` (id, title, progress, requiredProgress, isComplete). |
| `PlayerStatusUpdated` | Server → All Clients | Broadcasts array of `PlayerStatusSummary` records for the crew roster UI. |
| `InventoryUpdated` | Server → Owning Client | Syncs the player's 2 equipment slots (`Flashlight`, `Flare`) and mission items. |
| `Notification` | Server → Client(s) | Sends structured toast messages (`Info`, `Warning`, `Success`, `Danger`). |
| `RequestEquipment` | Client → Server | Validated by `SecurityService` (rate limit, cooldown, integer slot `1..2`, allowlisted item ID, and Hub preparation phase). |
| `RequestDestinationVote` | Client → Server | Validated by `SecurityService` (rate limit, string length, allowlisted `Station001`, and voting phase). |
