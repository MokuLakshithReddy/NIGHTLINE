# NIGHTLINE: LAST TRAIN — Testing & Verification Log

## 1. Verification Categories & Honest Boundaries

All verification results are separated by execution environment so that static analysis, standalone Luau VM execution, TypeScript workbench tests, and manual desktop Roblox Studio multiplayer testing are never conflated:

| Category | Status | Scope & Tooling Used |
| --- | --- | --- |
| **Clean-Checkout `npm ci` & Toolchain Bootstrap (`scripts/bootstrap-toolchain.sh`)** | **EXECUTED & PASSED** | Verified `npm ci` against committed `package-lock.json` and installed official Linux `x86_64` binaries for `luau` (`0.746`), `luau-analyze` (`0.746`), `luau-lsp` (`1.70.1`), `rojo` (`7.7.1`), `stylua` (`2.6.0`), `selene` (`0.32.0`), and Roblox `globalTypes.d.luau` into `/tmp/roblox-tools`. |
| **Official Rojo 7.7.1 Build & Static Type/Lint Analysis** | **EXECUTED & PASSED** | Executed `rojo build` (`v7.7.1`, producing `NIGHTLINE_Last_Train.rbxl`), `rojo sourcemap`, `luau-analyze` (`0.746`), `luau-lsp analyze --base-luaurc=.luaurc` (`1.70.1`, `--!strict` mode with `globalTypes.d.luau` across all 21 Luau files — 0 errors, 0 warnings), `stylua --check` (`2.6.0`), and `selene` (`0.32.0` with `roblox` stdlib — 0 errors, 0 warnings). |
| **Official Luau VM Runtime Execution (`luau 0.746`)** | **EXECUTED & PASSED** | Executed all 21 `/roblox/**/*.lua` modules (`ObjectiveService.lua`, `MonsterService.lua`, `RoundService.lua`, `HubService.lua`, `MovementService.lua`, `SecurityService.lua`, `InventoryService.lua`, `InteractionService.lua`, `InputController.lua`) inside the official `luau` VM binary via `src/engine/luauVmRunner.ts` across all 8 VM test suites (independent & cooperative verification of `RestorePower`, `RecoverCargo`, and `RepairSignal`, `MonsterService` interfaces, Station 001 physical geometry, and the 10-stage round lifecycle). *(Note: Tests deterministic module logic, 3D part bounds/collision flags, and path walkability; does NOT simulate Roblox's C++ 3D rigid-body physics solver or live multi-client network replication.)* |
| **TypeScript Browser Workbench Mirror Tests (`node:test`)** | **EXECUTED & PASSED** | Verified that the interactive browser workbench (`src/engine/nightlineEngine.ts`) and test runner pass all 7 `node:test` suites. |
| **Interactive Browser Workbench UI (Playwright)** | **EXECUTED & PASSED** | Verified the live 2D Train Hub & Station 001 workbench UI and Rojo source code inspector (including `ObjectiveService.lua`, `MonsterService.lua`, and `MonsterConfig.lua`) on port `3000`. |
| **Roblox Studio Desktop Multi-Client Simulation (1–6 Players)** | **NOT PERFORMED (MANUAL STEP REQUIRED)** | Requires opening `NIGHTLINE_Last_Train.rbxl` or running `rojo serve` in desktop Roblox Studio (`Test -> Local Server -> 2–6 Players`). Cannot be executed inside this headless Linux environment. |

---

## 2. Executed Luau VM, CI, & Toolchain Regression Test Cases

| Test ID | Target Luau Module(s) / Files | Scenario Verified | Execution Environment | Result |
| --- | --- | --- | --- | --- |
| `T-PRI-01-CI` | `package.json`, `package-lock.json`, `.github/workflows/ci.yml`, `scripts/bootstrap-toolchain.sh` | Verifies `package-lock.json` is valid, `.github/workflows/ci.yml` configures `cache-dependency-path: 'package-lock.json'` and runs `npm ci`, and all toolchain binaries (`luau`, `luau-analyze`, `luau-lsp`, `rojo`, `stylua`, `selene`) install cleanly without leaving `roblox.yml` in the repo root. | `bash` + `node:test` | **PASS** |
| `T-ISS-05-TC` | All 21 `/roblox/**/*.lua` files | Compiles `.rbxl` with `rojo build`, type-checks all 21 Luau files under `--!strict` with `luau-lsp analyze` and `luau-analyze`, checks formatting with `stylua --check`, and lints with `selene`. | `rojo`, `luau-lsp`, `luau-analyze`, `stylua`, `selene` | **PASS** |
| `T-OBJ-POWER-VM` | `ObjectiveService.lua`, `InventoryService.lua`, `HubService.lua`, `RoundService.lua` | Verifies `RestorePower` independently & cooperatively: rejects remote distance abuse (`OutOfRange`), rejects `RecoverCargo`/`RepairSignal` parts (`MissionMismatch`), rejects socket install without a carried fuse (`MissingRequiredFuse`), collects `FusePickup_01..03`, rejects duplicate fuse pickup (`FuseAlreadyCollected`) and duplicate socket install (`SocketAlreadyInstalled`), restores a carried fuse to its pickup pad when carrier P3 is eliminated (`OnPlayerEliminatedOrRemoved`), and completes `3/3` sockets (`ObjectiveCompleted`). | Official `luau` VM (`0.746`) | **PASS** |
| `T-OBJ-CARGO-VM` | `ObjectiveService.lua`, `InventoryService.lua`, `HubService.lua`, `RoundService.lua` | Verifies `RecoverCargo` independently & cooperatively: resets objective state to `0/2` after `CleanupRound`, rejects unrelated fuse/signal interactions (`MissionMismatch`), rejects delivery at `CargoDropPoint_01` when carrying 0 containers (`MissingCarriedCargo`), rejects duplicate container pickup (`CargoAlreadyCollected`), rejects carrying 2 containers simultaneously (`AlreadyCarryingCargo`), and completes `2/2` cooperative deliveries (`ObjectiveCompleted`). | Official `luau` VM (`0.746`) | **PASS** |
| `T-OBJ-SIGNAL-VM` | `ObjectiveService.lua`, `HubService.lua`, `RoundService.lua` | Verifies `RepairSignal` independently & cooperatively: rejects unrelated fuse/cargo interactions (`MissionMismatch`), activates `SignalTerminal_01..03` across the Main Concourse and Control Room (`1/3 -> 2/3 -> 3/3`), and rejects duplicate terminal activation (`TerminalAlreadyActivated`). | Official `luau` VM (`0.746`) | **PASS** |
| `T-HOLLOW-PREP-VM` | `MonsterService.lua`, `MonsterConfig.lua`, `HubService.lua`, `RoundService.lua` | Verifies all 6 Priority 4 Hollow AI interfaces: (1) validated state machine transitions (`INACTIVE -> PATROL -> INVESTIGATE -> CHASE -> SEARCH -> RETURN -> PATROL`, rejecting invalid `PATROL -> SEARCH`), (2) noise event emission and strongest stimulus selection (`FlareDistraction`), (3) Station 001 waypoint graph and BFS route computation (`WP_PlatformSouth -> WP_Control`), (4) hiding locker enter/exit (`HidingLocker_02_ConcourseNorth`) and single-occupant enforcement (`HidingSpotOccupied`), (5) player detection with FOV/LOS and hiding spot immunity, and (6) validated player elimination rejecting attacks on hidden players (`TargetHidden`), attacks through walls (`BlockedByWall`), and attacks during cooldown (`AttackCooldownActive`). | Official `luau` VM (`0.746`) | **PASS** |
| `T-PRI-02-ENV-VM` | `HubService.lua`, `GameConfig.lua` | Verifies Station 001 physical geometry: all floor slabs, `StationEntrySpawn_01..06`, and all 12 mission objective parts (`FusePickup_01..03`, `FuseSocket_01..03`, `CargoContainer_01..02`, `CargoDropPoint_01`, `SignalTerminal_01..03`) exist with `CanCollide = true` and `Anchored = true`. | Official `luau` VM (`0.746`) | **PASS** |
| `T-FIX-01..04-VM` | `RoundService.lua`, `HubService.lua`, `MovementService.lua` | Retains and verifies all prior regression suites: all 6 station spawns outside extraction zone, fresh-character respawn flow on `Humanoid.Died`, horizontal + vertical movement validation, physical extraction zone enforcement, and immediate round termination in `0.0s` when all active crew are eliminated. | Official `luau` VM (`0.746`) | **PASS** |

---

## 3. How to Run the Automated Test Suite From a Clean Checkout

```bash
npm ci
npm run bootstrap:toolchain
npm test
npm run lint
npm run build
```
