--!strict
--[[
	MonsterConfig.lua
	Configuration for The Hollow AI interfaces (Priority 4 & Section 5):
	- Player detection ranges, field-of-view angle, and line-of-sight scan cadence.
	- Noise event radii, intensities, and expiration durations.
	- Monster state machine definitions and valid state transitions.
	- Station 001 navigation waypoint graph and hiding spot coordinates.
]]

local NetworkTypes = require(script.Parent.Parent.Types.NetworkTypes)

export type WaypointSpec = {
	id: string,
	roomId: string,
	position: Vector3,
	neighbors: { string },
}

export type HidingSpotSpec = {
	id: string,
	roomId: string,
	objectText: string,
	position: Vector3,
	insideOffset: Vector3,
	exitOffset: Vector3,
}

local ValidStateTransitions: { [NetworkTypes.HollowState]: { [NetworkTypes.HollowState]: boolean } } =
	table.freeze({
		INACTIVE = table.freeze({
			PATROL = true,
			INACTIVE = true,
		}),
		PATROL = table.freeze({
			INVESTIGATE = true,
			CHASE = true,
			RETURN = true,
			INACTIVE = true,
		}),
		INVESTIGATE = table.freeze({
			PATROL = true,
			CHASE = true,
			SEARCH = true,
			RETURN = true,
			INACTIVE = true,
		}),
		CHASE = table.freeze({
			SEARCH = true,
			RETURN = true,
			PATROL = true,
			INACTIVE = true,
		}),
		SEARCH = table.freeze({
			CHASE = true,
			INVESTIGATE = true,
			RETURN = true,
			PATROL = true,
			INACTIVE = true,
		}),
		RETURN = table.freeze({
			PATROL = true,
			INVESTIGATE = true,
			CHASE = true,
			INACTIVE = true,
		}),
	})

local Station001Waypoints: { WaypointSpec } = table.freeze({
	table.freeze({
		id = "WP_PlatformNorth",
		roomId = "StationPlatform",
		position = Vector3.new(20, 3.75, -18),
		neighbors = table.freeze({ "WP_PlatformSouth", "WP_ConcourseNorth", "WP_ConcourseCenter" }),
	}),
	table.freeze({
		id = "WP_PlatformSouth",
		roomId = "StationPlatform",
		position = Vector3.new(20, 3.75, 18),
		neighbors = table.freeze({ "WP_PlatformNorth", "WP_ConcourseSouth", "WP_ConcourseCenter" }),
	}),
	table.freeze({
		id = "WP_ConcourseNorth",
		roomId = "MainConcourse",
		position = Vector3.new(47, 3.75, -24),
		neighbors = table.freeze({ "WP_PlatformNorth", "WP_ConcourseCenter", "WP_Maintenance" }),
	}),
	table.freeze({
		id = "WP_ConcourseCenter",
		roomId = "MainConcourse",
		position = Vector3.new(47, 3.75, 0),
		neighbors = table.freeze({
			"WP_PlatformNorth",
			"WP_PlatformSouth",
			"WP_ConcourseNorth",
			"WP_ConcourseSouth",
			"WP_Control",
		}),
	}),
	table.freeze({
		id = "WP_ConcourseSouth",
		roomId = "MainConcourse",
		position = Vector3.new(47, 3.75, 24),
		neighbors = table.freeze({ "WP_PlatformSouth", "WP_ConcourseCenter", "WP_Cargo" }),
	}),
	table.freeze({
		id = "WP_Maintenance",
		roomId = "MaintenanceRoom",
		position = Vector3.new(47, 3.75, -52),
		neighbors = table.freeze({ "WP_ConcourseNorth" }),
	}),
	table.freeze({
		id = "WP_Control",
		roomId = "ControlRoom",
		position = Vector3.new(75, 3.75, 0),
		neighbors = table.freeze({ "WP_ConcourseCenter" }),
	}),
	table.freeze({
		id = "WP_Cargo",
		roomId = "CargoStorage",
		position = Vector3.new(47, 3.75, 52),
		neighbors = table.freeze({ "WP_ConcourseSouth" }),
	}),
})

local Station001HidingSpots: { HidingSpotSpec } = table.freeze({
	table.freeze({
		id = "HidingLocker_01_Platform",
		roomId = "StationPlatform",
		objectText = "Transit Service Locker (Platform)",
		position = Vector3.new(26, 3.5, -34),
		insideOffset = Vector3.new(0, 0, 0),
		exitOffset = Vector3.new(0, 0, 4.0),
	}),
	table.freeze({
		id = "HidingLocker_02_ConcourseNorth",
		roomId = "MainConcourse",
		objectText = "Emergency Refuge Booth (North Concourse)",
		position = Vector3.new(34, 3.5, -34),
		insideOffset = Vector3.new(0, 0, 0),
		exitOffset = Vector3.new(0, 0, 4.0),
	}),
	table.freeze({
		id = "HidingLocker_03_ConcourseSouth",
		roomId = "MainConcourse",
		objectText = "Emergency Refuge Booth (South Concourse)",
		position = Vector3.new(34, 3.5, 34),
		insideOffset = Vector3.new(0, 0, 0),
		exitOffset = Vector3.new(0, 0, 4.0),
	}),
	table.freeze({
		id = "HidingLocker_04_Maintenance",
		roomId = "MaintenanceRoom",
		objectText = "Switchgear Utility Cabinet (Maintenance)",
		position = Vector3.new(36, 3.5, -54),
		insideOffset = Vector3.new(0, 0, 0),
		exitOffset = Vector3.new(0, 0, 4.0),
	}),
	table.freeze({
		id = "HidingLocker_05_Control",
		roomId = "ControlRoom",
		objectText = "Relay Server Rack Alcove (Control Room)",
		position = Vector3.new(76, 3.5, -14),
		insideOffset = Vector3.new(0, 0, 0),
		exitOffset = Vector3.new(0, 0, 4.0),
	}),
	table.freeze({
		id = "HidingLocker_06_Cargo",
		roomId = "CargoStorage",
		objectText = "Empty Freight Locker (Cargo Storage)",
		position = Vector3.new(36, 3.5, 54),
		insideOffset = Vector3.new(0, 0, 0),
		exitOffset = Vector3.new(0, 0, 4.0),
	}),
})

local MonsterConfig = {
	MONSTER_ID = "TheHollow",
	DISPLAY_NAME = "The Hollow",

	-- Detection & Sight Rules (Section 5.2)
	SIGHT_DETECTION_RANGE = 48.0,
	PROXIMITY_AWARENESS_RANGE = 11.0,
	FIELD_OF_VIEW_DEGREES = 110.0,
	SCAN_INTERVAL_SECONDS = 0.35,

	-- Noise Event Radii & Lifetimes (Section 5.2)
	NoiseRadii = table.freeze({
		Walk = 10.0,
		Sprint = 32.0,
		ObjectiveInteraction = 38.0,
		FlareDistraction = 56.0,
		DoorTransit = 22.0,
	}),
	NoiseIntensities = table.freeze({
		Walk = 0.25,
		Sprint = 0.70,
		ObjectiveInteraction = 0.85,
		FlareDistraction = 1.00,
		DoorTransit = 0.50,
	}),
	NOISE_EVENT_LIFETIME_SECONDS = 6.0,

	-- Fair Attack & Elimination Boundaries (Section 5.3)
	ATTACK_RANGE_STUDS = 6.5,
	ATTACK_COOLDOWN_SECONDS = 2.0,
	SEARCH_TIMEOUT_SECONDS = 8.0,

	ValidStateTransitions = ValidStateTransitions,
	Station001Waypoints = Station001Waypoints,
	Station001HidingSpots = Station001HidingSpots,
}

return table.freeze(MonsterConfig)
