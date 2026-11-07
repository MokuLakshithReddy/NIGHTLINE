--!strict
--[[
	ObjectiveConfig.lua
	Mission template definitions for Station 001 (Section 4.2).
]]

local NetworkTypes = require(script.Parent.Parent.Types.NetworkTypes)

export type ObjectiveTemplate = {
	id: NetworkTypes.MissionTemplateId,
	title: string,
	instruction: string,
	requiredProgress: number,
}

local Templates: { [NetworkTypes.MissionTemplateId]: ObjectiveTemplate } = {
	RestorePower = table.freeze({
		id = "RestorePower" :: NetworkTypes.MissionTemplateId,
		title = "Restore Auxiliary Power",
		instruction = "Find and install 3 transit fuses in designated maintenance sockets.",
		requiredProgress = 3,
	}),
	RecoverCargo = table.freeze({
		id = "RecoverCargo" :: NetworkTypes.MissionTemplateId,
		title = "Recover Lost Cargo",
		instruction = "Locate and deliver 2 sealed cargo containers to the platform drop point.",
		requiredProgress = 2,
	}),
	RepairSignal = table.freeze({
		id = "RepairSignal" :: NetworkTypes.MissionTemplateId,
		title = "Repair the Dispatch Signal",
		instruction = "Activate 3 communication terminals across the terminal concourse.",
		requiredProgress = 3,
	}),
}

local OrderedTemplateIds: { NetworkTypes.MissionTemplateId } = table.freeze({
	"RestorePower" :: NetworkTypes.MissionTemplateId,
	"RecoverCargo" :: NetworkTypes.MissionTemplateId,
	"RepairSignal" :: NetworkTypes.MissionTemplateId,
})

return table.freeze({
	Templates = table.freeze(Templates),
	OrderedTemplateIds = OrderedTemplateIds,
})
