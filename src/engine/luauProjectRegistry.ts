import defaultProjectJson from '../../default.project.json?raw';
import luauRcRaw from '../../.luaurc?raw';
import seleneTomlRaw from '../../selene.toml?raw';
import styluaTomlRaw from '../../stylua.toml?raw';
import rokitTomlRaw from '../../rokit.toml?raw';
import bootstrapToolchainShRaw from '../../scripts/bootstrap-toolchain.sh?raw';
import githubCiYmlRaw from '../../.github/workflows/ci.yml?raw';

import networkTypesLua from '../../roblox/ReplicatedStorage/Shared/Types/NetworkTypes.lua?raw';
import gameConfigLua from '../../roblox/ReplicatedStorage/Shared/Config/GameConfig.lua?raw';
import itemConfigLua from '../../roblox/ReplicatedStorage/Shared/Config/ItemConfig.lua?raw';
import stationConfigLua from '../../roblox/ReplicatedStorage/Shared/Config/StationConfig.lua?raw';
import objectiveConfigLua from '../../roblox/ReplicatedStorage/Shared/Config/ObjectiveConfig.lua?raw';
import rewardConfigLua from '../../roblox/ReplicatedStorage/Shared/Config/RewardConfig.lua?raw';
import signalLua from '../../roblox/ReplicatedStorage/Shared/Utils/Signal.lua?raw';
import janitorLua from '../../roblox/ReplicatedStorage/Shared/Utils/Janitor.lua?raw';
import remotesRegistryLua from '../../roblox/ReplicatedStorage/Remotes/RemotesRegistry.lua?raw';

import bootstrapServerLua from '../../roblox/ServerScriptService/Bootstrap.server.lua?raw';
import securityServiceLua from '../../roblox/ServerScriptService/Services/SecurityService.lua?raw';
import movementServiceLua from '../../roblox/ServerScriptService/Services/MovementService.lua?raw';
import hubServiceLua from '../../roblox/ServerScriptService/Services/HubService.lua?raw';
import inventoryServiceLua from '../../roblox/ServerScriptService/Services/InventoryService.lua?raw';
import roundServiceLua from '../../roblox/ServerScriptService/Services/RoundService.lua?raw';
import interactionServiceLua from '../../roblox/ServerScriptService/Services/InteractionService.lua?raw';

import clientBootstrapLua from '../../roblox/StarterPlayer/StarterPlayerScripts/ClientBootstrap.client.lua?raw';
import uiControllerLua from '../../roblox/StarterPlayer/StarterPlayerScripts/Controllers/UIController.lua?raw';
import inputControllerLua from '../../roblox/StarterPlayer/StarterPlayerScripts/Controllers/InputController.lua?raw';
import interactionControllerLua from '../../roblox/StarterPlayer/StarterPlayerScripts/Controllers/InteractionController.lua?raw';

import readmeMd from '../../README.md?raw';
import architectureMd from '../../docs/ARCHITECTURE.md?raw';
import progressMd from '../../docs/DEVELOPMENT_PROGRESS.md?raw';
import testingMd from '../../docs/TESTING.md?raw';
import knownIssuesMd from '../../docs/KNOWN_ISSUES.md?raw';

export interface ProjectSourceFile {
  path: string;
  robloxInstancePath: string;
  category: 'Rojo & Toolchain' | 'ReplicatedStorage' | 'ServerScriptService' | 'StarterPlayerScripts' | 'Documentation';
  summary: string;
  content: string;
}

export const PROJECT_SOURCE_FILES: ProjectSourceFile[] = [
  {
    path: '.github/workflows/ci.yml',
    robloxInstancePath: 'GitHub Actions CI Pipeline',
    category: 'Rojo & Toolchain',
    summary: 'Automated CI workflow running bootstrap-toolchain.sh, StyLua, Selene, Luau-LSP, Rojo build, and Luau VM tests.',
    content: githubCiYmlRaw,
  },
  {
    path: 'scripts/bootstrap-toolchain.sh',
    robloxInstancePath: 'Clean-Checkout Toolchain Installer',
    category: 'Rojo & Toolchain',
    summary: 'Installs official luau (0.746), luau-analyze, luau-lsp (1.70.1), globalTypes.d.luau, rojo (7.7.1), stylua, and selene.',
    content: bootstrapToolchainShRaw,
  },
  {
    path: 'default.project.json',
    robloxInstancePath: 'DataModel (Rojo Root)',
    category: 'Rojo & Toolchain',
    summary: 'Rojo 7.7.1 project file mapping /roblox scripts and Workspace.World.Hub folders.',
    content: defaultProjectJson,
  },
  {
    path: '.luaurc',
    robloxInstancePath: 'Luau Language Server Config',
    category: 'Rojo & Toolchain',
    summary: 'Enforces strict Luau type checking ("languageMode": "strict") and lint diagnostics.',
    content: luauRcRaw,
  },
  {
    path: 'selene.toml',
    robloxInstancePath: 'Selene Linter Config',
    category: 'Rojo & Toolchain',
    summary: 'Configures Roblox standard library linting rules for Selene.',
    content: seleneTomlRaw,
  },
  {
    path: 'stylua.toml',
    robloxInstancePath: 'StyLua Formatter Config',
    category: 'Rojo & Toolchain',
    summary: 'Configures deterministic Luau formatting (tabs, width 100, double quotes).',
    content: styluaTomlRaw,
  },
  {
    path: 'rokit.toml',
    robloxInstancePath: 'Rokit / Aftman Toolchain',
    category: 'Rojo & Toolchain',
    summary: 'Pins CLI versions for rojo 7.7.1, stylua 2.6.0, selene 0.32.0, and luau-lsp 1.70.1.',
    content: rokitTomlRaw,
  },
  {
    path: 'roblox/ReplicatedStorage/Shared/Types/NetworkTypes.lua',
    robloxInstancePath: 'ReplicatedStorage.Shared.Types.NetworkTypes',
    category: 'ReplicatedStorage',
    summary: 'Strict Luau exported types for RoundState, PlayerRoundStatus, RoundOutcome, and Remote payloads.',
    content: networkTypesLua,
  },
  {
    path: 'roblox/ReplicatedStorage/Shared/Config/GameConfig.lua',
    robloxInstancePath: 'ReplicatedStorage.Shared.Config.GameConfig',
    category: 'ReplicatedStorage',
    summary: 'Centralized round timings, crew limits, walk/sprint speeds, extraction radius, and security tolerances.',
    content: gameConfigLua,
  },
  {
    path: 'roblox/ReplicatedStorage/Shared/Config/ItemConfig.lua',
    robloxInstancePath: 'ReplicatedStorage.Shared.Config.ItemConfig',
    category: 'ReplicatedStorage',
    summary: 'Definitions and allowlist for MVP equipment (Flashlight, Flare) and mission items (Fuse).',
    content: itemConfigLua,
  },
  {
    path: 'roblox/ReplicatedStorage/Shared/Config/StationConfig.lua',
    robloxInstancePath: 'ReplicatedStorage.Shared.Config.StationConfig',
    category: 'ReplicatedStorage',
    summary: 'Metadata and mission pool for Station 001: The Forgotten Terminal.',
    content: stationConfigLua,
  },
  {
    path: 'roblox/ReplicatedStorage/Shared/Config/ObjectiveConfig.lua',
    robloxInstancePath: 'ReplicatedStorage.Shared.Config.ObjectiveConfig',
    category: 'ReplicatedStorage',
    summary: 'Mission templates (RestorePower, RecoverCargo, RepairSignal) and required counts.',
    content: objectiveConfigLua,
  },
  {
    path: 'roblox/ReplicatedStorage/Shared/Config/RewardConfig.lua',
    robloxInstancePath: 'ReplicatedStorage.Shared.Config.RewardConfig',
    category: 'ReplicatedStorage',
    summary: 'Server reward formula constants for Scrap and extraction bonuses.',
    content: rewardConfigLua,
  },
  {
    path: 'roblox/ReplicatedStorage/Shared/Utils/Signal.lua',
    robloxInstancePath: 'ReplicatedStorage.Shared.Utils.Signal',
    category: 'ReplicatedStorage',
    summary: 'Lightweight Luau Signal & Connection implementation with DisconnectAll().',
    content: signalLua,
  },
  {
    path: 'roblox/ReplicatedStorage/Shared/Utils/Janitor.lua',
    robloxInstancePath: 'ReplicatedStorage.Shared.Utils.Janitor',
    category: 'ReplicatedStorage',
    summary: 'Deterministic round resource cleanup tracker for Instances, Connections, and threads.',
    content: janitorLua,
  },
  {
    path: 'roblox/ReplicatedStorage/Remotes/RemotesRegistry.lua',
    robloxInstancePath: 'ReplicatedStorage.Remotes.RemotesRegistry',
    category: 'ReplicatedStorage',
    summary: 'Creates and validates all 8 Networking Contract RemoteEvents (including RequestSprint).',
    content: remotesRegistryLua,
  },
  {
    path: 'roblox/ServerScriptService/Bootstrap.server.lua',
    robloxInstancePath: 'ServerScriptService.Bootstrap',
    category: 'ServerScriptService',
    summary: 'Server bootstrap initializing Remotes and Services in strict dependency order.',
    content: bootstrapServerLua,
  },
  {
    path: 'roblox/ServerScriptService/Services/SecurityService.lua',
    robloxInstancePath: 'ServerScriptService.Services.SecurityService',
    category: 'ServerScriptService',
    summary: 'Per-player rate limiting, cooldowns, string/integer validation, and character distance checks.',
    content: securityServiceLua,
  },
  {
    path: 'roblox/ServerScriptService/Services/MovementService.lua',
    robloxInstancePath: 'ServerScriptService.Services.MovementService',
    category: 'ServerScriptService',
    summary: 'Server-authoritative sprint validation, WalkSpeed application, and movement speed/teleport rubberbanding.',
    content: movementServiceLua,
  },
  {
    path: 'roblox/ServerScriptService/Services/HubService.lua',
    robloxInstancePath: 'ServerScriptService.Services.HubService',
    category: 'ServerScriptService',
    summary: 'Builds Train Hub, explicit 1..6 spawn-slot allocator, Recovery Bay berths, and physical Extraction Platform zone.',
    content: hubServiceLua,
  },
  {
    path: 'roblox/ServerScriptService/Services/InventoryService.lua',
    robloxInstancePath: 'ServerScriptService.Services.InventoryService',
    category: 'ServerScriptService',
    summary: 'Server-authoritative 2-slot equipment loadout and RequestEquipment validation.',
    content: inventoryServiceLua,
  },
  {
    path: 'roblox/ServerScriptService/Services/RoundService.lua',
    robloxInstancePath: 'ServerScriptService.Services.RoundService',
    category: 'ServerScriptService',
    summary: 'Authoritative 8-state round loop, state-aware respawning, elimination handling, and physical extraction validation.',
    content: roundServiceLua,
  },
  {
    path: 'roblox/ServerScriptService/Services/InteractionService.lua',
    robloxInstancePath: 'ServerScriptService.Services.InteractionService',
    category: 'ServerScriptService',
    summary: 'Server-side ProximityPromptService.PromptTriggered distance, tag, and ExtractionPlatformZone validation.',
    content: interactionServiceLua,
  },
  {
    path: 'roblox/StarterPlayer/StarterPlayerScripts/ClientBootstrap.client.lua',
    robloxInstancePath: 'StarterPlayer.StarterPlayerScripts.ClientBootstrap',
    category: 'StarterPlayerScripts',
    summary: 'Client bootstrap initializing UIController, InputController, and InteractionController.',
    content: clientBootstrapLua,
  },
  {
    path: 'roblox/StarterPlayer/StarterPlayerScripts/Controllers/UIController.lua',
    robloxInstancePath: 'StarterPlayer.StarterPlayerScripts.Controllers.UIController',
    category: 'StarterPlayerScripts',
    summary: 'Responsive ScreenGui HUD for round state, countdown, crew roster, and 2-slot inventory.',
    content: uiControllerLua,
  },
  {
    path: 'roblox/StarterPlayer/StarterPlayerScripts/Controllers/InputController.lua',
    robloxInstancePath: 'StarterPlayer.StarterPlayerScripts.Controllers.InputController',
    category: 'StarterPlayerScripts',
    summary: 'Cross-platform input bindings (PC Shift/1/2, Mobile Touch Sprint, Gamepad ButtonL3/DPad).',
    content: inputControllerLua,
  },
  {
    path: 'roblox/StarterPlayer/StarterPlayerScripts/Controllers/InteractionController.lua',
    robloxInstancePath: 'StarterPlayer.StarterPlayerScripts.Controllers.InteractionController',
    category: 'StarterPlayerScripts',
    summary: 'Client-side ProximityPrompt highlight affordances on Train Hub terminals.',
    content: interactionControllerLua,
  },
  {
    path: 'README.md',
    robloxInstancePath: 'Repository Root',
    category: 'Documentation',
    summary: 'Project overview, Rojo build/serve commands, and manual Studio settings.',
    content: readmeMd,
  },
  {
    path: 'docs/ARCHITECTURE.md',
    robloxInstancePath: 'docs/ARCHITECTURE.md',
    category: 'Documentation',
    summary: 'Authority boundary, Service/Controller lifecycles, and Networking Contract.',
    content: architectureMd,
  },
  {
    path: 'docs/DEVELOPMENT_PROGRESS.md',
    robloxInstancePath: 'docs/DEVELOPMENT_PROGRESS.md',
    category: 'Documentation',
    summary: 'Milestone 0 & Milestone 1 completion report and roadmap status.',
    content: progressMd,
  },
  {
    path: 'docs/TESTING.md',
    robloxInstancePath: 'docs/TESTING.md',
    category: 'Documentation',
    summary: 'Executed static, unit, and workbench test cases and verification evidence.',
    content: testingMd,
  },
  {
    path: 'docs/KNOWN_ISSUES.md',
    robloxInstancePath: 'docs/KNOWN_ISSUES.md',
    category: 'Documentation',
    summary: 'Environment limitations and Milestone 1 scope boundaries.',
    content: knownIssuesMd,
  },
];
