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
	self._state = "INACTIVE"
	self._currentPosition = Vector3.new(47, 3.75, 0)
	self._lookDirection = Vector3.new(0, 0, -1)
	self._targetUserId = nil
	self._lastKnownTargetPosition = nil
	self._lastAttackClock = -999
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
	if not self:CanTransitionState(self._state, newState) then
		return false, "InvalidStateTransition"
	end

	self._state = newState
	if newState == "INACTIVE" or newState == "PATROL" or newState == "RETURN" then
		self._targetUserId = nil
	else
		if targetUserId ~= nil then
			self._targetUserId = targetUserId
		end
		if targetPosition ~= nil then
			self._lastKnownTargetPosition = targetPosition
		end
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

return MonsterService
