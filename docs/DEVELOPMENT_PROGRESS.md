# NIGHTLINE: LAST TRAIN — Development Progress

## Current Status Summary

- **Milestone 0 — Environment and Project Foundation:** **COMPLETE (Rojo 7.7.1 + Reproducible Toolchain Bootstrap + GitHub Actions CI)**
- **Milestone 1 — Train Hub and Round Foundation:** **COMPLETE (Issues 01–07 + Commit `81542c7` Remediation Fixes 1–7 Verified)**
- **Milestone 2 — Station 001 and Objectives:** **NOT STARTED (Blocked until Commit `81542c7` Remediation PR is reviewed)**
- **Milestone 3 — The Hollow and Survival:** **NOT STARTED**
- **Milestone 4 — Rewards and Persistence:** **NOT STARTED**
- **Milestone 5 — Mobile UX, Art and Audio Polish:** **NOT STARTED**
- **Milestone 6 — Security, Performance and Multiplayer QA:** **NOT STARTED**
- **Milestone 7 — Closed Test and Public Launch Preparation:** **NOT STARTED**

---

## Completed Milestones & Remediation Log

### Commit `81542c7` Code Review & Remediation (Fixes 1–7)

1. **Fix 1 — Station 001 Extraction Placement Bug (`GameConfig.lua`, `HubService.lua`):**
   - Previously, `SpawnPlayerInActiveStation` placed slots `1..6` at `X = 15, Z = -16 .. -1`, which overlapped `ExtractionPlatformZone` (`X = 15, Z = -8`, radius `12.0` studs) and caused players to stand inside the extraction zone immediately upon arriving at Station 001.
   - Added `GameConfig.STATION_ENTRY_SPAWNS` and physical `StationEntrySpawn_01..06` parts at `(14..18, 3, 18..30)` — a minimum horizontal distance of **26.02 studs** away from `EXTRACTION_ZONE_POSITION` (`15, 2.5, -8`).
   - Added regression tests proving all 6 slots spawn strictly outside the extraction zone and no player is automatically extracted upon station arrival or transition into `EXTRACTION`.
2. **Fix 2 — Elimination and Fresh-Character Respawn Flow (`RoundService.lua`, `HubService.lua`):**
   - Removed all in-place `Humanoid.Health` restoration and dead-character `PivotTo` calls from the `Humanoid.Died` path.
   - `HubService:_pivotLivingCharacter()` now checks `if not humanoid or humanoid.Health <= 0 then return false end` and never mutates `Humanoid.Health`.
   - When `Humanoid.Died` fires during an active expedition, `RoundService:EliminatePlayer(player, "CharacterDied", false)` marks the player `ELIMINATED` and leaves the dead character untouched; when the fresh character model subsequently spawns via `player.CharacterAdded`, `RoundService:HandleCharacterAdded()` routes the new living character into `HubService:SpawnEliminatedPlayerInHub(player, entry.spawnSlot)`.
3. **Fix 3 — Strengthened `MovementService` Vertical & Horizontal Validation (`MovementService.lua`, `GameConfig.lua`):**
   - Upgraded `MovementService:ValidatePlayerMovement()` from 2D-only (`X/Z`) checks to full 3D validation covering:
     - Horizontal displacement (`<= (baseHorizSpeed + MOVEMENT_SPEED_TOLERANCE) * elapsed + MOVEMENT_STEP_SLACK`)
     - Vertical upward displacement (`<= MAX_JUMP_UPWARD_SPEED * elapsed + VERTICAL_APEX_TOLERANCE`, allowing legitimate jumps while rubberbanding upward fly/super-jump exploits with `"RubberbandedVerticalUpwardAnomaly"`)
     - Vertical downward displacement (`>= -(MAX_FALL_SPEED * elapsed + VERTICAL_FALL_TOLERANCE)`, allowing gravity falls while rubberbanding downward noclip teleports with `"RubberbandedVerticalDownwardAnomaly"`)
     - Bounded server-authorized teleport grace (`NotifyServerTeleport` verifying proximity to `teleportTargetPosition`).
4. **Fix 4 — All-Crew-Eliminated Immediate Round Termination (`RoundService.lua`):**
   - Updated `EliminatePlayer()`, `UnregisterPlayer()`, and `_waitPhaseOrAbort()` so that when `self:_countLivingOrExtractedExpeditionPlayers() == 0` during `TRAVEL`, `EXPLORATION`, or `EXTRACTION`, the round immediately transitions to `RETURN` (`self:_enterReturnPhase()`) with `self._lastOutcome = "FAILED"` and `_waitPhaseOrAbort()` exits immediately (`return false`) without waiting for the remaining 180s/60s phase timer.
5. **Fix 5 — Reproducible Testing from a Clean Checkout (`scripts/bootstrap-toolchain.sh`, `src/engine/luauVmRunner.ts`):**
   - Added `scripts/bootstrap-toolchain.sh` to automatically download, verify, and install `luau` (`0.746`), `luau-analyze` (`0.746`), `luau-lsp` (`1.70.1`), Roblox `globalTypes.d.luau`, `rojo` (`7.7.1`), `stylua` (`2.6.0`), and `selene` (`0.32.0`) into `${NIGHTLINE_TOOLCHAIN_DIR:-/tmp/roblox-tools}`.
   - Configured `selene` execution inside `/tmp/roblox-tools` so `roblox.yml` never pollutes the repository root.
6. **Fix 6 — Regression Tests & Honest Luau VM Harness Boundaries (`src/engine/luauVmRunner.ts`, `src/engine/nightline.test.ts`):**
   - Enforced strict dead-`Humanoid` immutability in the Luau VM harness (attempting to set `Health > 0` on a dead `Humanoid` or call `PivotTo` on a dead `Character` throws a runtime error) and implemented explicit `player:LoadCharacter()` fresh-character instantiation.
   - Added regression tests covering all 5 fixes in both the Luau VM runner and the TypeScript workbench test suite.
7. **Fix 7 — GitHub Actions CI Workflow (`.github/workflows/ci.yml`):**
   - Added `.github/workflows/ci.yml` to run `scripts/bootstrap-toolchain.sh`, `stylua --check`, `selene`, `rojo sourcemap`, `rojo build`, `luau-lsp analyze`, `npm test`, `npm run lint`, and `npm run build` on every push and pull request.
