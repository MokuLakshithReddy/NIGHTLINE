--!strict
--[[
	StationConfig.lua
	Metadata and rules for launch destinations (Section 4).
]]

local NetworkTypes = require(script.Parent.Parent.Types.NetworkTypes)

export type StationDefinition = {
	id: NetworkTypes.StationId,
	code: string,
	displayName: string,
	subtitle: string,
	unlockedByDefault: boolean,
	threatName: string,
	areas: { string },
	missionPool: { NetworkTypes.MissionTemplateId },
}

local Stations: { [NetworkTypes.StationId]: StationDefinition } = {
	Station001 = table.freeze({
		id = "Station001" :: NetworkTypes.StationId,
		code = "STN-001",
		displayName = "Station 001: The Forgotten Terminal",
		subtitle = "Subsurface Transit Hub · Sector 4",
		unlockedByDefault = true,
		threatName = "The Hollow",
		areas = table.freeze({
			"Train Platform",
			"Main Concourse",
			"Maintenance Room",
			"Control Room",
			"Cargo Storage",
			"Underground Tunnel",
		}),
		missionPool = table.freeze({
			"RestorePower" :: NetworkTypes.MissionTemplateId,
			"RecoverCargo" :: NetworkTypes.MissionTemplateId,
			"RepairSignal" :: NetworkTypes.MissionTemplateId,
		}),
	}),
}

local AllowedStationIds: { [string]: boolean } = table.freeze({
	Station001 = true,
})

return table.freeze({
	Stations = table.freeze(Stations),
	AllowedStationIds = AllowedStationIds,
})
