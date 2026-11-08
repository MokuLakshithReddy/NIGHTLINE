--!strict
--[[
	InventoryService.lua
	Owns server-authoritative player equipment loadouts (2 slots) and mission items (Section 6.1 & Section 10).
	Never allows clients to set arbitrary item IDs or mutate inventory outside preparation phases.
	Mission items (Fuse, CargoContainer) are modified exclusively by server-side ObjectiveService validation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local NetworkTypes = require(ReplicatedStorage.Shared.Types.NetworkTypes)

type PlayerInventoryRecord = {
	equipmentSlots: { [number]: NetworkTypes.EquipmentItemId? },
	missionItems: { [NetworkTypes.MissionItemId]: number },
}

local InventoryService: { [string]: any } = {
	Name = "InventoryService",
	_inventories = {} :: { [number]: PlayerInventoryRecord },
	_remotes = nil :: { [string]: RemoteEvent }?,
	_securityService = nil :: any,
	_roundService = nil :: any,
}

function InventoryService:Init(dependencies: {
	remotes: { [string]: RemoteEvent },
	securityService: any,
})
	self._remotes = dependencies.remotes
	self._securityService = dependencies.securityService
	table.clear(self._inventories)
end

function InventoryService:SetRoundService(roundService: any)
	self._roundService = roundService
end

function InventoryService:Start()
	local remotes = self._remotes
	assert(remotes, "InventoryService requires remotes initialized")

	remotes.RequestEquipment.OnServerEvent:Connect(
		function(player: Player, slotIndex: any, requestedItemId: any)
			self:HandleEquipmentRequest(player, slotIndex, requestedItemId)
		end
	)

	Players.PlayerRemoving:Connect(function(player: Player)
		self._inventories[player.UserId] = nil
	end)
end

function InventoryService:EnsurePlayerInventory(player: Player): PlayerInventoryRecord
	local existing = self._inventories[player.UserId]
	if existing then
		return existing
	end

	local record: PlayerInventoryRecord = {
		equipmentSlots = {
			[1] = "Flashlight" :: NetworkTypes.EquipmentItemId,
			[2] = nil,
		},
		missionItems = {},
	}
	self._inventories[player.UserId] = record
	self:SyncToPlayer(player)
	return record
end

function InventoryService:ResetMissionItemsForRound(player: Player)
	local record = self:EnsurePlayerInventory(player)
	table.clear(record.missionItems)
	self:SyncToPlayer(player)
end

function InventoryService:GetMissionItemCount(
	player: Player,
	itemId: NetworkTypes.MissionItemId
): number
	local record = self:EnsurePlayerInventory(player)
	return record.missionItems[itemId] or 0
end

function InventoryService:AddMissionItem(
	player: Player,
	itemId: NetworkTypes.MissionItemId,
	amount: number?
): (boolean, number)
	if not ItemConfig.AllowedMissionItemIds[itemId] then
		return false, 0
	end
	local delta = if amount and amount > 0 then math.floor(amount) else 1
	local record = self:EnsurePlayerInventory(player)
	local currentCount = record.missionItems[itemId] or 0
	local updatedCount = currentCount + delta
	record.missionItems[itemId] = updatedCount
	self:SyncToPlayer(player)
	return true, updatedCount
end

function InventoryService:ConsumeMissionItem(
	player: Player,
	itemId: NetworkTypes.MissionItemId,
	amount: number?
): (boolean, number)
	if not ItemConfig.AllowedMissionItemIds[itemId] then
		return false, 0
	end
	local delta = if amount and amount > 0 then math.floor(amount) else 1
	local record = self:EnsurePlayerInventory(player)
	local currentCount = record.missionItems[itemId] or 0
	if currentCount < delta then
		return false, currentCount
	end
	local remaining = currentCount - delta
	if remaining > 0 then
		record.missionItems[itemId] = remaining
	else
		record.missionItems[itemId] = nil
	end
	self:SyncToPlayer(player)
	return true, remaining
end

function InventoryService:GetInventoryPayload(player: Player): NetworkTypes.InventoryPayload
	local record = self:EnsurePlayerInventory(player)
	return {
		userId = player.UserId,
		equipmentSlots = {
			[1] = record.equipmentSlots[1],
			[2] = record.equipmentSlots[2],
		},
		missionItems = table.clone(record.missionItems),
	}
end

function InventoryService:SyncToPlayer(player: Player)
	local remotes = self._remotes
	if not remotes then
		return
	end
	local payload = self:GetInventoryPayload(player)
	remotes.InventoryUpdated:FireClient(player, payload)
end

function InventoryService:HandleEquipmentRequest(
	player: Player,
	slotIndex: any,
	requestedItemId: any
): (boolean, string)
	local security = self._securityService
	if not security:ValidatePlayerInstance(player) then
		return false, "InvalidPlayer"
	end

	if not security:CheckRateLimit(player.UserId, "RequestEquipment") then
		return false, "RateLimited"
	end

	if not security:CheckAndSetCooldown(player.UserId, "RequestEquipment", 0.25) then
		return false, "CooldownActive"
	end

	-- Validate round phase: equipment preparation is only allowed in Hub / Preparation phases
	if self._roundService then
		local currentState: NetworkTypes.RoundState = self._roundService:GetState()
		local playerStatus: NetworkTypes.PlayerRoundStatus =
			self._roundService:GetPlayerStatus(player)
		local isPrepPhase = (
			currentState == "WAITING"
			or currentState == "INTERMISSION"
			or currentState == "BOARDING"
		)
		if not isPrepPhase and playerStatus ~= "HUB_WAITING" then
			self:_sendNotification(
				player,
				"EquipmentLocked",
				"Equipment can only be changed inside the Train Hub before departure.",
				"Warning"
			)
			return false, "InvalidRoundPhase"
		end
	end

	-- Validate slot index (1..EQUIPMENT_SLOTS)
	if not security:ValidateIntegerInRange(slotIndex, 1, GameConfig.EQUIPMENT_SLOTS) then
		return false, "InvalidSlotIndex"
	end

	local record = self:EnsurePlayerInventory(player)

	-- Allow clearing a slot by passing nil or ""
	if requestedItemId == nil or requestedItemId == "" then
		record.equipmentSlots[slotIndex] = nil
		self:SyncToPlayer(player)
		return true, "SlotCleared"
	end

	-- Validate requestedItemId against Hub equipment allowlist
	if not security:ValidateString(requestedItemId, 32, ItemConfig.AllowedHubEquipmentIds) then
		return false, "InvalidItemId"
	end

	local validItemId = requestedItemId :: NetworkTypes.EquipmentItemId

	-- Prevent duplicate single-item assignment across slots by swapping or clearing the other slot
	for otherSlot = 1, GameConfig.EQUIPMENT_SLOTS do
		if otherSlot ~= slotIndex and record.equipmentSlots[otherSlot] == validItemId then
			record.equipmentSlots[otherSlot] = nil
		end
	end

	record.equipmentSlots[slotIndex] = validItemId
	self:SyncToPlayer(player)

	local itemDef = ItemConfig.Items[validItemId]
	local itemName = if itemDef then itemDef.displayName else validItemId
	self:_sendNotification(
		player,
		"EquipmentUpdated",
		string.format("Equipped %s in Slot %d.", itemName, slotIndex),
		"Info"
	)

	return true, "Equipped"
end

function InventoryService:_sendNotification(
	player: Player,
	messageKey: string,
	messageText: string,
	severity: NetworkTypes.NotificationSeverity
)
	local remotes = self._remotes
	if not remotes then
		return
	end
	local payload: NetworkTypes.NotificationPayload = {
		messageKey = messageKey,
		messageText = messageText,
		severity = severity,
		timestamp = os.time(),
	}
	remotes.Notification:FireClient(player, payload)
end

return InventoryService
