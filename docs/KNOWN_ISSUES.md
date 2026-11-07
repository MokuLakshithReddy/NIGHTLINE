# NIGHTLINE: LAST TRAIN — Known Issues & Environment Limitations

## 1. Environment & Tooling Limitations

1. **No Direct Desktop Roblox Studio GUI in Headless Linux Container:**
   - **Cause:** This development workspace runs inside a headless Linux container (`x86_64 GNU/Linux`) without a desktop Windows/macOS Roblox Studio GUI or Studio MCP bridge attached.
   - **What IS Verified Automatically in Container (`src/engine/luauVmRunner.ts`):**
     - **Rojo 7.7.1 Build:** `rojo build default.project.json -o /tmp/NIGHTLINE_Last_Train.rbxl` compiles the full place binary cleanly.
     - **Strict Luau Type & Lint Analysis:** `luau-lsp analyze --base-luaurc=.luaurc` (with Roblox `globalTypes.d.luau`), `selene roblox`, and `stylua --check roblox` run with 0 errors and 0 warnings.
     - **Official Luau VM Execution (`luau 0.746`):** All `/roblox/**/*.lua` modules execute inside the official `luau` VM against a lightweight Roblox DataModel harness to verify Issues 01–04 at runtime.
   - **What Still Requires Manual Desktop Roblox Studio Verification:**
     - Live Roblox 3D character physics, `Humanoid` replication across multiple Studio client windows (`Test -> Local Server -> 2–4 Players`), and native `ProximityPrompt` UI rendering must be verified manually in desktop Roblox Studio using the built `NIGHTLINE_Last_Train.rbxl` file or `rojo serve`.

## 2. Current Scope Boundaries (By Design for Milestone 1)

1. **Station 001 Full Greybox Layout & Objectives (`Milestone 2`):**
   - Physical extraction boarding validation (`ExtractionPlatformZone`) and active station platform spawning are now implemented and verified; full Station 001 multi-room layout (`StationService`) and interactive objectives (`ObjectiveService`: `RestorePower`, `RecoverCargo`, `RepairSignal`) are scheduled next in **Milestone 2**.
2. **The Hollow AI (`Milestone 3`):**
   - Scheduled for **Milestone 3** per the build specification.
3. **DataStore Persistence & Scrap Economy (`Milestone 4`):**
   - Scheduled for **Milestone 4** per the build specification.
