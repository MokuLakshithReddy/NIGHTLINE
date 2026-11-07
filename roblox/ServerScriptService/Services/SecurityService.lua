--!strict
--[[
	SecurityService.lua
	Centralized server-side validation, rate limiting, cooldowns, and character distance checks (Section 11.1 & Section 13).
	Every client-to-server remote and prompt interaction must pass through SecurityService plus domain validation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

type RateBucket = {
	windowStart: number,
	count: number,
}

local SecurityService = {
	Name = "SecurityService",
	_rateBuckets = {} :: { [number]: { [string]: RateBucket } },
	_actionCooldowns = {} :: { [number]: { [string]: number } },
}

function SecurityService:Init()
	table.clear(self._rateBuckets)
	table.clear(self._actionCooldowns)
end

function SecurityService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		self:ClearPlayerState(player.UserId)
	end)
end

function SecurityService:ClearPlayerState(userId: number)
	self._rateBuckets[userId] = nil
	self._actionCooldowns[userId] = nil
end

function SecurityService:ValidatePlayerInstance(player: any): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if player.Parent ~= Players then
		return false
	end
	return true
end

function SecurityService:CheckRateLimit(userId: number, actionKey: string, maxCallsPerWindow: number?, windowSeconds: number?): boolean
	local now = os.clock()
	local maxCalls = maxCallsPerWindow or GameConfig.REMOTE_MAX_CALLS_PER_WINDOW
	local window = windowSeconds or GameConfig.REMOTE_RATE_LIMIT_WINDOW

	local playerBuckets = self._rateBuckets[userId]
	if not playerBuckets then
		playerBuckets = {}
		self._rateBuckets[userId] = playerBuckets
	end

	local bucket = playerBuckets[actionKey]
	if not bucket or (now - bucket.windowStart) >= window then
		playerBuckets[actionKey] = {
			windowStart = now,
			count = 1,
		}
		return true
	end

	if bucket.count >= maxCalls then
		warn(string.format("[SecurityService] Rate limit exceeded for userId=%d action=%s", userId, actionKey))
		return false
	end

	bucket.count += 1
	return true
end

function SecurityService:CheckAndSetCooldown(userId: number, actionKey: string, cooldownSeconds: number): boolean
	local now = os.clock()
	local playerCooldowns = self._actionCooldowns[userId]
	if not playerCooldowns then
		playerCooldowns = {}
		self._actionCooldowns[userId] = playerCooldowns
	end

	local expiresAt = playerCooldowns[actionKey]
	if expiresAt and now < expiresAt then
		return false
	end

	playerCooldowns[actionKey] = now + cooldownSeconds
	return true
end

function SecurityService:ValidateString(value: any, maxLength: number, allowlist: { [string]: boolean }?): boolean
	if type(value) ~= "string" then
		return false
	end
	if #value == 0 or #value > maxLength then
		return false
	end
	if allowlist and not allowlist[value] then
		return false
	end
	return true
end

function SecurityService:ValidateIntegerInRange(value: any, minValue: number, maxValue: number): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if math.floor(value) ~= value then
		return false
	end
	return value >= minValue and value <= maxValue
end

function SecurityService:GetValidatedCharacterRoot(player: Player): (Model?, BasePart?, Humanoid?)
	if not self:ValidatePlayerInstance(player) then
		return nil, nil, nil
	end
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not rootPart:IsA("BasePart") or not humanoid then
		return nil, nil, nil
	end
	if humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, rootPart, humanoid
end

function SecurityService:ValidateDistance(player: Player, targetPosition: Vector3, maxDistance: number?): boolean
	local _, rootPart = self:GetValidatedCharacterRoot(player)
	if not rootPart then
		return false
	end
	local limit = maxDistance or GameConfig.MAX_INTERACTION_DISTANCE
	local distance = (rootPart.Position - targetPosition).Magnitude
	return distance <= limit
end

return SecurityService
