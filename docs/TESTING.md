# NIGHTLINE: LAST TRAIN — Testing & Verification Log

## 1. Verification Categories & Honest Boundaries

All verification results are separated by execution environment so that static analysis, standalone Luau VM execution, TypeScript workbench tests, and manual desktop Roblox Studio multiplayer testing are never conflated:

| Category | Status | Scope & Tooling Used |
| --- | --- | --- |
| **Clean-Checkout `npm ci` & Toolchain Bootstrap (`scripts/bootstrap-toolchain.sh`)** | **EXECUTED & PASSED** | Verified `npm ci` against committed `package-lock.json` and installed official Linux `x86_64` binaries for `luau` (`0.746`), `luau-analyze` (`0.746`), `luau-lsp` (`1.70.1`), `rojo` (`7.7.1`), `stylua` (`2.6.0`), `selene` (`0.32.0`), and Roblox `globalTypes.d.luau` into `/tmp/roblox-tools`. |
| **Official Rojo 7.7.1 Build & Static Type/Lint Analysis** | **EXECUTED & PASSED** | Executed `rojo build` (`v7.7.1`, producing `NIGHTLINE_Last_Train.rbxl`), `rojo sourcemap`, `luau-analyze` (`0.746`), `luau-lsp analyze --base-luaurc=.luaurc` (`1.70.1`, `--!strict` mode with `globalTypes.d.luau` — 0 errors, 0 warnings), `stylua --check` (`2.6.0`), and `selene` (`0.32.0` with `roblox` stdlib — 0 errors, 0 warnings). |
| **Official Luau VM Runtime Execution (`luau 0.746`)** | **EXECUTED & PASSED** | Executed the actual `/roblox/**/*.lua` modules (`RoundService.lua`, `HubService.lua`, `MovementService.lua`, `SecurityService.lua`, `InventoryService.lua`, `InteractionService.lua`, `InputController.lua`) inside the official `luau` VM binary via `src/engine/luauVmRunner.ts` across all 8 VM test suites (including Station 001 physical geometry audit and the complete 10-stage round lifecycle). *(Note: Tests deterministic module logic, 3D part bounds/collision flags, and path walkability; does NOT simulate Roblox's C++ 3D rigid-body physics solver or live multi-client network replication.)* |
| **TypeScript Browser Workbench Mirror Tests (`node:test`)** | **EXECUTED & PASSED** | Verified that the interactive browser workbench (`src/engine/nightlineEngine.ts`) stays in parity with the Luau server modules across all 7 `node:test` suites. |
| **Interactive Browser Workbench UI (Playwright)** | **EXECUTED & PASSED** | Verified the live 2D Train Hub & Station 001 canvas, arrival/extraction bulkhead hatches, Station 001 entry spawns (`E1..E6`), Extraction Platform Zone, Recovery Bay berths, QA actions, and Rojo code inspector on port `3000`. |
| **Roblox Studio Desktop Multi-Client Simulation (1–6 Players)** | **NOT PERFORMED (MANUAL STEP REQUIRED)** | Requires opening `NIGHTLINE_Last_Train.rbxl` or running `rojo serve` in desktop Roblox Studio (`Test -> Local Server -> 2–6 Players`). Cannot be executed inside this headless Linux environment. |

---

## 2. Executed Luau VM, CI, & Toolchain Regression Test Cases

| Test ID | Target Luau Module(s) / Files | Scenario Verified | Execution Environment | Result |
| --- | --- | --- | --- | --- |
| `T-PRI-01-CI` | `package.json`, `package-lock.json`, `.github/workflows/ci.yml`, `scripts/bootstrap-toolchain.sh` | Verifies `package-lock.json` is valid, `.github/workflows/ci.yml` configures `cache-dependency-path: 'package-lock.json'` and runs `npm ci`, and all toolchain binaries (`luau`, `luau-analyze`, `luau-lsp`, `rojo`, `stylua`, `selene`) install cleanly without leaving `roblox.yml` in the repo root. | `bash` + `node:test` | **PASS** |
| `T-ISS-05-TC` | All 18 `/roblox/**/*.lua` files | Compiles `.rbxl` with `rojo build`, type-checks all Luau files under `--!strict` with `luau-lsp analyze` and `luau-analyze`, checks formatting with `stylua --check`, and lints with `selene`. | `rojo`, `luau-lsp`, `luau-analyze`, `stylua`, `selene` | **PASS** |
| `T-PRI-02-ENV-VM` | `HubService.lua`, `GameConfig.lua` | Verifies Station 001 physical geometry: `TrainFloor`, `TrainToStationBridge`, `StationPlatformFloor`, `MainConcourseFloor`, `MaintenanceRoomFloor`, `ControlRoomFloor`, `CargoStorageFloor`, `ExtractionPlatformDeck`, and `StationEntrySpawn_01..06` all exist with `CanCollide = true` and `Anchored = true`; verifies `IsPathWalkable` across Train -> Bridge -> Station Platform -> Main Concourse -> all 3 objective rooms -> Extraction Platform -> Train Interior with zero fall-through gaps and solid perimeter wall blocking (`IsPositionBlockedByWall`). | Official `luau` VM (`0.746`) | **PASS** |
| `T-PRI-03-LIFE-VM` | `RoundService.lua`, `HubService.lua`, `InteractionService.lua`, `InventoryService.lua` | Executes the complete 10-stage round lifecycle end-to-end: (1) Boarding the train, (2) Train departure & sealed doors, (3) Station 001 arrival across all 6 spawns with 0 auto-extractions, (4) Exploring & completing all 3 station objectives (`RestorePower`, `RepairSignal`, `RecoverCargo`), (5) Navigating back to extraction, (6) Successful extraction (`EXTRACTED`, `lastOutcome = "SUCCESS"`), (7) Left-behind / failed extraction (`ELIMINATED`, `lastOutcome = "FAILED"`), (8) Mid-expedition `Humanoid.Died` and fresh-character `LoadCharacter()` respawn into Hub Recovery Bay, (9) All-crew-eliminated immediate termination to `RETURN`, and (10) Clean return to `INTERMISSION` in the Train Hub. | Official `luau` VM (`0.746`) | **PASS** |
| `T-FIX-01-VM` | `GameConfig.lua`, `HubService.lua`, `RoundService.lua` | Spawns all 6 crew slots (`1..6`) into Station 001 (`EXPLORATION`); verifies every slot (`15..21, 3.75, 18..30`) is supported by `CanCollide = true` floor geometry, is at least `26.02` studs outside `ExtractionPlatformZone` (`16, 3.0, -8`, radius `10.0`), and never auto-extracts on arrival. | Official `luau` VM (`0.746`) | **PASS** |
| `T-FIX-02-VM` | `RoundService.lua`, `HubService.lua` | Fires `Humanoid.Died` on an active expedition player while the mock `Humanoid`/`Character` forbids in-place `Health > 0` restoration or `PivotTo` on dead characters; verifies `Humanoid.Died` only marks the player `ELIMINATED` and that a subsequent `player:LoadCharacter()` spawns a brand-new `Character` model into the Hub Recovery Bay (`Z >= 35`). | Official `luau` VM (`0.746`) | **PASS** |
| `T-FIX-03-VM` | `MovementService.lua`, `InputController.lua` | Verifies server sprint authority (`RequestSprint`), accepts legitimate upward jumps (`+11` studs Y in `0.25s`), accepts legitimate gravity falls (`-28` studs Y in `0.25s`), accepts server-authorized teleports (`NotifyServerTeleport`), and rejects/rubberbands horizontal speed hacks (`RubberbandedSpeedAnomaly`), upward fly hacks (`RubberbandedVerticalUpwardAnomaly`), and downward noclip hacks (`RubberbandedVerticalDownwardAnomaly`). | Official `luau` VM (`0.746`) | **PASS** |
| `T-FIX-04-VM` | `RoundService.lua` | Starts a 2-player expedition in `EXPLORATION` (180s timer); eliminates both crew members; verifies `RoundService:GetState()` immediately transitions to `"RETURN"` with `GetLastOutcome() == "FAILED"` in `0.0s` elapsed virtual clock time and `_waitPhaseOrAbort("EXPLORATION", 180)` returns `false` immediately. | Official `luau` VM (`0.746`) | **PASS** |
| `T-ISS-02-VM` | `HubService.lua`, `RoundService.lua` | Connects P1 (Slot 1), P2 (Slot 2), P3 (Slot 3); disconnects P2; connects P4 and verifies P4 receives freed Slot 2 without colliding with P3's Slot 3. | Official `luau` VM (`0.746`) | **PASS** |
| `T-ISS-04-VM` | `RoundService.lua`, `HubService.lua` | Verifies P4 inside `ExtractionPlatformZone` (`16, 3.75, -8`) extracts (`EXTRACTED`), while P3 remaining at their station arrival spawn (`Z >= 18`) is rejected (`OutOfExtractionZone`) and marked `ELIMINATED` on departure. | Official `luau` VM (`0.746`) | **PASS** |

---

## 3. How to Run the Automated Test Suite From a Clean Checkout

```bash
npm ci
npm run bootstrap:toolchain
npm test
npm run lint
npm run build
```
