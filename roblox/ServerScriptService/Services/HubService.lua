--!strict
--[[
	HubService.lua
	Constructs and maintains the navigable Train Hub inside Workspace.World.Hub (Milestone 1).
	Responsibilities:
	- Explicit 1..6 Spawn-Slot Allocation and release on player departure (Issue 02).
	- State-aware player spawning for living/fresh characters: Hub Spawns, Boarding Bay,
	  Active Station Concourse Entry Spawns (strictly outside Extraction Zone), and Eliminated Recovery Bay.
	- Never heals or pivots a dead Humanoid; dead characters must respawn as fresh character models (Remediation #2).
	- Physical Extraction Platform Zone construction and 3D proximity/bounds validation (Remediation #1 & Issue 04).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local HubService: { [string]: any } = {
	Name = "HubService",
	_worldFolder = nil :: Folder?,
	_hubFolder = nil :: Folder?,
	_trainModel = nil :: Model?,
	_spawnsFolder = nil :: Folder?,
	_runtimeFolder = nil :: Folder?,
	_activeStationFolder = nil :: Folder?,
	_spawnParts = {} :: { BasePart },
	_boardingSpawnParts = {} :: { BasePart },
	_stationEntrySpawnParts = {} :: { BasePart },
	_eliminatedSpawnParts = {} :: { BasePart },
	_extractionZonePart = nil :: BasePart?,
	_allocatedSlots = {} :: { [number]: number }, -- slotIndex (1..6) -> userId
	_playerSlots = {} :: { [number]: number }, -- userId -> slotIndex (1..6)
	_movementService = nil :: any,
}

local function createPart(props: {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	canCollide: boolean?,
	parent: Instance,
}): Part
	local part = Instance.new("Part")
	part.Name = props.name
	part.Size = props.size
	part.CFrame = props.cframe
	part.Color = props.color
	part.Material = props.material or Enum.Material.Metal
	part.Transparency = props.transparency or 0
	part.CanCollide = if props.canCollide ~= nil then props.canCollide else true
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = props.parent
	return part
end

function HubService:Init()
	table.clear(self._allocatedSlots)
	table.clear(self._playerSlots)
	self:_ensureWorkspaceHierarchy()
	self:_buildTrainHubGeometry()
end

function HubService:SetMovementService(movementService: any)
	self._movementService = movementService
end

function HubService:Start()
	-- Hub geometry is ready before players join
end

-- Issue 02: Explicit Spawn-Slot Allocation System
function HubService:AllocateSpawnSlot(userId: number): number
	local existingSlot = self._playerSlots[userId]
	if existingSlot then
		return existingSlot
	end

	for slotIndex = 1, GameConfig.MAX_PLAYERS_PER_SERVER do
		if self._allocatedSlots[slotIndex] == nil then
			self._allocatedSlots[slotIndex] = userId
			self._playerSlots[userId] = slotIndex
			return slotIndex
		end
	end

	-- Fallback if server exceeds nominal capacity
	local fallbackSlot = ((userId - 1) % GameConfig.MAX_PLAYERS_PER_SERVER) + 1
	self._playerSlots[userId] = fallbackSlot
	return fallbackSlot
end

function HubService:ReleaseSpawnSlot(userId: number)
	local slotIndex = self._playerSlots[userId]
	if slotIndex and self._allocatedSlots[slotIndex] == userId then
		self._allocatedSlots[slotIndex] = nil
	end
	self._playerSlots[userId] = nil
end

function HubService:GetPlayerSpawnSlot(userId: number): number
	return self._playerSlots[userId] or self:AllocateSpawnSlot(userId)
end

function HubService:GetAllocatedSlotMap(): { [number]: number }
	return table.clone(self._allocatedSlots)
end

function HubService:_ensureWorkspaceHierarchy()
	local world = Workspace:FindFirstChild("World")
	if not world or not world:IsA("Folder") then
		world = Instance.new("Folder")
		world.Name = "World"
		world.Parent = Workspace
	end
	self._worldFolder = world

	local hub = world:FindFirstChild("Hub")
	if not hub or not hub:IsA("Folder") then
		hub = Instance.new("Folder")
		hub.Name = "Hub"
		hub.Parent = world
	end
	self._hubFolder = hub

	local train = hub:FindFirstChild("Train")
	if not train or not train:IsA("Model") then
		train = Instance.new("Model")
		train.Name = "Train"
		train.Parent = hub
	end
	self._trainModel = train

	local spawns = hub:FindFirstChild("Spawns")
	if not spawns or not spawns:IsA("Folder") then
		spawns = Instance.new("Folder")
		spawns.Name = "Spawns"
		spawns.Parent = hub
	end
	self._spawnsFolder = spawns

	local runtime = world:FindFirstChild("Runtime")
	if not runtime or not runtime:IsA("Folder") then
		runtime = Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = world
	end
	self._runtimeFolder = runtime

	local activeStation = runtime:FindFirstChild("ActiveStation")
	if not activeStation or not activeStation:IsA("Folder") then
		activeStation = Instance.new("Folder")
		activeStation.Name = "ActiveStation"
		activeStation.Parent = runtime
	end
	self._activeStationFolder = activeStation
end

function HubService:_buildTrainHubGeometry()
	local train = self._trainModel
	local spawns = self._spawnsFolder
	assert(train and spawns, "HubService hierarchy not initialized")

	train:ClearAllChildren()
	spawns:ClearAllChildren()
	table.clear(self._spawnParts)
	table.clear(self._boardingSpawnParts)
	table.clear(self._stationEntrySpawnParts)
	table.clear(self._eliminatedSpawnParts)
	self._extractionZonePart = nil

	-- Train Hub Floor (84 studs long along Z, 22 studs wide along X)
	local floor = createPart({
		name = "TrainFloor",
		size = Vector3.new(22, 1.5, 84),
		cframe = CFrame.new(0, 0, 0),
		color = Color3.fromRGB(30, 35, 44),
		material = Enum.Material.DiamondPlate,
		parent = train,
	})
	train.PrimaryPart = floor

	createPart({
		name = "TrainRoof",
		size = Vector3.new(22, 1, 84),
		cframe = CFrame.new(0, 13, 0),
		color = Color3.fromRGB(22, 26, 34),
		material = Enum.Material.Metal,
		parent = train,
	})

	createPart({
		name = "WallLeft",
		size = Vector3.new(1, 12, 84),
		cframe = CFrame.new(-10.5, 6.5, 0),
		color = Color3.fromRGB(42, 49, 60),
		material = Enum.Material.Metal,
		parent = train,
	})
	createPart({
		name = "WallRight",
		size = Vector3.new(1, 12, 84),
		cframe = CFrame.new(10.5, 6.5, 0),
		color = Color3.fromRGB(42, 49, 60),
		material = Enum.Material.Metal,
		parent = train,
	})

	createPart({
		name = "BulkheadFront",
		size = Vector3.new(22, 12, 1),
		cframe = CFrame.new(0, 6.5, -41.5),
		color = Color3.fromRGB(35, 40, 50),
		material = Enum.Material.Metal,
		parent = train,
	})
	createPart({
		name = "BulkheadRear",
		size = Vector3.new(22, 12, 1),
		cframe = CFrame.new(0, 6.5, 41.5),
		color = Color3.fromRGB(35, 40, 50),
		material = Enum.Material.Metal,
		parent = train,
	})

	for zOffset = -30, 30, 20 do
		local lightFixture = createPart({
			name = string.format("CeilingLamp_%d", zOffset),
			size = Vector3.new(4, 0.4, 2),
			cframe = CFrame.new(0, 12.2, zOffset),
			color = Color3.fromRGB(245, 185, 95),
			material = Enum.Material.Neon,
			canCollide = false,
			parent = train,
		})
		local pointLight = Instance.new("PointLight")
		pointLight.Color = Color3.fromRGB(255, 210, 145)
		pointLight.Brightness = 1.6
		pointLight.Range = 28
		pointLight.Parent = lightFixture
	end

	-- 1. Destination Console (Front Command Zone, Z = -34)
	local destinationConsole = createPart({
		name = "DestinationConsole",
		size = Vector3.new(6, 4.5, 2.5),
		cframe = CFrame.new(0, 3, -34),
		color = Color3.fromRGB(28, 64, 92),
		material = Enum.Material.Metal,
		parent = train,
	})
	CollectionService:AddTag(destinationConsole, GameConfig.Tags.DestinationTerminal)
	destinationConsole:SetAttribute("StationId", GameConfig.DEFAULT_STATION_ID)

	local destinationPrompt = Instance.new("ProximityPrompt")
	destinationPrompt.Name = "DestinationVotePrompt"
	destinationPrompt.ActionText = "Confirm Route: Station 001"
	destinationPrompt.ObjectText = "Dispatch Navigation Console"
	destinationPrompt.KeyboardKeyCode = Enum.KeyCode.E
	destinationPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	destinationPrompt.MaxActivationDistance = 10
	destinationPrompt.HoldDuration = 0
	destinationPrompt.RequiresLineOfSight = false
	destinationPrompt.Parent = destinationConsole

	-- 2. Equipment Lockers (Left Wall, Z = -12 and Z = -4)
	local lockerItems = {
		{ id = "Flashlight", label = "Equip Service Flashlight (Slot 1)", z = -12, slot = 1 },
		{ id = "Flare", label = "Equip Acoustic Flare (Slot 2)", z = -4, slot = 2 },
	}
	for _, lockerInfo in ipairs(lockerItems) do
		local lockerPart = createPart({
			name = "EquipmentLocker_" .. lockerInfo.id,
			size = Vector3.new(2, 6, 4),
			cframe = CFrame.new(-8.8, 3.8, lockerInfo.z),
			color = Color3.fromRGB(68, 82, 98),
			material = Enum.Material.Metal,
			parent = train,
		})
		CollectionService:AddTag(lockerPart, GameConfig.Tags.EquipmentLocker)
		lockerPart:SetAttribute("ItemId", lockerInfo.id)
		lockerPart:SetAttribute("SlotIndex", lockerInfo.slot)

		local lockerPrompt = Instance.new("ProximityPrompt")
		lockerPrompt.Name = "EquipPrompt_" .. lockerInfo.id
		lockerPrompt.ActionText = lockerInfo.label
		lockerPrompt.ObjectText = "Crew Equipment Locker"
		lockerPrompt.KeyboardKeyCode = Enum.KeyCode.E
		lockerPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		lockerPrompt.MaxActivationDistance = 10
		lockerPrompt.HoldDuration = 0
		lockerPrompt.RequiresLineOfSight = false
		lockerPrompt.Parent = lockerPart
	end

	-- 3. Boarding Ready Bay & Gate (Right Side Platform Doorway, Z = -8)
	local boardingGate = createPart({
		name = "BoardingReadyGate",
		size = Vector3.new(1.5, 8, 8),
		cframe = CFrame.new(9.2, 4.8, -8),
		color = Color3.fromRGB(196, 130, 42),
		material = Enum.Material.Metal,
		parent = train,
	})
	CollectionService:AddTag(boardingGate, GameConfig.Tags.BoardingZone)

	local boardingPrompt = Instance.new("ProximityPrompt")
	boardingPrompt.Name = "BoardingReadyPrompt"
	boardingPrompt.ActionText = "Toggle Boarding Ready"
	boardingPrompt.ObjectText = "Expedition Boarding Hatch"
	boardingPrompt.KeyboardKeyCode = Enum.KeyCode.E
	boardingPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	boardingPrompt.MaxActivationDistance = 12
	boardingPrompt.HoldDuration = 0
	boardingPrompt.RequiresLineOfSight = false
	boardingPrompt.Parent = boardingGate

	-- 4. Six Player Hub Spawns (Z = 12 to 32)
	local spawnOffsets = {
		Vector3.new(-5, 2.5, 12),
		Vector3.new(5, 2.5, 12),
		Vector3.new(-5, 2.5, 22),
		Vector3.new(5, 2.5, 22),
		Vector3.new(-5, 2.5, 32),
		Vector3.new(5, 2.5, 32),
	}

	for index, offset in ipairs(spawnOffsets) do
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = string.format("HubSpawn_%02d", index)
		spawnLocation.Size = Vector3.new(4, 0.5, 4)
		spawnLocation.CFrame = CFrame.new(offset) * CFrame.Angles(0, math.pi, 0)
		spawnLocation.Anchored = true
		spawnLocation.CanCollide = true
		spawnLocation.Neutral = true
		spawnLocation.Transparency = 0.25
		spawnLocation.Color = Color3.fromRGB(56, 189, 248)
		spawnLocation.Material = Enum.Material.SmoothPlastic
		spawnLocation.Parent = spawns
		CollectionService:AddTag(spawnLocation, GameConfig.Tags.HubSpawn)
		table.insert(self._spawnParts, spawnLocation)
	end

	-- 5. Six Forward Boarding Bay Positions (Z = -24 to -14)
	local boardingOffsets = {
		Vector3.new(-4, 2.5, -24),
		Vector3.new(4, 2.5, -24),
		Vector3.new(-4, 2.5, -19),
		Vector3.new(4, 2.5, -19),
		Vector3.new(-4, 2.5, -14),
		Vector3.new(4, 2.5, -14),
	}
	for index, offset in ipairs(boardingOffsets) do
		local marker = createPart({
			name = string.format("BoardingSpot_%02d", index),
			size = Vector3.new(3, 0.2, 3),
			cframe = CFrame.new(offset),
			color = Color3.fromRGB(245, 158, 11),
			material = Enum.Material.Neon,
			transparency = 0.6,
			canCollide = false,
			parent = train,
		})
		table.insert(self._boardingSpawnParts, marker)
	end

	-- 6. Six Station 001 Concourse Entry Spawns (Remediation #1: Z = 18..30, strictly outside Extraction Zone at Z = -8)
	for index, offset in ipairs(GameConfig.STATION_ENTRY_SPAWNS) do
		local entryPad = createPart({
			name = string.format("StationEntrySpawn_%02d", index),
			size = Vector3.new(3, 0.2, 3),
			cframe = CFrame.new(offset),
			color = Color3.fromRGB(56, 189, 248),
			material = Enum.Material.SmoothPlastic,
			transparency = 0.5,
			canCollide = false,
			parent = train,
		})
		CollectionService:AddTag(entryPad, GameConfig.Tags.StationEntrySpawn)
		table.insert(self._stationEntrySpawnParts, entryPad)
	end

	-- 7. Eliminated Recovery Berths in Rear Hub Bay (Issue 01 & Remediation #2: Fresh respawn for eliminated players)
	local eliminatedOffsets = {
		Vector3.new(-7, 2.5, 36),
		Vector3.new(-3, 2.5, 36),
		Vector3.new(0, 2.5, 36),
		Vector3.new(3, 2.5, 36),
		Vector3.new(7, 2.5, 36),
		Vector3.new(0, 2.5, 38),
	}
	for index, offset in ipairs(eliminatedOffsets) do
		local berth = createPart({
			name = string.format("EliminatedRecoveryBerth_%02d", index),
			size = Vector3.new(2.5, 0.2, 2.5),
			cframe = CFrame.new(offset),
			color = Color3.fromRGB(244, 63, 94),
			material = Enum.Material.SmoothPlastic,
			transparency = 0.5,
			canCollide = false,
			parent = train,
		})
		CollectionService:AddTag(berth, GameConfig.Tags.EliminatedSpawn)
		table.insert(self._eliminatedSpawnParts, berth)
	end

	-- 8. Physical Extraction Platform Zone adjacent to Boarding Gate (Issue 04 & Remediation #1)
	local extractionZone = createPart({
		name = "ExtractionPlatformZone",
		size = GameConfig.EXTRACTION_ZONE_SIZE,
		cframe = CFrame.new(GameConfig.EXTRACTION_ZONE_POSITION),
		color = Color3.fromRGB(16, 185, 129),
		material = Enum.Material.Neon,
		transparency = 0.65,
		canCollide = false,
		parent = train,
	})
	CollectionService:AddTag(extractionZone, GameConfig.Tags.ExtractionZone)

	local extractionPrompt = Instance.new("ProximityPrompt")
	extractionPrompt.Name = "ExtractionPlatformPrompt"
	extractionPrompt.ActionText = "Extract to Train"
	extractionPrompt.ObjectText = "Station 001 Extraction Platform"
	extractionPrompt.KeyboardKeyCode = Enum.KeyCode.E
	extractionPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	extractionPrompt.MaxActivationDistance = GameConfig.EXTRACTION_ZONE_RADIUS
	extractionPrompt.HoldDuration = 0
	extractionPrompt.RequiresLineOfSight = false
	extractionPrompt.Parent = extractionZone

	self._extractionZonePart = extractionZone
end

-- Remediation #2: Never restore Humanoid.Health or attempt to revive/pivot a dead character.
-- Only living characters (including fresh characters spawned via LoadCharacter / CharacterAdded) are pivoted.
function HubService:_pivotLivingCharacter(player: Player, targetCFrame: CFrame): boolean
	local character = player.Character
	if not character or not character.Parent then
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	if self._movementService then
		self._movementService:ResetPlayerState(player)
		self._movementService:NotifyServerTeleport(player, targetCFrame.Position)
	else
		humanoid.WalkSpeed = GameConfig.WALK_SPEED
	end

	character:PivotTo(targetCFrame)
	return true
end

function HubService:SpawnPlayerInHub(player: Player, slotIndex: number?): boolean
	local spawnCount = #self._spawnParts
	if spawnCount == 0 then
		return false
	end
	local resolvedSlot = slotIndex or self:GetPlayerSpawnSlot(player.UserId)
	local chosenIndex = ((resolvedSlot - 1) % spawnCount) + 1
	local spawnPad = self._spawnParts[chosenIndex]
	return self:_pivotLivingCharacter(player, spawnPad.CFrame + Vector3.new(0, 3, 0))
end

-- Remediation #2: Eliminated players respawn as a fresh character into the Hub Recovery Bay
function HubService:SpawnEliminatedPlayerInHub(player: Player, slotIndex: number?): boolean
	local count = #self._eliminatedSpawnParts
	if count == 0 then
		return self:SpawnPlayerInHub(player, slotIndex)
	end
	local resolvedSlot = slotIndex or self:GetPlayerSpawnSlot(player.UserId)
	local berth = self._eliminatedSpawnParts[((resolvedSlot - 1) % count) + 1]
	return self:_pivotLivingCharacter(player, berth.CFrame + Vector3.new(0, 3, 0))
end

-- Remediation #1: All 6 active station spawns are located at Z = 18..30, outside the Extraction Zone (Z = -8, r = 12)
function HubService:GetActiveStationSpawnPosition(slotIndex: number): Vector3
	local spawns = GameConfig.STATION_ENTRY_SPAWNS
	local chosenIndex = ((slotIndex - 1) % #spawns) + 1
	return spawns[chosenIndex]
end

function HubService:SpawnPlayerInActiveStation(player: Player, slotIndex: number?): boolean
	local resolvedSlot = slotIndex or self:GetPlayerSpawnSlot(player.UserId)
	local targetPos = self:GetActiveStationSpawnPosition(resolvedSlot)
	return self:_pivotLivingCharacter(player, CFrame.new(targetPos))
end

function HubService:MoveCrewToBoardingBay(players: { Player })
	local count = #self._boardingSpawnParts
	if count == 0 then
		return
	end
	for _, player in ipairs(players) do
		local slotIndex = self:GetPlayerSpawnSlot(player.UserId)
		local marker = self._boardingSpawnParts[((slotIndex - 1) % count) + 1]
		self:_pivotLivingCharacter(player, marker.CFrame + Vector3.new(0, 3, 0))
	end
end

function HubService:ReturnAllPlayersToHub(players: { Player })
	for _, player in ipairs(players) do
		local slotIndex = self:GetPlayerSpawnSlot(player.UserId)
		self:SpawnPlayerInHub(player, slotIndex)
	end
end

-- Issue 04 & Remediation #1: Physical Extraction Zone validation on the server
function HubService:GetExtractionZonePart(): BasePart?
	return self._extractionZonePart
end

function HubService:IsPositionInExtractionZone(position: Vector3): boolean
	local zoneCenter = if self._extractionZonePart
		then self._extractionZonePart.Position
		else GameConfig.EXTRACTION_ZONE_POSITION

	local horizontalDist =
		Vector3.new(position.X - zoneCenter.X, 0, position.Z - zoneCenter.Z).Magnitude
	local verticalDist = math.abs(position.Y - zoneCenter.Y)

	return horizontalDist <= GameConfig.EXTRACTION_ZONE_RADIUS
		and verticalDist <= GameConfig.EXTRACTION_VERTICAL_HALF_HEIGHT
end

function HubService:IsPlayerInExtractionZone(player: Player): boolean
	local character = player.Character
	if not character or not character.Parent then
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not rootPart:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false
	end

	return self:IsPositionInExtractionZone(rootPart.Position)
end

function HubService:ClearRuntimeStation()
	local activeStation = self._activeStationFolder
	if activeStation then
		activeStation:ClearAllChildren()
	end
end

return HubService
