--!strict
--[[
	UIController.lua
	Client-side controller managing the responsive NIGHTLINEGui ScreenGui (Section 8.1, 8.2 & 8.3).
	Displays:
	- Top Round HUD (State badge, Server countdown timer, Destination & Mission summary)
	- Crew Roster status panel (showsHUB_WAITING, BOARDED, IN_EXPEDITION, EXTRACTED, ELIMINATED)
	- Bottom 2-Slot Equipment Bar + Hub Preparation Controls (Equip Flashlight/Flare, Confirm Route)
	- Notification Banner (paired icon + text + colour for accessibility)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local NetworkTypes = require(ReplicatedStorage.Shared.Types.NetworkTypes)
local ObjectiveConfig = require(ReplicatedStorage.Shared.Config.ObjectiveConfig)
local StationConfig = require(ReplicatedStorage.Shared.Config.StationConfig)

local UIController = {
	Name = "UIController",
	_remotes = nil :: { [string]: RemoteEvent }?,
	_screenGui = nil :: ScreenGui?,
	_stateLabel = nil :: TextLabel?,
	_timerLabel = nil :: TextLabel?,
	_missionLabel = nil :: TextLabel?,
	_crewListFrame = nil :: Frame?,
	_slot1Button = nil :: TextButton?,
	_slot2Button = nil :: TextButton?,
	_notificationLabel = nil :: TextLabel?,
	_activeSlot = 1,
	_currentState = "WAITING" :: NetworkTypes.RoundState,
	_phaseEndsAt = 0,
	_timeOffset = 0,
	_inventory = {
		userId = 0,
		equipmentSlots = { [1] = "Flashlight" :: NetworkTypes.EquipmentItemId?, [2] = nil },
		missionItems = {},
	} :: NetworkTypes.InventoryPayload,
}

function UIController:Init(dependencies: { remotes: { [string]: RemoteEvent } })
	self._remotes = dependencies.remotes
	self:_buildScreenGui()
end

function UIController:Start()
	local remotes = self._remotes
	assert(remotes, "UIController requires remotes initialized")

	remotes.RoundStateChanged.OnClientEvent:Connect(function(payload: NetworkTypes.RoundStatePayload)
		self:_onRoundStateChanged(payload)
	end)

	remotes.ObjectiveUpdated.OnClientEvent:Connect(function(payload: NetworkTypes.ObjectivePayload)
		self:_onObjectiveUpdated(payload)
	end)

	remotes.PlayerStatusUpdated.OnClientEvent:Connect(function(roster: { NetworkTypes.PlayerStatusSummary })
		self:_onPlayerStatusUpdated(roster)
	end)

	remotes.InventoryUpdated.OnClientEvent:Connect(function(payload: NetworkTypes.InventoryPayload)
		self:_onInventoryUpdated(payload)
	end)

	remotes.Notification.OnClientEvent:Connect(function(payload: NetworkTypes.NotificationPayload)
		self:_onNotification(payload)
	end)

	RunService.Heartbeat:Connect(function()
		self:_updateCountdownDisplay()
	end)
end

function UIController:SelectEquipmentSlot(slotIndex: number)
	if slotIndex < 1 or slotIndex > GameConfig.EQUIPMENT_SLOTS then
		return
	end
	self._activeSlot = slotIndex
	self:_refreshSlotButtons()
end

function UIController:RequestHubEquipment(slotIndex: number, itemId: NetworkTypes.EquipmentItemId?)
	local remotes = self._remotes
	if not remotes then
		return
	end
	remotes.RequestEquipment:FireServer(slotIndex, itemId)
end

function UIController:_buildScreenGui()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NIGHTLINEGui"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui
	self._screenGui = screenGui

	-- Top Status Bar (Scale-based anchor at top center)
	local topFrame = Instance.new("Frame")
	topFrame.Name = "GameplayHUD"
	topFrame.AnchorPoint = Vector2.new(0.5, 0)
	topFrame.Position = UDim2.fromScale(0.5, 0.02)
	topFrame.Size = UDim2.fromScale(0.62, 0.11)
	topFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
	topFrame.BackgroundTransparency = 0.12
	topFrame.BorderSizePixel = 0
	topFrame.Parent = screenGui

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.Position = UDim2.fromScale(0.03, 0.1)
	stateLabel.Size = UDim2.fromScale(0.62, 0.42)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Font = Enum.Font.GothamBold
	stateLabel.TextColor3 = Color3.fromRGB(248, 250, 252)
	stateLabel.TextScaled = true
	stateLabel.TextXAlignment = Enum.TextXAlignment.Left
	stateLabel.Text = "[HUB] WAITING FOR CREW"
	stateLabel.Parent = topFrame
	self._stateLabel = stateLabel

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Position = UDim2.fromScale(0.67, 0.1)
	timerLabel.Size = UDim2.fromScale(0.30, 0.42)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Enum.Font.Code
	timerLabel.TextColor3 = Color3.fromRGB(245, 158, 11)
	timerLabel.TextScaled = true
	timerLabel.TextXAlignment = Enum.TextXAlignment.Right
	timerLabel.Text = "00:00"
	timerLabel.Parent = topFrame
	self._timerLabel = timerLabel

	local missionLabel = Instance.new("TextLabel")
	missionLabel.Name = "MissionLabel"
	missionLabel.Position = UDim2.fromScale(0.03, 0.54)
	missionLabel.Size = UDim2.fromScale(0.94, 0.36)
	missionLabel.BackgroundTransparency = 1
	missionLabel.Font = Enum.Font.GothamMedium
	missionLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
	missionLabel.TextScaled = true
	missionLabel.TextXAlignment = Enum.TextXAlignment.Left
	missionLabel.Text = "Destination: Station 001: The Forgotten Terminal"
	missionLabel.Parent = topFrame
	self._missionLabel = missionLabel

	-- Notification Banner (Below Top HUD)
	local notificationLabel = Instance.new("TextLabel")
	notificationLabel.Name = "NotificationBanner"
	notificationLabel.AnchorPoint = Vector2.new(0.5, 0)
	notificationLabel.Position = UDim2.fromScale(0.5, 0.14)
	notificationLabel.Size = UDim2.fromScale(0.58, 0.05)
	notificationLabel.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
	notificationLabel.BackgroundTransparency = 0.15
	notificationLabel.BorderSizePixel = 0
	notificationLabel.Font = Enum.Font.GothamMedium
	notificationLabel.TextColor3 = Color3.fromRGB(226, 232, 240)
	notificationLabel.TextScaled = true
	notificationLabel.Text = "INFO · Welcome aboard NIGHTLINE. Prepare in the Train Hub."
	notificationLabel.Parent = screenGui
	self._notificationLabel = notificationLabel

	-- Crew Roster Panel (Right Side)
	local crewFrame = Instance.new("Frame")
	crewFrame.Name = "TrainHubRoster"
	crewFrame.AnchorPoint = Vector2.new(1, 0)
	crewFrame.Position = UDim2.fromScale(0.98, 0.21)
	crewFrame.Size = UDim2.fromScale(0.24, 0.38)
	crewFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
	crewFrame.BackgroundTransparency = 0.18
	crewFrame.BorderSizePixel = 0
	crewFrame.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0.02, 0)
	listLayout.Parent = crewFrame
	self._crewListFrame = crewFrame

	-- Bottom 2-Slot Equipment Dock
	local inventoryBar = Instance.new("Frame")
	inventoryBar.Name = "Inventory"
	inventoryBar.AnchorPoint = Vector2.new(0.5, 1)
	inventoryBar.Position = UDim2.fromScale(0.5, 0.96)
	inventoryBar.Size = UDim2.fromScale(0.42, 0.09)
	inventoryBar.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
	inventoryBar.BackgroundTransparency = 0.12
	inventoryBar.BorderSizePixel = 0
	inventoryBar.Parent = screenGui

	local slot1Btn = Instance.new("TextButton")
	slot1Btn.Name = "Slot1Button"
	slot1Btn.Position = UDim2.fromScale(0.03, 0.12)
	slot1Btn.Size = UDim2.fromScale(0.45, 0.76)
	slot1Btn.BackgroundColor3 = Color3.fromRGB(30, 58, 138)
	slot1Btn.Font = Enum.Font.GothamBold
	slot1Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	slot1Btn.TextScaled = true
	slot1Btn.Text = "[1] Service Flashlight"
	slot1Btn.Parent = inventoryBar
	slot1Btn.Activated:Connect(function()
		self:SelectEquipmentSlot(1)
		self:RequestHubEquipment(1, "Flashlight")
	end)
	self._slot1Button = slot1Btn

	local slot2Btn = Instance.new("TextButton")
	slot2Btn.Name = "Slot2Button"
	slot2Btn.Position = UDim2.fromScale(0.52, 0.12)
	slot2Btn.Size = UDim2.fromScale(0.45, 0.76)
	slot2Btn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
	slot2Btn.Font = Enum.Font.GothamBold
	slot2Btn.TextColor3 = Color3.fromRGB(226, 232, 240)
	slot2Btn.TextScaled = true
	slot2Btn.Text = "[2] Empty Slot (Tap for Flare)"
	slot2Btn.Parent = inventoryBar
	slot2Btn.Activated:Connect(function()
		self:SelectEquipmentSlot(2)
		self:RequestHubEquipment(2, "Flare")
	end)
	self._slot2Button = slot2Btn
end

function UIController:_onRoundStateChanged(payload: NetworkTypes.RoundStatePayload)
	self._currentState = payload.state
	self._phaseEndsAt = payload.phaseEndsAt
	self._timeOffset = payload.serverTimestamp - os.time()

	if self._stateLabel then
		self._stateLabel.Text = string.format(
			"ROUND #%d · %s (%d/%d BOARDED)",
			payload.roundNumber,
			payload.state,
			payload.boardedCrewCount,
			payload.activeCrewCount
		)
	end

	local stationDef = StationConfig.Stations[payload.stationId]
	local stationName = if stationDef then stationDef.displayName else payload.stationId
	local missionTitle = "Awaiting Assignment"
	if payload.missionId and ObjectiveConfig.Templates[payload.missionId] then
		missionTitle = ObjectiveConfig.Templates[payload.missionId].title
	end

	if self._missionLabel then
		self._missionLabel.Text = string.format("%s · Mission: %s", stationName, missionTitle)
	end

	self:_updateCountdownDisplay()
end

function UIController:_onObjectiveUpdated(payload: NetworkTypes.ObjectivePayload)
	if self._missionLabel then
		local statusPrefix = if payload.isComplete then "COMPLETE" else "ACTIVE"
		self._missionLabel.Text = string.format(
			"[%s] %s (%d/%d)",
			statusPrefix,
			payload.title,
			payload.progress,
			payload.requiredProgress
		)
	end
end

function UIController:_onPlayerStatusUpdated(roster: { NetworkTypes.PlayerStatusSummary })
	local crewFrame = self._crewListFrame
	if not crewFrame then
		return
	end

	for _, child in ipairs(crewFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	for index, member in ipairs(roster) do
		local row = Instance.new("TextLabel")
		row.Name = string.format("CrewRow_%d", member.userId)
		row.LayoutOrder = index
		row.Size = UDim2.fromScale(1, 0.14)
		row.BackgroundTransparency = 0.3
		row.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
		row.Font = Enum.Font.GothamMedium
		row.TextColor3 = Color3.fromRGB(241, 245, 249)
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = string.format("  %s · %s (HP %d)", member.displayName, member.status, member.health)
		row.Parent = crewFrame
	end
end

function UIController:_onInventoryUpdated(payload: NetworkTypes.InventoryPayload)
	self._inventory = payload
	self:_refreshSlotButtons()
end

function UIController:_refreshSlotButtons()
	local slots = self._inventory.equipmentSlots
	if self._slot1Button then
		local item1 = slots[1]
		local name1 = if item1 and ItemConfig.Items[item1] then ItemConfig.Items[item1].displayName else "Empty (Equip Flashlight)"
		self._slot1Button.Text = string.format("[1] %s", name1)
		self._slot1Button.BackgroundColor3 = if self._activeSlot == 1
			then Color3.fromRGB(37, 99, 235)
			else Color3.fromRGB(30, 41, 59)
	end
	if self._slot2Button then
		local item2 = slots[2]
		local name2 = if item2 and ItemConfig.Items[item2] then ItemConfig.Items[item2].displayName else "Empty (Equip Flare)"
		self._slot2Button.Text = string.format("[2] %s", name2)
		self._slot2Button.BackgroundColor3 = if self._activeSlot == 2
			then Color3.fromRGB(37, 99, 235)
			else Color3.fromRGB(30, 41, 59)
	end
end

function UIController:_onNotification(payload: NetworkTypes.NotificationPayload)
	if not self._notificationLabel then
		return
	end
	local prefix = string.upper(payload.severity)
	self._notificationLabel.Text = string.format("%s · %s", prefix, payload.messageText)
end

function UIController:_updateCountdownDisplay()
	if not self._timerLabel then
		return
	end
	if self._phaseEndsAt <= 0 then
		self._timerLabel.Text = "STANDBY"
		return
	end

	local estimatedServerNow = os.time() + self._timeOffset
	local remaining = math.max(0, self._phaseEndsAt - estimatedServerNow)
	local minutes = math.floor(remaining / 60)
	local seconds = remaining % 60
	self._timerLabel.Text = string.format("%02d:%02d", minutes, seconds)
end

return UIController
