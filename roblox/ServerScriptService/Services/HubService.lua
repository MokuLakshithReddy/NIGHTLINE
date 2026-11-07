--!strict
--[[
	HubService.lua
	Constructs and maintains the navigable Train Hub inside Workspace.World.Hub (Milestone 1).
	Creates:
	- Train Carriages (Command Car & Crew/Equipment Car) with windows, lighting, and signage.
	- 6 Hub Spawn Pads inside the Crew Car.
	- Tagged interactive terminals (Destination Vote Console, Equipment Locker, Boarding Gate) with ProximityPrompts.
	- Safe player spawning and return-to-hub positioning.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local HubService = {
	Name = "HubService",
	_worldFolder = nil :: Folder?,
	_hubFolder = nil :: Folder?,
	_trainModel = nil :: Model?,
	_spawnsFolder = nil :: Folder?,
	_runtimeFolder = nil :: Folder?,
	_activeStationFolder = nil :: Folder?,
	_spawnParts = {} :: { BasePart },
	_boardingSpawnParts = {} :: { BasePart },
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
	self:_ensureWorkspaceHierarchy()
	self:_buildTrainHubGeometry()
end

function HubService:Start()
	-- Hub geometry is ready before players join
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

	-- Clear any previous procedural hub parts to keep idempotency
	train:ClearAllChildren()
	spawns:ClearAllChildren()
	table.clear(self._spawnParts)
	table.clear(self._boardingSpawnParts)

	-- Train Hub Floor (80 studs long along Z, 22 studs wide along X)
	local floor = createPart({
		name = "TrainFloor",
		size = Vector3.new(22, 1.5, 84),
		cframe = CFrame.new(0, 0, 0),
		color = Color3.fromRGB(30, 35, 44),
		material = Enum.Material.DiamondPlate,
		parent = train,
	})
	train.PrimaryPart = floor

	-- Roof with warm industrial lighting strips
	createPart({
		name = "TrainRoof",
		size = Vector3.new(22, 1, 84),
		cframe = CFrame.new(0, 13, 0),
		color = Color3.fromRGB(22, 26, 34),
		material = Enum.Material.Metal,
		parent = train,
	})

	-- Left and Right Carriage Walls
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

	-- Front Bulkhead (Locomotive End at Z = -41.5) & Rear Bulkhead (Z = 41.5)
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

	-- Interior Warm Light Fixtures
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

	-- 1. Destination Console (Front Command Zone, Z = -32)
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

	-- 2. Equipment Lockers (Left Wall, Z = -10 and Z = -4)
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

	-- 4. Six Player Hub Spawns (Z = 10 to 32)
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
end

function HubService:SpawnPlayerInHub(player: Player, slotIndex: number?)
	local spawnCount = #self._spawnParts
	if spawnCount == 0 then
		return
	end
	local chosenIndex = ((slotIndex or 1) - 1) % spawnCount + 1
	local spawnPad = self._spawnParts[chosenIndex]

	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = GameConfig.WALK_SPEED
			humanoid.MaxHealth = GameConfig.DEFAULT_MAX_HEALTH
			humanoid.Health = GameConfig.DEFAULT_MAX_HEALTH
		end
		if rootPart and rootPart:IsA("BasePart") then
			character:PivotTo(spawnPad.CFrame + Vector3.new(0, 3, 0))
		end
	end
end

function HubService:MoveCrewToBoardingBay(players: { Player })
	local count = #self._boardingSpawnParts
	if count == 0 then
		return
	end
	for index, player in ipairs(players) do
		local character = player.Character
		if character then
			local marker = self._boardingSpawnParts[((index - 1) % count) + 1]
			character:PivotTo(marker.CFrame + Vector3.new(0, 3, 0))
		end
	end
end

function HubService:ReturnAllPlayersToHub(players: { Player })
	for index, player in ipairs(players) do
		self:SpawnPlayerInHub(player, index)
	end
end

function HubService:ClearRuntimeStation()
	local activeStation = self._activeStationFolder
	if activeStation then
		activeStation:ClearAllChildren()
	end
end

return HubService
