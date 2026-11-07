# NIGHTLINE: LAST TRAIN — Development Progress

## Current Status Summary

- **Milestone 0 — Environment and Project Foundation:** **COMPLETE (Updated to Rojo 7.7.1)**
- **Milestone 1 — Train Hub and Round Foundation:** **COMPLETE (Hardened with Issues 01–07 Fixes)**
- **Milestone 2 — Station 001 and Objectives:** **NOT STARTED (Next Milestone)**
- **Milestone 3 — The Hollow and Survival:** **NOT STARTED**
- **Milestone 4 — Rewards and Persistence:** **NOT STARTED**
- **Milestone 5 — Mobile UX, Art and Audio Polish:** **NOT STARTED**
- **Milestone 6 — Security, Performance and Multiplayer QA:** **NOT STARTED**
- **Milestone 7 — Closed Test and Public Launch Preparation:** **NOT STARTED**

---

## Completed Milestones & Hardening Log

### Milestone 0 — Environment and Project Foundation
- Configured `default.project.json` (Rojo `7.7.1`, with deprecated `Workspace.FilteringEnabled` removed per Issue 07), `.luaurc` (`--!strict` mode), `selene.toml`, `stylua.toml`, and `rokit.toml` (`rojo@7.7.1`, `stylua@2.6.0`, `selene@0.32.0`, `luau-lsp@1.70.1` per Issue 06).
- Installed and executed the official Linux `x86_64` binaries for `rojo` (`7.7.1`), `luau` (`0.746`), `luau-lsp` (`1.70.1`), `selene` (`0.32.0`), and `stylua` (`2.6.0`) in the automated test suite (`src/engine/luauVmRunner.ts` per Issue 05).

### Milestone 1 — Train Hub and Round Foundation (Including Issues 01–04 Fixes)
- **Issue 01 Fixed (`RoundService.lua`, `HubService.lua`):** Replaced unconditional `HubService:SpawnPlayerInHub()` in `CharacterAdded` with `RoundService:HandleCharacterAdded()` and `Humanoid.Died` -> `EliminatePlayer()`. Players dying during an expedition are marked `ELIMINATED` and respawn into `EliminatedRecoveryBerth_01..06` in the Hub Recovery Bay so they cannot re-enter the active station.
- **Issue 02 Fixed (`HubService.lua`, `RoundService.lua`):** Replaced `#Players:GetPlayers()` slot indexing with explicit `1..6` slot allocation (`AllocateSpawnSlot` / `ReleaseSpawnSlot`) that frees slots on player departure and prevents slot collisions.
- **Issue 03 Fixed (`MovementService.lua`, `InputController.lua`, `RemotesRegistry.lua`):** Removed client-side `Humanoid.WalkSpeed` assignment from `InputController.lua`. Added `RequestSprint` RemoteEvent and server-authoritative `MovementService.lua` with sprint eligibility checks and periodic movement speed/teleport rubberbanding.
- **Issue 04 Fixed (`RoundService.lua`, `HubService.lua`, `InteractionService.lua`, `GameConfig.lua`):** Replaced simulated auto-extraction in `_enterReturnPhase()` with a physical `ExtractionPlatformZone` (`NightlineExtractionZone`, radius `13.0` studs) and server-side proximity & survival checks (`HubService:IsPlayerInExtractionZone(player)`). Players who fail to reach the extraction zone before departure are marked `ELIMINATED`.
