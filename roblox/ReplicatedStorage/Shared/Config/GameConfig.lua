--!strict
--[[
	GameConfig.lua
	Centralized tunable configuration for NIGHTLINE: LAST TRAIN.
	All round timings, crew limits, interaction tolerances, and rate limits live here.
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
	VERSION = "0.1.0-milestone1",

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

	-- Character & Movement Settings
	WALK_SPEED = 14,
	SPRINT_SPEED = 22,
	DEFAULT_MAX_HEALTH = 100,

	-- Security & Interaction Thresholds (Section 6.2 & Section 11.1)
	MAX_INTERACTION_DISTANCE = 14.0,
	PROMPT_COOLDOWN_SECONDS = 0.5,
	REMOTE_RATE_LIMIT_WINDOW = 1.0,
	REMOTE_MAX_CALLS_PER_WINDOW = 6,

	-- CollectionService Tags (Section 6.2 & Section 9.3)
	Tags = table.freeze({
		HubSpawn = "NightlineHubSpawn",
		BoardingZone = "NightlineBoardingZone",
		EquipmentLocker = "NightlineEquipmentLocker",
		DestinationTerminal = "NightlineDestinationTerminal",
	}),
}

return table.freeze(GameConfig)
