# NIGHTLINE: LAST TRAIN
## Game Design, Product Requirements and Technical Build Specification

**Version:** 1.0  
**Date:** 7 November 2026  
**Audience:** Coding agent implementing the Roblox experience for a solo developer  
**Tagline:** Every stop is a risk. Every return is a reward.

---

# Document purpose and instructions to the coding agent

This document is the source of truth for the first playable version of NIGHTLINE: LAST TRAIN. Use it to inspect the current project, implement the experience in small working increments, and verify each increment in Roblox Studio. The goal is a polished, replayable Roblox multiplayer survival experience—not a pitch deck, mock-up, or disconnected set of scripts.

> **AGENT OPERATING RULE** Inspect the existing repository and Roblox place before changing anything. Preserve valid work. Do not overwrite an existing project or invent access to external services. If an operation requires the developer to click or configure something in Roblox Creator Dashboard, provide exact manual steps instead of claiming it has been completed.

## Implementation rules

- Build in the milestone order in Section 17. Do not implement every planned feature at once.
- Keep the first release small: one train hub, one station, one monster, three mission templates, one permanent currency and a complete expedition loop.
- Use native Roblox Studio, Luau and Roblox platform services. Do not add an external backend, database, paid framework or third-party package unless a concrete requirement cannot be met natively and the developer approves it.
- Keep authoritative gameplay on the server. Treat all client-originated values and requests as untrusted.
- Use modular ModuleScripts with clear responsibilities. Avoid one giant script and avoid unnecessary framework abstractions.
- Use --!strict in modules where practical; define shared types and configuration rather than duplicating magic values.
- Use original or properly licensed assets only. Do not insert unknown free models or scripts with hidden dependencies. Document the source and license of imported assets.
- Every milestone must end with a playable test, a list of changed files, test evidence, known limitations and the next recommended task.
- Do not claim a feature is complete unless it runs in Studio and passes its acceptance criteria.

# 1. Product vision and positioning

## 1.1 One-sentence pitch

NIGHTLINE is a 1–6 player cooperative survival adventure in which a crew rides the last train through an abandoned city, explores dangerous stations for resources and objectives, evades a sound-hunting creature, and must return before the train departs.

## 1.2 Player promise

Every expedition gives the crew a short, readable mission, a changing risk-versus-reward decision, a memorable threat encounter and progress toward improving the train. The train is both the safe hub and the shared long-term project.

## 1.3 Product goals

- Make the core loop understandable within the first minute without requiring a long tutorial.
- Make a complete first expedition possible for a solo player while remaining more social with a crew.
- Create replayability through changing objective locations, loot placement and a small set of station events.
- Give players a persistent, understandable reason to return through train upgrades and collectible artifacts.
- Support PC, mobile and controller input for all essential actions.
- Build a codebase that a solo developer can maintain and expand without rewriting core systems.

## 1.4 Non-goals for the first public version

- No open-world city or multiple connected public places.
- No procedural generation of entire station geometry.
- No player trading, crafting tree, player housing or guild system.
- No PvP combat, firearms or complex combat abilities.
- No cross-server custom matchmaking unless default Roblox server matchmaking is proven insufficient.
- No paid power advantages, premium currency or battle pass at initial launch.
- No requirement for a separate website, API server, Supabase, Redis or other external backend.

# 2. Product definition and launch scope

| Attribute | Launch decision |
| --- | --- |
| Working title | NIGHTLINE: LAST TRAIN; verify title availability and naming conflicts before publishing. |
| Platform | Roblox experience built in Roblox Studio. |
| Genre | Cooperative survival, exploration, light horror and collection progression. |
| Players | 1–6 players in one server/crew. Solo play must be supported. |
| Camera | Third-person Roblox character camera; no mandatory first-person mode. |
| Session target | Approximately 5–7 minutes for one expedition, excluding time spent waiting in the hub. |
| Art direction | Stylized 3D / readable low-poly forms, distinctive silhouettes, controlled lighting. |
| Business model | Free to play. Cosmetic monetization may be added after the core loop is validated. |
| Server model | One Roblox server runs one crew and one active expedition at a time. |

> **SCOPE CONTROL** The scope above is the launch target. Additional stations, monsters, trading, procedural maps and advanced progression are future expansions, not reasons to delay the first playable version.

# 3. Core gameplay loop and round design

## 3.1 Core loop

1. Join the train hub and form a crew. A solo player may start an expedition.
2. Prepare equipment and review the selected station mission.
3. Ride to Station 001.
4. Explore, complete the primary objective and optionally collect loot.
5. Avoid The Hollow. Noise and visibility can expose players.
6. Return to the marked extraction platform before departure.
7. Receive server-calculated rewards, return to the hub and spend Scrap on progression.
8. Repeat with changed objective/loot locations and station events.

## 3.2 Round states and timings

| State | Target duration | Server responsibilities |
| --- | --- | --- |
| WAITING | Until one or more players are available | Maintain hub; do not run an expedition. |
| INTERMISSION | 15 seconds (tunable) | Announce countdown; accept eligible players and destination votes if enabled. |
| BOARDING | 45 seconds | Lock crew roster for the round; show mission and equipment preparation. |
| TRAVEL | 20 seconds | Transition to station; play train travel sequence. |
| EXPLORATION | 180 seconds | Enable objectives, loot and monster; track mission progress. |
| EXTRACTION | 60 seconds | Warn crew; open/mark return route; continue threat pressure. |
| RETURN | 20 seconds | Resolve extraction; move surviving/extracted players to the train hub. |
| RESULTS | 30 seconds | Show outcome and rewards; clean temporary station state. |

Nominal timed cycle is approximately 6 minutes 10 seconds when all timed states run in sequence. All durations must be centralized in GameConfig and adjustable after playtesting. If the crew completes the main objective early, it may still use remaining exploration time to collect optional loot; extraction starts at the configured deadline.

## 3.3 State transition rules

- Only RoundService may change the authoritative round state.
- A state transition must be explicit, logged and broadcast to clients after the server state is updated.
- A round cannot start if another round is active or if there are no eligible players.
- A late-joining player remains in the safe hub and is eligible for the next round; do not spawn them into an active station.
- If all active expedition players leave or become ineligible, terminate the round safely and clean all runtime objects.
- If every active player is eliminated or fails extraction, mark the expedition as failed and still execute results/cleanup.
- Timers must be server-owned. Clients display the remaining time but do not authoritatively control it.

## 3.4 Player outcome rules

- A player who returns to the extraction point before departure counts as extracted.
- A player hit by The Hollow is eliminated from the current expedition and returned to the safe hub or a spectator state; they cannot re-enter the active station.
- An eliminated player may receive the completed primary-mission reward if the crew completed it, but does not receive the extraction bonus. Keep this rule configurable.
- Permanent Scrap and previously saved progression are never erased because an expedition failed.
- A disconnected player receives no uncommitted expedition reward. Do not attempt to save transient round state as permanent progression.

# 4. Station 001: The Forgotten Terminal

The first station is a compact, hand-authored level. It should be easy to learn but support different runs through randomized objective placement, loot spawns and a small selection of events. Do not procedurally generate the full map in the MVP.

## 4.1 Required areas

| Area | Gameplay purpose | Design notes |
| --- | --- | --- |
| Train platform | Entry and extraction | Clear landmark, readable return path, safe-side boundary. |
| Main concourse | Navigation hub | Connects major areas; signage and sightlines should orient players. |
| Maintenance room | Fuse objective / equipment | Contains safe and risky routes; clear interactable locations. |
| Control room | Signal objective | Console/terminal interactions; visual feedback for progress. |
| Cargo storage | Lost cargo objective / loot | Carryable containers; optional rewards. |
| Underground tunnel | High-risk optional exploration | Potential rare loot and strong monster encounter space; do not make it mandatory for basic navigation. |

## 4.2 Mission templates

| Mission | Required interaction | Completion condition |
| --- | --- | --- |
| Restore Power | Find and install 3 fuses in designated sockets. | All 3 valid fuse sockets activated. |
| Recover Lost Cargo | Locate and deliver 2 cargo containers to the marked drop point. | Both server-tracked containers delivered. |
| Repair the Signal | Activate 3 communication terminals in the station. | All 3 terminals activated. |

All three mission templates should exist in the launch build. Select one primary mission per expedition. Mission counts and rewards are configuration values. Use server-side objective state; never accept a client claim that an objective is complete.

## 4.3 Randomization rules

- Randomize among valid predefined objective spawn points; do not place an objective inside blocked geometry or beyond an inaccessible route.
- Randomize optional loot among tagged spawn points with rarity weights defined in configuration.
- Select zero or one small station event in the earliest build; increase to two or three only after stability is proven.
- Use a server-side random seed per round and log the seed for reproducible debugging.
- The station layout, platform location and critical navigation landmarks remain fixed in the MVP.

## 4.4 Initial station events

| Event | Effect | MVP priority |
| --- | --- | --- |
| Power failure | Temporarily disables selected lights or changes lighting in one zone. | Optional after core loop. |
| Locked maintenance door | Blocks one route and encourages an alternate path. | Optional after core loop. |
| Supply cache | Spawns a temporary optional loot opportunity. | Recommended first event. |
| False emergency signal | Creates misleading audio or a distraction. | Future update. |

# 5. Enemy specification: The Hollow

The Hollow is the signature threat. It is a stylized, non-graphic shadow creature with a recognizable silhouette, distinct audio cues and readable behaviour. It should create tension through investigation and pursuit, not through constant unavoidable chasing.

## 5.1 MVP behaviour states

| State | Behaviour | Exit condition |
| --- | --- | --- |
| PATROL | Follow authored patrol points within an assigned zone. | Noise event, player detection or alert condition. |
| INVESTIGATE | Move toward the strongest valid recent noise event. | Target found, event expires or route is unreachable. |
| CHASE | Pursue a detected player using server pathfinding. | Target is lost, unreachable or leaves valid station bounds. |
| SEARCH | Search near the target’s last known position. | Search timeout or a new target is detected. |
| RETURN | Navigate back to patrol zone. | Return completed; resume PATROL. |

## 5.2 Detection and sound rules

- Running generates a louder noise event than walking.
- Some objective interactions generate a short noise event.
- A noise event contains a world position, loudness/radius, timestamp and source category; it must be created by trusted server logic.
- Line-of-sight checks use server raycasts and defined detection range/angle values.
- The Hollow chooses a target using simple, explainable rules (recent noise, visibility, distance and current state).
- Do not run expensive pathfinding or target scans every frame. Use controlled update intervals and recalculate when a path is blocked or the target changes materially.

## 5.3 Player threat and fairness

- A successful monster attack eliminates the player from the current expedition for the MVP. Do not permanently remove currency or saved progress.
- Provide clear audio/visual telegraphing before an attack where feasible.
- Avoid attacks through walls, attacks from outside the station bounds or repeated hit events in one animation.
- Include a server-side attack cooldown and validate range/line of sight before applying the result.
- Solo difficulty must be tuned so a player can learn and escape; do not scale threat solely by increasing speed or damage.

## 5.4 AI implementation constraints

- Use PathfindingService for navigation and a finite-state-machine module for behaviour.
- Compute paths at controlled intervals, on target change, or when the current path becomes blocked.
- Use collision groups and path-agent settings appropriate to the monster dimensions.
- Keep the authoritative NPC simulation on the server; set network ownership appropriately for the NPC assembly where needed.
- Provide a safe fallback if a path cannot be computed: wait, choose a nearby valid waypoint or return to patrol. Never leave the AI in an infinite loop.

# 6. Equipment, inventory and interactions

## 6.1 MVP equipment and items

| Item | Type | Function | Priority |
| --- | --- | --- | --- |
| Flashlight | Equipment | Provides readable local illumination; battery depletion may be a later tuning feature. | MVP |
| Flare | Consumable | Creates a temporary distraction/noise stimulus to redirect The Hollow. | MVP if feasible |
| Fuse | Mission item | Used only for Restore Power; server tracks objective use. | MVP |
| Battery | Loot / consumable | Optional flashlight charge; can be postponed if flashlight has no charge system. | Later |
| Medkit | Consumable | Potential revive/heal mechanic. | Post-MVP |

Limit the initial player equipment loadout to two slots. Mission items may be tracked separately from equipment slots so players cannot accidentally unequip or drop a critical objective item. Keep inventory behaviour simple and server-owned.

## 6.2 Interaction rules

- Use ProximityPrompt for contextual interaction with doors, terminals, fuse sockets, cargo and loot.
- Handle prompt activation on the server and validate character existence, living/eligible state, distance, round state, object state and cooldown.
- Use CollectionService tags and attributes to identify interactable categories; avoid fragile logic based solely on object names.
- Every interactable must transition from available to used/complete atomically on the server to prevent duplicate pickups or duplicate objective progress.
- Provide client-side prompt feedback, but never treat client UI state as proof of a successful interaction.

# 7. Progression, rewards and economy

## 7.1 Currencies

| Currency | Role | How acquired | Use |
| --- | --- | --- | --- |
| Scrap | Primary permanent currency | Mission completion, extraction, optional recovered caches. | Train upgrades and earned cosmetics. |
| Artifacts | Collection items, not spendable currency | Rare optional station finds. | Collection completion and cosmetic unlocks. |

Do not add a premium currency in the MVP. The economy must be configurable and tested for progression pacing. Suggested initial reward values are placeholders only; put them in RewardConfig and tune using playtest data.

## 7.2 Reward calculation

Use a server-side reward formula with separate, auditable components: primary mission reward + extraction bonus + eligible optional loot. Define eligibility per player. A player who extracts receives the extraction bonus; a player eliminated earlier may receive the mission reward if the crew completed the mission. Never trust client-supplied reward amounts.

## 7.3 Progression categories

| Category | Examples | Launch treatment |
| --- | --- | --- |
| Train upgrades | Lighting, equipment locker, workshop, cargo storage, advanced engine. | Implement a small starter set; make costs and effects configurable. |
| Station unlocks | Additional destinations and routes. | Station 001 is initially available; future stations are locked content. |
| Artifacts | Named collectible set with rarity and collection progress. | Basic collection tracking; no trading. |
| Cosmetics | Train exterior/interior appearance and character cosmetics. | Earned cosmetics may be included; paid cosmetics later. |

## 7.4 Progression fairness

- Core mission completion must not require paid items.
- Paid cosmetics must not improve movement speed, monster resistance, damage or reward multipliers.
- Permanent progress survives failed expeditions.
- Prices and reward values are configuration-driven, not scattered through service scripts.
- Prevent duplicate grants by tracking the source of a reward or making reward processing idempotent.

# 8. UX, UI and accessibility requirements

## 8.1 Required screens

| Screen | Required content |
| --- | --- |
| Main menu | Play, settings, credits and basic game identity. |
| Train hub | Crew roster, next mission/destination, equipment, upgrade access and round countdown. |
| Gameplay HUD | Mission title/progress, departure timer, player status, equipment slots and teammate status. |
| Inventory / equipment | Two equipment slots and clear item descriptions. |
| Results | Mission outcome, extracted/eliminated status, rewards and progression changes. |
| Upgrade shop | Scrap balance, available upgrades, cost, effect and purchase confirmation. |

## 8.2 Controls

| Action | Keyboard / mouse | Touch | Controller |
| --- | --- | --- | --- |
| Move | WASD | Roblox virtual joystick | Left stick |
| Look | Mouse | Touch drag | Right stick |
| Jump | Space | Roblox jump control | A / cross (platform mapping) |
| Interact | E / prompt key | Contextual prompt button | Contextual prompt button |
| Sprint | Shift | Visible sprint control | Dedicated or contextual mapping |
| Equipment | 1 / 2 or UI | Two touch buttons | D-pad / mapped buttons |

## 8.3 UI and accessibility rules

- Use responsive layouts and anchor/scale constraints; do not rely on fixed pixel positions.
- All critical information must remain readable on small phone screens.
- Do not use colour alone to communicate mission progress or danger; pair colour with text/icon/sound.
- Provide settings for master/music/effects volume if audio is used extensively.
- Use short, plain-language objective instructions and clear success/failure feedback.
- Use Roblox contextual prompts for platform-specific input affordances.
- Avoid a long onboarding sequence. Teach movement and interaction in the hub or through the first objective.

# 9. Technical architecture

## 9.1 Architecture principle

> **AUTHORITY BOUNDARY** The server owns round state, objective state, item ownership, monster decisions, player rewards, upgrades, purchase validation and persistent data. The client owns input, local UI, camera presentation, non-authoritative visual effects and audio presentation.

## 9.2 High-level flow

```text
ROBLOX CLIENT
  Input / UI / Camera / Audio / Local VFX
          |
          | validated RemoteEvents / platform prompts
          v
ROBLOX SERVER
  RoundService -> StationService -> ObjectiveService
  MonsterService -> InventoryService -> RewardService
  PlayerDataService -> PurchaseService -> SecurityService
          |
          v
ROBLOX PLATFORM SERVICES
  DataStoreService / MarketplaceService / AnalyticsService
```

## 9.3 Recommended Roblox services

| Roblox service / facility | Use |
| --- | --- |
| Players | Player lifecycle and crew membership. |
| ReplicatedStorage | Shared config/types and RemoteEvents only; avoid storing large server-only assets here. |
| ServerScriptService | Server bootstrap and service modules. |
| ServerStorage | Server-only station, monster, item and equipment templates. |
| StarterPlayerScripts | Client controllers for input, interaction presentation, camera and effects. |
| StarterGui | ScreenGui assets and UI components. |
| DataStoreService | Persistent currency, upgrades, cosmetics, artifacts and statistics. |
| PathfindingService | Monster navigation. |
| CollectionService | Tags for interactables, spawn points, patrol points and loot locations. |
| ProximityPromptService | Contextual interaction events and prompt handling. |
| MarketplaceService | Optional future pass/product purchase handling. |
| AnalyticsService | Engagement and gameplay funnel events. |
| SoundService | Audio groups, music, environment and effects. |

## 9.4 Project tree

```text
NIGHTLINE/
|-- Workspace/
|   |-- World/
|   |   |-- Hub/
|   |   |   |-- Train/
|   |   |   `-- Spawns/
|   |   `-- Runtime/
|   |       `-- ActiveStation/       (cloned at runtime)
|   `-- Environment/
|
|-- ReplicatedStorage/
|   |-- Shared/
|   |   |-- Config/
|   |   |   |-- GameConfig.lua
|   |   |   |-- ItemConfig.lua
|   |   |   |-- StationConfig.lua
|   |   |   |-- MonsterConfig.lua
|   |   |   |-- ObjectiveConfig.lua
|   |   |   `-- RewardConfig.lua
|   |   |-- Types/
|   |   `-- Utils/
|   `-- Remotes/
|
|-- ServerScriptService/
|   |-- Bootstrap.server.lua
|   |-- Services/
|   |   |-- RoundService.lua
|   |   |-- StationService.lua
|   |   |-- ObjectiveService.lua
|   |   |-- MonsterService.lua
|   |   |-- InventoryService.lua
|   |   |-- InteractionService.lua
|   |   |-- RewardService.lua
|   |   |-- PlayerDataService.lua
|   |   |-- PurchaseService.lua        (stub until monetization)
|   |   |-- SecurityService.lua
|   |   `-- AnalyticsService.lua
|   `-- AI/
|       |-- HollowAI.lua
|       `-- AIStateMachine.lua
|
|-- ServerStorage/
|   |-- Assets/
|   |   |-- Stations/Station001/
|   |   |-- Monsters/Hollow/
|   |   |-- Items/
|   |   `-- Equipment/
|   `-- Templates/
|
|-- StarterGui/
|   `-- NIGHTLINEGui/
|       |-- MainMenu/
|       |-- TrainHub/
|       |-- GameplayHUD/
|       |-- Inventory/
|       |-- Results/
|       `-- UpgradeShop/
|
`-- StarterPlayer/
    `-- StarterPlayerScripts/
        |-- ClientBootstrap.client.lua
        `-- Controllers/
            |-- UIController.client.lua
            |-- InputController.client.lua
            |-- CameraController.client.lua
            |-- InteractionController.client.lua
            |-- AudioController.client.lua
            `-- EffectsController.client.lua
```

The tree is a logical target, not a requirement to create empty folders for every future feature on day one. Create folders and modules as their milestone begins. Keep station templates and server-only assets in ServerStorage; clone only the active station into Workspace at runtime.

# 10. Module and service responsibilities

| Module / service | Responsibilities | Must not do |
| --- | --- | --- |
| Bootstrap.server.lua | Create/validate remotes; initialize services in dependency order; connect player lifecycle; start RoundService. | Contain all game logic or perform long yielding initialization without error handling. |
| RoundService | Own state machine, timers, roster, phase transitions, outcome and cleanup orchestration. | Trust client timers or allow multiple concurrent rounds. |
| StationService | Clone/unload Station001, choose valid spawn points, place objective/loot markers, manage station events. | Grant player rewards or own round state. |
| ObjectiveService | Create mission instance, validate progress, track completion and publish objective updates. | Accept objective completion claims from clients. |
| MonsterService / HollowAI | Spawn and manage The Hollow, run state machine, detect players/noise and apply validated attack outcome. | Run unbounded per-frame scans or trust client positions as proof of hit. |
| InventoryService | Own equipment slots, mission item counts, consumables and item pickup state. | Allow a client to set item counts or item IDs. |
| InteractionService | Register tagged interactables/prompts, validate proximity/state/cooldowns and route accepted interactions. | Use object names as the sole validation contract. |
| RewardService | Calculate eligible rewards, make grants idempotent and call PlayerDataService. | Accept reward amounts from client. |
| PlayerDataService | Load, validate, migrate, cache and save persistent player profiles. | Save every frame or silently replace a failed load with defaults. |
| SecurityService | Centralize rate limits and reusable server validation helpers. | Be the only place where domain-specific validation occurs; services must validate their own rules too. |
| AnalyticsService | Record key server-confirmed gameplay events. | Send personally identifying or unnecessary sensitive information. |

# 11. Networking contract

Create RemoteEvents in ReplicatedStorage/Remotes and document their direction and payload. Prefer a small, explicit set of events. Do not create a RemoteFunction for every UI operation. A client request should receive an explicit server result/notification when needed.

| RemoteEvent | Direction | Payload outline | Server validation |
| --- | --- | --- | --- |
| RoundStateChanged | Server → clients | state, serverTimestamp, phaseEndsAt, stationId | Server-authored only. |
| ObjectiveUpdated | Server → clients | objectiveId, progress, requiredProgress, isComplete | Server-authored only. |
| PlayerStatusUpdated | Server → clients | userId, status, health/status summary | Server-authored only. |
| InventoryUpdated | Server → owning client (or relevant crew) | server-approved slot/item summary | Server-authored only. |
| Notification | Server → client(s) | messageKey, safe display parameters, severity | Server-authored only. |
| RequestEquipment | Client → server | slotIndex, requestedItemId or action | Validate phase, ownership, slot, item availability and cooldown. |
| RequestDestinationVote | Client → server | stationId | Validate eligible player, current phase and allowed station. |

For ProximityPrompt interactions, prefer handling PromptTriggered on the server rather than sending a separate client “I collected this” RemoteEvent. The server still validates distance, player status, round phase, prompt/object availability and interaction cooldown. All client-to-server remotes must use strict type checks, bounds checks and rate limits.

## 11.1 Remote safety checklist

- Validate that the player argument is the actual sender where the Roblox event provides it; do not accept a userId supplied by the client as identity.
- Validate strings against allowlists and maximum lengths.
- Validate numbers for type, finite value and expected range.
- Validate phase and player eligibility before performing an action.
- Validate distance using server-observed character position and a reasonable tolerance.
- Check item ownership and object state on the server.
- Apply per-player rate limits and cooldowns.
- Return safe, minimal error messages; do not expose internal stack traces or data-store details to clients.

# 12. Persistent data and data model

## 12.1 Suggested profile schema

```lua
local DefaultData = {
    SchemaVersion = 1,
    Scrap = 0,
    UnlockedStations = { Station001 = true },
    TrainUpgrades = {},
    OwnedCosmetics = {},
    EquippedCosmetics = {},
    Artifacts = {},
    Statistics = {
        Runs = 0,
        SuccessfulEscapes = 0,
        ObjectivesCompleted = 0,
        ItemsRecovered = 0,
    },
}
```

This is a logical schema example. Validate every loaded field and apply migrations when SchemaVersion changes. Do not assume stored data is valid simply because the game wrote it previously.

## 12.2 Persistence requirements

- Use DataStoreService with stable per-user keys and a versioned schema.
- Use UpdateAsync for read-modify-write updates where appropriate; wrap calls in pcall and handle throttling/failure.
- Serialize writes per player so overlapping saves cannot race.
- Use controlled retries with exponential backoff and jitter; do not spin indefinitely.
- Load data before allowing purchases or reward grants. If a load fails, do not silently create a fresh default profile and later overwrite valid stored data.
- Save on PlayerRemoving, BindToClose and periodically while the player is active; avoid saving every frame or on every tiny UI change.
- Consider a session-lock/lease strategy to reduce simultaneous-session data conflicts. Expire stale locks safely.
- Keep transient round inventory and unbanked loot separate from persistent profile data until a server-approved reward is granted.
- Use a separate test experience/data-store namespace for Studio tests. Never test destructive migrations against live production data.

## 12.3 Save failure behaviour

If a save fails after retries, keep the in-memory data for a later retry where possible, log a structured server warning and avoid telling the player that progress is safely saved when it is not. Provide an observable save status for internal QA. Never wipe or replace existing user data as a recovery shortcut.

# 13. Security and exploit resistance

| Threat | Required protection |
| --- | --- |
| Client grants currency | RewardService calculates and grants currency on the server. |
| Remote spam | Per-player rate limiting, cooldowns and payload validation. |
| Remote pickup from distance | Server-side distance and line-of-sight checks where needed. |
| Duplicate pickup/objective completion | Atomic server state transition; one successful grant per object/mission. |
| Inventory injection | Server-owned inventory and allowlisted item IDs. |
| Teleport/speed exploit | Do not trust client-reported position or movement; validate critical interactions using server-observed character state. |
| Fake purchase completion | Verify purchases using MarketplaceService server-side receipt handling; make grants idempotent. |
| NPC manipulation | Run authoritative enemy decision and attack checks on the server. |
| Data loss / duplicate writes | Profile validation, serialized saves, retries, schema migration and session conflict handling. |

> **SECURITY REQUIREMENT** ProximityPrompt is an interaction UI, not a security boundary. Treat prompt activation and every remote request as potentially abusive. Validate on the server even when the request normally comes from a legitimate UI.

# 14. Performance, quality and compatibility

## 14.1 Performance design

- Use modular low-poly assets and avoid unnecessarily dense meshes or oversized textures.
- Keep dynamic lights and real-time shadows selective; use baked/ambient presentation where possible.
- Do not run monster perception, pathfinding or broad world scans every frame.
- Avoid large numbers of unanchored physics objects and expensive constraints.
- Keep server-only assets in ServerStorage; replicate only what clients need.
- Evaluate Workspace streaming for station scale and device memory; test with streaming enabled rather than assuming it is automatically correct.
- Reuse sound and visual assets; cap repeated sound/particle effects.
- Clean all temporary station models, connections, tasks and event listeners after each round.

## 14.2 Device compatibility

| Device | Acceptance expectation |
| --- | --- |
| Desktop | All gameplay actions available using keyboard and mouse. |
| Mobile | All essential actions available with thumb-friendly touch controls; HUD remains readable on small screens. |
| Controller | Movement, camera, jump, interaction and equipment actions are mapped and testable. |

## 14.3 Code quality

- Use descriptive service and function names; avoid unexplained abbreviations.
- Keep configuration separate from business logic.
- Disconnect event connections and cancel tasks when a round or player session ends.
- Handle nil characters, missing PrimaryParts, unloaded profiles and missing station assets without crashing the server.
- Log state transitions and important failures with structured context, but never log player secrets or unnecessary personal data.
- Provide a simple way to run a solo test and a multi-client Studio test.

# 15. Analytics and product validation

Collect only gameplay events that help determine whether the first-time experience, core loop and return motivation work. Use Roblox analytics capabilities where suitable. Do not optimize for raw session length if players are idle; prioritize meaningful play and player satisfaction.

| Event / metric | When to record | Question answered |
| --- | --- | --- |
| FirstSessionStarted | First confirmed play session. | Are new players entering successfully? |
| HubTutorialCompleted | Player completes minimal first-time guidance. | Do players understand basic controls and preparation? |
| ExpeditionStarted | Server transitions to TRAVEL/EXPLORATION. | How many players reach the core experience? |
| ObjectiveCompleted | Server confirms the primary objective. | Are missions understandable and achievable? |
| PlayerExtracted | Player reaches the extraction area before departure. | Is extraction clear and fairly balanced? |
| ExpeditionEnded | Round results finalized. | What proportion of expeditions succeed? |
| UpgradePurchased | Server confirms Scrap spend and upgrade. | Do rewards create meaningful progression? |
| PlayerReturned | Player starts a later session. | Do players come back? |

## 15.1 Initial product questions

- Can a new player identify the current objective without help?
- Can a solo player complete a fair first expedition?
- Do players understand why The Hollow detected them?
- Do players know where extraction is and how much time remains?
- Does returning to the train feel rewarding?
- Do players voluntarily start another expedition or invite friends?

Do not claim that the concept will reach a particular concurrent-player or visit target. Use private playtests and observed analytics to decide what to improve before spending on promotion.

# 16. Monetization policy

Launch with no required purchases. Once the core experience is stable and retention has been observed, optional cosmetic monetization may be added.

| Potential offer | Examples | Rules |
| --- | --- | --- |
| Train cosmetics | Exterior skins, cabin decoration, lighting themes. | No gameplay advantage. |
| Character cosmetics | Outfits, accessories, emotes. | Optional and clearly described. |
| Equipment skins | Flashlight and flare appearance. | Visual only; identical gameplay function. |
| Supporter pass | Cosmetic title, badge-style identity or decoration. | Do not gate core missions or essential progression. |

If any developer products or passes are introduced, validate ownership/purchases on the server and make receipt processing idempotent. Do not implement monetization until the developer explicitly approves the offer design and current Roblox platform requirements have been checked.

# 17. Implementation roadmap and acceptance criteria

Implement these milestones in order. The coding agent should not skip ahead to content polish while the previous milestone is unstable.

## Milestone 0 — Project reconnaissance and setup

- Inspect the current workspace, repository, place file and existing scripts.
- Record what already exists and identify the current source-of-truth project structure.
- Create a safe version-control checkpoint before major refactoring if Git is available.
- Confirm the Roblox Studio sync/editing workflow (native Studio or Rojo if already adopted). Do not introduce Rojo solely for preference if the existing workflow works.
- Create a concise project README with setup, run, test and known manual Creator Dashboard settings.

Acceptance: the project opens in Roblox Studio, the existing work is preserved, and the agent can explain how source files map to the place hierarchy.

## Milestone 1 — Foundation and train hub

- Create the initial folders/modules and Bootstrap.server.lua / ClientBootstrap.client.lua.
- Create and validate the documented RemoteEvents.
- Implement RoundService state machine with server-owned timers.
- Build a simple but navigable train hub and spawn points.
- Show basic UI for round state and countdown.
- Support one-player start and late-join waiting behaviour.

Acceptance: a player can join, remain in the hub, see a countdown, move through the hub and transition into a dummy round state without errors. A second player can join and be rostered correctly.

## Milestone 2 — Station and objectives

- Create the Station 001 greybox with platform, concourse, maintenance room, control room, cargo storage and tunnel.
- Add tagged objective/loot spawn points.
- Implement StationService load/unload and per-round spawn selection.
- Implement all three mission templates with server-side progress.
- Implement extraction platform, timer and result outcomes.

Acceptance: a player can start a complete expedition, finish one of the three missions, return to extraction and see a valid result. Temporary station objects are removed before the next round.

## Milestone 3 — The Hollow and survival

- Create a placeholder enemy model before final art.
- Implement patrol, investigate, chase, search and return states.
- Implement server-created noise events and line-of-sight detection.
- Implement attack telegraph/cooldown and elimination outcome.
- Tune solo difficulty before scaling to crews.

Acceptance: The Hollow can navigate the map, respond to noise, pursue visible players, lose targets and recover. It cannot attack through walls or repeatedly apply one attack. A solo expedition remains reasonably learnable.

## Milestone 4 — Rewards and persistence

- Implement RewardService with server-owned reward formula.
- Implement PlayerDataService load/validate/migrate/save lifecycle.
- Implement Scrap balance and a small starter set of train upgrades.
- Implement artifact collection tracking if the core reward flow is stable.
- Test failed loads/saves and player rejoin behaviour in a separate test data store.

Acceptance: earned Scrap and purchased upgrades persist after leaving/rejoining a test session; a failed expedition does not delete saved progress; duplicate reward requests do not double grant.

## Milestone 5 — Mobile UX, art and audio polish

- Replace greybox station assets with cohesive original stylized assets.
- Polish train hub, lighting, signage, monster silhouette and sound cues.
- Finish responsive HUD and touch controls.
- Add feedback for objectives, pickups, monster detection, extraction and results.
- Tune audio levels and add player volume settings.

Acceptance: PC and at least one representative mobile device can complete a round; all essential instructions and controls are readable and usable.

## Milestone 6 — Security, performance and multiplayer QA

- Test with up to six simulated clients using Roblox Studio server/client testing.
- Test disconnects, late joins, simultaneous interactions and all-player departure.
- Attempt remote spam, invalid item IDs, far-distance prompt activation and duplicate pickups.
- Profile server and client performance during a full expedition.
- Verify there are no unbounded tasks, leaked connections or runtime station leftovers.

Acceptance: all release QA checklist items in Section 18 pass or are explicitly recorded as launch blockers with a remediation plan.

## Milestone 7 — Closed test and public launch preparation

- Run a small private playtest with players who have not seen the design document.
- Observe onboarding, objective comprehension, extraction navigation and replay behaviour.
- Fix blockers and confusing moments before adding more content.
- Prepare title, icon, thumbnails, description, content maturity settings and Creator Dashboard configuration.
- Verify all assets have permitted use and that the game page accurately represents the experience.

Acceptance: testers can independently complete and repeat expeditions; no known critical data-loss, security or progression blocker remains; launch settings have been manually verified in Creator Dashboard.

# 18. Release QA checklist

- One-player expedition works from start to finish.
- Six-player expedition works without round-state conflicts.
- A player joining mid-round waits correctly for the next round.
- Disconnecting a player does not break objectives or timers.
- All players leaving triggers cleanup and no stuck round.
- The Hollow navigates around obstacles and handles unreachable paths.
- The Hollow detects players/noise and can lose a target.
- The Hollow cannot damage through walls or outside valid range.
- Objective progress cannot be forged by client input.
- Remote spam is rate-limited and rejected safely.
- Duplicate pickups and duplicate reward grants are prevented.
- Player data survives normal leave/rejoin in the test environment.
- A failed data load does not silently overwrite an existing profile.
- A failed data save is logged and handled without false success messaging.
- Round cleanup removes temporary station instances and connections.
- Mobile controls support movement, look, jump, interact and equipment.
- HUD is readable across common screen sizes.
- The experience runs repeated rounds without major memory or performance degradation.
- Imported assets have known sources and approved usage rights.
- Roblox Creator Dashboard settings are manually verified before publishing.

# 19. Definition of done for every coding-agent task

1. State the scope of the change and which requirement it addresses.
2. Inspect related existing modules before editing; do not duplicate an existing system.
3. Implement the smallest coherent change with clear ownership and configuration.
4. Run available static checks and Roblox Studio tests relevant to the change.
5. Test at least the happy path and the most important failure/edge case.
6. Report exact files added/changed and the tests actually run.
7. List any manual Studio/Creator Dashboard action still required.
8. List unresolved defects and do not claim success for untested behaviour.

## 19.1 Required agent response format

```text
TASK: <milestone / feature>
STATUS: Complete | Partial | Blocked
CHANGES: <files and concise summary>
TESTS RUN: <exact Studio / static checks performed>
RESULTS: <what passed and failed>
MANUAL STEPS: <developer actions still required, or None>
KNOWN ISSUES: <remaining defects / risks>
NEXT TASK: <single recommended next implementation task>
```

# 20. Risks and mitigations

| Risk | Why it matters | Mitigation |
| --- | --- | --- |
| Scope expansion | A solo developer can get stuck building content before the core loop works. | Hold the MVP boundary; treat future features as backlog. |
| Unclear objectives | Players leave if they do not know what to do. | Clear HUD, signage, objective markers and first-run guidance. |
| Unfair monster behaviour | Players may interpret detection/attacks as random or exploitative. | Telegraph cues, line-of-sight validation, noise feedback and controlled difficulty. |
| Data loss | Progression failure damages trust. | Validated profiles, controlled saves, migrations, test stores and failure handling. |
| Mobile usability | A large share of Roblox play occurs on touch devices. | Design responsive HUD and touch controls from the start; test on device. |
| Performance degradation | Repeated rounds can leave objects, tasks or connections behind. | Round cleanup ownership, profiling and repeated-round QA. |
| Unknown free-model scripts | Imported models can contain unwanted or malicious scripts. | Use original/approved assets; inspect every imported model and script. |
| Popularity uncertainty | No concept or launch plan guarantees broad adoption. | Use real playtests and retention/engagement data to iterate. |

# 21. Deferred backlog after the first stable release

- Station 002 and additional destinations with distinct visual identities.
- Additional monsters with different detection and counterplay patterns.
- More station events and curated mission variants.
- Teammate revive system and expanded player status states.
- More train carriages and meaningful upgrade branches.
- Artifact sets, collection rewards and earned cosmetic sets.
- Weekly anomalies or limited-time challenges.
- Optional cosmetic game passes and developer products after platform-policy review.
- Cross-server crew formation/queueing only if standard matchmaking is insufficient.

# 22. Official technical references

Use current Roblox documentation as the implementation authority when platform APIs or publishing requirements change. Check the current documentation before relying on API behaviour.

- **Roblox Studio:** https://create.roblox.com/docs/studio
- **Luau:** https://luau.org/
- **Client-server boundary and security:** https://create.roblox.com/docs/scripting/security/client-server-boundary
- **Data stores:** https://create.roblox.com/docs/cloud-services/data-stores
- **PathfindingService:** https://create.roblox.com/docs/characters/pathfinding
- **Proximity prompts:** https://create.roblox.com/docs/ui/proximity-prompts
- **Instance streaming:** https://create.roblox.com/docs/workspace/streaming
- **Roblox analytics:** https://create.roblox.com/docs/production/analytics
- **MarketplaceService:** https://create.roblox.com/docs/reference/engine/classes/MarketplaceService
- **Testing in Studio:** https://create.roblox.com/docs/studio/testing-modes
# Appendix A — Initial configuration values

Keep all tunable values in configuration modules. The values below are provisional starting points for playtesting, not final balance decisions.

| Setting | Initial value / rule |
| --- | --- |
| Maximum players per server | 6 (configure in Roblox experience/place settings). |
| Minimum crew to start | 1. |
| Intermission | 15 seconds. |
| Boarding | 45 seconds. |
| Travel | 20 seconds. |
| Exploration | 180 seconds. |
| Extraction | 60 seconds. |
| Return | 20 seconds. |
| Results | 30 seconds. |
| Primary objective | One of three templates per expedition. |
| Equipment slots | 2. |
| Station events | 0–1 in first playable build; tune after tests. |
| Currencies | Scrap and non-spendable Artifacts. |

# Appendix B — Initial build priority

When in doubt, implement in this order:

1. A server-controlled round state machine and reliable train hub.
2. One complete station expedition with one working objective.
3. Extraction, outcomes and cleanup.
4. All three mission templates and randomized spawn points.
5. The Hollow AI and fair attack rules.
6. Server-owned rewards and persistent Scrap.
7. Train upgrades and collectible artifacts.
8. Mobile polish, art/audio polish and analytics.
9. Only then consider additional content and monetization.

> **FINAL PRODUCT PRINCIPLE** Ship a small, complete, reliable NIGHTLINE before building a large NIGHTLINE. A polished repeatable expedition is the foundation for every future station, monster and progression system.
