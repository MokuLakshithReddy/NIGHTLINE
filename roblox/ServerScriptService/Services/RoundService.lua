--!strict
--[[
	RoundService.lua
	Authoritative server-side Round State Machine for NIGHTLINE: LAST TRAIN (Section 3.2, 3.3, 3.4 & Milestone 1).
	Includes fixes for:
	- Remediation #1: All 6 active station spawns are strictly outside the physical Extraction Zone.
	- Remediation #2 (Issue 01): State-aware fresh-character respawn flow. Never heals or pivots a dead Humanoid inside Humanoid.Died.
	- Issue 02: Explicit 1..6 spawn-slot allocation on join and slot release on departure.
	- Remediation #3 (Issue 03): Periodic MovementService 3D (horizontal + vertical) sanity validation tick.
	- Remediation #4: Immediate round termination to RETURN (FAILED) when all active expedition players are eliminated, without waiting for the phase timer.
	- Issue 04: Physical extraction zone proximity, survival, and eligibility validation.
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
	spawnSlot: number,
	status: NetworkTypes.PlayerRoundStatus,
	isReady: boolean,
	diedDuringExpedition: boolean,
	votedStationId: NetworkTypes.StationId?,
	characterConnections: { RBXScriptConnection },
}

local RoundService: { [string]: any } = {
	Name = "RoundService",
	StateChanged = Signal.new(),

	_state = "WAITING" :: NetworkTypes.RoundState,
	_roundNumber = 0,
	_phaseEndsAt = 0,
	_lastOutcome = "PENDING" :: NetworkTypes.RoundOutcome,
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
	_movementService = nil :: any,
}

function RoundService:Init(dependencies: {
	remotes: { [string]: RemoteEvent },
	securityService: any,
	hubService: any,
	inventoryService: any,
	movementService: any?,
})
	self._remotes = dependencies.remotes
	self._securityService = dependencies.securityService
	self._hubService = dependencies.hubService
	self._inventoryService = dependencies.inventoryService
	self._movementService = dependencies.movementService

	self._state = "WAITING"
	self._roundNumber = 0
	self._phaseEndsAt = 0
	self._lastOutcome = "PENDING"
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

	for _, player in ipairs(Players:GetPlayers()) do
		self:RegisterPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		self:RegisterPlayer(player)
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

function RoundService:GetLastOutcome(): NetworkTypes.RoundOutcome
	return self._lastOutcome
end

function RoundService:GetPlayerStatus(player: Player): NetworkTypes.PlayerRoundStatus
	local entry = self._roster[player.UserId]
	if not entry then
		return "HUB_WAITING"
	end
	return entry.status
end

function RoundService:GetPlayerSpawnSlot(player: Player): number
	local entry = self._roster[player.UserId]
	if entry then
		return entry.spawnSlot
	end
	if self._hubService then
		return self._hubService:GetPlayerSpawnSlot(player.UserId)
	end
	return 1
end

function RoundService:_clearCharacterConnections(entry: PlayerRosterEntry)
	for _, conn in ipairs(entry.characterConnections) do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(entry.characterConnections)
end

-- Issue 01 & Issue 02: Explicit slot allocation and player-state-aware CharacterAdded spawning
function RoundService:RegisterPlayer(player: Player): number
	local existing = self._roster[player.UserId]
	if existing then
		return existing.spawnSlot
	end

	local isRoundActive = self:_isExpeditionPhase(self._state)
	local allocatedSlot = if self._hubService
		then self._hubService:AllocateSpawnSlot(player.UserId)
		else 1

	local entry: PlayerRosterEntry = {
		player = player,
		spawnSlot = allocatedSlot,
		status = "HUB_WAITING",
		isReady = false,
		diedDuringExpedition = false,
		votedStationId = GameConfig.DEFAULT_STATION_ID,
		characterConnections = {},
	}
	self._roster[player.UserId] = entry

	if self._inventoryService then
		self._inventoryService:EnsurePlayerInventory(player)
	end

	player.CharacterAdded:Connect(function(character: Model)
		self:HandleCharacterAdded(player, character)
	end)

	if player.Character then
		self:HandleCharacterAdded(player, player.Character)
	end

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
			string.format(
				"Welcome aboard NIGHTLINE (Berth #%d). Check your equipment and board before departure.",
				allocatedSlot
			),
			"Info"
		)
	end

	return allocatedSlot
end

-- Remediation #2: State-aware fresh-character respawn handler.
-- When a fresh character spawns via CharacterAdded, route it according to the player's authoritative status.
-- Never attempt to revive a dead Humanoid inside Humanoid.Died.
function RoundService:HandleCharacterAdded(player: Player, character: Model)
	local entry = self._roster[player.UserId]
	if not entry then
		return
	end

	self:_clearCharacterConnections(entry)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local diedConn = humanoid.Died:Connect(function()
			-- Remediation #2: Only update authoritative player status and round state on death.
			-- Do NOT restore Humanoid.Health or pivot the dead character inside Humanoid.Died.
			if entry.status == "IN_EXPEDITION" then
				self:EliminatePlayer(player, "CharacterDied", false)
			end
		end)
		table.insert(entry.characterConnections, diedConn)
	end

	if not self._hubService then
		return
	end

	-- Route the newly spawned (living) character strictly by authoritative player state and round state
	if entry.status == "IN_EXPEDITION" then
		if entry.diedDuringExpedition then
			entry.status = "ELIMINATED"
			self._hubService:SpawnEliminatedPlayerInHub(player, entry.spawnSlot)
			self:_broadcastPlayerStatuses()
		elseif self._state == "TRAVEL" then
			self._hubService:MoveCrewToBoardingBay({ player })
		elseif self._state == "EXPLORATION" or self._state == "EXTRACTION" then
			self._hubService:SpawnPlayerInActiveStation(player, entry.spawnSlot)
		else
			self._hubService:SpawnPlayerInHub(player, entry.spawnSlot)
		end
	elseif entry.status == "ELIMINATED" then
		-- Freshly respawned character of an eliminated player spawns in the Hub Recovery Bay
		self._hubService:SpawnEliminatedPlayerInHub(player, entry.spawnSlot)
		self:_broadcastPlayerStatuses()
	elseif entry.status == "EXTRACTED" then
		self._hubService:MoveCrewToBoardingBay({ player })
	else
		-- HUB_WAITING or BOARDED
		self._hubService:SpawnPlayerInHub(player, entry.spawnSlot)
	end
end

-- Remediation #2 & #4: Authoritative player elimination during active expedition.
-- Does not heal or revive a dead character; only relocates living characters (e.g. left behind)
-- while dead characters wait for a fresh CharacterAdded respawn into the Recovery Bay.
function RoundService:EliminatePlayer(
	player: Player,
	reason: string?,
	relocateIfAlive: boolean?
): (boolean, string)
	local entry = self._roster[player.UserId]
	if not entry then
		return false, "NotRegistered"
	end

	if entry.status ~= "IN_EXPEDITION" then
		return false, "PlayerNotInExpedition"
	end

	entry.status = "ELIMINATED"
	entry.diedDuringExpedition = true

	if self._movementService then
		self._movementService:ResetPlayerState(player)
	end

	-- Only relocate immediately if explicitly requested for a living character (e.g., left behind at station)
	local shouldRelocateLiving = if relocateIfAlive ~= nil then relocateIfAlive else false
	if shouldRelocateLiving and self._hubService then
		self._hubService:SpawnEliminatedPlayerInHub(player, entry.spawnSlot)
	end

	self:SendNotificationToPlayer(
		player,
		"PlayerEliminated",
		string.format(
			"You were eliminated (%s). Respawning in the Train Hub recovery bay.",
			reason or "Hazard"
		),
		"Danger"
	)

	self:_broadcastPlayerStatuses()

	-- Remediation #4: Immediately terminate the active expedition phase if all active crew are now eliminated
	if
		self:_countLivingOrExtractedExpeditionPlayers() == 0
		and (self._state == "TRAVEL" or self._state == "EXPLORATION" or self._state == "EXTRACTION")
	then
		self._lastOutcome = "FAILED"
		self:BroadcastNotification(
			"AllCrewEliminated",
			"All expedition crew members were eliminated. Terminating expedition and returning train to Hub.",
			"Danger"
		)
		self:_enterReturnPhase()
	end

	return true, "Eliminated"
end

-- Issue 04 & Remediation #1: Physical Extraction Zone validation and extraction registration
function RoundService:TryExtractPlayer(player: Player): (boolean, string)
	local security = self._securityService
	if not security:ValidatePlayerInstance(player) then
		return false, "InvalidPlayer"
	end

	if self._state ~= "EXTRACTION" then
		self:SendNotificationToPlayer(
			player,
			"ExtractionNotOpen",
			"Extraction is only active during the Extraction phase.",
			"Warning"
		)
		return false, "InvalidPhase"
	end

	local entry = self._roster[player.UserId]
	if not entry or not self._activeExpeditionUserIds[player.UserId] then
		return false, "NotInActiveExpedition"
	end

	if entry.status == "EXTRACTED" then
		return true, "AlreadyExtracted"
	end

	if entry.status ~= "IN_EXPEDITION" then
		return false, "IneligibleStatus"
	end

	local _, _, humanoid = security:GetValidatedCharacterRoot(player)
	if not humanoid or humanoid.Health <= 0 then
		return false, "PlayerNotAlive"
	end

	if not self._hubService or not self._hubService:IsPlayerInExtractionZone(player) then
		self:SendNotificationToPlayer(
			player,
			"NotInExtractionZone",
			"Reach the green Extraction Platform beside the train to extract!",
			"Warning"
		)
		return false, "OutOfExtractionZone"
	end

	entry.status = "EXTRACTED"
	self._hubService:MoveCrewToBoardingBay({ player })
	self:_broadcastPlayerStatuses()

	self:SendNotificationToPlayer(
		player,
		"PlayerExtracted",
		"Extraction confirmed! You are safely aboard the train.",
		"Success"
	)

	return true, "Extracted"
end

function RoundService:UnregisterPlayer(player: Player)
	local userId = player.UserId
	local entry = self._roster[userId]
	if entry then
		self:_clearCharacterConnections(entry)
	end
	self._roster[userId] = nil

	-- Issue 02: Release spawn slot on player departure
	if self._hubService then
		self._hubService:ReleaseSpawnSlot(userId)
	end

	local wasInExpedition = self._activeExpeditionUserIds[userId] == true
	if wasInExpedition then
		self._activeExpeditionUserIds[userId] = nil
	end

	self:_broadcastPlayerStatuses()

	-- Section 3.3 & Remediation #4: If all active expedition players leave or none remain alive/extracted, terminate safely
	if self:_isExpeditionPhase(self._state) then
		if self:_countActiveExpeditionPlayers() == 0 then
			warn(
				"[RoundService] All active expedition players left; terminating round safely and cleaning up."
			)
			self:CleanupRound()
			self:_transitionTo("WAITING", 0)
		elseif
			(self._state == "TRAVEL" or self._state == "EXPLORATION" or self._state == "EXTRACTION")
			and self:_countLivingOrExtractedExpeditionPlayers() == 0
		then
			self._lastOutcome = "FAILED"
			self:_enterReturnPhase()
		end
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

	local validStationId = (stationId :: any) :: NetworkTypes.StationId
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

function RoundService:_countLivingOrExtractedExpeditionPlayers(): number
	local count = 0
	for userId in pairs(self._activeExpeditionUserIds) do
		local entry = self._roster[userId]
		if entry and entry.player.Parent == Players then
			if entry.status == "IN_EXPEDITION" or entry.status == "EXTRACTED" then
				count += 1
			end
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
			if
				self:_waitPhaseOrAbort(
					GameConfig.RoundDurations.INTERMISSION,
					false,
					"INTERMISSION"
				)
			then
				self:_enterBoardingPhase()
			end
		elseif self._state == "BOARDING" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.BOARDING, false, "BOARDING") then
				self:_lockCrewAndDepart()
			end
		elseif self._state == "TRAVEL" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.TRAVEL, true, "TRAVEL") then
				self:_enterExplorationPhase()
			end
		elseif self._state == "EXPLORATION" then
			if
				self:_waitPhaseOrAbort(GameConfig.RoundDurations.EXPLORATION, true, "EXPLORATION")
			then
				self:_enterExtractionPhase()
			end
		elseif self._state == "EXTRACTION" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.EXTRACTION, true, "EXTRACTION") then
				self:_enterReturnPhase()
			end
		elseif self._state == "RETURN" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.RETURN, true, "RETURN") then
				self:_enterResultsPhase()
			end
		elseif self._state == "RESULTS" then
			if self:_waitPhaseOrAbort(GameConfig.RoundDurations.RESULTS, false, "RESULTS") then
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

function RoundService:_waitPhaseOrAbort(
	durationSeconds: number,
	requireActiveCrew: boolean,
	expectedState: NetworkTypes.RoundState?
): boolean
	local startingState: NetworkTypes.RoundState = expectedState or self._state
	local deadline = os.clock() + durationSeconds
	local stepInterval = GameConfig.MOVEMENT_CHECK_INTERVAL

	while os.clock() < deadline do
		-- Remediation #4: If state transitioned externally (e.g., all-crew-eliminated triggered _enterReturnPhase), abort wait immediately
		if self._state ~= startingState then
			return false
		end

		if requireActiveCrew and self:_countActiveExpeditionPlayers() == 0 then
			self:CleanupRound()
			self:_transitionTo("WAITING", 0)
			return false
		end

		-- Remediation #4: If all active expedition players are eliminated during TRAVEL, EXPLORATION, or EXTRACTION, terminate immediately
		if
			(self._state == "TRAVEL" or self._state == "EXPLORATION" or self._state == "EXTRACTION")
			and self:_countLivingOrExtractedExpeditionPlayers() == 0
		then
			self._lastOutcome = "FAILED"
			self:_enterReturnPhase()
			return false
		end

		if
			not requireActiveCrew
			and self:_countEligibleHubPlayers() < GameConfig.MIN_CREW_TO_START
		then
			self:CleanupRound()
			self:_transitionTo("WAITING", 0)
			return false
		end

		-- Issue 03 & Remediation #3: Server-side 3D movement sanity check tick
		if self._movementService then
			for _, entry in pairs(self._roster) do
				if entry.player.Parent == Players then
					self._movementService:ValidatePlayerMovement(entry.player, stepInterval)
				end
			end
		end

		-- Issue 04: Auto-check physical extraction zone during EXTRACTION phase
		if self._state == "EXTRACTION" and self._hubService then
			for userId in pairs(self._activeExpeditionUserIds) do
				local entry = self._roster[userId]
				if entry and entry.player.Parent == Players and entry.status == "IN_EXPEDITION" then
					if self._hubService:IsPlayerInExtractionZone(entry.player) then
						self:TryExtractPlayer(entry.player)
					end
				end
			end
		end

		task.wait(stepInterval)
	end

	return self._state == startingState
end

function RoundService:_startNewIntermission()
	self._roundNumber += 1
	self._lastOutcome = "PENDING"
	local templateList = ObjectiveConfig.OrderedTemplateIds
	local missionIndex = ((self._roundNumber - 1) % #templateList) + 1
	self._selectedMissionId = templateList[missionIndex]

	for _, entry in pairs(self._roster) do
		entry.status = "HUB_WAITING"
		entry.isReady = false
		entry.diedDuringExpedition = false
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
	for _, entry in pairs(self._roster) do
		if entry.player.Parent == Players then
			entry.isReady = true
			entry.status = "BOARDED"
			entry.diedDuringExpedition = false
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
			entry.diedDuringExpedition = false
			self._activeExpeditionUserIds[userId] = true
			table.insert(departingPlayers, entry.player)
		else
			entry.status = "HUB_WAITING"
		end
	end

	if #departingPlayers == 0 then
		for userId, entry in pairs(self._roster) do
			if entry.player.Parent == Players then
				entry.isReady = true
				entry.status = "IN_EXPEDITION"
				entry.diedDuringExpedition = false
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
	-- Remediation #1: Move active expedition crew onto Station 001 concourse entry spawns (Z = 18..30, outside extraction zone)
	if self._hubService then
		for userId in pairs(self._activeExpeditionUserIds) do
			local entry = self._roster[userId]
			if entry and entry.player.Parent == Players and entry.status == "IN_EXPEDITION" then
				self._hubService:SpawnPlayerInActiveStation(entry.player, entry.spawnSlot)
			end
		end
	end

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
		"Departure horn sounded! Reach the green Extraction Platform within 60 seconds!",
		"Danger"
	)
end

-- Issue 04 & Remediation #2: Physical Extraction Platform proximity, survival, and eligibility check on departure
function RoundService:_enterReturnPhase()
	if self._state == "RETURN" then
		return
	end

	local extractedCount = 0

	for userId in pairs(self._activeExpeditionUserIds) do
		local entry = self._roster[userId]
		if entry and entry.player.Parent == Players then
			if entry.status == "EXTRACTED" then
				extractedCount += 1
			elseif entry.status == "IN_EXPEDITION" then
				-- Perform final physical extraction zone and living state check
				local isInZone = if self._hubService
					then self._hubService:IsPlayerInExtractionZone(entry.player)
					else false

				if isInZone and not entry.diedDuringExpedition then
					entry.status = "EXTRACTED"
					extractedCount += 1
					if self._hubService then
						self._hubService:MoveCrewToBoardingBay({ entry.player })
					end
				else
					-- Player failed to reach the physical extraction platform before departure
					entry.status = "ELIMINATED"
					entry.diedDuringExpedition = true
					if self._movementService then
						self._movementService:ResetPlayerState(entry.player)
					end
					if self._hubService then
						-- Only pivots if character is currently alive; never heals a dead humanoid
						self._hubService:SpawnEliminatedPlayerInHub(entry.player, entry.spawnSlot)
					end
					self:SendNotificationToPlayer(
						entry.player,
						"FailedExtraction",
						"Train departed without you! You failed to reach the extraction platform in time.",
						"Danger"
					)
				end
			end
		end
	end

	self._lastOutcome = if extractedCount > 0 then "SUCCESS" else "FAILED"

	self:_transitionTo("RETURN", GameConfig.RoundDurations.RETURN)
	self:_broadcastPlayerStatuses()

	if self._lastOutcome == "SUCCESS" then
		self:BroadcastNotification(
			"ReturningToHub",
			string.format(
				"Train departing Station 001 with %d extracted crew. Returning to Train Hub.",
				extractedCount
			),
			"Success"
		)
	else
		self:BroadcastNotification(
			"ExpeditionFailed",
			"Expedition failed: no crew members extracted before departure. Returning train to Hub.",
			"Danger"
		)
	end
end

function RoundService:_enterResultsPhase()
	self:_transitionTo("RESULTS", GameConfig.RoundDurations.RESULTS)
	self:_broadcastPlayerStatuses()
	self:BroadcastNotification(
		"ExpeditionResults",
		string.format(
			"Expedition complete (Outcome: %s). Reviewing crew status and resetting Train Hub.",
			self._lastOutcome
		),
		if self._lastOutcome == "SUCCESS" then "Info" else "Warning"
	)
end

function RoundService:CleanupRound()
	self._roundJanitor:Cleanup()

	if self._hubService then
		self._hubService:ClearRuntimeStation()
	end

	local allPlayers: { Player } = {}
	for _, entry in pairs(self._roster) do
		entry.status = "HUB_WAITING"
		entry.isReady = false
		entry.diedDuringExpedition = false
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
			"[RoundService] Round #%d State -> %s (duration=%ds, crew=%d, outcome=%s)",
			self._roundNumber,
			newState,
			durationSeconds,
			self:_countActiveExpeditionPlayers(),
			self._lastOutcome
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
		lastOutcome = self._lastOutcome,
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
