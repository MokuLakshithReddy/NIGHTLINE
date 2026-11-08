--!strict
--[[
	InteractionService.lua
	Validates server-side ProximityPrompt activations using CollectionService tags,
	character existence, living state, distance checks, and per-player cooldowns (Section 6.2 & Section 10).
	Routes StationObjective prompts to ObjectiveService and HidingSpot prompts to MonsterService.
]]

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local InteractionService: { [string]: any } = {
	Name = "InteractionService",
	_securityService = nil :: any,
	_inventoryService = nil :: any,
	_roundService = nil :: any,
	_objectiveService = nil :: any,
	_monsterService = nil :: any,
}

function InteractionService:Init(dependencies: {
	securityService: any,
	inventoryService: any,
	roundService: any,
	objectiveService: any?,
	monsterService: any?,
})
	self._securityService = dependencies.securityService
	self._inventoryService = dependencies.inventoryService
	self._roundService = dependencies.roundService
	self._objectiveService = dependencies.objectiveService
	self._monsterService = dependencies.monsterService
end

function InteractionService:SetObjectiveService(objectiveService: any)
	self._objectiveService = objectiveService
end

function InteractionService:SetMonsterService(monsterService: any)
	self._monsterService = monsterService
end

function InteractionService:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		self:HandlePromptTriggered(prompt, player)
	end)
end

function InteractionService:HandlePromptTriggered(
	prompt: ProximityPrompt,
	player: Player
): (boolean, string)
	local security = self._securityService
	if not security:ValidatePlayerInstance(player) then
		return false, "InvalidPlayer"
	end

	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
		return false, "InvalidPrompt"
	end

	local parentPart = prompt.Parent
	if not parentPart or not parentPart:IsA("BasePart") then
		return false, "MissingPromptPart"
	end

	-- Per-player prompt cooldown check
	if
		not security:CheckAndSetCooldown(
			player.UserId,
			"PromptTriggered",
			GameConfig.PROMPT_COOLDOWN_SECONDS
		)
	then
		return false, "CooldownActive"
	end

	-- Validate living character and distance on the server
	if
		not security:ValidateDistance(
			player,
			parentPart.Position,
			GameConfig.MAX_INTERACTION_DISTANCE
		)
	then
		warn(string.format("[InteractionService] Rejected far prompt trigger from %s", player.Name))
		return false, "OutOfRange"
	end

	-- Route interaction by CollectionService tag (never rely solely on object names)
	if CollectionService:HasTag(parentPart, GameConfig.Tags.EquipmentLocker) then
		local itemId = parentPart:GetAttribute("ItemId")
		local slotIndex = parentPart:GetAttribute("SlotIndex") or 1
		return self._inventoryService:HandleEquipmentRequest(player, slotIndex, itemId)
	elseif CollectionService:HasTag(parentPart, GameConfig.Tags.DestinationTerminal) then
		local stationId = parentPart:GetAttribute("StationId") or GameConfig.DEFAULT_STATION_ID
		return self._roundService:HandleDestinationVote(player, stationId)
	elseif CollectionService:HasTag(parentPart, GameConfig.Tags.BoardingZone) then
		return self._roundService:TogglePlayerBoardingReady(player)
	elseif CollectionService:HasTag(parentPart, GameConfig.Tags.ExtractionZone) then
		return self._roundService:TryExtractPlayer(player)
	elseif CollectionService:HasTag(parentPart, GameConfig.Tags.StationObjective) then
		if self._objectiveService then
			return self._objectiveService:HandleObjectiveInteraction(player, parentPart)
		end
		return self._roundService:HandleStationObjectiveInteraction(player, parentPart)
	elseif CollectionService:HasTag(parentPart, GameConfig.Tags.HidingSpot) then
		if self._monsterService then
			return self._monsterService:HandleHidingSpotInteraction(player, parentPart)
		end
		return false, "MissingMonsterService"
	end

	return false, "UnhandledTag"
end

return InteractionService
