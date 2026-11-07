# NIGHTLINE: LAST TRAIN

**Tagline:** Every stop is a risk. Every return is a reward.  
**Version:** 0.1.1 (Milestone 0 & Milestone 1 Complete + Issues 01–07 Resolved)  
**Target Platform:** Roblox (Luau `--!strict`, Rojo 7.7.1, Native Modular Service/Controller Architecture)

---

## 1. Project Overview

**NIGHTLINE: LAST TRAIN** is a 1–6 player cooperative survival adventure on Roblox. A crew boards the last functioning train traveling through an abandoned transit network, prepares equipment inside the Train Hub, votes on the next station destination, explores dangerous stations to complete objectives while evading **The Hollow**, and extracts before the train departs.

This repository provides:
1. **The Native Luau & Rojo 7.7.1 Project (`/roblox`, `default.project.json`, `selene.toml`, `stylua.toml`, `.luaurc`, `rokit.toml`)**: Verified with the official `rojo` (`7.7.1`), `luau-lsp` (`1.70.1`), `selene` (`0.32.0`), `stylua` (`2.6.0`), and `luau` VM (`0.746`) binaries.
2. **Real Luau VM & Toolchain Automated Test Suite (`src/engine/luauVmRunner.ts`, `src/engine/nightline.test.ts`)**: Compiles `NIGHTLINE_Last_Train.rbxl` with Rojo 7.7.1, runs `luau-lsp analyze` in `--!strict` mode, runs `selene` and `stylua --check`, and executes the actual `/roblox/**/*.lua` modules inside the official `luau` VM.
3. **Interactive Studio Workbench & Train Hub Simulator (`/src`)**: Runs an interactive 2D Train Hub & Server State Machine Workbench on port `3000` (`npm run dev`). Note: The TypeScript workbench is a visual companion for browser inspection; runtime Luau correctness is verified by the official `luau` VM and toolchain in `src/engine/luauVmRunner.ts` and requires final multi-client testing in desktop Roblox Studio.

---

## 2. Technology Stack

- **Language:** Luau (`--!strict` mode enabled across all 18 modules)
- **Architecture:** Native modular Service (`ServerScriptService/Services`) and Controller (`StarterPlayerScripts/Controllers`) ModuleScripts with explicit `Init()` and `Start()` lifecycles. No Knit, Flamework, Nevermore, or Matter.
- **Workflow:** Rojo `7.7.1` (`default.project.json`, compliant with Roblox's November 2026 content-property serialization update)
- **Formatting, Linting & Type Checking:** StyLua `2.6.0` (`stylua.toml`), Selene `0.32.0` (`selene.toml`), and Luau Language Server `1.70.1` (`.luaurc`)
- **Toolchain Management:** Rokit (`rokit.toml`)

---

## 3. Repository Structure

```text
/
|-- default.project.json          # Rojo 7.7.1 project file (no deprecated FilteringEnabled)
|-- .luaurc                       # Luau Language Server strict mode configuration
|-- selene.toml                   # Selene linter rules (std = "roblox")
|-- stylua.toml                   # StyLua code formatting configuration
|-- rokit.toml                    # Pinned CLI versions: rojo 7.7.1, stylua 2.6.0, selene 0.32.0, luau-lsp 1.70.1
|-- roblox/
|   |-- ReplicatedStorage/
|   |   |-- Shared/
|   |   |   |-- Config/
|   |   |   |   |-- GameConfig.lua
|   |   |   |   |-- ItemConfig.lua
|   |   |   |   |-- StationConfig.lua
|   |   |   |   |-- ObjectiveConfig.lua
|   |   |   |   `-- RewardConfig.lua
|   |   |   |-- Types/
|   |   |   |   `-- NetworkTypes.lua
|   |   |   `-- Utils/
|   |   |       |-- Signal.lua
|   |   |       `-- Janitor.lua
|   |   `-- Remotes/
|   |       `-- RemotesRegistry.lua
|   |-- ServerScriptService/
|   |   |-- Bootstrap.server.lua
|   |   `-- Services/
|   |       |-- SecurityService.lua
|   |       |-- MovementService.lua
|   |       |-- HubService.lua
|   |       |-- InventoryService.lua
|   |       |-- RoundService.lua
|   |       `-- InteractionService.lua
|   `-- StarterPlayer/
|       `-- StarterPlayerScripts/
|           |-- ClientBootstrap.client.lua
|           `-- Controllers/
|               |-- UIController.lua
|               |-- InputController.lua
|               `-- InteractionController.lua
|-- docs/
|   |-- ARCHITECTURE.md
|   |-- DEVELOPMENT_PROGRESS.md
|   |-- TESTING.md
|   `-- KNOWN_ISSUES.md
`-- src/                          # Luau VM Test Runner + Interactive Train Hub Workbench
```

---

## 4. Setup, Build, and Sync Instructions

### 4.1 Using Rojo 7.7.1 with Roblox Studio

1. Install toolchain binaries via Rokit:
   ```bash
   rokit install
   ```
2. Build a standalone Roblox place file (`.rbxl`):
   ```bash
   rojo build default.project.json -o NIGHTLINE_Last_Train.rbxl
   ```
3. Or start live sync into an open Roblox Studio session with the Rojo 7.7.1 plugin installed:
   ```bash
   rojo serve default.project.json
   ```
4. Run strict type analysis, formatting, and linting:
   ```bash
   rojo sourcemap default.project.json -o sourcemap.json
   luau-lsp analyze --base-luaurc=.luaurc --sourcemap=sourcemap.json roblox
   stylua --check roblox
   selene roblox
   ```

### 4.2 Manual Roblox Creator Dashboard & Studio Settings Required

When opening `NIGHTLINE_Last_Train.rbxl` in desktop Roblox Studio for multiplayer testing:
1. **Max Players per Server:** Set Place Settings -> Access -> **Maximum Visitor Count = 6**.
2. **Studio API Access (prepared for Milestone 4):** Enable Game Settings -> Security -> **Enable Studio Access to API Services**.
3. **Multiplayer Local Server Test:** In Roblox Studio -> **Test** tab -> select **Local Server** with **2–4 Players** and click **Start** to verify multi-client character spawning, sprint replication, and physical extraction zone boarding in live Studio physics.

### 4.3 Running Automated Luau VM & Toolchain Tests

```bash
# Compiles .rbxl via Rojo 7.7.1, runs luau-lsp --!strict, selene, stylua, and executes /roblox/**/*.lua in the official Luau VM
npx --yes tsx --test src/engine/nightline.test.ts

# Start the interactive Train Hub & Rojo Workbench on port 3000
npm run dev
```
