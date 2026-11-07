# NIGHTLINE: LAST TRAIN — Testing & Verification Log

## 1. Verification Categories

In accordance with Section 6 of the development instructions and **Issue 05**, all tests are explicitly separated by verification environment so TypeScript workbench results are never conflated with Luau runtime execution or Roblox Studio multiplayer testing:

| Category | Status | Scope & Tooling Used |
| --- | --- | --- |
| **Official Rojo 7.7.1 Build & Static Type/Lint Analysis** | **EXECUTED & PASSED** | Executed `rojo build` (`v7.7.1`, producing `NIGHTLINE_Last_Train.rbxl`), `rojo sourcemap`, `luau-lsp analyze --base-luaurc=.luaurc` (`1.70.1`, `--!strict` mode with `globalTypes.d.luau` — 0 errors, 0 warnings), `stylua --check` (`2.6.0`), and `selene` (`0.32.0` with `roblox` stdlib — 0 errors, 0 warnings). |
| **Official Luau VM Runtime Execution (`luau 0.746`)** | **EXECUTED & PASSED** | Executed the actual `/roblox/**/*.lua` modules (`RoundService.lua`, `HubService.lua`, `MovementService.lua`, `SecurityService.lua`, `InventoryService.lua`, `InteractionService.lua`, `InputController.lua`) inside the official `luau` VM binary via `src/engine/luauVmRunner.ts`. |
| **TypeScript Browser Workbench Mirror Tests (`node:test`)** | **EXECUTED & PASSED** | Verified that the interactive browser workbench (`src/engine/nightlineEngine.ts`) stays in parity with the Luau server modules. *(Note: Treated strictly as UI workbench parity, not a substitute for Luau VM or Roblox Studio testing.)* |
| **Interactive Browser Workbench UI (Playwright)** | **EXECUTED & PASSED** | Verified the live 2D Train Hub canvas, physical Extraction Platform Zone, Recovery Bay berths, QA actions, and Rojo code inspector on port `3000`. |
| **Roblox Studio Desktop Multi-Client Simulation** | **MANUAL STEP REQUIRED** | Requires opening `NIGHTLINE_Last_Train.rbxl` or running `rojo serve` in desktop Roblox Studio (`Test -> Local Server -> 2–4 Players`). Cannot be executed inside this headless Linux container. |

---

## 2. Executed Luau VM & Toolchain Test Cases

| Test ID | Target Luau Module(s) | Scenario Verified | Execution Environment | Result |
| --- | --- | --- | --- | --- |
| `T-ISS-06-07` | `rokit.toml`, `default.project.json` | Verifies Rojo `7.7.1` pin and confirms deprecated `Workspace.FilteringEnabled` is removed. | `node:test` + `rojo 7.7.1` | **PASS** |
| `T-ISS-05-TC` | All 18 `/roblox/**/*.lua` files | Compiles `.rbxl` with `rojo build`, type-checks all Luau files under `--!strict` with `luau-lsp analyze`, checks formatting with `stylua --check`, and lints with `selene`. | `rojo`, `luau-lsp`, `stylua`, `selene` | **PASS** |
| `T-ISS-02-VM` | `HubService.lua`, `RoundService.lua` | Connects Players P1 (Slot 1), P2 (Slot 2), P3 (Slot 3); disconnects P2; connects P4 and verifies P4 receives freed Slot 2 without colliding with P3's Slot 3. | Official `luau` VM (`0.746`) | **PASS** |
| `T-ISS-03-VM` | `MovementService.lua`, `InputController.lua` | Fires `InputController:RequestSprint(true/false)` over `RequestSprint` RemoteEvent; verifies server `MovementService` sets `Humanoid.WalkSpeed` (`22`/`14`) and rubberbands a 90-stud speed-hack teleport back to the last valid server position. | Official `luau` VM (`0.746`) | **PASS** |
| `T-ISS-01-VM` | `RoundService.lua`, `HubService.lua` | Starts active `EXPLORATION` expedition; fires `Humanoid.Died` on P1; verifies P1 becomes `ELIMINATED`, respawns in the Hub Recovery Bay (`Z >= 35`) on `CharacterAdded`, and is blocked from sprinting or re-entering the active station. | Official `luau` VM (`0.746`) | **PASS** |
| `T-ISS-04-VM` | `RoundService.lua`, `HubService.lua` | Transitions to `EXTRACTION`; verifies P3 outside `ExtractionPlatformZone` (`Z = 25`) is rejected by `TryExtractPlayer` (`OutOfExtractionZone`) and marked `ELIMINATED` on departure, while P4 inside `ExtractionPlatformZone` (`15, 2.5, -8`) extracts (`EXTRACTED`, outcome `SUCCESS`). | Official `luau` VM (`0.746`) | **PASS** |

---

## 3. How to Run the Automated Test Suite

```bash
npx --yes tsx --test src/engine/nightline.test.ts
```
