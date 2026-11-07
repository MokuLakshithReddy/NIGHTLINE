# NIGHTLINE: LAST TRAIN — Known Issues & Environment Limitations

## 1. Environment & Tooling Limitations

1. **No Direct Desktop Roblox Studio GUI in Headless Linux Container:**
   - **Cause:** This development workspace runs inside a headless Linux container (`x86_64 GNU/Linux`) without a desktop Windows/macOS Roblox Studio GUI or Studio MCP bridge attached.
   - **What IS Verified Automatically in Container & CI (`scripts/bootstrap-toolchain.sh` + `src/engine/luauVmRunner.ts`):**
     - **Reproducible Clean-Checkout Toolchain:** `scripts/bootstrap-toolchain.sh` installs `luau` (`0.746`), `luau-analyze` (`0.746`), `luau-lsp` (`1.70.1`), `rojo` (`7.7.1`), `stylua` (`2.6.0`), `selene` (`0.32.0`), and Roblox `globalTypes.d.luau`.
     - **Rojo 7.7.1 Build:** `rojo build default.project.json -o /tmp/NIGHTLINE_Last_Train.rbxl` compiles the full place binary cleanly.
     - **Strict Luau Type & Lint Analysis:** `luau-lsp analyze --base-luaurc=.luaurc` (with Roblox `globalTypes.d.luau`), `selene`, and `stylua --check roblox` run with 0 errors and 0 warnings.
     - **Official Luau VM Execution (`luau 0.746`):** All `/roblox/**/*.lua` modules execute inside the official `luau` VM against a deterministic DataModel API contract shim to verify Fixes 1–4 and Issues 01–04.
   - **What the Luau VM Harness Does NOT Simulate (Requires Manual Desktop Roblox Studio Testing):**
     - The standalone Luau VM harness does **not** simulate Roblox's 3D rigid-body physics engine (gravity integration, character collision geometry, floor raycasting) or Roblox's automatic C++ `Players.RespawnTime` character loader. Instead, the harness strictly forbids in-place healing/pivoting of dead `Humanoid` instances and requires explicit `player:LoadCharacter()` calls to test fresh-character respawn routing.
     - Multi-client live physics replication (`Test -> Local Server -> 2–4 Players`) and native `ProximityPrompt` billboarding must be verified manually in desktop Roblox Studio using `NIGHTLINE_Last_Train.rbxl` or `rojo serve`.

## 2. Current Scope Boundaries (By Design Before Milestone 2)

1. **Station 001 Full Greybox Layout & Objectives (`Milestone 2`):**
   - Station 001 entry spawns (`StationEntrySpawn_01..06` at `Z = 18..30`, outside the extraction zone) and physical extraction boarding validation (`ExtractionPlatformZone` at `Z = -8`) are implemented and verified; full Station 001 multi-room layout (`StationService`) and interactive objectives (`ObjectiveService`: `RestorePower`, `RecoverCargo`, `RepairSignal`) will begin in **Milestone 2** after this remediation review is complete.
2. **The Hollow AI (`Milestone 3`):**
   - Scheduled for **Milestone 3** per the build specification.
3. **DataStore Persistence & Scrap Economy (`Milestone 4`):**
   - Scheduled for **Milestone 4** per the build specification.
