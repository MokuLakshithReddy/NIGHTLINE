# NIGHTLINE: LAST TRAIN — Known Issues & Environment Limitations

## 1. Environment & Tooling Limitations

1. **No Direct Desktop Roblox Studio GUI in Headless Linux Container:**
   - **Cause:** This development workspace runs inside a headless Linux container (`x86_64 GNU/Linux`) without a desktop Windows/macOS Roblox Studio GUI or Studio MCP bridge attached.
   - **What IS Verified Automatically in Container & CI (`scripts/bootstrap-toolchain.sh` + `src/engine/luauVmRunner.ts`):**
     - **Clean-Checkout `npm ci` & Reproducible Toolchain:** `npm ci` validates `package-lock.json`, and `scripts/bootstrap-toolchain.sh` installs `luau` (`0.746`), `luau-analyze` (`0.746`), `luau-lsp` (`1.70.1`), `rojo` (`7.7.1`), `stylua` (`2.6.0`), `selene` (`0.32.0`), and Roblox `globalTypes.d.luau`.
     - **Rojo 7.7.1 Build:** `rojo build default.project.json -o /tmp/NIGHTLINE_Last_Train.rbxl` compiles the full place binary cleanly across all 21 Luau modules.
     - **Strict Luau Type & Lint Analysis:** `luau-analyze`, `luau-lsp analyze --base-luaurc=.luaurc` (with Roblox `globalTypes.d.luau`), `selene`, and `stylua --check roblox` run with 0 errors and 0 warnings.
     - **Official Luau VM Execution (`luau 0.746`):** All 21 `/roblox/**/*.lua` modules execute inside the official `luau` VM against a deterministic DataModel API contract shim to verify:
       - Independent and cooperative gameplay mechanics for `RestorePower` (3 fuses -> carry -> 3 maintenance sockets), `RecoverCargo` (2 cargo containers -> carry -> platform drop point), and `RepairSignal` (3 communication terminals), including cross-mission rejection (`MissionMismatch`), duplicate prevention, remote distance rejection (`OutOfRange`), between-round reset, and carrier elimination item recovery.
       - All 6 prepared server-side interfaces for **The Hollow** in `MonsterService.lua` and `MonsterConfig.lua` (player detection, noise events, state machine, waypoint navigation, hiding lockers, and validated player elimination).
       - Station 001 physical geometry (`CanCollide = true` floors, zero-gap `TrainToStationBridge`, openable train-to-station doorways, perimeter collision walls, supported `StationEntrySpawn_01..06` pads) and all 10 stages of the round lifecycle.
   - **What the Luau VM Harness Does NOT Simulate (Requires Manual Desktop Roblox Studio Testing):**
     - The standalone Luau VM harness verifies part positions, sizes, `CanCollide`/`Anchored` flags, and continuous 3D path support (`IsPositionSupportedByFloor`, `IsPositionBlockedByWall`, `IsPathWalkable`), but it does **not** run Roblox's C++ 3D rigid-body physics solver, Humanoid step-climbing solver, or automatic C++ `Players.RespawnTime` character loader.
     - Six-player live network replication (`Test -> Local Server -> 2–6 Players`), 3D camera collision, and native `ProximityPrompt` billboarding have **not** been tested in desktop Roblox Studio and must be verified manually in Roblox Studio using `NIGHTLINE_Last_Train.rbxl` or `rojo serve`.

## 2. Current Scope Boundaries (By Design)

1. **Autonomous Spawning & Patrol Loop for The Hollow (`Milestone 3`):**
   - Per project instructions, all server-side interfaces for **The Hollow** (`MonsterConfig.lua` and `MonsterService.lua`: detection, noise events, state management, station navigation, hiding locations, and player elimination) are prepared and verified, while spawning the active autonomous monster NPC is deferred until the mission-specific objective system is reviewed.
2. **Flare Distraction Noise Emitter:**
   - The Flare is currently an equipment/loadout item; there is no server-authoritative deploy/use action yet. No `FlareDistraction` noise is generated until a validated server-side flare deployment path exists. Do not expose a client-supplied position, radius, or intensity as a substitute.
3. **DataStore Persistence & Scrap Economy (`Milestone 4`):**
   - Scheduled for **Milestone 4** per the build specification.
