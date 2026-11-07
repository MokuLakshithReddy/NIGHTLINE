--!strict
--[[
	MovementService.lua
	Server-authoritative sprint control and movement sanity validation (Issue 03).
	Responsibilities:
	- Owns per-player sprint state and sets Humanoid.WalkSpeed on the server.
	- Validates sprint eligibility (player must be alive and not rate-limited).
	- Runs periodic movement sanity checks (ValidateMovementTick) to detect client speed/teleport exploits
	  while respecting server-authored teleports (NotifyServerTeleport).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

type PlayerMovementRecord = {
	isSprinting: boolean,
	lastValidPosition: Vector3?,
	lastSampleTime: number,
	teleportGraceUntil: number,
	violationCount: number,
}

local MovementService: { [string]: any } = {
	Name = "MovementService",
	_records = {} :: { [number]: PlayerMovementRecord },
	_remotes = nil :: { [string]: RemoteEvent }?,
	_securityService = nil :: any,
	_roundService = nil :: any,
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
		lastSampleTime = os.clock(),
		teleportGraceUntil = 0,
		violationCount = 0,
	}
	self._records[userId] = record
	return record
end

function MovementService:NotifyServerTeleport(player: Player, targetPosition: Vector3)
	local record = self:EnsureRecord(player.UserId)
	local now = os.clock()
	record.lastValidPosition = targetPosition
	record.lastSampleTime = now
	record.teleportGraceUntil = now + 1.0
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
	if now < record.teleportGraceUntil or not record.lastValidPosition then
		record.lastValidPosition = currentPos
		record.lastSampleTime = now
		return true, "TeleportGrace"
	end

	local elapsed = math.max(dtSeconds, now - record.lastSampleTime, 0.05)
	local prevPos = record.lastValidPosition
	local horizontalDelta =
		Vector3.new(currentPos.X - prevPos.X, 0, currentPos.Z - prevPos.Z).Magnitude
	local maxAllowedSpeed = GameConfig.SPRINT_SPEED + GameConfig.MOVEMENT_SPEED_TOLERANCE
	local maxAllowedDistance = maxAllowedSpeed * elapsed

	if horizontalDelta > maxAllowedDistance then
		record.violationCount += 1
		warn(
			string.format(
				"[MovementService] Movement speed anomaly for %s: moved %.1f studs in %.2fs (max %.1f). Restoring server position.",
				player.Name,
				horizontalDelta,
				elapsed,
				maxAllowedDistance
			)
		)
		character:PivotTo(CFrame.new(prevPos))
		record.lastSampleTime = now
		return false, "RubberbandedSpeedAnomaly"
	end

	record.lastValidPosition = currentPos
	record.lastSampleTime = now
	return true, "ValidMovement"
end

return MovementService
