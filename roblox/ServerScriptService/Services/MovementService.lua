--!strict
--[[
	MovementService.lua
	Server-authoritative sprint control and 3D movement sanity validation (Issue 03 & Remediation #3).
	Responsibilities:
	- Owns per-player sprint state and sets Humanoid.WalkSpeed on the server.
	- Validates sprint eligibility (player must be alive, not eliminated, and not rate-limited).
	- Validates both horizontal AND vertical displacement while preserving legitimate jumps,
	  gravity falls, and server-authorized teleports (NotifyServerTeleport).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MonsterConfig = require(ReplicatedStorage.Shared.Config.MonsterConfig)
local NetworkTypes = require(ReplicatedStorage.Shared.Types.NetworkTypes)

type PlayerMovementRecord = {
	isSprinting: boolean,
	lastValidPosition: Vector3?,
	teleportTargetPosition: Vector3?,
	lastSampleTime: number,
	teleportGraceUntil: number,
	violationCount: number,
	lastNoiseAt: number,
	lastNoisePosition: Vector3?,
}

local MovementService: { [string]: any } = {
	Name = "MovementService",
	_records = {} :: { [number]: PlayerMovementRecord },
	_remotes = nil :: { [string]: RemoteEvent }?,
	_securityService = nil :: any,
	_roundService = nil :: any,
	_monsterService = nil :: any,
}

function MovementService:Init(dependencies: {
	remotes: { [string]: RemoteEvent },
	securityService: any,
})
	self._remotes = dependencies.remotes
	self._securityService = dependencies.securityService
	table.clear(self._records)
end

function MovementService:SetRoundService(roundService: any)
	self._roundService = roundService
end

function MovementService:SetMonsterService(monsterService: any)
	self._monsterService = monsterService
end

function MovementService:Start()
	local remotes = self._remotes
	assert(remotes, "MovementService requires remotes initialized")

	remotes.RequestSprint.OnServerEvent:Connect(function(player: Player, wantsSprint: any)
		self:HandleSprintRequest(player, wantsSprint)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self._records[player.UserId] = nil
	end)
end

function MovementService:EnsureRecord(userId: number): PlayerMovementRecord
	local existing = self._records[userId]
	if existing then
		return existing
	end
	local record: PlayerMovementRecord = {
		isSprinting = false,
		lastValidPosition = nil,
		teleportTargetPosition = nil,
		lastSampleTime = os.clock(),
		teleportGraceUntil = 0,
		violationCount = 0,
		lastNoiseAt = 0,
		lastNoisePosition = nil,
	}
	self._records[userId] = record
	return record
end

function MovementService:ResetPlayerState(player: Player)
	local record = self:EnsureRecord(player.UserId)
	record.isSprinting = false
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.WalkSpeed = GameConfig.WALK_SPEED
		end
	end
end

function MovementService:NotifyServerTeleport(player: Player, targetPosition: Vector3)
	local record = self:EnsureRecord(player.UserId)
	local now = os.clock()
	record.lastValidPosition = targetPosition
	record.teleportTargetPosition = targetPosition
	record.lastSampleTime = now
	record.teleportGraceUntil = now + GameConfig.TELEPORT_GRACE_SECONDS
	record.lastNoiseAt = now
	record.lastNoisePosition = targetPosition
end

function MovementService:IsPlayerSprinting(player: Player): boolean
	local record = self._records[player.UserId]
	return if record then record.isSprinting else false
end

function MovementService:HandleSprintRequest(player: Player, wantsSprint: any): (boolean, string)
	local security = self._securityService
	if not security:ValidatePlayerInstance(player) then
		return false, "InvalidPlayer"
	end

	if type(wantsSprint) ~= "boolean" then
		return false, "InvalidPayload"
	end

	if not security:CheckRateLimit(player.UserId, "RequestSprint", 12, 1.0) then
		return false, "RateLimited"
	end

	local _, _, humanoid = security:GetValidatedCharacterRoot(player)
	if not humanoid then
		return false, "CharacterNotAlive"
	end

	-- Eliminated players in the Hub recovery bay cannot sprint during an active round
	if self._roundService then
		local status = self._roundService:GetPlayerStatus(player)
		if status == "ELIMINATED" and wantsSprint then
			local record = self:EnsureRecord(player.UserId)
			record.isSprinting = false
			humanoid.WalkSpeed = GameConfig.WALK_SPEED
			return false, "EliminatedCannotSprint"
		end
	end

	local record = self:EnsureRecord(player.UserId)
	record.isSprinting = wantsSprint
	humanoid.WalkSpeed = if wantsSprint then GameConfig.SPRINT_SPEED else GameConfig.WALK_SPEED
	return true, if wantsSprint then "Sprinting" else "Walking"
end

function MovementService:_emitMovementNoise(
	player: Player,
	currentPosition: Vector3,
	record: PlayerMovementRecord,
	now: number
)
	local monsterService = self._monsterService
	local roundService = self._roundService
	if not monsterService or not roundService then
		return
	end
	if roundService:GetPlayerStatus(player) ~= "IN_EXPEDITION" then
		return
	end

	local lastNoisePosition = record.lastNoisePosition
	if not lastNoisePosition then
		record.lastNoisePosition = currentPosition
		return
	end

	local horizontalDistance = Vector3.new(
		currentPosition.X - lastNoisePosition.X,
		0,
		currentPosition.Z - lastNoisePosition.Z
	).Magnitude
	if horizontalDistance < MonsterConfig.MIN_MOVEMENT_FOR_NOISE_STUDS then
		return
	end

	local interval = if record.isSprinting
		then MonsterConfig.SPRINT_NOISE_INTERVAL_SECONDS
		else MonsterConfig.WALK_NOISE_INTERVAL_SECONDS
	if now - record.lastNoiseAt < interval then
		return
	end

	local category: NetworkTypes.NoiseCategory = if record.isSprinting then "Sprint" else "Walk"
	monsterService:EmitPlayerNoise(player, category)
	record.lastNoiseAt = now
	record.lastNoisePosition = currentPosition
end

function MovementService:ValidatePlayerMovement(
	player: Player,
	dtSeconds: number
): (boolean, string)
	local security = self._securityService
	local character, rootPart, humanoid = security:GetValidatedCharacterRoot(player)
	if not character or not rootPart or not humanoid then
		return true, "NoCharacter"
	end

	local record = self:EnsureRecord(player.UserId)
	local now = os.clock()

	-- Enforce authoritative WalkSpeed on the server humanoid in case of replication tamper
	local expectedWalkSpeed = if record.isSprinting
		then GameConfig.SPRINT_SPEED
		else GameConfig.WALK_SPEED
	if humanoid.WalkSpeed > expectedWalkSpeed then
		humanoid.WalkSpeed = expectedWalkSpeed
	end

	local currentPos = rootPart.Position
	if not record.lastValidPosition then
		record.lastValidPosition = currentPos
		record.lastNoisePosition = currentPos
		record.lastSampleTime = now
		return true, "InitialSample"
	end

	-- Remediation #3: Preserve server-authorized teleports while bounding movement near the teleport target
	if now < record.teleportGraceUntil and record.teleportTargetPosition then
		local tpTarget = record.teleportTargetPosition
		local tpHorizDelta =
			Vector3.new(currentPos.X - tpTarget.X, 0, currentPos.Z - tpTarget.Z).Magnitude
		local tpVertDelta = math.abs(currentPos.Y - tpTarget.Y)
		local maxGraceHoriz = (GameConfig.SPRINT_SPEED + GameConfig.MOVEMENT_SPEED_TOLERANCE)
				* GameConfig.TELEPORT_GRACE_SECONDS
			+ GameConfig.MOVEMENT_STEP_SLACK
		local maxGraceVert = GameConfig.MAX_JUMP_UPWARD_SPEED * 0.5
			+ GameConfig.VERTICAL_APEX_TOLERANCE

		if tpHorizDelta <= maxGraceHoriz and tpVertDelta <= maxGraceVert then
			record.lastValidPosition = currentPos
			record.lastSampleTime = now
			return true, "TeleportGrace"
		end
	end

	local elapsed = math.max(dtSeconds, now - record.lastSampleTime, 0.05)
	local prevPos = record.lastValidPosition

	-- 1. Horizontal displacement check (preserves walk/sprint + network jitter slack)
	local horizontalDelta =
		Vector3.new(currentPos.X - prevPos.X, 0, currentPos.Z - prevPos.Z).Magnitude
	local baseHorizSpeed = if record.isSprinting
		then GameConfig.SPRINT_SPEED
		else GameConfig.WALK_SPEED
	local maxAllowedHorizDistance = (baseHorizSpeed + GameConfig.MOVEMENT_SPEED_TOLERANCE) * elapsed
		+ GameConfig.MOVEMENT_STEP_SLACK

	if horizontalDelta > maxAllowedHorizDistance then
		record.violationCount += 1
		warn(
			string.format(
				"[MovementService] Horizontal speed anomaly for %s: moved %.1f studs in %.2fs (max %.1f). Restoring server position.",
				player.Name,
				horizontalDelta,
				elapsed,
				maxAllowedHorizDistance
			)
		)
		character:PivotTo(CFrame.new(prevPos))
		record.lastSampleTime = now
		return false, "RubberbandedSpeedAnomaly"
	end

	-- 2. Vertical displacement check (preserves legitimate jumps and gravity falls; blocks vertical fly/noclip teleports)
	local verticalDelta = currentPos.Y - prevPos.Y
	local maxAllowedUpwardDistance = GameConfig.MAX_JUMP_UPWARD_SPEED * elapsed
		+ GameConfig.VERTICAL_APEX_TOLERANCE
	local maxAllowedDownwardDistance = GameConfig.MAX_FALL_SPEED * elapsed
		+ GameConfig.VERTICAL_FALL_TOLERANCE

	if verticalDelta > maxAllowedUpwardDistance then
		record.violationCount += 1
		warn(
			string.format(
				"[MovementService] Vertical upward anomaly for %s: moved +%.1f studs Y in %.2fs (max +%.1f). Restoring server position.",
				player.Name,
				verticalDelta,
				elapsed,
				maxAllowedUpwardDistance
			)
		)
		character:PivotTo(CFrame.new(prevPos))
		record.lastSampleTime = now
		return false, "RubberbandedVerticalUpwardAnomaly"
	end

	if verticalDelta < -maxAllowedDownwardDistance then
		record.violationCount += 1
		warn(
			string.format(
				"[MovementService] Vertical downward anomaly for %s: moved %.1f studs Y in %.2fs (max -%.1f). Restoring server position.",
				player.Name,
				verticalDelta,
				elapsed,
				maxAllowedDownwardDistance
			)
		)
		character:PivotTo(CFrame.new(prevPos))
		record.lastSampleTime = now
		return false, "RubberbandedVerticalDownwardAnomaly"
	end

	if horizontalDelta >= MonsterConfig.MIN_MOVEMENT_FOR_NOISE_STUDS then
		self:_emitMovementNoise(player, currentPos, record, now)
	end
	record.lastValidPosition = currentPos
	record.lastSampleTime = now
	return true, "ValidMovement"
end

return MovementService
