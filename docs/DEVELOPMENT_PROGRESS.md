# NIGHTLINE: LAST TRAIN — Development Progress

## Current Status Summary

- **Milestone 0 — Environment and Project Foundation:** **COMPLETE**
- **Milestone 1 — Train Hub and Round Foundation:** **COMPLETE**
- **Milestone 2 — Station 001 and Objectives:** **NOT STARTED (Next Milestone)**
- **Milestone 3 — The Hollow and Survival:** **NOT STARTED**
- **Milestone 4 — Rewards and Persistence:** **NOT STARTED**
- **Milestone 5 — Mobile UX, Art and Audio Polish:** **NOT STARTED**
- **Milestone 6 — Security, Performance and Multiplayer QA:** **NOT STARTED**
- **Milestone 7 — Closed Test and Public Launch Preparation:** **NOT STARTED**

---

## Completed Milestones Detail

### Milestone 0 — Environment and Project Foundation
- Inspected the container workspace and verified available tooling.
- Identified that direct Roblox Studio GUI / MCP integration is not attached to this Linux container, and established a clean **Rojo (`default.project.json`) + strict Luau (`--!strict`)** file-based workflow alongside a browser-based **Train Hub & Round State Machine Simulator** so Milestone 0 and Milestone 1 can be executed, inspected, and tested immediately.
- Configured `.luaurc`, `selene.toml`, `stylua.toml`, and `rokit.toml`.
- Created shared configuration modules (`GameConfig.lua`, `ItemConfig.lua`, `StationConfig.lua`, `ObjectiveConfig.lua`, `RewardConfig.lua`), strict type definitions (`NetworkTypes.lua`), reusable utilities (`Signal.lua`, `Janitor.lua`), and `RemotesRegistry.lua`.

### Milestone 1 — Train Hub and Round Foundation
- Implemented `HubService.lua` to construct the Train Hub inside `Workspace/World/Hub/Train` with 6 `SpawnLocation` pads in `Workspace/World/Hub/Spawns`, interior warm lighting, and `CollectionService`-tagged interactive terminals (`DestinationConsole`, `EquipmentLocker_Flashlight`, `EquipmentLocker_Flare`, `BoardingReadyGate`) with `ProximityPrompt`s.
- Implemented `SecurityService.lua` for per-player rate limiting, action cooldowns, string/integer validation, and server-side character distance verification.
- Implemented `InventoryService.lua` for server-authoritative 2-slot equipment management (`Flashlight`, `Flare`) restricted to Hub preparation phases.
- Implemented `RoundService.lua` for the 8-state round lifecycle (`WAITING`, `INTERMISSION`, `BOARDING`, `TRAVEL`, `EXPLORATION`, `EXTRACTION`, `RETURN`, `RESULTS`), server-owned countdown timers, crew roster management, late-joiner Hub isolation, mid-round disconnect recovery, and deterministic `CleanupRound()`.
- Implemented `InteractionService.lua` to validate server-side `ProximityPromptService.PromptTriggered` events.
- Implemented client controllers (`UIController.lua`, `InputController.lua`, `InteractionController.lua`) and bootstrap scripts (`Bootstrap.server.lua`, `ClientBootstrap.client.lua`).
