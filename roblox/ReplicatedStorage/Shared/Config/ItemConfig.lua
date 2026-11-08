--!strict
--[[
	ItemConfig.lua
	Definitions for MVP equipment and mission items (Section 6.1).
	Used by InventoryService and ObjectiveService on the server and UI/Input controllers on the client.
]]

export type ItemDefinition = {
	id: string,
	displayName: string,
	category: "Equipment" | "MissionItem" | "Consumable",
	description: string,
	equippableInHub: boolean,
	cooldownSeconds: number,
}

local ItemConfig: { [string]: ItemDefinition } = {
	Flashlight = table.freeze({
		id = "Flashlight",
		displayName = "Service Flashlight",
		category = "Equipment" :: "Equipment",
		description = "Provides directional local illumination inside dark station concourses.",
		equippableInHub = true,
		cooldownSeconds = 0.35,
	}),
	Flare = table.freeze({
		id = "Flare",
		displayName = "Acoustic Signal Flare",
		category = "Consumable" :: "Consumable",
		description = "Emits high-visibility red light and an acoustic lure to redirect threats.",
		equippableInHub = true,
		cooldownSeconds = 2.0,
	}),
	Fuse = table.freeze({
		id = "Fuse",
		displayName = "High-Voltage Transit Fuse",
		category = "MissionItem" :: "MissionItem",
		description = "Industrial fuse required for the Restore Power station objective.",
		equippableInHub = false,
		cooldownSeconds = 0.5,
	}),
	CargoContainer = table.freeze({
		id = "CargoContainer",
		displayName = "Sealed Transit Cargo Container",
		category = "MissionItem" :: "MissionItem",
		description = "Sealed manifest container required for the Recover Cargo station objective.",
		equippableInHub = false,
		cooldownSeconds = 0.5,
	}),
}

local AllowedHubEquipmentIds: { [string]: boolean } = table.freeze({
	Flashlight = true,
	Flare = true,
})

local AllowedMissionItemIds: { [string]: boolean } = table.freeze({
	Fuse = true,
	CargoContainer = true,
})

return table.freeze({
	Items = table.freeze(ItemConfig),
	AllowedHubEquipmentIds = AllowedHubEquipmentIds,
	AllowedMissionItemIds = AllowedMissionItemIds,
})
