--!strict
--[[
	GameConfig.lua
	Centralized tunable configuration for NIGHTLINE: LAST TRAIN.
	All round timings, crew limits, movement physics bounds, station spawn coordinates,
	station environment bounds, interaction tolerances, and rate limits live here.
]]

local NetworkTypes = require(script.Parent.Parent.Types.NetworkTypes)

export type RoundDurationsMap = {
	WAITING: number,
	INTERMISSION: number,
	BOARDING: number,
	TRAVEL: number,
	EXPLORATION: number,
	EXTRACTION: number,
	RETURN: number,
	RESULTS: number,
}

local GameConfig = {
	GAME_TITLE = "NIGHTLINE: LAST TRAIN",
	VERSION = "0.3.0-objectives-and-hollow-prep",

	-- Crew & Server Limits (Appendix A)
	MAX_PLAYERS_PER_SERVER = 6,
	MIN_CREW_TO_START = 1,
	EQUIPMENT_SLOTS = 2,

	-- Default Destination
	DEFAULT_STATION_ID = "Station001" :: NetworkTypes.StationId,

	-- Authoritative Round State Durations in Seconds (Section 3.2 & Appendix A)
	RoundDurations = table.freeze({
		WAITING = 0, -- Indefinite until >= MIN_CREW_TO_START players are available
		INTERMISSION = 15,
		BOARDING = 45,
		TRAVEL = 20,
		EXPLORATION = 180,
		EXTRACTION = 60,
		RETURN = 20,
		RESULTS = 30,
	}) :: RoundDurationsMap,

	-- Character & Movement Settings (Issue 03 & Remediation #3: Horizontal + Vertical validation)
	WALK_SPEED = 14,
	SPRINT_SPEED = 22,
	MOVEMENT_SPEED_TOLERANCE = 6,
	MOVEMENT_STEP_SLACK = 2.0,
	MAX_JUMP_UPWARD_SPEED = 55,
	VERTICAL_APEX_TOLERANCE = 6.0,
	MAX_FALL_SPEED = 160,
	VERTICAL_FALL_TOLERANCE = 12.0,
	TELEPORT_GRACE_SECONDS = 1.0,
	MOVEMENT_CHECK_INTERVAL = 0.25,
	SPRINT_COOLDOWN_SECONDS = 0.1,
	DEFAULT_MAX_HEALTH = 100,

	-- Physical Extraction Platform & Station Entry Spawns (Priority 2: Playable Station 001 Environment)
	-- Extraction zone sits on the North-Center Station Platform outside the Z = -8 Train Boarding Doorway.
	EXTRACTION_ZONE_POSITION = Vector3.new(16, 3.0, -8),
	EXTRACTION_ZONE_SIZE = Vector3.new(10, 8, 16),
	EXTRACTION_ZONE_RADIUS = 10.0,
	EXTRACTION_VERTICAL_HALF_HEIGHT = 8.0,

	-- Six Station 001 Arrival Spawns on the South Station Platform (X = 15..21, Z = 18..30).
	-- Supported by solid CanCollide=true StationPlatformFloor + StationEntrySpawn pads.
	-- Minimum distance to EXTRACTION_ZONE_POSITION (16, 3, -8) is 26.02 studs (radius = 10.0).
	STATION_ENTRY_SPAWNS = table.freeze({
		Vector3.new(15, 3.75, 18),
		Vector3.new(21, 3.75, 18),
		Vector3.new(15, 3.75, 24),
		Vector3.new(21, 3.75, 24),
		Vector3.new(15, 3.75, 30),
		Vector3.new(21, 3.75, 30),
	}) :: { Vector3 },

	-- Station 001 Exploration Waypoints / Objective Coordinates (on solid CanCollide=true floors)
	STATION_EXPLORATION_POINTS = table.freeze({
		MainConcourse = Vector3.new(45, 3.75, 0),
		MaintenanceRoom = Vector3.new(47, 3.75, -54),
		ControlRoom = Vector3.new(77, 3.75, 0),
		CargoStorage = Vector3.new(47, 3.75, 54),
	}),

	-- Security & Interaction Thresholds (Section 6.2 & Section 11.1)
	MAX_INTERACTION_DISTANCE = 14.0,
	PROMPT_COOLDOWN_SECONDS = 0.5,
	REMOTE_RATE_LIMIT_WINDOW = 1.0,
	REMOTE_MAX_CALLS_PER_WINDOW = 6,

	-- CollectionService Tags (Section 6.2 & Section 9.3)
	Tags = table.freeze({
		HubSpawn = "NightlineHubSpawn",
		EliminatedSpawn = "NightlineEliminatedSpawn",
		StationEntrySpawn = "NightlineStationEntrySpawn",
		BoardingZone = "NightlineBoardingZone",
		ExtractionZone = "NightlineExtractionZone",
		EquipmentLocker = "NightlineEquipmentLocker",
		DestinationTerminal = "NightlineDestinationTerminal",
		StationObjective = "NightlineStationObjective",
		FusePickup = "NightlineFusePickup",
		FuseSocket = "NightlineFuseSocket",
		CargoPickup = "NightlineCargoPickup",
		CargoDropPoint = "NightlineCargoDropPoint",
		SignalTerminal = "NightlineSignalTerminal",
		HidingSpot = "NightlineHidingSpot",
		HollowWaypoint = "NightlineHollowWaypoint",
	}),
}

return table.freeze(GameConfig)
