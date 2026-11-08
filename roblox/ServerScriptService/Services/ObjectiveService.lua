--!strict
--[[
	ObjectiveService.lua
	Authoritative server-side Mission & Objective Service for NIGHTLINE: LAST TRAIN (Priority 1 & Priority 2).
	Extracted from RoundService so RoundService remains focused on round orchestration.

	Responsibilities:
	- Mission selection & per-round state initialization (RestorePower, RecoverCargo, RepairSignal).
	- Server-authoritative validation for all three mission-specific mechanics:
	  1. RestorePower:
	     - Find 3 individual fuses (FusePickup_01..03).
	     - Pick up and carry fuses in InventoryService ("Fuse").
	     - Install fuses into 3 designated maintenance sockets (FuseSocket_01..03).
	     - Prevent duplicate fuse collection, duplicate socket installation, or socket installation without carrying a fuse.
	  2. RecoverCargo:
	     - Locate 2 sealed cargo containers (CargoContainer_01..02).
	     - Pick up and carry sealed cargo containers ("CargoContainer", 1 carried at a time per player).
	     - Deliver carried cargo containers to the designated Platform Cargo Drop Point (CargoDropPoint_01).
	     - Prevent duplicate container pickup, carrying multiple heavy containers simultaneously, or invalid delivery without carrying cargo.
	  3. RepairSignal:
	     - Activate 3 communication terminals (SignalTerminal_01..03).
	     - Prevent duplicate activation of an already active terminal.
	- Rejects interactions unrelated to the currently selected mission ("MissionMismatch").
	- Rejects remote abuse (validates living player, active expedition membership, round phase, and 3D distance).
	- Recovers carried uninstalled fuses / undelivered cargo back to their station spawn pads if a carrier is eliminated or disconnects.
	- Resets all objective state cleanly between rounds.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local NetworkTypes = require(ReplicatedStorage.Shared.Types.NetworkTypes)
local ObjectiveConfig = require(ReplicatedStorage.Shared.Config.ObjectiveConfig)

local ObjectiveService: { [string]: any } = {
	Name = "ObjectiveService",

	_activeMissionId = "RestorePower" :: NetworkTypes.MissionTemplateId,
	_progress = 0,
	_requiredProgress = 3,
	_isComplete = false,

	-- Mission-specific tracking tables (reset every round)
	_collectedFuseKeys = {} :: { [string]: boolean },
	_installedSockets = {} :: { [number]: boolean },
	_playerCarriedFuseKeys = {} :: { [number]: { string } },

	_collectedCargoKeys = {} :: { [string]: boolean },
	_deliveredCargoKeys = {} :: { [string]: boolean },
	_playerCarriedCargoKey = {} :: { [number]: string },

	_activatedTerminals = {} :: { [number]: boolean },

	_remotes = nil :: { [string]: RemoteEvent }?,
	_securityService = nil :: any,
	_hubService = nil :: any,
	_inventoryService = nil :: any,
	_roundService = nil :: any,
	_monsterService = nil :: any,
}

function ObjectiveService:Init(dependencies: {
	remotes: { [string]: RemoteEvent },
	securityService: any,
	hubService: any,
	inventoryService: any,
})
	self._remotes = dependencies.remotes
	self._securityService = dependencies.securityService
	self._hubService = dependencies.hubService
	self._inventoryService = dependencies.inventoryService

	self._activeMissionId = ObjectiveConfig.OrderedTemplateIds[1]
	local template = ObjectiveConfig.Templates[self._activeMissionId]
	self._requiredProgress = if template then template.requiredProgress else 3
	self:ResetObjectiveState()
end

function ObjectiveService:SetRoundService(roundService: any)
	self._roundService = roundService
end

function ObjectiveService:SetMonsterService(monsterService: any)
	self._monsterService = monsterService
end

function ObjectiveService:Start()
	-- ObjectiveService is driven by RoundService lifecycle and InteractionService prompt events
end

function ObjectiveService:ResetObjectiveState()
	self._progress = 0
	self._isComplete = false
	local template = ObjectiveConfig.Templates[self._activeMissionId]
	self._requiredProgress = if template then template.requiredProgress else 3

	table.clear(self._collectedFuseKeys)
	table.clear(self._installedSockets)
	table.clear(self._playerCarriedFuseKeys)
	table.clear(self._collectedCargoKeys)
	table.clear(self._deliveredCargoKeys)
	table.clear(self._playerCarriedCargoKey)
	table.clear(self._activatedTerminals)
end

function ObjectiveService:SelectMissionForRound(
	roundNumber: number,
	explicitMissionId: NetworkTypes.MissionTemplateId?
): NetworkTypes.MissionTemplateId
	if explicitMissionId and ObjectiveConfig.Templates[explicitMissionId] then
		self._activeMissionId = explicitMissionId
	else
		local list = ObjectiveConfig.OrderedTemplateIds
		local idx = ((math.max(1, roundNumber) - 1) % #list) + 1
		self._activeMissionId = list[idx]
	end
	self:ResetObjectiveState()
	return self._activeMissionId
end

function ObjectiveService:SetActiveMission(
	missionId: NetworkTypes.MissionTemplateId
): (boolean, string)
	if not ObjectiveConfig.Templates[missionId] then
		return false, "InvalidMissionId"
	end
	self._activeMissionId = missionId
	self:ResetObjectiveState()
	self:ConfigureStationObjectiveParts()
	self:BroadcastObjectiveUpdate()
	return true, "MissionSelected"
end

function ObjectiveService:GetActiveMissionId(): NetworkTypes.MissionTemplateId
	return self._activeMissionId
end

function ObjectiveService:GetObjectiveProgress(): (number, number, boolean)
	return self._progress, self._requiredProgress, self._isComplete
end

function ObjectiveService:IsObjectiveComplete(): boolean
	return self._isComplete
end

--[[
	Configures all physical Station 001 objective parts for the active mission:
	- Resets attributes (Collected, Installed, Activated, DeliveredCount, Completed).
	- Enables ProximityPrompts only for parts belonging to self._activeMissionId.
]]
function ObjectiveService:ConfigureStationObjectiveParts()
	if not self._hubService then
		return
	end

	local parts: { BasePart } = self._hubService:GetStationObjectiveParts()
	for _, part in ipairs(parts) do
		local partMissionId = part:GetAttribute("MissionId")
		local isForActiveMission = (partMissionId == self._activeMissionId)

		part:SetAttribute("Collected", false)
		part:SetAttribute("Installed", false)
		part:SetAttribute("Activated", false)
		part:SetAttribute("DeliveredCount", 0)
		part:SetAttribute("Completed", false)
		part.Transparency = if isForActiveMission then 0 else 0.78

		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = isForActiveMission
		end
	end
end

function ObjectiveService:StartStationObjective(missionId: NetworkTypes.MissionTemplateId?)
	if missionId and ObjectiveConfig.Templates[missionId] then
		self._activeMissionId = missionId
	end
	self:ResetObjectiveState()
	self:ConfigureStationObjectiveParts()
	self:BroadcastObjectiveUpdate()
end

--[[
	If a player carrying an uninstalled Fuse or undelivered CargoContainer is eliminated or disconnects,
	return their carried items to their original Station 001 pickup pads so surviving teammates are never soft-locked.
]]
function ObjectiveService:OnPlayerEliminatedOrRemoved(player: Player)
	local userId = player.UserId

	-- Return any carried uninstalled fuses
	local carriedFuses = self._playerCarriedFuseKeys[userId]
	if carriedFuses then
		for _, fuseKey in ipairs(carriedFuses) do
			self._collectedFuseKeys[fuseKey] = nil
			self:_restorePickupPartByKey(fuseKey)
		end
		self._playerCarriedFuseKeys[userId] = nil
	end

	-- Return any carried undelivered cargo container
	local carriedCargoKey = self._playerCarriedCargoKey[userId]
	if carriedCargoKey and not self._deliveredCargoKeys[carriedCargoKey] then
		self._collectedCargoKeys[carriedCargoKey] = nil
		self:_restorePickupPartByKey(carriedCargoKey)
		self._playerCarriedCargoKey[userId] = nil
	end

	if self._inventoryService then
		self._inventoryService:ResetMissionItemsForRound(player)
	end
end

function ObjectiveService:_restorePickupPartByKey(itemKey: string)
	if not self._hubService then
		return
	end
	local parts: { BasePart } = self._hubService:GetStationObjectiveParts()
	for _, part in ipairs(parts) do
		if part:GetAttribute("ItemKey") == itemKey then
			part:SetAttribute("Collected", false)
			part:SetAttribute("Completed", false)
			part.Transparency = 0
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			if prompt and part:GetAttribute("MissionId") == self._activeMissionId then
				prompt.Enabled = true
			end
		end
	end
end

function ObjectiveService:HandleObjectiveInteraction(
	player: Player,
	objectivePart: BasePart
): (boolean, string)
	local security = self._securityService
	if not security or not security:ValidatePlayerInstance(player) then
		return false, "InvalidPlayer"
	end

	if typeof(objectivePart) ~= "Instance" or not objectivePart:IsA("BasePart") then
		return false, "InvalidObjectivePart"
	end

	if not CollectionService:HasTag(objectivePart, GameConfig.Tags.StationObjective) then
		return false, "NotAnObjectivePart"
	end

	-- Validate active round phase and player expedition eligibility
	if self._roundService then
		local currentState: NetworkTypes.RoundState = self._roundService:GetState()
		if currentState ~= "EXPLORATION" and currentState ~= "EXTRACTION" then
			return false, "InvalidPhase"
		end

		if not self._roundService:IsPlayerInActiveExpedition(player) then
			return false, "NotInActiveExpedition"
		end

		local playerStatus: NetworkTypes.PlayerRoundStatus =
			self._roundService:GetPlayerStatus(player)
		if playerStatus ~= "IN_EXPEDITION" then
			return false, "PlayerNotInExpedition"
		end
	end

	-- Validate living character and 3D proximity to prevent remote abuse
	local _, rootPart, humanoid = security:GetValidatedCharacterRoot(player)
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return false, "PlayerNotAlive"
	end

	if
		not security:ValidateDistance(
			player,
			objectivePart.Position,
			GameConfig.MAX_INTERACTION_DISTANCE
		)
	then
		return false, "OutOfRange"
	end

	-- Priority 1: Reject interactions unrelated to the currently selected mission
	local partMissionId = objectivePart:GetAttribute("MissionId")
	if partMissionId ~= self._activeMissionId then
		self:_notifyPlayer(
			player,
			"ObjectiveMissionMismatch",
			string.format(
				"This object belongs to %s, not the active %s mission.",
				tostring(partMissionId),
				tostring(self._activeMissionId)
			),
			"Warning"
		)
		return false, "MissionMismatch"
	end

	if self._isComplete then
		return false, "ObjectiveAlreadyCompleted"
	end

	local role =
		objectivePart:GetAttribute("ObjectiveRole") :: NetworkTypes.ObjectiveInteractionRole?
	if not role then
		return false, "MissingObjectiveRole"
	end

	if self._activeMissionId == "RestorePower" then
		return self:_handleRestorePower(player, objectivePart, role)
	elseif self._activeMissionId == "RecoverCargo" then
		return self:_handleRecoverCargo(player, objectivePart, role)
	elseif self._activeMissionId == "RepairSignal" then
		return self:_handleRepairSignal(player, objectivePart, role)
	end

	return false, "UnhandledMissionType"
end

function ObjectiveService:_handleRestorePower(
	player: Player,
	objectivePart: BasePart,
	role: NetworkTypes.ObjectiveInteractionRole
): (boolean, string)
	local userId = player.UserId

	if role == "FusePickup" then
		local itemKey = tostring(objectivePart:GetAttribute("ItemKey") or objectivePart.Name)
		if self._collectedFuseKeys[itemKey] or objectivePart:GetAttribute("Collected") == true then
			return false, "FuseAlreadyCollected"
		end

		self._collectedFuseKeys[itemKey] = true
		objectivePart:SetAttribute("Collected", true)
		objectivePart:SetAttribute("Completed", true)
		objectivePart.Transparency = 0.85

		local prompt = objectivePart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end

		local carriedList = self._playerCarriedFuseKeys[userId]
		if not carriedList then
			carriedList = {}
			self._playerCarriedFuseKeys[userId] = carriedList
		end
		table.insert(carriedList, itemKey)

		local fuseCount = 1
		if self._inventoryService then
			local _, updatedCount = self._inventoryService:AddMissionItem(player, "Fuse", 1)
			fuseCount = updatedCount
		end

		self:_emitObjectiveNoise(player, objectivePart.Position)
		self:_notifyPlayer(
			player,
			"FusePickedUp",
			string.format(
				"Picked up High-Voltage Transit Fuse (carrying %d). Install it in a Maintenance Room fuse socket.",
				fuseCount
			),
			"Info"
		)
		return true, "FuseCollected"
	elseif role == "FuseSocket" then
		local socketIndex = tonumber(objectivePart:GetAttribute("ObjectiveIndex")) or 0
		if
			socketIndex < 1
			or self._installedSockets[socketIndex]
			or objectivePart:GetAttribute("Installed") == true
		then
			return false, "SocketAlreadyInstalled"
		end

		local carriedCount = if self._inventoryService
			then self._inventoryService:GetMissionItemCount(player, "Fuse")
			else 0
		if carriedCount < 1 then
			self:_notifyPlayer(
				player,
				"MissingFuseForSocket",
				"You must find and carry a High-Voltage Transit Fuse before installing into a socket.",
				"Warning"
			)
			return false, "MissingRequiredFuse"
		end

		if self._inventoryService then
			local consumedOk = self._inventoryService:ConsumeMissionItem(player, "Fuse", 1)
			if not consumedOk then
				return false, "MissingRequiredFuse"
			end
		end

		local carriedList = self._playerCarriedFuseKeys[userId]
		if carriedList and #carriedList > 0 then
			table.remove(carriedList, 1)
		end

		self._installedSockets[socketIndex] = true
		objectivePart:SetAttribute("Installed", true)
		objectivePart:SetAttribute("Completed", true)

		local prompt = objectivePart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end

		self:_advanceProgress(
			player,
			string.format("installed Transit Fuse into Socket #%d", socketIndex),
			objectivePart.Position
		)
		return true, if self._isComplete then "ObjectiveCompleted" else "FuseInstalled"
	end

	return false, "InvalidRoleForRestorePower"
end

function ObjectiveService:_handleRecoverCargo(
	player: Player,
	objectivePart: BasePart,
	role: NetworkTypes.ObjectiveInteractionRole
): (boolean, string)
	local userId = player.UserId

	if role == "CargoPickup" then
		local cargoKey = tostring(objectivePart:GetAttribute("ItemKey") or objectivePart.Name)
		if
			self._collectedCargoKeys[cargoKey]
			or objectivePart:GetAttribute("Collected") == true
		then
			return false, "CargoAlreadyCollected"
		end

		local currentCarried = if self._inventoryService
			then self._inventoryService:GetMissionItemCount(player, "CargoContainer")
			else 0
		if currentCarried >= 1 or self._playerCarriedCargoKey[userId] ~= nil then
			self:_notifyPlayer(
				player,
				"AlreadyCarryingCargo",
				"You are already carrying a Sealed Cargo Container. Deliver it to the Platform Drop Point first.",
				"Warning"
			)
			return false, "AlreadyCarryingCargo"
		end

		self._collectedCargoKeys[cargoKey] = true
		self._playerCarriedCargoKey[userId] = cargoKey
		objectivePart:SetAttribute("Collected", true)
		objectivePart:SetAttribute("Completed", true)
		objectivePart.Transparency = 0.85

		local prompt = objectivePart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end

		if self._inventoryService then
			self._inventoryService:AddMissionItem(player, "CargoContainer", 1)
		end

		self:_emitObjectiveNoise(player, objectivePart.Position)
		self:_notifyPlayer(
			player,
			"CargoPickedUp",
			"Picked up Sealed Cargo Container. Deliver it to the Station Platform Cargo Drop Point.",
			"Info"
		)
		return true, "CargoCollected"
	elseif role == "CargoDropPoint" then
		local currentCarried = if self._inventoryService
			then self._inventoryService:GetMissionItemCount(player, "CargoContainer")
			else 0
		local carriedKey = self._playerCarriedCargoKey[userId]

		if currentCarried < 1 or not carriedKey then
			self:_notifyPlayer(
				player,
				"MissingCargoForDrop",
				"You are not carrying a Sealed Cargo Container to deliver.",
				"Warning"
			)
			return false, "MissingCarriedCargo"
		end

		if self._deliveredCargoKeys[carriedKey] then
			return false, "DuplicateCargoDelivery"
		end

		if self._inventoryService then
			local consumedOk =
				self._inventoryService:ConsumeMissionItem(player, "CargoContainer", 1)
			if not consumedOk then
				return false, "MissingCarriedCargo"
			end
		end

		self._deliveredCargoKeys[carriedKey] = true
		self._playerCarriedCargoKey[userId] = nil

		local prevDelivered = tonumber(objectivePart:GetAttribute("DeliveredCount")) or 0
		local newDelivered = prevDelivered + 1
		objectivePart:SetAttribute("DeliveredCount", newDelivered)

		self:_advanceProgress(
			player,
			string.format("delivered Sealed Cargo Container (%s)", carriedKey),
			objectivePart.Position
		)

		if self._isComplete then
			objectivePart:SetAttribute("Completed", true)
			local prompt = objectivePart:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = false
			end
		end

		return true, if self._isComplete then "ObjectiveCompleted" else "CargoDelivered"
	end

	return false, "InvalidRoleForRecoverCargo"
end

function ObjectiveService:_handleRepairSignal(
	player: Player,
	objectivePart: BasePart,
	role: NetworkTypes.ObjectiveInteractionRole
): (boolean, string)
	if role ~= "SignalTerminal" then
		return false, "InvalidRoleForRepairSignal"
	end

	local terminalIndex = tonumber(objectivePart:GetAttribute("ObjectiveIndex")) or 0
	if
		terminalIndex < 1
		or self._activatedTerminals[terminalIndex]
		or objectivePart:GetAttribute("Activated") == true
	then
		return false, "TerminalAlreadyActivated"
	end

	self._activatedTerminals[terminalIndex] = true
	objectivePart:SetAttribute("Activated", true)
	objectivePart:SetAttribute("Completed", true)

	local prompt = objectivePart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end

	self:_advanceProgress(
		player,
		string.format("activated Communication Terminal #%d", terminalIndex),
		objectivePart.Position
	)
	return true, if self._isComplete then "ObjectiveCompleted" else "SignalTerminalActivated"
end

function ObjectiveService:_advanceProgress(
	player: Player,
	actionSummary: string,
	worldPosition: Vector3
)
	self._progress = math.min(self._requiredProgress, self._progress + 1)
	if self._progress >= self._requiredProgress then
		self._isComplete = true
	end

	self:_emitObjectiveNoise(player, worldPosition)
	self:BroadcastObjectiveUpdate()

	if self._roundService then
		if self._isComplete then
			self._roundService:BroadcastNotification(
				"PrimaryObjectiveCompleted",
				string.format(
					"Primary objective completed (%d/%d)! %s %s. Proceed to the Station 001 Extraction Platform.",
					self._progress,
					self._requiredProgress,
					player.DisplayName,
					actionSummary
				),
				"Success"
			)
		else
			self._roundService:BroadcastNotification(
				"ObjectiveProgressUpdated",
				string.format(
					"%s %s (%d/%d).",
					player.DisplayName,
					actionSummary,
					self._progress,
					self._requiredProgress
				),
				"Info"
			)
		end
	end
end

function ObjectiveService:_emitObjectiveNoise(player: Player, position: Vector3)
	if self._monsterService then
		self._monsterService:EmitNoiseEvent(player, "ObjectiveInteraction", position)
	end
end

function ObjectiveService:BuildObjectivePayload(): NetworkTypes.ObjectivePayload
	local template = ObjectiveConfig.Templates[self._activeMissionId]
	local title = if template then template.title else tostring(self._activeMissionId)
	return {
		objectiveId = self._activeMissionId,
		title = title,
		progress = self._progress,
		requiredProgress = self._requiredProgress,
		isComplete = self._isComplete,
	}
end

function ObjectiveService:BroadcastObjectiveUpdate()
	local remotes = self._remotes
	if not remotes then
		return
	end
	remotes.ObjectiveUpdated:FireAllClients(self:BuildObjectivePayload())
end

function ObjectiveService:_notifyPlayer(
	player: Player,
	messageKey: string,
	messageText: string,
	severity: NetworkTypes.NotificationSeverity
)
	if self._roundService then
		self._roundService:SendNotificationToPlayer(player, messageKey, messageText, severity)
	end
end

return ObjectiveService
