--!strict
--[[
	MonsterService.lua
	Authoritative server-side preparation interfaces for The Hollow (Priority 4 & Section 5).
	NOTE: Per project instructions, the active autonomous monster NPC is NOT spawned until the
	mission-specific objective system is verified. This service provides the complete, testable
	server-side interfaces required for Milestone 3:
	1. Player Detection (range, FOV cone, wall line-of-sight via HubService, hiding spot immunity, threat scoring).
	2. Noise Events (emitting trusted server noise stimuli, expiration pruning, strongest stimulus selection).
	3. Monster State Management (INACTIVE, PATROL, INVESTIGATE, CHASE, SEARCH, RETURN + validated transitions).
	4. Station Navigation (Station 001 waypoint graph queries, nearest waypoint lookup, BFS route computation).
	5. Hiding Locations (entering/exiting Station 001 hiding lockers, single-occupant enforcement, cleanup).
	6. Player Elimination Hook (validating range, cooldown, line-of-sight, and non-hidden status before delegating to RoundService:EliminatePlayer).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MonsterConfig = require(ReplicatedStorage.Shared.Config.MonsterConfig)
local NetworkTypes = require(ReplicatedStorage.Shared.Types.NetworkTypes)

local MonsterService: { [string]: any } = {
	Name = "MonsterService",

	_state = "INACTIVE" :: NetworkTypes.HollowState,
	_currentPosition = Vector3.new(47, 3.75, 0),
	_lookDirection = Vector3.new(0, 0, -1),
	_targetUserId = nil :: number?,
	_lastKnownTargetPosition = nil :: Vector3?,
	_lastAttackClock = -999,
	_nextNoiseEventId = 1,
	_noiseEvents = {} :: { NetworkTypes.NoiseEvent },

	-- Hiding spot state: userId -> hidingSpotId and hidingSpotId -> userId
	_playerHidingSpot = {} :: { [number]: string },
	_hidingSpotOccupant = {} :: { [string]: number },
	_hidingSnapshots = {} :: { [number]: any },

	_securityService = nil :: any,
	_hubService = nil :: any,
	_roundService = nil :: any,
	_movementService = nil :: any,

	-- One server-owned encounter and one bounded AI coroutine per expedition.
	_encounterActive = false,
	_aiThread = nil :: thread?,
	_npcModel = nil :: Model?,
	_stateStartedAt = 0,
	_lastInvestigatedNoiseId = nil :: number?,
	_investigationPosition = nil :: Vector3?,
	_searchOrigin = nil :: Vector3?,
	_patrolWaypointId = nil :: string?,
	_patrolTargetWaypointId = nil :: string?,
	_patrolNeighborCursor = 0,
	_attackWindupUserId = nil :: number?,
	_attackWindupEndsAt = 0,
	_lastProgressPosition = nil :: Vector3?,
	_lastProgressAt = 0,
	_ignoreTargetUntil = 0,
}

function MonsterService:Init(dependencies: {
	securityService: any,
	hubService: any,
	roundService: any?,
	movementService: any?,
})
	self._securityService = dependencies.securityService
	self._hubService = dependencies.hubService
	self._roundService = dependencies.roundService
	self._movementService = dependencies.movementService
	self:ResetForRound()
end

function MonsterService:SetRoundService(roundService: any)
	self._roundService = roundService
end

function MonsterService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		self:ClearPlayerHidingState(player.UserId)
	end)
end

function MonsterService:ResetForRound()
	self:StopEncounter()
	self._state = "INACTIVE"
	self._currentPosition = Vector3.new(47, 3.75, 0)
	self._lookDirection = Vector3.new(0, 0, -1)
	self._targetUserId = nil
	self._lastKnownTargetPosition = nil
	self._lastAttackClock = -999
	self._stateStartedAt = os.clock()
	self._lastInvestigatedNoiseId = nil
	self._investigationPosition = nil
	self._searchOrigin = nil
	self._patrolWaypointId = nil
	self._patrolTargetWaypointId = nil
	self._patrolNeighborCursor = 0
	self._attackWindupUserId = nil
	self._attackWindupEndsAt = 0
	table.clear(self._noiseEvents)

	local hiddenUserIds = {}
	for userId in pairs(self._playerHidingSpot) do
		table.insert(hiddenUserIds, userId)
	end
	for _, userId in ipairs(hiddenUserIds) do
		self:ClearPlayerHidingState(userId)
	end
	for hidingSpotId in pairs(self._hidingSpotOccupant) do
		self:_updateHidingSpotPartAttributes(hidingSpotId, nil)
	end
	table.clear(self._playerHidingSpot)
	table.clear(self._hidingSpotOccupant)
	table.clear(self._hidingSnapshots)
end

-- ============================================================================
-- 1. Monster State Management Interface
-- ============================================================================
function MonsterService:GetState(): NetworkTypes.HollowState
	return self._state
end

function MonsterService:GetCurrentPosition(): Vector3
	return self._currentPosition
end

function MonsterService:SetTransform(position: Vector3, lookDirection: Vector3?)
	self._currentPosition = position
	if lookDirection and lookDirection.Magnitude > 0.001 then
		self._lookDirection = lookDirection * (1 / lookDirection.Magnitude)
	end
	local npcModel = self._npcModel
	if npcModel and npcModel.Parent then
		npcModel:PivotTo(CFrame.new(position))
	end
	local lastProgressPosition = self._lastProgressPosition
	if not lastProgressPosition
		or (position - lastProgressPosition).Magnitude >= MonsterConfig.MOVEMENT_PROGRESS_THRESHOLD_STUDS
	then
		self._lastProgressPosition = position
		self._lastProgressAt = os.clock()
	end
end

function MonsterService:GetTargetUserId(): number?
	return self._targetUserId
end

function MonsterService:GetLastKnownTargetPosition(): Vector3?
	return self._lastKnownTargetPosition
end

function MonsterService:CanTransitionState(
	fromState: NetworkTypes.HollowState,
	toState: NetworkTypes.HollowState
): boolean
	local allowedMap = MonsterConfig.ValidStateTransitions[fromState]
	if not allowedMap then
		return false
	end
	return allowedMap[toState] == true
end

function MonsterService:TransitionState(
	newState: NetworkTypes.HollowState,
	targetUserId: number?,
	targetPosition: Vector3?
): (boolean, string)
	if self._state == newState then
		if targetUserId ~= nil then
			self._targetUserId = targetUserId
		end
		if targetPosition ~= nil then
			self._lastKnownTargetPosition = targetPosition
		end
		return true, "StateRefreshed"
	end

	if not self:CanTransitionState(self._state, newState) then
		return false, "InvalidStateTransition"
	end

	self._state = newState
	self._stateStartedAt = os.clock()
	if newState == "INACTIVE" or newState == "PATROL" or newState == "RETURN" then
		self._targetUserId = nil
	else
		if targetUserId ~= nil then
			self._targetUserId = targetUserId
		elseif newState == "INVESTIGATE" or newState == "SEARCH" then
			self._targetUserId = nil
		end
		if targetPosition ~= nil then
			self._lastKnownTargetPosition = targetPosition
		end
	end

	local npcModel = self._npcModel
	if npcModel and npcModel.Parent then
		npcModel:SetAttribute("HollowState", newState)
	end
	return true, "StateTransitioned"
end

-- ============================================================================
-- 2. Noise Events Interface
-- ============================================================================
function MonsterService:EmitNoiseEvent(
	sourcePlayer: Player?,
	category: NetworkTypes.NoiseCategory,
	position: Vector3,
	customRadius: number?,
	customIntensity: number?
): NetworkTypes.NoiseEvent
	local now = os.clock()
	local radius = customRadius or MonsterConfig.NoiseRadii[category] or 20.0
	local intensity = customIntensity or MonsterConfig.NoiseIntensities[category] or 0.5

	local eventRecord: NetworkTypes.NoiseEvent = {
		id = self._nextNoiseEventId,
		sourceUserId = if sourcePlayer then sourcePlayer.UserId else nil,
		category = category,
		position = position,
		radius = radius,
		intensity = intensity,
		createdAt = now,
		expiresAt = now + MonsterConfig.NOISE_EVENT_LIFETIME_SECONDS,
	}
	self._nextNoiseEventId += 1
	table.insert(self._noiseEvents, eventRecord)
	self:PruneExpiredNoiseEvents(now)
	return eventRecord
end

function MonsterService:PruneExpiredNoiseEvents(atClock: number?)
	local now = atClock or os.clock()
	local active: { NetworkTypes.NoiseEvent } = {}
	for _, ev in ipairs(self._noiseEvents) do
		if ev.expiresAt > now then
			table.insert(active, ev)
		end
	end
	self._noiseEvents = active
end

function MonsterService:GetActiveNoiseEvents(atClock: number?): { NetworkTypes.NoiseEvent }
	self:PruneExpiredNoiseEvents(atClock)
	return table.clone(self._noiseEvents)
end

function MonsterService:SelectStrongestNoiseStimulus(
	observerPosition: Vector3,
	atClock: number?
): NetworkTypes.NoiseEvent?
	self:PruneExpiredNoiseEvents(atClock)
	local bestEvent: NetworkTypes.NoiseEvent? = nil
	local bestScore = 0

	for _, ev in ipairs(self._noiseEvents) do
		local dist = (ev.position - observerPosition).Magnitude
		if dist <= ev.radius then
			local attenuation = math.max(0.1, 1.0 - (dist / math.max(1.0, ev.radius)))
			local score = ev.intensity * attenuation
			if score > bestScore then
				bestScore = score
				bestEvent = ev
			end
		end
	end

	return bestEvent
end

-- ============================================================================
-- 3. Hiding Locations Interface
-- ============================================================================
function MonsterService:_getHidingSpotConfig(spotId: string): any
	for _, spec in ipairs(MonsterConfig.Station001HidingSpots) do
		if spec.id == spotId then
			return spec
		end
	end
	return nil
end

function MonsterService:IsPlayerHidden(player: Player): boolean
	local userId = player.UserId
	local spotId = self._playerHidingSpot[userId]
	local snapshot = self._hidingSnapshots[userId]
	if not spotId or not snapshot then
		return false
	end

	local rootPart = snapshot.rootPart
	local humanoid = snapshot.humanoid
	local physicallyInside = rootPart.Parent ~= nil
		and humanoid.Parent ~= nil
		and humanoid.Health > 0
		and rootPart.Anchored == true
		and (rootPart.Position - snapshot.insidePosition).Magnitude <= 1.25

	if not physicallyInside then
		self:ClearPlayerHidingState(userId)
		return false
	end
	return true
end

function MonsterService:GetPlayerHidingSpotId(player: Player): string?
	if not self:IsPlayerHidden(player) then
		return nil
	end
	return self._playerHidingSpot[player.UserId]
end

function MonsterService:ClearPlayerHidingState(userId: number)
	local spotId = self._playerHidingSpot[userId]
	local snapshot = self._hidingSnapshots[userId]
	local hidingPart: BasePart? = if spotId and self._hubService
		then self._hubService:GetHidingSpotPartById(spotId)
		else nil
	local door = if hidingPart then hidingPart:FindFirstChild("LockerDoor") else nil

	if door and door:IsA("BasePart") then
		door.CanCollide = false
	end

	if snapshot then
		local rootPart = snapshot.rootPart
		local humanoid = snapshot.humanoid
		if rootPart.Parent then
			if humanoid.Parent then
				if humanoid.Health > 0 then
					rootPart.CFrame = CFrame.new(snapshot.exitPosition)
					rootPart.AssemblyLinearVelocity = Vector3.zero
				end
				humanoid.WalkSpeed = snapshot.originalWalkSpeed
				humanoid.JumpPower = snapshot.originalJumpPower
				humanoid.JumpHeight = snapshot.originalJumpHeight
				humanoid.AutoRotate = snapshot.originalAutoRotate
			end
			rootPart.Anchored = snapshot.originalRootAnchored
			if self._movementService and humanoid.Health > 0 then
				self._movementService:NotifyServerTeleport(snapshot.player, snapshot.exitPosition)
			end
		end
	end

	if door and door:IsA("BasePart") then
		door.CanCollide = true
	end

	if spotId and self._hidingSpotOccupant[spotId] == userId then
		self._hidingSpotOccupant[spotId] = nil
	end
	if spotId then
		self:_updateHidingSpotPartAttributes(spotId, nil)
	end
	self._playerHidingSpot[userId] = nil
	self._hidingSnapshots[userId] = nil
end

function MonsterService:_updateHidingSpotPartAttributes(
	hidingSpotId: string,
	occupantUserId: number?
)
	if not self._hubService then
		return
	end
	local part: BasePart? = self._hubService:GetHidingSpotPartById(hidingSpotId)
	if not part then
		return
	end
	part:SetAttribute("OccupiedByUserId", occupantUserId or 0)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = if occupantUserId then "Exit Hiding Spot" else "Enter Hiding Spot"
	end
end

function MonsterService:HandleHidingSpotInteraction(
	player: Player,
	hidingSpotPart: BasePart
): (boolean, string)
	local security = self._securityService
	if not security or not security:ValidatePlayerInstance(player) then
		return false, "InvalidPlayer"
	end

	if typeof(hidingSpotPart) ~= "Instance" or not hidingSpotPart:IsA("BasePart") then
		return false, "InvalidHidingSpot"
	end

	if not CollectionService:HasTag(hidingSpotPart, GameConfig.Tags.HidingSpot) then
		return false, "NotAHidingSpot"
	end

	if self._roundService then
		local state: NetworkTypes.RoundState = self._roundService:GetState()
		if state ~= "EXPLORATION" and state ~= "EXTRACTION" then
			return false, "InvalidPhase"
		end
		if self._roundService:GetPlayerStatus(player) ~= "IN_EXPEDITION" then
			return false, "PlayerNotInExpedition"
		end
	end

	local _, rootPart, humanoid = security:GetValidatedCharacterRoot(player)
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return false, "PlayerNotAlive"
	end

	if
		not security:ValidateDistance(
			player,
			hidingSpotPart.Position,
			GameConfig.MAX_INTERACTION_DISTANCE
		)
	then
		return false, "OutOfRange"
	end

	local spotId = tostring(hidingSpotPart:GetAttribute("HidingSpotId") or hidingSpotPart.Name)
	local userId = player.UserId
	local currentSpot = self._playerHidingSpot[userId]

	if currentSpot == spotId then
		self:ClearPlayerHidingState(userId)
		return true, "ExitedHidingSpot"
	end

	local existingOccupant = self._hidingSpotOccupant[spotId]
	if existingOccupant and existingOccupant ~= userId then
		return false, "HidingSpotOccupied"
	end

	local spotConfig = self:_getHidingSpotConfig(spotId)
	if not spotConfig then
		return false, "InvalidHidingSpotConfig"
	end

	local insidePosition = hidingSpotPart.Position + spotConfig.insideOffset
	local exitPosition = hidingSpotPart.Position + spotConfig.exitOffset
	if self._hubService then
		if
			not self._hubService:IsPositionSupportedByFloor(insidePosition)
			or not self._hubService:IsPositionSupportedByFloor(exitPosition)
			or self._hubService:IsPositionBlockedByWall(exitPosition, 0.35)
		then
			return false, "UnsafeHidingSpotGeometry"
		end
	end

	if currentSpot then
		self:ClearPlayerHidingState(userId)
	end

	local door = hidingSpotPart:FindFirstChild("LockerDoor")
	if not door or not door:IsA("BasePart") then
		return false, "MissingLockerDoor"
	end

	local snapshot = {
		player = player,
		rootPart = rootPart,
		humanoid = humanoid,
		insidePosition = insidePosition,
		exitPosition = exitPosition,
		originalRootAnchored = rootPart.Anchored,
		originalWalkSpeed = humanoid.WalkSpeed,
		originalJumpPower = humanoid.JumpPower,
		originalJumpHeight = humanoid.JumpHeight,
		originalAutoRotate = humanoid.AutoRotate,
	}

	door.CanCollide = false
	rootPart.CFrame = CFrame.new(insidePosition)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.Anchored = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	door.CanCollide = true

	self._hidingSnapshots[userId] = snapshot
	self._playerHidingSpot[userId] = spotId
	self._hidingSpotOccupant[spotId] = userId
	if self._movementService then
		self._movementService:NotifyServerTeleport(player, insidePosition)
	end
	self:_updateHidingSpotPartAttributes(spotId, userId)
	return true, "EnteredHidingSpot"
end

-- ============================================================================
-- 4. Player Detection & Line-of-Sight Interface
-- ============================================================================
function MonsterService:HasLineOfSight(fromPosition: Vector3, toPosition: Vector3): boolean
	if not self._hubService then
		return true
	end
	local delta = toPosition - fromPosition
	local dist = delta.Magnitude
	if dist <= 1.0 then
		return true
	end

	local steps = math.max(2, math.ceil(dist / 1.5))
	for i = 1, steps - 1 do
		local alpha = i / steps
		local samplePos = Vector3.new(
			fromPosition.X + delta.X * alpha,
			fromPosition.Y + delta.Y * alpha,
			fromPosition.Z + delta.Z * alpha
		)
		if self._hubService:IsPositionBlockedByWall(samplePos, 0.25) then
			return false
		end
	end

	return true
end

function MonsterService:EvaluatePlayerDetection(
	observerPosition: Vector3,
	observerLookVector: Vector3,
	player: Player
): NetworkTypes.PlayerDetectionSnapshot
	local emptyResult: NetworkTypes.PlayerDetectionSnapshot = {
		detected = false,
		userId = player.UserId,
		position = nil,
		distance = math.huge,
		hasLineOfSight = false,
		isHidden = false,
		threatScore = 0,
	}

	local security = self._securityService
	if not security or not security:ValidatePlayerInstance(player) then
		return emptyResult
	end

	if self._roundService and self._roundService:GetPlayerStatus(player) ~= "IN_EXPEDITION" then
		return emptyResult
	end

	local _, rootPart, humanoid = security:GetValidatedCharacterRoot(player)
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return emptyResult
	end

	local playerPos = rootPart.Position
	local toPlayer = playerPos - observerPosition
	local distance = toPlayer.Magnitude
	local isHidden = self:IsPlayerHidden(player)

	if isHidden then
		return {
			detected = false,
			userId = player.UserId,
			position = playerPos,
			distance = distance,
			hasLineOfSight = false,
			isHidden = true,
			threatScore = 0,
		}
	end

	if distance > MonsterConfig.SIGHT_DETECTION_RANGE then
		return {
			detected = false,
			userId = player.UserId,
			position = playerPos,
			distance = distance,
			hasLineOfSight = false,
			isHidden = false,
			threatScore = 0,
		}
	end

	local hasLos = self:HasLineOfSight(observerPosition, playerPos)
	if not hasLos then
		return {
			detected = false,
			userId = player.UserId,
			position = playerPos,
			distance = distance,
			hasLineOfSight = false,
			isHidden = false,
			threatScore = 0,
		}
	end

	-- Check proximity alert or FOV cone
	local withinProximity = (distance <= MonsterConfig.PROXIMITY_AWARENESS_RANGE)
	local withinFov = false
	if distance > 0.001 and observerLookVector.Magnitude > 0.001 then
		local dirX = toPlayer.X / distance
		local dirZ = toPlayer.Z / distance
		local lookMag = math.sqrt(
			observerLookVector.X * observerLookVector.X
				+ observerLookVector.Z * observerLookVector.Z
		)
		if lookMag > 0.001 then
			local lookX = observerLookVector.X / lookMag
			local lookZ = observerLookVector.Z / lookMag
			local dot = dirX * lookX + dirZ * lookZ
			local halfFovRad = math.rad(MonsterConfig.FIELD_OF_VIEW_DEGREES * 0.5)
			withinFov = (dot >= math.cos(halfFovRad))
		else
			withinFov = true
		end
	else
		withinFov = true
	end

	local detected = withinProximity or withinFov
	local threatScore = if detected
		then math.max(0.05, 1.0 - (distance / MonsterConfig.SIGHT_DETECTION_RANGE))
		else 0

	return {
		detected = detected,
		userId = player.UserId,
		position = playerPos,
		distance = distance,
		hasLineOfSight = true,
		isHidden = false,
		threatScore = threatScore,
	}
end

function MonsterService:DetectBestPlayerTarget(
	observerPosition: Vector3,
	observerLookVector: Vector3
): NetworkTypes.PlayerDetectionSnapshot
	local bestSnapshot: NetworkTypes.PlayerDetectionSnapshot = {
		detected = false,
		userId = nil,
		position = nil,
		distance = math.huge,
		hasLineOfSight = false,
		isHidden = false,
		threatScore = 0,
	}

	for _, player in ipairs(Players:GetPlayers()) do
		local snap = self:EvaluatePlayerDetection(observerPosition, observerLookVector, player)
		if snap.detected and snap.threatScore > bestSnapshot.threatScore then
			bestSnapshot = snap
		end
	end

	return bestSnapshot
end

-- ============================================================================
-- 5. Station Navigation Interface (Waypoint Graph & BFS Routing)
-- ============================================================================
function MonsterService:GetStationNavigationGraph(): { [string]: NetworkTypes.StationWaypoint }
	if self._hubService then
		return self._hubService:GetStationWaypointGraph()
	end
	return {}
end

function MonsterService:FindNearestWaypoint(position: Vector3): NetworkTypes.StationWaypoint?
	local graph = self:GetStationNavigationGraph()
	local bestWp: NetworkTypes.StationWaypoint? = nil
	local bestDist = math.huge

	for _, wp in pairs(graph) do
		local d = (wp.position - position).Magnitude
		if d < bestDist then
			bestDist = d
			bestWp = wp
		end
	end

	return bestWp
end

function MonsterService:ComputeWaypointRoute(
	startWaypointId: string,
	goalWaypointId: string
): { NetworkTypes.StationWaypoint }
	local graph = self:GetStationNavigationGraph()
	local startNode = graph[startWaypointId]
	local goalNode = graph[goalWaypointId]
	if not startNode or not goalNode then
		return {}
	end

	if startWaypointId == goalWaypointId then
		return { startNode }
	end

	local queue: { string } = { startWaypointId }
	local visited: { [string]: boolean } = { [startWaypointId] = true }
	local parentMap: { [string]: string } = {}

	local head = 1
	while head <= #queue do
		local currentId = queue[head]
		head += 1

		if currentId == goalWaypointId then
			local reversed: { NetworkTypes.StationWaypoint } = {}
			local cursor: string? = goalWaypointId
			while cursor ~= nil do
				local node = graph[cursor]
				if node then
					table.insert(reversed, node)
				end
				cursor = parentMap[cursor]
			end

			local route: { NetworkTypes.StationWaypoint } = {}
			for i = #reversed, 1, -1 do
				table.insert(route, reversed[i])
			end
			return route
		end

		local currentNode = graph[currentId]
		if currentNode then
			for _, neighborId in ipairs(currentNode.neighbors) do
				if not visited[neighborId] and graph[neighborId] then
					visited[neighborId] = true
					parentMap[neighborId] = currentId
					table.insert(queue, neighborId)
				end
			end
		end
	end

	return {}
end

-- ============================================================================
-- 6. Player Elimination Interface (Validated Range, LOS, Cooldown, Non-Hidden)
-- ============================================================================
function MonsterService:CanEliminateTarget(
	attackerPosition: Vector3,
	targetPlayer: Player
): (boolean, string)
	local security = self._securityService
	if not security or not security:ValidatePlayerInstance(targetPlayer) then
		return false, "InvalidTargetPlayer"
	end

	if self._roundService then
		local state: NetworkTypes.RoundState = self._roundService:GetState()
		if state ~= "EXPLORATION" and state ~= "EXTRACTION" then
			return false, "InvalidRoundPhase"
		end
		if self._roundService:GetPlayerStatus(targetPlayer) ~= "IN_EXPEDITION" then
			return false, "TargetNotInExpedition"
		end
	end

	if self:IsPlayerHidden(targetPlayer) then
		return false, "TargetHidden"
	end

	local now = os.clock()
	if (now - self._lastAttackClock) < MonsterConfig.ATTACK_COOLDOWN_SECONDS then
		return false, "AttackCooldownActive"
	end

	local _, rootPart, humanoid = security:GetValidatedCharacterRoot(targetPlayer)
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return false, "TargetNotAlive"
	end

	local distance = (rootPart.Position - attackerPosition).Magnitude
	if distance > MonsterConfig.ATTACK_RANGE_STUDS then
		return false, "TargetOutOfAttackRange"
	end

	if not self:HasLineOfSight(attackerPosition, rootPart.Position) then
		return false, "BlockedByWall"
	end

	return true, "EligibleForElimination"
end

function MonsterService:ExecuteValidatedElimination(
	attackerPosition: Vector3,
	targetPlayer: Player,
	reason: string?
): (boolean, string)
	local canEliminate, checkReason = self:CanEliminateTarget(attackerPosition, targetPlayer)
	if not canEliminate then
		return false, checkReason
	end

	self._lastAttackClock = os.clock()
	self:ClearPlayerHidingState(targetPlayer.UserId)

	if not self._roundService then
		return false, "MissingRoundService"
	end

	return self._roundService:EliminatePlayer(targetPlayer, reason or "TheHollow", true)
end

-- ============================================================================
-- 7. Autonomous Hollow Encounter Runtime
-- ============================================================================
local function createHollowPart(
	model: Model,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.Parent = model
	return part
end

function MonsterService:_buildHollowRig(spawnPosition: Vector3): Model
	local stationModel = if self._hubService then self._hubService:GetActiveStationModel() else nil
	assert(stationModel and stationModel.Parent, "The Hollow requires an active Station 001 model")

	local model = Instance.new("Model")
	model.Name = MonsterConfig.NPC_MODEL_NAME
	model:SetAttribute("MonsterId", MonsterConfig.MONSTER_ID)
	model:SetAttribute("HollowState", "PATROL")
	model:SetAttribute("ServerAuthoritative", true)
	model.Parent = stationModel

	local shell = Color3.fromRGB(18, 21, 28)
	local edge = Color3.fromRGB(43, 50, 62)
	local eyes = Color3.fromRGB(255, 74, 54)
	local root = createHollowPart(
		model,
		"HumanoidRootPart",
		Vector3.new(1.4, 4.8, 1.2),
		spawnPosition,
		shell,
		Enum.Material.Metal,
		1
	)
	model.PrimaryPart = root

	createHollowPart(
		model,
		"Torso",
		Vector3.new(2.0, 2.35, 1.15),
		spawnPosition + Vector3.new(0, 0.85, 0),
		shell,
		Enum.Material.Metal
	)
	createHollowPart(
		model,
		"Head",
		Vector3.new(1.25, 1.35, 1.1),
		spawnPosition + Vector3.new(0, 2.55, 0),
		edge,
		Enum.Material.Metal
	)
	createHollowPart(
		model,
		"LeftArm",
		Vector3.new(0.48, 2.45, 0.55),
		spawnPosition + Vector3.new(-1.18, 0.72, 0),
		shell,
		Enum.Material.Metal
	)
	createHollowPart(
		model,
		"RightArm",
		Vector3.new(0.48, 2.45, 0.55),
		spawnPosition + Vector3.new(1.18, 0.72, 0),
		shell,
		Enum.Material.Metal
	)
	createHollowPart(
		model,
		"LeftLeg",
		Vector3.new(0.68, 2.15, 0.72),
		spawnPosition + Vector3.new(-0.52, -1.42, 0),
		shell,
		Enum.Material.Metal
	)
	createHollowPart(
		model,
		"RightLeg",
		Vector3.new(0.68, 2.15, 0.72),
		spawnPosition + Vector3.new(0.52, -1.42, 0),
		shell,
		Enum.Material.Metal
	)
	createHollowPart(
		model,
		"LeftEye",
		Vector3.new(0.16, 0.12, 0.08),
		spawnPosition + Vector3.new(-0.27, 2.66, -0.57),
		eyes,
		Enum.Material.Neon
	)
	createHollowPart(
		model,
		"RightEye",
		Vector3.new(0.16, 0.12, 0.08),
		spawnPosition + Vector3.new(0.27, 2.66, -0.57),
		eyes,
		Enum.Material.Neon
	)
	createHollowPart(
		model,
		"AttackTelegraph",
		Vector3.new(0.72, 0.72, 0.72),
		spawnPosition + Vector3.new(0, 1.0, -0.8),
		eyes,
		Enum.Material.Neon,
		1
	)

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.DisplayName = MonsterConfig.DISPLAY_NAME
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.WalkSpeed = MonsterConfig.CHASE_SPEED_STUDS_PER_SECOND
	humanoid.AutoRotate = false
	humanoid.Parent = model

	model:PivotTo(CFrame.new(spawnPosition))
	return model
end

function MonsterService:GetNpcModel(): Model?
	return self._npcModel
end

function MonsterService:IsEncounterActive(): boolean
	return self._encounterActive and self._npcModel ~= nil and self._npcModel.Parent ~= nil
end

function MonsterService:_setAttackTelegraph(isVisible: boolean)
	local model = self._npcModel
	local telegraph = if model then model:FindFirstChild("AttackTelegraph") else nil
	if telegraph and telegraph:IsA("BasePart") then
		telegraph.Transparency = if isVisible then 0.05 else 1
	end
end

function MonsterService:StartEncounter(): (boolean, string)
	if self._encounterActive then
		return true, "AlreadyActive"
	end

	local roundService = self._roundService
	if not roundService or roundService:GetState() ~= "EXPLORATION" then
		return false, "InvalidEncounterPhase"
	end

	local graph = self:GetStationNavigationGraph()
	local homeWaypoint = graph[MonsterConfig.HOME_WAYPOINT_ID]
	if not homeWaypoint then
		return false, "MissingHomeWaypoint"
	end

	self._currentPosition = homeWaypoint.position
	self._lookDirection = Vector3.new(0, 0, -1)
	self._npcModel = self:_buildHollowRig(homeWaypoint.position)
	self._encounterActive = true
	self._patrolWaypointId = homeWaypoint.id
	self._patrolTargetWaypointId = nil
	self._patrolNeighborCursor = 0
	self._lastInvestigatedNoiseId = nil
	self._attackWindupUserId = nil
	self._attackWindupEndsAt = 0
	self._lastProgressPosition = homeWaypoint.position
	self._lastProgressAt = os.clock()
	self._ignoreTargetUntil = 0

	local transitioned, reason = self:TransitionState("PATROL")
	if not transitioned then
		self:StopEncounter()
		return false, reason
	end

	self._aiThread = task.spawn(function()
		local previousTick = os.clock()
		while self._encounterActive do
			task.wait(MonsterConfig.AI_UPDATE_INTERVAL_SECONDS)
			local now = os.clock()
			local dtSeconds = math.clamp(now - previousTick, 0.05, 0.5)
			previousTick = now
			local ok, err = pcall(function()
				self:StepAutonomousAI(dtSeconds)
			end)
			if not ok then
				warn("[MonsterService] Hollow AI step failed:", err)
			end
		end
	end)

	return true, "EncounterStarted"
end

function MonsterService:StopEncounter()
	self._encounterActive = false
	local aiThread = self._aiThread
	self._aiThread = nil
	if aiThread then
		pcall(task.cancel, aiThread)
	end

	local npcModel = self._npcModel
	self._npcModel = nil
	if npcModel and npcModel.Parent then
		npcModel:Destroy()
	end

	self._attackWindupUserId = nil
	self._attackWindupEndsAt = 0
	self._investigationPosition = nil
	self._searchOrigin = nil
	self._patrolTargetWaypointId = nil
	self._targetUserId = nil
	self._lastKnownTargetPosition = nil
	self._lastProgressPosition = nil
	self._lastProgressAt = 0
	self._ignoreTargetUntil = 0
	self._state = "INACTIVE"
	self._stateStartedAt = os.clock()
end

function MonsterService:_findPlayerByUserId(userId: number): Player?
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

function MonsterService:_moveTowards(
	targetPosition: Vector3,
	speed: number,
	dtSeconds: number
): boolean
	local currentPosition = self._currentPosition
	local destination = Vector3.new(targetPosition.X, currentPosition.Y, targetPosition.Z)
	local directPathAllowed = true

	if self._hubService then
		directPathAllowed = self._hubService:IsPathWalkable(currentPosition, destination, 0.8)
	end

	if not directPathAllowed then
		local fromWaypoint = self:FindNearestWaypoint(currentPosition)
		local toWaypoint = self:FindNearestWaypoint(destination)
		if not fromWaypoint or not toWaypoint then
			return false
		end
		local route = self:ComputeWaypointRoute(fromWaypoint.id, toWaypoint.id)
		if #route < 2 then
			return false
		end
		destination = Vector3.new(route[2].position.X, currentPosition.Y, route[2].position.Z)
	end

	local delta = destination - currentPosition
	local distance = delta.Magnitude
	if distance <= MonsterConfig.WAYPOINT_REACHED_DISTANCE then
		return true
	end

	local direction = delta * (1 / math.max(distance, 0.001))
	local stepDistance = math.min(distance, speed * dtSeconds)
	local candidate = currentPosition + direction * stepDistance

	if self._hubService then
		if
			not self._hubService:IsPositionSupportedByFloor(candidate)
			or not self._hubService:IsPathWalkable(currentPosition, candidate, 0.5)
		then
			return false
		end
	end

	self:SetTransform(candidate, direction)
	return distance - stepDistance <= MonsterConfig.WAYPOINT_REACHED_DISTANCE
end

function MonsterService:_choosePatrolTarget(): NetworkTypes.StationWaypoint?
	local graph = self:GetStationNavigationGraph()
	local currentWaypoint = if self._patrolWaypointId then graph[self._patrolWaypointId] else nil
	if not currentWaypoint or #currentWaypoint.neighbors == 0 then
		currentWaypoint = self:FindNearestWaypoint(self._currentPosition)
	end
	if not currentWaypoint or #currentWaypoint.neighbors == 0 then
		return nil
	end

	self._patrolNeighborCursor = (self._patrolNeighborCursor % #currentWaypoint.neighbors) + 1
	local targetId = currentWaypoint.neighbors[self._patrolNeighborCursor]
	return graph[targetId]
end

function MonsterService:_stepChase(
	detection: NetworkTypes.PlayerDetectionSnapshot,
	dtSeconds: number
)
	local targetUserId = detection.userId
	local targetPlayer = if targetUserId then self:_findPlayerByUserId(targetUserId) else nil
	if not targetPlayer or not detection.position then
		self:_setAttackTelegraph(false)
		self._attackWindupUserId = nil
		self._attackWindupEndsAt = 0
		self:TransitionState("SEARCH", nil, self._lastKnownTargetPosition)
		self._searchOrigin = self._lastKnownTargetPosition or self._currentPosition
		return
	end

	self._lastKnownTargetPosition = detection.position
	local distance = (detection.position - self._currentPosition).Magnitude
	if
		distance <= MonsterConfig.ATTACK_RANGE_STUDS
		and self:HasLineOfSight(self._currentPosition, detection.position)
	then
		local now = os.clock()
		if self._attackWindupUserId ~= targetPlayer.UserId then
			self._attackWindupUserId = targetPlayer.UserId
			self._attackWindupEndsAt = now + MonsterConfig.ATTACK_TELEGRAPH_SECONDS
			self:_setAttackTelegraph(true)
			if self._roundService then
				self._roundService:SendNotificationToPlayer(
					targetPlayer,
					"HollowAttackTelegraph",
					"The Hollow is closing in! Break line of sight or hide now!",
					"Danger"
				)
			end
			return
		end

		if now >= self._attackWindupEndsAt then
			local eliminated =
				self:ExecuteValidatedElimination(self._currentPosition, targetPlayer, "TheHollow")
			self:_setAttackTelegraph(false)
			self._attackWindupUserId = nil
			self._attackWindupEndsAt = 0
			if eliminated then
				self:TransitionState("SEARCH", nil, detection.position)
				self._searchOrigin = detection.position
			end
		end
		return
	end

	self:_setAttackTelegraph(false)
	self._attackWindupUserId = nil
	self._attackWindupEndsAt = 0
	self:_moveTowards(detection.position, MonsterConfig.CHASE_SPEED_STUDS_PER_SECOND, dtSeconds)
end

function MonsterService:_recoverFromStuck(now: number)
	local lastProgressPosition = self._lastProgressPosition
	if not lastProgressPosition then
		self._lastProgressPosition = self._currentPosition
		self._lastProgressAt = now
		return
	end

	if (self._currentPosition - lastProgressPosition).Magnitude >= MonsterConfig.MOVEMENT_PROGRESS_THRESHOLD_STUDS then
		self._lastProgressPosition = self._currentPosition
		self._lastProgressAt = now
		return
	end

	if now - self._lastProgressAt < MonsterConfig.MOVEMENT_STUCK_TIMEOUT_SECONDS then
		return
	end

	-- Temporarily forget a blocked visual target and recover through a known waypoint/state.
	self._lastProgressPosition = self._currentPosition
	self._lastProgressAt = now
	self._ignoreTargetUntil = now + MonsterConfig.TARGET_REACQUIRE_COOLDOWN_SECONDS
	self:_setAttackTelegraph(false)
	self._attackWindupUserId = nil
	self._attackWindupEndsAt = 0

	if self._state == "CHASE" then
		self._searchOrigin = self._lastKnownTargetPosition or self._currentPosition
		self:TransitionState("SEARCH", nil, self._searchOrigin)
	elseif self._state == "INVESTIGATE" then
		self._searchOrigin = self._investigationPosition or self._currentPosition
		self:TransitionState("SEARCH", nil, self._searchOrigin)
	elseif self._state == "SEARCH" then
		self:TransitionState("RETURN")
	elseif self._state == "RETURN" then
		local nearest = self:FindNearestWaypoint(self._currentPosition)
		self._patrolWaypointId = if nearest then nearest.id else MonsterConfig.HOME_WAYPOINT_ID
		self._patrolTargetWaypointId = nil
		self:TransitionState("PATROL")
	else
		local nearest = self:FindNearestWaypoint(self._currentPosition)
		if nearest then
			self._patrolWaypointId = nearest.id
		end
		self._patrolTargetWaypointId = nil
	end
end

function MonsterService:StepAutonomousAI(dtSeconds: number): boolean
	if not self:IsEncounterActive() then
		return false
	end
	if self._roundService then
		local phase = self._roundService:GetState()
		if phase ~= "EXPLORATION" and phase ~= "EXTRACTION" then
			return false
		end
	end

	local safeDelta = math.clamp(dtSeconds, 0.05, 0.5)
	local now = os.clock()
	self:_recoverFromStuck(now)
	local detection = self:DetectBestPlayerTarget(self._currentPosition, self._lookDirection)
	if now < self._ignoreTargetUntil then
		detection.detected = false
		detection.userId = nil
	end
	if detection.detected and detection.userId and detection.position then
		self:TransitionState("CHASE", detection.userId, detection.position)
		self:_stepChase(detection, safeDelta)
		return true
	end

	if self._state == "CHASE" then
		self:_setAttackTelegraph(false)
		self._attackWindupUserId = nil
		self._attackWindupEndsAt = 0
		self:TransitionState("SEARCH", nil, self._lastKnownTargetPosition)
		self._searchOrigin = self._lastKnownTargetPosition or self._currentPosition
	end

	local strongestNoise = self:SelectStrongestNoiseStimulus(self._currentPosition)
	if strongestNoise and strongestNoise.id ~= self._lastInvestigatedNoiseId then
		self._lastInvestigatedNoiseId = strongestNoise.id
		self._investigationPosition = strongestNoise.position
		self:TransitionState("INVESTIGATE", nil, strongestNoise.position)
	end

	if self._state == "PATROL" then
		if not self._patrolTargetWaypointId then
			local nextWaypoint = self:_choosePatrolTarget()
			if nextWaypoint then
				self._patrolTargetWaypointId = nextWaypoint.id
			end
		end
		local targetWaypoint = if self._patrolTargetWaypointId
			then self:GetStationNavigationGraph()[self._patrolTargetWaypointId]
			else nil
		if
			targetWaypoint
			and self:_moveTowards(
				targetWaypoint.position,
				MonsterConfig.PATROL_SPEED_STUDS_PER_SECOND,
				safeDelta
			)
		then
			self._patrolWaypointId = targetWaypoint.id
			self._patrolTargetWaypointId = nil
		end
	elseif self._state == "INVESTIGATE" then
		local target = self._investigationPosition or self._lastKnownTargetPosition
		if target then
			local reached = self:_moveTowards(
				target,
				MonsterConfig.INVESTIGATE_SPEED_STUDS_PER_SECOND,
				safeDelta
			)
			if
				reached
				or os.clock() - self._stateStartedAt
					>= MonsterConfig.INVESTIGATE_TIMEOUT_SECONDS
			then
				self._searchOrigin = target
				self:TransitionState("SEARCH", nil, target)
			end
		end
	elseif self._state == "SEARCH" then
		local origin = self._searchOrigin or self._lastKnownTargetPosition or self._currentPosition
		local elapsed = os.clock() - self._stateStartedAt
		if elapsed >= MonsterConfig.SEARCH_TIMEOUT_SECONDS then
			self:TransitionState("RETURN")
		elseif elapsed >= MonsterConfig.SEARCH_SWEEP_INTERVAL_SECONDS then
			local sweepTime = elapsed * 0.8
			local offset = Vector3.new(
				math.cos(sweepTime) * MonsterConfig.SEARCH_SWEEP_RADIUS,
				0,
				math.sin(sweepTime) * MonsterConfig.SEARCH_SWEEP_RADIUS
			)
			self:_moveTowards(
				origin + offset,
				MonsterConfig.SEARCH_SPEED_STUDS_PER_SECOND,
				safeDelta
			)
			self:SetTransform(
				self._currentPosition,
				Vector3.new(math.cos(sweepTime), 0, math.sin(sweepTime))
			)
		end
	elseif self._state == "RETURN" then
		local home = self:GetStationNavigationGraph()[MonsterConfig.HOME_WAYPOINT_ID]
		if
			home
			and self:_moveTowards(
				home.position,
				MonsterConfig.RETURN_SPEED_STUDS_PER_SECOND,
				safeDelta
			)
		then
			self._patrolWaypointId = home.id
			self._patrolTargetWaypointId = nil
			self._investigationPosition = nil
			self:TransitionState("PATROL")
		end
	end

	return true
end
return MonsterService
