# NIGHTLINE: LAST TRAIN — Testing & Verification Log

## 1. Verification Categories

In accordance with Section 6 of the development instructions, all tests are explicitly categorized by verification environment:

| Category | Status | Scope |
| --- | --- | --- |
| **Static Code & Rojo Inspection** | **EXECUTED & PASSED** | Verified `default.project.json` path mappings, `--!strict` headers, balanced Luau block syntax, and RemoteEvent contract alignment across all 17 Luau modules. |
| **Automated Unit & Integration Tests (`node:test`)** | **EXECUTED & PASSED** | Executed deterministic tests covering `RoundService` 8-state transitions, `SecurityService` rate limiting & payload validation, `InventoryService` slot rules, `InteractionService` distance checks, multiplayer crew rostering (1–6 players), late-join isolation, and all-player disconnect cleanup. |
| **Interactive Browser Workbench Verification (Playwright)** | **EXECUTED & PASSED** | Verified the live Train Hub simulation, equipment locker interactions, destination voting, boarding countdown, late-joiner handling, and Rojo code inspector in headless Chromium at desktop (`1440x900`) and mobile (`390x844`) viewports. |
| **Roblox Studio Simulation** | **MANUAL STEP REQUIRED** | Requires opening the generated Rojo project (`rojo build` / `rojo serve`) in desktop Roblox Studio. Exact steps are provided in `README.md`. |
| **Live Production Testing** | **NOT EXECUTED** | Deferred until Milestone 6 & Milestone 7 per specification. |

---

## 2. Executed Test Cases (Milestone 0 & Milestone 1)

| Test ID | System | Scenario | Type | Result |
| --- | --- | --- | --- | --- |
| `T-M0-01` | Rojo & Luau Files | Verify every `$path` in `default.project.json` exists and all `.lua` files start with `--!strict` and have valid balanced Luau syntax. | Automated Static | **PASS** |
| `T-M1-01` | `RoundService` | Server starts in `WAITING` with 0 players and automatically transitions to `INTERMISSION` (15s) when Player 1 joins. | Automated Unit | **PASS** |
| `T-M1-02` | `RoundService` | Full 8-state cycle (`WAITING` -> `INTERMISSION` -> `BOARDING` -> `TRAVEL` -> `EXPLORATION` -> `EXTRACTION` -> `RETURN` -> `RESULTS` -> `INTERMISSION`) advances cleanly using server timers. | Automated Unit | **PASS** |
| `T-M1-03` | `RoundService` (Late Join) | Player joining during `TRAVEL` or `EXPLORATION` is assigned `HUB_WAITING` in the safe Train Hub and is not placed into `_activeExpeditionUserIds`. | Automated Unit | **PASS** |
| `T-M1-04` | `RoundService` (Disconnect) | All active expedition players disconnecting during `EXPLORATION` immediately triggers `CleanupRound()` and resets state to `WAITING`. | Automated Unit | **PASS** |
| `T-M1-05` | `InventoryService` | Valid equipment requests (`Slot 1 = Flashlight`, `Slot 2 = Flare`) during `INTERMISSION`/`BOARDING` update server inventory and prevent duplicate items across slots. | Automated Unit | **PASS** |
| `T-M1-06` | `SecurityService` | Rejects out-of-range slot indices (`0`, `3`, `NaN`), non-allowlisted item IDs (`"AdminRailgun"`), non-allowlisted station IDs (`"Station999"`), and equipment changes during `EXPLORATION`. | Automated Unit | **PASS** |
| `T-M1-07` | `SecurityService` (Rate Limit) | Exceeding 6 remote calls within 1.0 second from a single player triggers rate-limit rejection. | Automated Unit | **PASS** |
| `T-M1-08` | `InteractionService` | Rejects `ProximityPrompt` activation when player distance exceeds `14.0` studs or when prompt cooldown (`0.5s`) is active. | Automated Unit | **PASS** |

---

## 3. How to Run the Automated Test Suite

```bash
npx --yes tsx --test src/engine/nightline.test.ts
```
