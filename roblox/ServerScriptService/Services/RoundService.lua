--!strict
--[[
	RoundService.lua
	Authoritative server-side Round State Machine for NIGHTLINE: LAST TRAIN (Section 3.2, 3.3, 3.4 & Milestone 1).
	Owns:
	- State transitions: WAITING -> INTERMISSION -> BOARDING -> TRAVEL -> EXPLORATION -> EXTRACTION -> RETURN -> RESULTS
	- Server-owned countdown timers
	- Crew roster and boarding preparation
	- Destination votes (validated via SecurityService)
	- Late-joining player isolation (late joiners remain in safe Hub and join next round)
	- All-player disconnect termination and deterministic Janitor cleanup
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local NetworkTypes = require(ReplicatedStorage.Shared.Types.NetworkTypes)
local ObjectiveConfig = require(ReplicatedStorage.Shared.Config.ObjectiveConfig)
local StationConfig = require(ReplicatedStorage.Shared.Config.StationConfig)
local Janitor = require(ReplicatedStorage.Shared.Utils.Janitor)
local Signal = require(ReplicatedStorage.Shared.Utils.Signal)

type PlayerRosterEntry = {
	player: Player,
	status: NetworkTypes.PlayerRoundStatus,
	isReady: boolean,
	votedStationId: NetworkTypes.StationId?,
}

local RoundService = {
	Name = "RoundService",
	StateChanged = Signal.new(),

	_state = "WAITING" :: NetworkTypes.RoundState,
	_roundNumber = 0,
	_phaseEndsAt = 0,
	_selectedStationId = GameConfig.DEFAULT_STATION_ID :: NetworkTypes.StationId,
	_selectedMissionId = "RestorePower" :: NetworkTypes.MissionTemplateId,
	_roster = {} :: { [number]: PlayerRosterEntry },
	_activeExpeditionUserIds = {} :: { [number]: boolean },
	_roundJanitor = Janitor.new(),
	_loopThread = nil :: thread?,

	_remotes = nil :: { [string]: RemoteEvent }?,
	_securityService = nil :: any,
	_hubService = nil :: any,
	_inventoryService = nil :: any,
}

function RoundService:Init(dependencies: {
	remotes: { [string]: RemoteEvent },
	securityService: any,
	hubService: any,
	inventoryService: any,
})
	self._remotes = dependencies.remotes
	self._securityService = dependencies.securityService
	self._hubService = dependencies.hubService
	self._inventoryService = dependencies.inventoryService

	self._state = "WAITING"
	self._roundNumber = 0
	self._phaseEndsAt = 0
	self._selectedStationId = GameConfig.DEFAULT_STATION_ID
	self._selectedMissionId = ObjectiveConfig.OrderedTemplateIds[1]
	table.clear(self._roster)
	table.clear(self._activeExpeditionUserIds)
end

function RoundService:Start()
	local remotes = self._remotes
	assert(remotes, "RoundService requires remotes initialized")

	remotes.RequestDestinationVote.OnServerEvent:Connect(function(player: Player, stationId: any)
		self:HandleDestinationVote(player, stationId)
	end)

	for index, player in ipairs(Players:GetPlayers()) do
		self:RegisterPlayer(player, index)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		local slotIndex = #Players:GetPlayers()
		self:RegisterPlayer(player, slotIndex)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:UnregisterPlayer(player)
	end)

	self._loopThread = task.spawn(function()
		self:_runStateMachineLoop()
	end)
end

function RoundService:GetState(): NetworkTypes.RoundState
	return self._state
end

function RoundService:GetPlayerStatus(player: Player): NetworkTypes.PlayerRoundStatus
	local entry = self._roster[player.UserId]
	if not entry then
		return "HUB_WAITING"
	end
	return entry.status
end

function RoundService:RegisterPlayer(player: Player, spawnSlotIndex: number?)
	local isRoundActive = self:_isExpeditionPhase(self._state)

	local entry: PlayerRosterEntry = {
		player = player,
		status = "HUB_WAITING",
		isReady = false,
		votedStationId = GameConfig.DEFAULT_STATION_ID,
	}
	self._roster[player.UserId] = entry

	if self._inventoryService then
		self._inventoryService:EnsurePlayerInventory(player)
	end

	player.CharacterAdded:Connect(function()
		task.defer(function()
			-- Always spawn character inside the safe Train Hub unless they are actively transitioning
			if self._hubService then
				self._hubService:SpawnPlayerInHub(player, spawnSlotIndex or 1)
			end
		end)
	end)

	if player.Character and self._hubService then
		self._hubService:SpawnPlayerInHub(player, spawnSlotIndex or 1)
	end

	-- Sync current round state and roster statuses to the newly joined player
	self:_sendStateToPlayer(player)
	self:_broadcastPlayerStatuses()

	if isRoundActive then
		self:SendNotificationToPlayer(
			player,
			"LateJoinWaiting",
			"An expedition is currently underway. Prepare in the Train Hub for the next departure.",
			"Info"
		)
	else
		self:SendNotificationToPlayer(
			player,
			"WelcomeHub",
			"Welcome aboard NIGHTLINE. Check your equipment and board before departure.",
			"Info"
		)
	end
end

function RoundService:UnregisterPlayer(player: Player)
	local userId = player.UserId
	self._roster[userId] = nil

	if self._activeExpeditionUserIds[userId] then
		self._activeExpeditionUserIds[userId] = nil
	end

	self:_broadcastPlayerStatuses()

	-- Section 3.3: If all active expedition players leave during an active round, terminate safely and clean up
	if self:_isExpeditionPhase(self._state) and self:_countActiveExpeditionPlayers() == 0 then
		warn("[RoundService] All active expedition players left; terminating round safely and cleaning up.")
		self:CleanupRound()
		self:_transitionTo("WAITING", 0)
	end
end

function RoundService:TogglePlayerBoardingReady(player: Player): (boolean, string)
	local entry = self._roster[player.UserId]
	if not entry then
		return false, "NotRegistered"
	end

	if self._state ~= "INTERMISSION" and self._state ~= "BOARDING" then
		self:SendNotificationToPlayer(
			player,
			"BoardingClosed",
			"Boarding preparation is only active during Intermission and Boarding.",
			"Warning"
		)
		return false, "InvalidPhase"
	end

	entry.isReady = not entry.isReady
	entry.status = if entry.isReady then "BOARDED" else "HUB_WAITING"

	self:_broadcastPlayerStatuses()
	self:_broadcastState()

	if entry.isReady then
		self:SendNotificationToPlayer(
			player,
			"BoardingReadyConfirmed",
			"You are boarded and ready for departure.",
			"Success"
		)
	else
		self:SendNotificationToPlayer(
			player,
			"BoardingSteppedOff",
			"You stepped out of the boarding roster.",
			"Info"
		)
	end

	return true, if entry.isReady then "Ready" else "Unready"
end

function RoundService:HandleDestinationVote(player: Player, stationId: any): (boolean, string)
	local security = self._securityService
	if not security:ValidatePlayerInstance(player) then
		return false, "InvalidPlayer"
	end

	if not security:CheckRateLimit(player.UserId, "RequestDestinationVote") then
		return false, "RateLimited"
	end

	if self._state ~= "WAITING" and self._state ~= "INTERMISSION" and self._state ~= "BOARDING" then
		return false, "VotingClosed"
	end

	if not security:ValidateString(stationId, 32, StationConfig.AllowedStationIds) then
		return false, "InvalidStationId"
	end

	local entry = self._roster[player.UserId]
	if not entry then
		return false, "PlayerNotRostered"
	end

	local validStationId = stationId :: NetworkTypes.StationId
	entry.votedStationId = validStationId
	self._selectedStationId = validStationId

	local stationDef = StationConfig.Stations[validStationId]
	local stationName = if stationDef then stationDef.displayName else validStationId

	self:SendNotificationToPlayer(
		player,
		"DestinationVoteRecorded",
		string.format("Route confirmed for %s.", stationName),
		"Info"
	)
	self:_broadcastState()
	return true, "VoteRecorded"
end

function RoundService:_isExpeditionPhase(state: NetworkTypes.RoundState): boolean
	return state == "TRAVEL"
		or state == "EXPLORATION"
		or state == "EXTRACTION"
		or state == "RETURN"
		or state == "RESULTS"
end

function RoundService:_countEligibleHubPlayers(): number
	local count = 0
	for _, entry in pairs(self._roster) do
		if entry.player.Parent == Players then
			count += 1
		end
	end
	return count
end

function RoundService:_countBoardedPlayers(): number
	local count = 0
	for _, entry in pairs(self._roster) do
		if entry.player.Parent == Players and (entry.status == "BOARDED" or entry.isReady) then
			count += 1
		end
	end
	return count
end

function RoundService:_countActiveExpeditionPlayers(): number
	local count = 0
	for userId in pairs(self._activeExpeditionUserIds) do
		local entry = self._roster[userId]
		if entry and entry.player.Parent == Players then
			count += 1
		end
	end
	return count
end

function RoundService:_runStateMachineLoop()
	while true do
		if self._state == "WAITING" then
			if self:_countEligibleHubPlayers() >= GameConfig.MIN_CREW_TO_START then
				self:_startNewIntermission()
			else
				task.wait(0.5)
			end
		elseif self._state == "INTERMISSION" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.INTERMISSION, false) then
				self:_enterBoardingPhase()
			end
		elseif self._state == "BOARDING" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.BOARDING, false) then
				self:_lockCrewAndDepart()
			end
		elseif self._state == "TRAVEL" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.TRAVEL, true) then
				self:_enterExplorationPhase()
			end
		elseif self._state == "EXPLORATION" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.EXPLORATION, true) then
				self:_enterExtractionPhase()
			end
		elseif self._state == "EXTRACTION" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.EXTRACTION, true) then
				self:_enterReturnPhase()
			end
		elseif self._state == "RETURN" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.RETURN, true) then
				self:_enterResultsPhase()
			end
		elseif self._state == "RESULTS" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.RESULTS, false) then
				self:CleanupRound()
				if self:_countEligibleHubPlayers() >= GameConfig.MIN_CREW_TO_START then
					self:_startNewIntermission()
				else
					self:_transitionTo("WAITING", 0)
				end
			end
		else
			task.wait(1)
		end
	end
end

function RoundService:_waitPhaseOrAbort(durationSeconds: number, requireActiveCrew: boolean): boolean
	local deadline = os.clock() + durationSeconds
	while os.clock() < deadline do
		if requireActiveCrew and self:_countActiveExpeditionPlayers() == 0 then
			self:CleanupRound()
			self:_transitionTo("WAITING", 0)
			return false
		end
		if not requireActiveCrew and self:_countEligibleHubPlayers() < GameConfig.MIN_CREW_TO_START then
			self:CleanupRound()
			self:_transitionTo("WAITING", 0)
			return false
		end
		task.wait(0.25)
	end
	return true
end

function RoundService:_startNewIntermission()
	self._roundNumber += 1
	local templateList = ObjectiveConfig.OrderedTemplateIds
	local missionIndex = ((self._roundNumber - 1) % #templateList) + 1
	self._selectedMissionId = templateList[missionIndex]

	for _, entry in pairs(self._roster) do
		entry.status = "HUB_WAITING"
		entry.isReady = false
	end
	table.clear(self._activeExpeditionUserIds)

	self:_transitionTo("INTERMISSION", GameConfig.RoundDurations.INTERMISSION)
	self:_broadcastPlayerStatuses()
	self:BroadcastNotification(
		"IntermissionStarted",
		"Next departure scheduled. Select equipment and confirm route in the Train Hub.",
		"Info"
	)
end

function RoundService:_enterBoardingPhase()
	-- Default all present hub players into BOARDED roster so solo/casual players aren't left behind accidentally,
	-- while still allowing players to toggle ready state at the Boarding Gate
	for _, entry in pairs(self._roster) do
		if entry.player.Parent == Players then
			entry.isReady = true
			entry.status = "BOARDED"
		end
	end

	self:_transitionTo("BOARDING", GameConfig.RoundDurations.BOARDING)
	self:_broadcastPlayerStatuses()
	self:_broadcastObjectivePreview()
	self:BroadcastNotification(
		"BoardingStarted",
		"Boarding doors open. Finalize your 2-slot loadout before the train departs.",
		"Warning"
	)
end

function RoundService:_lockCrewAndDepart()
	table.clear(self._activeExpeditionUserIds)
	local departingPlayers: { Player } = {}

	for userId, entry in pairs(self._roster) do
		if entry.player.Parent == Players and (entry.isReady or entry.status == "BOARDED") then
			entry.status = "IN_EXPEDITION"
			self._activeExpeditionUserIds[userId] = true
			table.insert(departingPlayers, entry.player)
		else
			entry.status = "HUB_WAITING"
		end
	end

	-- If nobody remained boarded, ensure at least present players board if eligible
	if #departingPlayers == 0 then
		for userId, entry in pairs(self._roster) do
			if entry.player.Parent == Players then
				entry.isReady = true
				entry.status = "IN_EXPEDITION"
				self._activeExpeditionUserIds[userId] = true
				table.insert(departingPlayers, entry.player)
			end
		end
	end

	if #departingPlayers == 0 then
		self:CleanupRound()
		self:_transitionTo("WAITING", 0)
		return
	end

	if self._hubService then
		self._hubService:MoveCrewToBoardingBay(departingPlayers)
	end

	self:_transitionTo("TRAVEL", GameConfig.RoundDurations.TRAVEL)
	self:_broadcastPlayerStatuses()
	self:BroadcastNotification(
		"TrainDeparting",
		"Train departing Hub. En route to Station 001: The Forgotten Terminal.",
		"Info"
	)
end

function RoundService:_enterExplorationPhase()
	self:_transitionTo("EXPLORATION", GameConfig.RoundDurations.EXPLORATION)
	self:_broadcastObjectivePreview()
	self:BroadcastNotification(
		"ArrivedAtStation",
		"Arrived at Station 001. Complete the primary objective and watch for acoustic disturbances.",
		"Warning"
	)
end

function RoundService:_enterExtractionPhase()
	self:_transitionTo("EXTRACTION", GameConfig.RoundDurations.EXTRACTION)
	self:BroadcastNotification(
		"ExtractionWarning",
		"Departure horn sounded! Return to the extraction platform within 60 seconds!",
		"Danger"
	)
end

function RoundService:_enterReturnPhase()
	-- Resolve extraction for active crew members still in the expedition
	for userId in pairs(self._activeExpeditionUserIds) do
		local entry = self._roster[userId]
		if entry and entry.player.Parent == Players and entry.status == "IN_EXPEDITION" then
			entry.status = "EXTRACTED"
		end
	end

	self:_transitionTo("RETURN", GameConfig.RoundDurations.RETURN)
	self:_broadcastPlayerStatuses()
	self:BroadcastNotification(
		"ReturningToHub",
		"Train departing Station 001. Returning surviving crew to the Train Hub.",
		"Success"
	)
end

function RoundService:_enterResultsPhase()
	self:_transitionTo("RESULTS", GameConfig.RoundDurations.RESULTS)
	self:_broadcastPlayerStatuses()
	self:BroadcastNotification(
		"ExpeditionResults",
		"Expedition complete. Reviewing crew status and resetting Train Hub.",
		"Info"
	)
end

function RoundService:CleanupRound()
	-- Clean all temporary round resources via Janitor
	self._roundJanitor:Cleanup()

	-- Clear any runtime station instances
	if self._hubService then
		self._hubService:ClearRuntimeStation()
	end

	-- Reset player statuses and temporary mission items, and return all players to Hub spawns
	local allPlayers: { Player } = {}
	for _, entry in pairs(self._roster) do
		entry.status = "HUB_WAITING"
		entry.isReady = false
		if entry.player.Parent == Players then
			table.insert(allPlayers, entry.player)
			if self._inventoryService then
				self._inventoryService:ResetMissionItemsForRound(entry.player)
			end
		end
	end

	table.clear(self._activeExpeditionUserIds)

	if self._hubService and #allPlayers > 0 then
		self._hubService:ReturnAllPlayersToHub(allPlayers)
	end

	self:_broadcastPlayerStatuses()
end

function RoundService:_transitionTo(newState: NetworkTypes.RoundState, durationSeconds: number)
	local now = os.time()
	self._state = newState
	self._phaseEndsAt = if durationSeconds > 0 then (now + durationSeconds) else 0

	print(
		string.format(
			"[RoundService] Round #%d State -> %s (duration=%ds, crew=%d)",
			self._roundNumber,
			newState,
			durationSeconds,
			self:_countActiveExpeditionPlayers()
		)
	)

	self:_broadcastState()
	self.StateChanged:Fire(newState, durationSeconds)
end

function RoundService:_buildStatePayload(): NetworkTypes.RoundStatePayload
	return {
		state = self._state,
		serverTimestamp = os.time(),
		phaseEndsAt = self._phaseEndsAt,
		stationId = self._selectedStationId,
		missionId = self._selectedMissionId,
		activeCrewCount = self:_countEligibleHubPlayers(),
		boardedCrewCount = self:_countBoardedPlayers(),
		roundNumber = self._roundNumber,
	}
end

function RoundService:_sendStateToPlayer(player: Player)
	local remotes = self._remotes
	if not remotes then
		return
	end
	remotes.RoundStateChanged:FireClient(player, self:_buildStatePayload())
end

function RoundService:_broadcastState()
	local remotes = self._remotes
	if not remotes then
		return
	end
	remotes.RoundStateChanged:FireAllClients(self:_buildStatePayload())
end

function RoundService:_broadcastObjectivePreview()
	local remotes = self._remotes
	if not remotes then
		return
	end
	local template = ObjectiveConfig.Templates[self._selectedMissionId]
	if not template then
		return
	end
	local payload: NetworkTypes.ObjectivePayload = {
		objectiveId = template.id,
		title = template.title,
		progress = 0,
		requiredProgress = template.requiredProgress,
		isComplete = false,
	}
	remotes.ObjectiveUpdated:FireAllClients(payload)
end

function RoundService:_broadcastPlayerStatuses()
	local remotes = self._remotes
	if not remotes then
		return
	end
	local list: { NetworkTypes.PlayerStatusSummary } = {}
	for userId, entry in pairs(self._roster) do
		if entry.player.Parent == Players then
			local health = GameConfig.DEFAULT_MAX_HEALTH
			local maxHealth = GameConfig.DEFAULT_MAX_HEALTH
			local character = entry.player.Character
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					health = math.floor(humanoid.Health)
					maxHealth = math.floor(humanoid.MaxHealth)
				end
			end
			table.insert(list, {
				userId = userId,
				displayName = entry.player.DisplayName,
				status = entry.status,
				health = health,
				maxHealth = maxHealth,
				isReady = entry.isReady,
			})
		end
	end
	remotes.PlayerStatusUpdated:FireAllClients(list)
end

function RoundService:SendNotificationToPlayer(
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

function RoundService:BroadcastNotification(
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
	remotes.Notification:FireAllClients(payload)
end

return RoundService
