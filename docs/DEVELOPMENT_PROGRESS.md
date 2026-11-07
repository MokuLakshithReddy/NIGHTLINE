# NIGHTLINE: LAST TRAIN — Development Progress

## Current Status Summary

- **Milestone 0 — Environment and Project Foundation:** **COMPLETE (Rojo 7.7.1 + Committed `package-lock.json` + Reproducible Toolchain Bootstrap + GitHub Actions CI)**
- **Milestone 1 — Train Hub and Round Foundation:** **COMPLETE (Issues 01–07 + Commit `81542c7` Remediation Fixes 1–7 Verified)**
- **Milestone 2 — Station 001 Physical Environment & Complete Round Lifecycle:** **COMPLETE (Priorities 1–4 Implemented & Verified in Official Luau VM)**
- **Milestone 3 — The Hollow and Survival:** **NOT STARTED (Deferred per instructions until Station 001 & Round Lifecycle PR is reviewed)**
- **Milestone 4 — Rewards and Persistence:** **NOT STARTED**
- **Milestone 5 — Mobile UX, Art and Audio Polish:** **NOT STARTED**
- **Milestone 6 — Security, Performance and Multiplayer QA:** **NOT STARTED**
- **Milestone 7 — Closed Test and Public Launch Preparation:** **NOT STARTED**

---

## Completed Priorities in Current Iteration (`feat/station-001-environment-and-ci`)

### Priority 1 — Fixed CI, `package-lock.json`, and Clean-Checkout `npm ci`
1. **Resolved Peer Dependency Conflict (`package.json`):** Updated `"esbuild"` from `"^0.25.0"` to `"^0.28.0"` so `vite@^8.3.0` (`peerOptional esbuild@"^0.27.0 || ^0.28.0"`) resolves cleanly without `ERESOLVE` errors.
2. **Generated & Committed `package-lock.json`:** Created a deterministic lockfile (`lockfileVersion: 3`, 0 vulnerabilities) at the repository root and verified `npm ci` succeeds from a clean checkout.
3. **Hardened `.github/workflows/ci.yml`:** Added `cache-dependency-path: 'package-lock.json'` to `actions/setup-node@v4` and executed every workflow step end-to-end (`npm ci`, `bash scripts/bootstrap-toolchain.sh`, `stylua --check roblox`, `selene`, `rojo sourcemap`, `rojo build`, `luau-analyze`, `luau-lsp analyze`, `npm test`, `npm run lint`, `npm run build`) with 0 failures.

### Priority 2 — Built Physically Playable Station 001 Environment (`HubService.lua`, `GameConfig.lua`, `RoundService.lua`, `InteractionService.lua`)
1. **Solid `CanCollide = true` Floor Geometry (`Y = 0`, top surface `Y = 0.75`):**
   - `TrainFloor` (`X = -11..11, Z = -42..42`)
   - `TrainToStationBridge` (`X = 9..13, Z = -42..42`) — overlaps `TrainFloor` and `StationPlatformFloor` so there are zero fall-through gaps between the train and the station.
   - `StationPlatformFloor` (`X = 11..29, Z = -42..42`)
   - `MainConcourseFloor` (`X = 29..65, Z = -42..42`)
   - `MaintenanceRoomFloor` (`X = 33..61, Z = -66..-42`)
   - `ControlRoomFloor` (`X = 65..89, Z = -18..18`)
   - `CargoStorageFloor` (`X = 33..61, Z = 42..66`)
2. **Segmented Train Right Wall & Openable Bulkhead Doors:**
   - Replaced the single unbroken `WallRight` part with `WallRight_Front`, `WallRight_Center`, `WallRight_Rear`, and overhead lintels to form two 8-stud-wide by 9-stud-high doorways at `Z = -12..-4` (Extraction Hatch) and `Z = 20..28` (Arrival Hatch).
   - `HubService:SetStationDoorsOpen(isOpen)` seals `Door_ExtractionHatch` and `Door_ArrivalHatch` (`CanCollide = true`) during `INTERMISSION`, `BOARDING`, `TRAVEL`, `RETURN`, and `RESULTS`, and opens them (`CanCollide = false`, retracted) during `EXPLORATION` and `EXTRACTION`.
3. **Six Supported `CanCollide = true` Station Arrival Spawns & Accessible Extraction Deck:**
   - `StationEntrySpawn_01..06` (`X = 15..21, Z = 18..30, Y = 0.85`, `Size = (4, 0.2, 4)`) have `CanCollide = true` and `Anchored = true`, sit directly on `StationPlatformFloor`, and are at least **26.02 studs** away from `ExtractionPlatformZone` (`16, 3.0, -8`, radius `10.0`).
   - `ExtractionPlatformDeck` (`16, 0.85, -8`, `Size = (10, 0.2, 16)`, `CanCollide = true`) provides a solid walkable deck beneath `ExtractionPlatformZone`.
4. **Perimeter Collision Walls & Walkable Objective Rooms:**
   - Added 12-stud-tall `CanCollide = true` perimeter walls around the station platform, concourse, and wing rooms with 12-stud-wide open doorways into the Maintenance Room, Control Room, and Cargo Storage Bay.
   - Added `HubService:IsPositionSupportedByFloor(pos)`, `HubService:IsPositionBlockedByWall(pos, radius)`, and `HubService:IsPathWalkable(fromPos, toPos, stepStuds)` to programmatically verify floor support and wall collision along player navigation paths.

### Priority 3 & Priority 4 — Complete 10-Stage Round Lifecycle & Regression Verification
- Verified all 10 stages of the round lifecycle inside the official `luau` VM (`0.746`):
  1. Players boarding the train (`INTERMISSION` -> `BOARDING`, walking from Hub spawns `S1..S6` through the train carriage to `BoardingGate` and `BoardingSpot_01..06`).
  2. Train departure (`BOARDING` -> `TRAVEL`, bulkhead doors sealed, late joiners remain `HUB_WAITING`).
  3. Arrival at Station 001 (`TRAVEL` -> `EXPLORATION`, bulkhead doors open, 6 crew slots spawn at `StationEntrySpawn_01..06` with `CanCollide = true` floor support and zero auto-extraction).
  4. Players exploring the station (continuous walkable paths into `MainConcourse`, `MaintenanceRoom`, `ControlRoom`, and `CargoStorage`, completing all 3 station objectives `1/3 -> 2/3 -> 3/3`).
  5. Players travelling back to extraction (continuous walkable paths from all 3 wing rooms back to `ExtractionPlatformZone` at `16, 3.75, -8` and back into the train carriage).
  6. Successful extraction (`TryExtractPlayer` and `_enterReturnPhase` mark players in `ExtractionPlatformZone` as `EXTRACTED` with `lastOutcome = "SUCCESS"`).
  7. Failed extraction (players remaining outside `ExtractionPlatformZone` when `EXTRACTION` expires are marked `ELIMINATED`; when 0 players extract, `lastOutcome = "FAILED"`).
  8. Player death and fresh-character respawn (`Humanoid.Died` marks the player `ELIMINATED` without healing or pivoting the dead character; subsequent `player:LoadCharacter()` spawns the fresh living character into the Hub Recovery Bay at `Z = 35..38`).
  9. All players being eliminated (immediate termination into `RETURN` with `lastOutcome = "FAILED"` in `0.0s` without waiting for the remaining phase timer).
  10. Clean return to the hub (`RETURN` -> `RESULTS` -> `CleanupRound` -> `INTERMISSION`, sealing bulkhead doors and resetting all players to `HUB_WAITING` in the Train Hub).
