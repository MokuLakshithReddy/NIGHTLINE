--!strict
--[[
	GameConfig.lua
	Centralized tunable configuration for NIGHTLINE: LAST TRAIN.
	All round timings, crew limits, movement physics bounds, station spawn coordinates,
	interaction tolerances, and rate limits live here.
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
	VERSION = "0.1.2-milestone1-remediated",

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

	-- Physical Extraction Platform & Station Entry Spawns (Remediation #1: All 6 station spawns outside extraction zone)
	EXTRACTION_ZONE_POSITION = Vector3.new(15, 2.5, -8),
	EXTRACTION_ZONE_SIZE = Vector3.new(8, 8, 16),
	EXTRACTION_ZONE_RADIUS = 12.0,
	EXTRACTION_VERTICAL_HALF_HEIGHT = 8.0,

	-- Six Station 001 Concourse Arrival Spawns (Z = 18..30, minimum 26 studs away from Extraction Zone at Z = -8)
	STATION_ENTRY_SPAWNS = table.freeze({
		Vector3.new(14, 3, 18),
		Vector3.new(18, 3, 18),
		Vector3.new(14, 3, 24),
		Vector3.new(18, 3, 24),
		Vector3.new(14, 3, 30),
		Vector3.new(18, 3, 30),
	}) :: { Vector3 },

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
	}),
}

return table.freeze(GameConfig)
