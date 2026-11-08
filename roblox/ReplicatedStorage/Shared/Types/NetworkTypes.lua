--!strict
--[[
	NetworkTypes.lua
	Shared strict Luau type definitions for NIGHTLINE: LAST TRAIN.
	Defines round states, player statuses, equipment slots, objective roles,
	Hollow AI preparation interfaces, and networking payloads.
]]

export type RoundState =
	"WAITING"
	| "INTERMISSION"
	| "BOARDING"
	| "TRAVEL"
	| "EXPLORATION"
	| "EXTRACTION"
	| "RETURN"
	| "RESULTS"

export type PlayerRoundStatus =
	"HUB_WAITING"
	| "BOARDED"
	| "IN_EXPEDITION"
	| "EXTRACTED"
	| "ELIMINATED"
	| "DISCONNECTED"

export type RoundOutcome = "PENDING" | "SUCCESS" | "PARTIAL" | "FAILED"

export type StationId = "Station001"

export type MissionTemplateId = "RestorePower" | "RecoverCargo" | "RepairSignal"

export type ObjectiveInteractionRole =
	"FusePickup"
	| "FuseSocket"
	| "CargoPickup"
	| "CargoDropPoint"
	| "SignalTerminal"

export type EquipmentItemId = "Flashlight" | "Flare"

export type MissionItemId = "Fuse" | "CargoContainer"

export type NotificationSeverity = "Info" | "Warning" | "Success" | "Danger"

-- Priority 4: The Hollow AI Preparation Types (Section 5)
export type HollowState = "INACTIVE" | "PATROL" | "INVESTIGATE" | "CHASE" | "SEARCH" | "RETURN"

export type NoiseCategory =
	"Walk"
	| "Sprint"
	| "ObjectiveInteraction"
	| "FlareDistraction"
	| "DoorTransit"

export type NoiseEvent = {
	id: number,
	sourceUserId: number?,
	category: NoiseCategory,
	position: any,
	radius: number,
	intensity: number,
	createdAt: number,
	expiresAt: number,
}

export type PlayerDetectionSnapshot = {
	detected: boolean,
	userId: number?,
	position: any,
	distance: number,
	hasLineOfSight: boolean,
	isHidden: boolean,
	threatScore: number,
}

export type StationWaypoint = {
	id: string,
	roomId: string,
	position: any,
	neighbors: { string },
}

export type HidingSpotRecord = {
	id: string,
	part: any,
	position: any,
	occupantUserId: number?,
}

export type RoundStatePayload = {
	state: RoundState,
	serverTimestamp: number,
	phaseEndsAt: number,
	stationId: StationId,
	missionId: MissionTemplateId?,
	activeCrewCount: number,
	boardedCrewCount: number,
	roundNumber: number,
	lastOutcome: RoundOutcome?,
}

export type ObjectivePayload = {
	objectiveId: MissionTemplateId,
	title: string,
	progress: number,
	requiredProgress: number,
	isComplete: boolean,
}

export type PlayerStatusSummary = {
	userId: number,
	displayName: string,
	status: PlayerRoundStatus,
	health: number,
	maxHealth: number,
	isReady: boolean,
}

export type InventorySlotMap = {
	[number]: EquipmentItemId?,
}

export type InventoryPayload = {
	userId: number,
	equipmentSlots: InventorySlotMap,
	missionItems: { [MissionItemId]: number },
}

export type NotificationPayload = {
	messageKey: string,
	messageText: string,
	severity: NotificationSeverity,
	timestamp: number,
}

export type ServiceLifecycle = {
	Name: string,
	Init: (self: any) -> (),
	Start: (self: any) -> (),
}

local NetworkTypes = {}

return table.freeze(NetworkTypes)
