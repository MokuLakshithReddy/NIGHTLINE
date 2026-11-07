--!strict
--[[
	NetworkTypes.lua
	Shared strict Luau type definitions for NIGHTLINE: LAST TRAIN.
	Defines round states, player statuses, equipment slots, and networking payloads.
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

export type RoundOutcome = "PENDING" | "SUCCESS" | "FAILED"

export type StationId = "Station001"

export type MissionTemplateId = "RestorePower" | "RecoverCargo" | "RepairSignal"

export type EquipmentItemId = "Flashlight" | "Flare"

export type MissionItemId = "Fuse"

export type NotificationSeverity = "Info" | "Warning" | "Success" | "Danger"

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
