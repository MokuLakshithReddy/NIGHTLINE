# NIGHTLINE: LAST TRAIN

**Tagline:** Every stop is a risk. Every return is a reward.  
**Version:** 0.1.0 (Milestone 0 & Milestone 1 Complete)  
**Target Platform:** Roblox (Luau `--!strict`, Rojo 7.4+, Native Modular Service/Controller Architecture)

---

## 1. Project Overview

**NIGHTLINE: LAST TRAIN** is a 1–6 player cooperative survival adventure on Roblox. A crew boards the last functioning train traveling through an abandoned transit network, prepares equipment inside the Train Hub, votes on the next station destination, explores dangerous stations to complete objectives while evading **The Hollow**, and extracts before the train departs.

This repository provides:
1. **The Native Luau & Rojo Project (`/roblox`, `default.project.json`, `selene.toml`, `stylua.toml`, `.luaurc`, `rokit.toml`)**: Ready to sync or build into a `.rbxl` place file for Roblox Studio.
2. **Interactive Studio Workbench & Train Hub Simulator (`/src`)**: Because the cloud Linux development container does not have a desktop Roblox Studio GUI or MCP connection attached, this repository also runs an interactive 2D Train Hub & Server State Machine Workbench on port `3000` (`npm run dev`). It executes the exact Milestone 0 & Milestone 1 server state machine, `SecurityService` validation rules, `ProximityPrompt` interactions, multiplayer crew roster, late-join isolation, and Luau static verification suite.

---

## 2. Technology Stack

- **Language:** Luau (`--!strict` mode enabled across all modules)
- **Architecture:** Native modular Service (`ServerScriptService/Services`) and Controller (`StarterPlayerScripts/Controllers`) ModuleScripts with explicit `Init()` and `Start()` lifecycles. No Knit, Flamework, Nevermore, or Matter.
- **Workflow:** Rojo (`default.project.json`)
- **Formatting & Linting:** StyLua (`stylua.toml`) and Selene (`selene.toml`)
- **Toolchain Management:** Rokit / Aftman (`rokit.toml`)

---

## 3. Repository Structure

```text
/
|-- default.project.json          # Rojo project file mapping /roblox into the Roblox DataModel
|-- .luaurc                       # Luau Language Server strict mode configuration
|-- selene.toml                   # Selene linter rules (std = "roblox")
|-- stylua.toml                   # StyLua code formatting configuration
|-- rokit.toml                    # Pinned CLI versions for rojo, stylua, selene, luau-lsp
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
`-- src/                          # Interactive Train Hub Simulator & Luau Static Verifier
```

---

## 4. Setup, Build, and Sync Instructions

### 4.1 Using Rojo with Roblox Studio (Local Machine)

1. Install toolchain binaries via Rokit or Aftman:
   ```bash
   rokit install
   ```
2. Build a standalone Roblox place file (`.rbxl`):
   ```bash
   rojo build default.project.json -o NIGHTLINE_Last_Train.rbxl
   ```
3. Or start live sync into an open Roblox Studio session with the Rojo plugin installed:
   ```bash
   rojo serve default.project.json
   ```
4. Run formatting and linting locally:
   ```bash
   stylua --check roblox/
   selene roblox/
   ```

### 4.2 Manual Roblox Creator Dashboard & Studio Settings Required

When opening `NIGHTLINE_Last_Train.rbxl` in Roblox Studio for multiplayer or future DataStore testing:
1. **Max Players per Server:** Set Place Settings -> Access -> **Maximum Visitor Count = 6**.
2. **Studio API Access (prepared for Milestone 4):** Enable Game Settings -> Security -> **Enable Studio Access to API Services**.
3. **Character AutoLoads:** Leave `Players.CharacterAutoLoads = true` (default); `HubService` pivots newly spawned characters onto one of the 6 tagged `HubSpawn` pads inside the Train Hub.

### 4.3 Running Automated Tests & Workbench

```bash
# Run automated unit tests + Luau static & Rojo tree verification
npx --yes tsx --test src/engine/nightline.test.ts

# Start the interactive Train Hub & Rojo Workbench on port 3000
npm run dev
```
