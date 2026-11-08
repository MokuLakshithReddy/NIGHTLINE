--!strict
--[[
	ObjectiveConfig.lua
	Mission template definitions and Station 001 physical interactable specifications (Section 4.2 & Priority 1):
	1. RestorePower:
	   - 3 individual transit fuses (FusePickup_01..03) located across Station 001.
	   - 3 designated maintenance sockets (FuseSocket_01..03) inside the Maintenance Room.
	2. RecoverCargo:
	   - 2 sealed cargo containers (CargoContainer_01..02) located in Cargo Storage.
	   - 1 designated Cargo Drop Point (CargoDropPoint_01) on the Station Platform.
	3. RepairSignal:
	   - 3 communication terminals (SignalTerminal_01..03) across Control Room and Concourse.
]]

local NetworkTypes = require(script.Parent.Parent.Types.NetworkTypes)

export type ObjectiveTemplate = {
	id: NetworkTypes.MissionTemplateId,
	title: string,
	instruction: string,
	requiredProgress: number,
}

export type StationObjectiveNodeSpec = {
	name: string,
	missionId: NetworkTypes.MissionTemplateId,
	role: NetworkTypes.ObjectiveInteractionRole,
	index: number,
	itemKey: string?,
	objectText: string,
	actionText: string,
	position: Vector3,
	size: Vector3,
	color: Color3,
}

local Templates: { [NetworkTypes.MissionTemplateId]: ObjectiveTemplate } = {
	RestorePower = table.freeze({
		id = "RestorePower" :: NetworkTypes.MissionTemplateId,
		title = "Restore Auxiliary Power",
		instruction = "Find 3 transit fuses, pick them up, and install them into the Maintenance Room fuse sockets.",
		requiredProgress = 3,
	}),
	RecoverCargo = table.freeze({
		id = "RecoverCargo" :: NetworkTypes.MissionTemplateId,
		title = "Recover Lost Cargo",
		instruction = "Locate 2 sealed cargo containers in Cargo Storage and deliver them to the Platform Cargo Drop Point.",
		requiredProgress = 2,
	}),
	RepairSignal = table.freeze({
		id = "RepairSignal" :: NetworkTypes.MissionTemplateId,
		title = "Repair the Dispatch Signal",
		instruction = "Activate all 3 dispatch communication terminals across the Control Room and Concourse.",
		requiredProgress = 3,
	}),
}

local OrderedTemplateIds: { NetworkTypes.MissionTemplateId } = table.freeze({
	"RestorePower" :: NetworkTypes.MissionTemplateId,
	"RecoverCargo" :: NetworkTypes.MissionTemplateId,
	"RepairSignal" :: NetworkTypes.MissionTemplateId,
})

local Station001ObjectiveNodes: { StationObjectiveNodeSpec } = table.freeze({
	-- =========================================================================
	-- Mission 1: RestorePower (3 Fuse Pickups + 3 Maintenance Fuse Sockets)
	-- =========================================================================
	table.freeze({
		name = "FusePickup_01",
		missionId = "RestorePower" :: NetworkTypes.MissionTemplateId,
		role = "FusePickup" :: NetworkTypes.ObjectiveInteractionRole,
		index = 1,
		itemKey = "Fuse_01",
		objectText = "High-Voltage Transit Fuse #1 (North Concourse)",
		actionText = "Pick Up Transit Fuse",
		position = Vector3.new(38, 2.2, -24),
		size = Vector3.new(2.2, 1.8, 2.2),
		color = Color3.fromRGB(251, 191, 36),
	}),
	table.freeze({
		name = "FusePickup_02",
		missionId = "RestorePower" :: NetworkTypes.MissionTemplateId,
		role = "FusePickup" :: NetworkTypes.ObjectiveInteractionRole,
		index = 2,
		itemKey = "Fuse_02",
		objectText = "High-Voltage Transit Fuse #2 (Control Room)",
		actionText = "Pick Up Transit Fuse",
		position = Vector3.new(74, 2.2, -10),
		size = Vector3.new(2.2, 1.8, 2.2),
		color = Color3.fromRGB(251, 191, 36),
	}),
	table.freeze({
		name = "FusePickup_03",
		missionId = "RestorePower" :: NetworkTypes.MissionTemplateId,
		role = "FusePickup" :: NetworkTypes.ObjectiveInteractionRole,
		index = 3,
		itemKey = "Fuse_03",
		objectText = "High-Voltage Transit Fuse #3 (Cargo Storage)",
		actionText = "Pick Up Transit Fuse",
		position = Vector3.new(40, 2.2, 50),
		size = Vector3.new(2.2, 1.8, 2.2),
		color = Color3.fromRGB(251, 191, 36),
	}),
	table.freeze({
		name = "FuseSocket_01",
		missionId = "RestorePower" :: NetworkTypes.MissionTemplateId,
		role = "FuseSocket" :: NetworkTypes.ObjectiveInteractionRole,
		index = 1,
		itemKey = "Socket_01",
		objectText = "Maintenance Fuse Socket #1 (Maintenance Room)",
		actionText = "Install Transit Fuse",
		position = Vector3.new(41, 3.0, -58),
		size = Vector3.new(3.2, 4.5, 2.2),
		color = Color3.fromRGB(245, 158, 11),
	}),
	table.freeze({
		name = "FuseSocket_02",
		missionId = "RestorePower" :: NetworkTypes.MissionTemplateId,
		role = "FuseSocket" :: NetworkTypes.ObjectiveInteractionRole,
		index = 2,
		itemKey = "Socket_02",
		objectText = "Maintenance Fuse Socket #2 (Maintenance Room)",
		actionText = "Install Transit Fuse",
		position = Vector3.new(47, 3.0, -58),
		size = Vector3.new(3.2, 4.5, 2.2),
		color = Color3.fromRGB(245, 158, 11),
	}),
	table.freeze({
		name = "FuseSocket_03",
		missionId = "RestorePower" :: NetworkTypes.MissionTemplateId,
		role = "FuseSocket" :: NetworkTypes.ObjectiveInteractionRole,
		index = 3,
		itemKey = "Socket_03",
		objectText = "Maintenance Fuse Socket #3 (Maintenance Room)",
		actionText = "Install Transit Fuse",
		position = Vector3.new(53, 3.0, -58),
		size = Vector3.new(3.2, 4.5, 2.2),
		color = Color3.fromRGB(245, 158, 11),
	}),

	-- =========================================================================
	-- Mission 2: RecoverCargo (2 Sealed Cargo Containers + 1 Platform Drop Point)
	-- =========================================================================
	table.freeze({
		name = "CargoContainer_01",
		missionId = "RecoverCargo" :: NetworkTypes.MissionTemplateId,
		role = "CargoPickup" :: NetworkTypes.ObjectiveInteractionRole,
		index = 1,
		itemKey = "Cargo_01",
		objectText = "Sealed Cargo Container #1 (Cargo Storage West)",
		actionText = "Pick Up Sealed Cargo Container",
		position = Vector3.new(41, 2.4, 58),
		size = Vector3.new(3.5, 2.8, 3.5),
		color = Color3.fromRGB(168, 85, 247),
	}),
	table.freeze({
		name = "CargoContainer_02",
		missionId = "RecoverCargo" :: NetworkTypes.MissionTemplateId,
		role = "CargoPickup" :: NetworkTypes.ObjectiveInteractionRole,
		index = 2,
		itemKey = "Cargo_02",
		objectText = "Sealed Cargo Container #2 (Cargo Storage East)",
		actionText = "Pick Up Sealed Cargo Container",
		position = Vector3.new(53, 2.4, 58),
		size = Vector3.new(3.5, 2.8, 3.5),
		color = Color3.fromRGB(168, 85, 247),
	}),
	table.freeze({
		name = "CargoDropPoint_01",
		missionId = "RecoverCargo" :: NetworkTypes.MissionTemplateId,
		role = "CargoDropPoint" :: NetworkTypes.ObjectiveInteractionRole,
		index = 1,
		itemKey = "CargoDrop_01",
		objectText = "Station Platform Cargo Drop Point",
		actionText = "Deliver Sealed Cargo Container",
		position = Vector3.new(23, 2.2, -8),
		size = Vector3.new(5.0, 2.5, 5.0),
		color = Color3.fromRGB(192, 132, 252),
	}),

	-- =========================================================================
	-- Mission 3: RepairSignal (3 Communication Terminals)
	-- =========================================================================
	table.freeze({
		name = "SignalTerminal_01",
		missionId = "RepairSignal" :: NetworkTypes.MissionTemplateId,
		role = "SignalTerminal" :: NetworkTypes.ObjectiveInteractionRole,
		index = 1,
		itemKey = "Signal_01",
		objectText = "Dispatch Comm Terminal #1 (Control Room North)",
		actionText = "Activate Communication Terminal",
		position = Vector3.new(82, 3.0, -8),
		size = Vector3.new(3.5, 4.5, 2.5),
		color = Color3.fromRGB(56, 189, 248),
	}),
	table.freeze({
		name = "SignalTerminal_02",
		missionId = "RepairSignal" :: NetworkTypes.MissionTemplateId,
		role = "SignalTerminal" :: NetworkTypes.ObjectiveInteractionRole,
		index = 2,
		itemKey = "Signal_02",
		objectText = "Dispatch Comm Terminal #2 (Control Room South)",
		actionText = "Activate Communication Terminal",
		position = Vector3.new(82, 3.0, 8),
		size = Vector3.new(3.5, 4.5, 2.5),
		color = Color3.fromRGB(56, 189, 248),
	}),
	table.freeze({
		name = "SignalTerminal_03",
		missionId = "RepairSignal" :: NetworkTypes.MissionTemplateId,
		role = "SignalTerminal" :: NetworkTypes.ObjectiveInteractionRole,
		index = 3,
		itemKey = "Signal_03",
		objectText = "Dispatch Comm Terminal #3 (Main Concourse Relay)",
		actionText = "Activate Communication Terminal",
		position = Vector3.new(56, 3.0, 0),
		size = Vector3.new(3.5, 4.5, 2.5),
		color = Color3.fromRGB(56, 189, 248),
	}),
})

return table.freeze({
	Templates = table.freeze(Templates),
	OrderedTemplateIds = OrderedTemplateIds,
	Station001ObjectiveNodes = Station001ObjectiveNodes,
})
