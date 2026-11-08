--!strict
--[[
	HubService.lua
	Constructs and maintains the navigable Train Hub inside Workspace.World.Hub
	and the physically playable Station 001 environment inside Workspace.World.Runtime.ActiveStation.
	Responsibilities:
	- Explicit 1..6 Spawn-Slot Allocation and release on player departure (Issue 02).
	- State-aware player spawning for living/fresh characters: Hub Spawns, Boarding Bay,
	  Station 001 Arrival Spawns (strictly outside Extraction Zone), and Eliminated Recovery Bay.
	- Never heals or pivots a dead Humanoid; dead characters must respawn as fresh character models (Remediation #2).
	- Physically playable Station 001 environment:
	  - Solid CanCollide=true StationPlatformFloor, TrainToStationBridge (0-stud gap), MainConcourseFloor,
	    MaintenanceRoomFloor, ControlRoomFloor, and CargoStorageFloor.
	  - Segmented Train right wall with openable bulkhead doors connecting the train interior to the station platform.
	  - Six solid CanCollide=true StationEntrySpawn pads supported by StationPlatformFloor, strictly outside the extraction zone.
	  - Accessible ExtractionPlatformDeck & ExtractionPlatformZone (16, 3, -8) with ProximityPrompt.
	  - Mission-specific objective objects (RestorePower: 3 Fuses + 3 Sockets; RecoverCargo: 2 Cargo Containers + Drop Point;
	    RepairSignal: 3 Communication Terminals).
	  - Hollow AI preparation infrastructure: Station 001 Navigation Waypoints and Hiding Locations.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MonsterConfig = require(ReplicatedStorage.Shared.Config.MonsterConfig)
local NetworkTypes = require(ReplicatedStorage.Shared.Types.NetworkTypes)
local ObjectiveConfig = require(ReplicatedStorage.Shared.Config.ObjectiveConfig)

local HubService: { [string]: any } = {
	Name = "HubService",
	_worldFolder = nil :: Folder?,
	_hubFolder = nil :: Folder?,
	_trainModel = nil :: Model?,
	_spawnsFolder = nil :: Folder?,
	_runtimeFolder = nil :: Folder?,
	_activeStationFolder = nil :: Folder?,
	_stationModel = nil :: Model?,
	_spawnParts = {} :: { BasePart },
	_boardingSpawnParts = {} :: { BasePart },
	_stationEntrySpawnParts = {} :: { BasePart },
	_eliminatedSpawnParts = {} :: { BasePart },
	_stationObjectiveParts = {} :: { BasePart },
	_stationObjectivePartsByName = {} :: { [string]: BasePart },
	_hidingSpotParts = {} :: { BasePart },
	_hidingSpotPartsById = {} :: { [string]: BasePart },
	_stationWaypointParts = {} :: { BasePart },
	_stationWaypointGraph = {} :: { [string]: NetworkTypes.StationWaypoint },
	_trainDoorParts = {} :: { BasePart },
	_collidableFloorParts = {} :: { BasePart },
	_collidableWallParts = {} :: { BasePart },
	_extractionZonePart = nil :: BasePart?,
	_stationDoorsOpen = false,
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
	self:BuildStation001Environment()
	self:SetStationDoorsOpen(false)
end

function HubService:SetMovementService(movementService: any)
	self._movementService = movementService
end

function HubService:Start()
	-- Hub & Station 001 physical geometry are ready before players join
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

function HubService:_registerFloorPart(part: BasePart)
	table.insert(self._collidableFloorParts, part)
end

function HubService:_registerWallPart(part: BasePart)
	table.insert(self._collidableWallParts, part)
end

function HubService:_buildTrainHubGeometry()
	local train = self._trainModel
	local spawns = self._spawnsFolder
	assert(train and spawns, "HubService hierarchy not initialized")

	train:ClearAllChildren()
	spawns:ClearAllChildren()
	table.clear(self._spawnParts)
	table.clear(self._boardingSpawnParts)
	table.clear(self._eliminatedSpawnParts)
	table.clear(self._trainDoorParts)
	table.clear(self._collidableFloorParts)
	table.clear(self._collidableWallParts)

	-- Train Hub Floor (84 studs long along Z: -42..+42, 22 studs wide along X: -11..+11)
	local floor = createPart({
		name = "TrainFloor",
		size = Vector3.new(22, 1.5, 84),
		cframe = CFrame.new(0, 0, 0),
		color = Color3.fromRGB(30, 35, 44),
		material = Enum.Material.DiamondPlate,
		canCollide = true,
		parent = train,
	})
	train.PrimaryPart = floor
	self:_registerFloorPart(floor)

	createPart({
		name = "TrainRoof",
		size = Vector3.new(22, 1, 84),
		cframe = CFrame.new(0, 13, 0),
		color = Color3.fromRGB(22, 26, 34),
		material = Enum.Material.Metal,
		canCollide = true,
		parent = train,
	})

	local wallLeft = createPart({
		name = "WallLeft",
		size = Vector3.new(1, 12, 84),
		cframe = CFrame.new(-10.5, 6.5, 0),
		color = Color3.fromRGB(42, 49, 60),
		material = Enum.Material.Metal,
		canCollide = true,
		parent = train,
	})
	self:_registerWallPart(wallLeft)

	-- Segmented Right Wall (X = 10.5) with two 8-stud-wide station doorways:
	-- Doorway 1 (Boarding & Extraction Hatch): Z = -12 .. -4 (centered at Z = -8)
	-- Doorway 2 (Station Arrival Hatch): Z = 20 .. 28 (centered at Z = 24)
	local wallRightFront = createPart({
		name = "WallRight_Front",
		size = Vector3.new(1, 12, 30),
		cframe = CFrame.new(10.5, 6.5, -27),
		color = Color3.fromRGB(42, 49, 60),
		material = Enum.Material.Metal,
		canCollide = true,
		parent = train,
	})
	self:_registerWallPart(wallRightFront)

	local wallRightCenter = createPart({
		name = "WallRight_Center",
		size = Vector3.new(1, 12, 24),
		cframe = CFrame.new(10.5, 6.5, 8),
		color = Color3.fromRGB(42, 49, 60),
		material = Enum.Material.Metal,
		canCollide = true,
		parent = train,
	})
	self:_registerWallPart(wallRightCenter)

	local wallRightRear = createPart({
		name = "WallRight_Rear",
		size = Vector3.new(1, 12, 14),
		cframe = CFrame.new(10.5, 6.5, 35),
		color = Color3.fromRGB(42, 49, 60),
		material = Enum.Material.Metal,
		canCollide = true,
		parent = train,
	})
	self:_registerWallPart(wallRightRear)

	-- Doorway lintels above the 9-stud-tall openings
	createPart({
		name = "WallRight_Lintel_Extraction",
		size = Vector3.new(1, 2.75, 8),
		cframe = CFrame.new(10.5, 11.125, -8),
		color = Color3.fromRGB(35, 40, 50),
		material = Enum.Material.Metal,
		canCollide = true,
		parent = train,
	})
	createPart({
		name = "WallRight_Lintel_Arrival",
		size = Vector3.new(1, 2.75, 8),
		cframe = CFrame.new(10.5, 11.125, 24),
		color = Color3.fromRGB(35, 40, 50),
		material = Enum.Material.Metal,
		canCollide = true,
		parent = train,
	})

	-- Sliding Bulkhead Doors (closed during Hub/Travel/Return; open during Station Exploration/Extraction)
	local extractionDoor = createPart({
		name = "Door_ExtractionHatch",
		size = Vector3.new(0.8, 9, 8),
		cframe = CFrame.new(10.5, 5.25, -8),
		color = Color3.fromRGB(196, 130, 42),
		material = Enum.Material.Metal,
		transparency = 0.15,
		canCollide = true,
		parent = train,
	})
	table.insert(self._trainDoorParts, extractionDoor)

	local arrivalDoor = createPart({
		name = "Door_ArrivalHatch",
		size = Vector3.new(0.8, 9, 8),
		cframe = CFrame.new(10.5, 5.25, 24),
		color = Color3.fromRGB(56, 189, 248),
		material = Enum.Material.Metal,
		transparency = 0.15,
		canCollide = true,
		parent = train,
	})
	table.insert(self._trainDoorParts, arrivalDoor)

	local bulkheadFront = createPart({
		name = "BulkheadFront",
		size = Vector3.new(22, 12, 1),
		cframe = CFrame.new(0, 6.5, -41.5),
		color = Color3.fromRGB(35, 40, 50),
		material = Enum.Material.Metal,
		canCollide = true,
		parent = train,
	})
	self:_registerWallPart(bulkheadFront)

	local bulkheadRear = createPart({
		name = "BulkheadRear",
		size = Vector3.new(22, 12, 1),
		cframe = CFrame.new(0, 6.5, 41.5),
		color = Color3.fromRGB(35, 40, 50),
		material = Enum.Material.Metal,
		canCollide = true,
		parent = train,
	})
	self:_registerWallPart(bulkheadRear)

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
		canCollide = true,
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
			canCollide = true,
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

	-- 3. Boarding Ready Stanchion Console beside the Z = -8 Doorway (at Z = -14 so doorway is clear)
	local boardingGate = createPart({
		name = "BoardingReadyGate",
		size = Vector3.new(1.2, 6, 2.5),
		cframe = CFrame.new(9.2, 3.8, -14),
		color = Color3.fromRGB(196, 130, 42),
		material = Enum.Material.Metal,
		canCollide = true,
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

	-- 4. Six Player Hub Spawns (Z = 12 to 32, resting on TrainFloor with CanCollide=true)
	local spawnOffsets = {
		Vector3.new(-5, 0.85, 12),
		Vector3.new(5, 0.85, 12),
		Vector3.new(-5, 0.85, 22),
		Vector3.new(5, 0.85, 22),
		Vector3.new(-5, 0.85, 32),
		Vector3.new(5, 0.85, 32),
	}

	for index, offset in ipairs(spawnOffsets) do
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = string.format("HubSpawn_%02d", index)
		spawnLocation.Size = Vector3.new(4, 0.2, 4)
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
		self:_registerFloorPart(spawnLocation)
	end

	-- 5. Six Forward Boarding Bay Pads (Z = -24 to -14, flush CanCollide=true pads on TrainFloor)
	local boardingOffsets = {
		Vector3.new(-4, 0.85, -24),
		Vector3.new(4, 0.85, -24),
		Vector3.new(-4, 0.85, -19),
		Vector3.new(4, 0.85, -19),
		Vector3.new(-4, 0.85, -14),
		Vector3.new(4, 0.85, -14),
	}
	for index, offset in ipairs(boardingOffsets) do
		local marker = createPart({
			name = string.format("BoardingSpot_%02d", index),
			size = Vector3.new(3, 0.2, 3),
			cframe = CFrame.new(offset),
			color = Color3.fromRGB(245, 158, 11),
			material = Enum.Material.Neon,
			transparency = 0.4,
			canCollide = true,
			parent = train,
		})
		table.insert(self._boardingSpawnParts, marker)
		self:_registerFloorPart(marker)
	end

	-- 6. Eliminated Recovery Berths in Rear Hub Bay (Issue 01 & Remediation #2: CanCollide=true pads on TrainFloor)
	local eliminatedOffsets = {
		Vector3.new(-7, 0.85, 36),
		Vector3.new(-3, 0.85, 36),
		Vector3.new(0, 0.85, 36),
		Vector3.new(3, 0.85, 36),
		Vector3.new(7, 0.85, 36),
		Vector3.new(0, 0.85, 38),
	}
	for index, offset in ipairs(eliminatedOffsets) do
		local berth = createPart({
			name = string.format("EliminatedRecoveryBerth_%02d", index),
			size = Vector3.new(2.5, 0.2, 2.5),
			cframe = CFrame.new(offset),
			color = Color3.fromRGB(244, 63, 94),
			material = Enum.Material.SmoothPlastic,
			transparency = 0.35,
			canCollide = true,
			parent = train,
		})
		CollectionService:AddTag(berth, GameConfig.Tags.EliminatedSpawn)
		table.insert(self._eliminatedSpawnParts, berth)
		self:_registerFloorPart(berth)
	end
end

--[[
	Builds the complete, physically playable Station 001 environment inside
	Workspace.World.Runtime.ActiveStation, including:
	- Solid CanCollide=true floors (TrainToStationBridge, StationPlatformFloor, MainConcourseFloor,
	  MaintenanceRoomFloor, ControlRoomFloor, CargoStorageFloor).
	- Six solid CanCollide=true StationEntrySpawn pads (Z = 18..30, outside Extraction Zone).
	- Accessible ExtractionPlatformDeck & ExtractionPlatformZone (16, 3, -8).
	- Full perimeter collision walls.
	- Mission-specific objective nodes for RestorePower, RecoverCargo, and RepairSignal.
	- Hollow AI preparation infrastructure: Station 001 Navigation Waypoints and Hiding Locations.
]]
function HubService:BuildStation001Environment(): Model
	local activeStation = self._activeStationFolder
	assert(activeStation, "ActiveStation folder not initialized")

	activeStation:ClearAllChildren()
	table.clear(self._stationEntrySpawnParts)
	table.clear(self._stationObjectiveParts)
	table.clear(self._stationObjectivePartsByName)
	table.clear(self._hidingSpotParts)
	table.clear(self._hidingSpotPartsById)
	table.clear(self._stationWaypointParts)
	table.clear(self._stationWaypointGraph)
	self._extractionZonePart = nil

	-- Rebuild floor/wall registries so we keep Train Hub floors/walls + active station floors/walls
	local keptFloors: { BasePart } = {}
	for _, p in ipairs(self._collidableFloorParts) do
		if p.Parent and p.Parent ~= activeStation then
			table.insert(keptFloors, p)
		end
	end
	self._collidableFloorParts = keptFloors

	local keptWalls: { BasePart } = {}
	for _, p in ipairs(self._collidableWallParts) do
		if p.Parent and p.Parent ~= activeStation then
			table.insert(keptWalls, p)
		end
	end
	self._collidableWallParts = keptWalls

	local stationModel = Instance.new("Model")
	stationModel.Name = "Station001_ForgottenTerminal"
	stationModel.Parent = activeStation
	self._stationModel = stationModel

	-- 1. Zero-Gap Train-to-Station Bridge Deck (X = 9..13, Z = -42..+42, Y = 0)
	local bridgeDeck = createPart({
		name = "TrainToStationBridge",
		size = Vector3.new(4, 1.5, 84),
		cframe = CFrame.new(11, 0, 0),
		color = Color3.fromRGB(51, 65, 85),
		material = Enum.Material.DiamondPlate,
		canCollide = true,
		parent = stationModel,
	})
	self:_registerFloorPart(bridgeDeck)

	-- 2. Station 001 Boarding & Extraction Platform Floor (X = 11..29, Z = -42..+42, Y = 0)
	local platformFloor = createPart({
		name = "StationPlatformFloor",
		size = Vector3.new(18, 1.5, 84),
		cframe = CFrame.new(20, 0, 0),
		color = Color3.fromRGB(45, 55, 72),
		material = Enum.Material.DiamondPlate,
		canCollide = true,
		parent = stationModel,
	})
	stationModel.PrimaryPart = platformFloor
	self:_registerFloorPart(platformFloor)

	-- 3. Station 001 Main Concourse Floor (X = 29..65, Z = -42..+42, Y = 0)
	local concourseFloor = createPart({
		name = "MainConcourseFloor",
		size = Vector3.new(36, 1.5, 84),
		cframe = CFrame.new(47, 0, 0),
		color = Color3.fromRGB(38, 46, 62),
		material = Enum.Material.SmoothPlastic,
		canCollide = true,
		parent = stationModel,
	})
	self:_registerFloorPart(concourseFloor)

	-- 4. Maintenance Room Floor — North Wing (X = 33..61, Z = -66..-42, Y = 0)
	local maintenanceFloor = createPart({
		name = "MaintenanceRoomFloor",
		size = Vector3.new(28, 1.5, 24),
		cframe = CFrame.new(47, 0, -54),
		color = Color3.fromRGB(44, 52, 64),
		material = Enum.Material.DiamondPlate,
		canCollide = true,
		parent = stationModel,
	})
	self:_registerFloorPart(maintenanceFloor)

	-- 5. Control Room Floor — East Wing (X = 65..89, Z = -18..+18, Y = 0)
	local controlRoomFloor = createPart({
		name = "ControlRoomFloor",
		size = Vector3.new(24, 1.5, 36),
		cframe = CFrame.new(77, 0, 0),
		color = Color3.fromRGB(32, 48, 68),
		material = Enum.Material.SmoothPlastic,
		canCollide = true,
		parent = stationModel,
	})
	self:_registerFloorPart(controlRoomFloor)

	-- 6. Cargo Storage Bay Floor — South Wing (X = 33..61, Z = 42..66, Y = 0)
	local cargoFloor = createPart({
		name = "CargoStorageFloor",
		size = Vector3.new(28, 1.5, 24),
		cframe = CFrame.new(47, 0, 54),
		color = Color3.fromRGB(52, 48, 44),
		material = Enum.Material.DiamondPlate,
		canCollide = true,
		parent = stationModel,
	})
	self:_registerFloorPart(cargoFloor)

	-- 7. Six Solid Station 001 Entry Spawn Pads (X = 15..21, Z = 18..30, Y = 0.85, CanCollide = true)
	for index, spawnPos in ipairs(GameConfig.STATION_ENTRY_SPAWNS) do
		local entryPad = createPart({
			name = string.format("StationEntrySpawn_%02d", index),
			size = Vector3.new(4, 0.2, 4),
			cframe = CFrame.new(spawnPos.X, 0.85, spawnPos.Z),
			color = Color3.fromRGB(56, 189, 248),
			material = Enum.Material.SmoothPlastic,
			transparency = 0.15,
			canCollide = true,
			parent = stationModel,
		})
		CollectionService:AddTag(entryPad, GameConfig.Tags.StationEntrySpawn)
		table.insert(self._stationEntrySpawnParts, entryPad)
		self:_registerFloorPart(entryPad)
	end

	-- 8. Accessible Physical Extraction Platform Deck & Trigger Zone (X = 16, Z = -8)
	local extractionDeck = createPart({
		name = "ExtractionPlatformDeck",
		size = Vector3.new(10, 0.2, 16),
		cframe = CFrame.new(
			GameConfig.EXTRACTION_ZONE_POSITION.X,
			0.85,
			GameConfig.EXTRACTION_ZONE_POSITION.Z
		),
		color = Color3.fromRGB(16, 185, 129),
		material = Enum.Material.DiamondPlate,
		transparency = 0.1,
		canCollide = true,
		parent = stationModel,
	})
	self:_registerFloorPart(extractionDeck)

	local extractionZone = createPart({
		name = "ExtractionPlatformZone",
		size = GameConfig.EXTRACTION_ZONE_SIZE,
		cframe = CFrame.new(GameConfig.EXTRACTION_ZONE_POSITION),
		color = Color3.fromRGB(16, 185, 129),
		material = Enum.Material.Neon,
		transparency = 0.72,
		canCollide = false,
		parent = stationModel,
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

	-- 9. Station Perimeter Collision Walls & Room Dividers with 12-stud Doorways (CanCollide = true)
	local wallSpecs = {
		{
			name = "StationWall_NorthWest",
			size = Vector3.new(30, 12, 1),
			pos = Vector3.new(26, 6.5, -42.5),
		},
		{
			name = "StationWall_NorthEast",
			size = Vector3.new(12, 12, 1),
			pos = Vector3.new(59, 6.5, -42.5),
		},
		{
			name = "MaintenanceWall_North",
			size = Vector3.new(28, 12, 1),
			pos = Vector3.new(47, 6.5, -66.5),
		},
		{
			name = "MaintenanceWall_West",
			size = Vector3.new(1, 12, 24),
			pos = Vector3.new(32.5, 6.5, -54),
		},
		{
			name = "MaintenanceWall_East",
			size = Vector3.new(1, 12, 24),
			pos = Vector3.new(61.5, 6.5, -54),
		},
		{
			name = "StationWall_SouthWest",
			size = Vector3.new(30, 12, 1),
			pos = Vector3.new(26, 6.5, 42.5),
		},
		{
			name = "StationWall_SouthEast",
			size = Vector3.new(12, 12, 1),
			pos = Vector3.new(59, 6.5, 42.5),
		},
		{
			name = "CargoWall_South",
			size = Vector3.new(28, 12, 1),
			pos = Vector3.new(47, 6.5, 66.5),
		},
		{
			name = "CargoWall_West",
			size = Vector3.new(1, 12, 24),
			pos = Vector3.new(32.5, 6.5, 54),
		},
		{
			name = "CargoWall_East",
			size = Vector3.new(1, 12, 24),
			pos = Vector3.new(61.5, 6.5, 54),
		},
		{
			name = "ConcourseWall_EastNorth",
			size = Vector3.new(1, 12, 36),
			pos = Vector3.new(65.5, 6.5, -24),
		},
		{
			name = "ConcourseWall_EastSouth",
			size = Vector3.new(1, 12, 36),
			pos = Vector3.new(65.5, 6.5, 24),
		},
		{
			name = "ControlWall_East",
			size = Vector3.new(1, 12, 36),
			pos = Vector3.new(89.5, 6.5, 0),
		},
		{
			name = "ControlWall_North",
			size = Vector3.new(24, 12, 1),
			pos = Vector3.new(77, 6.5, -18.5),
		},
		{
			name = "ControlWall_South",
			size = Vector3.new(24, 12, 1),
			pos = Vector3.new(77, 6.5, 18.5),
		},
	}

	for _, spec in ipairs(wallSpecs) do
		local wallPart = createPart({
			name = spec.name,
			size = spec.size,
			cframe = CFrame.new(spec.pos),
			color = Color3.fromRGB(36, 42, 54),
			material = Enum.Material.Metal,
			canCollide = true,
			parent = stationModel,
		})
		self:_registerWallPart(wallPart)
	end

	-- 10. Priority 1: Mission-Specific Station 001 Objective Nodes (RestorePower, RecoverCargo, RepairSignal)
	local roleToTag: { [NetworkTypes.ObjectiveInteractionRole]: string } = {
		FusePickup = GameConfig.Tags.FusePickup,
		FuseSocket = GameConfig.Tags.FuseSocket,
		CargoPickup = GameConfig.Tags.CargoPickup,
		CargoDropPoint = GameConfig.Tags.CargoDropPoint,
		SignalTerminal = GameConfig.Tags.SignalTerminal,
	}

	for _, nodeSpec in ipairs(ObjectiveConfig.Station001ObjectiveNodes) do
		local nodePart = createPart({
			name = nodeSpec.name,
			size = nodeSpec.size,
			cframe = CFrame.new(nodeSpec.position),
			color = nodeSpec.color,
			material = Enum.Material.Metal,
			canCollide = true,
			parent = stationModel,
		})
		CollectionService:AddTag(nodePart, GameConfig.Tags.StationObjective)
		local specificTag = roleToTag[nodeSpec.role]
		if specificTag then
			CollectionService:AddTag(nodePart, specificTag)
		end

		nodePart:SetAttribute("MissionId", nodeSpec.missionId)
		nodePart:SetAttribute("ObjectiveRole", nodeSpec.role)
		nodePart:SetAttribute("ObjectiveIndex", nodeSpec.index)
		nodePart:SetAttribute("ItemKey", nodeSpec.itemKey or nodeSpec.name)
		nodePart:SetAttribute("Collected", false)
		nodePart:SetAttribute("Installed", false)
		nodePart:SetAttribute("Activated", false)
		nodePart:SetAttribute("DeliveredCount", 0)
		nodePart:SetAttribute("Completed", false)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ObjectivePrompt_" .. nodeSpec.name
		prompt.ObjectText = nodeSpec.objectText
		prompt.ActionText = nodeSpec.actionText
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = 12
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = nodePart

		table.insert(self._stationObjectiveParts, nodePart)
		self._stationObjectivePartsByName[nodeSpec.name] = nodePart
	end

	-- 11. Priority 4: Station 001 Hiding Locations (for The Hollow AI preparation)
	for _, hideSpec in ipairs(MonsterConfig.Station001HidingSpots) do
		local hidePart = createPart({
			name = hideSpec.id,
			size = Vector3.new(3.2, 6.5, 3.2),
			cframe = CFrame.new(hideSpec.position),
			color = Color3.fromRGB(51, 65, 85),
			material = Enum.Material.Metal,
			canCollide = true,
			parent = stationModel,
		})
		CollectionService:AddTag(hidePart, GameConfig.Tags.HidingSpot)
		hidePart:SetAttribute("HidingSpotId", hideSpec.id)
		hidePart:SetAttribute("RoomId", hideSpec.roomId)
		hidePart:SetAttribute("OccupiedByUserId", 0)

		local hidePrompt = Instance.new("ProximityPrompt")
		hidePrompt.Name = "HidingSpotPrompt_" .. hideSpec.id
		hidePrompt.ObjectText = hideSpec.objectText
		hidePrompt.ActionText = "Enter Hiding Spot"
		hidePrompt.KeyboardKeyCode = Enum.KeyCode.E
		hidePrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		hidePrompt.MaxActivationDistance = 10
		hidePrompt.HoldDuration = 0
		hidePrompt.RequiresLineOfSight = false
		hidePrompt.Parent = hidePart

		table.insert(self._hidingSpotParts, hidePart)
		self._hidingSpotPartsById[hideSpec.id] = hidePart
	end

	-- 12. Priority 4: Station 001 Navigation Waypoints (for The Hollow AI pathfinding graph)
	for _, wpSpec in ipairs(MonsterConfig.Station001Waypoints) do
		local wpPart = createPart({
			name = wpSpec.id,
			size = Vector3.new(1.5, 0.2, 1.5),
			cframe = CFrame.new(wpSpec.position.X, 0.85, wpSpec.position.Z),
			color = Color3.fromRGB(100, 116, 139),
			material = Enum.Material.SmoothPlastic,
			transparency = 0.85,
			canCollide = false,
			parent = stationModel,
		})
		CollectionService:AddTag(wpPart, GameConfig.Tags.HollowWaypoint)
		wpPart:SetAttribute("WaypointId", wpSpec.id)
		wpPart:SetAttribute("RoomId", wpSpec.roomId)
		table.insert(self._stationWaypointParts, wpPart)

		self._stationWaypointGraph[wpSpec.id] = {
			id = wpSpec.id,
			roomId = wpSpec.roomId,
			position = wpSpec.position,
			neighbors = table.clone(wpSpec.neighbors),
		}
	end

	return stationModel
end

function HubService:SetStationDoorsOpen(isOpen: boolean)
	self._stationDoorsOpen = isOpen
	for _, doorPart in ipairs(self._trainDoorParts) do
		doorPart.CanCollide = not isOpen
		doorPart.Transparency = if isOpen then 0.85 else 0.15
	end
end

function HubService:AreStationDoorsOpen(): boolean
	return self._stationDoorsOpen
end

function HubService:GetStationObjectiveParts(): { BasePart }
	return table.clone(self._stationObjectiveParts)
end

function HubService:GetStationObjectivePartByName(name: string): BasePart?
	return self._stationObjectivePartsByName[name]
end

function HubService:GetHidingSpotParts(): { BasePart }
	return table.clone(self._hidingSpotParts)
end

function HubService:GetHidingSpotPartById(hidingSpotId: string): BasePart?
	return self._hidingSpotPartsById[hidingSpotId]
end

function HubService:GetStationWaypointGraph(): { [string]: NetworkTypes.StationWaypoint }
	return table.clone(self._stationWaypointGraph)
end

--[[
	Verifies that a 3D world position is physically supported underneath by at least one
	anchored, CanCollide=true floor or spawn pad part with no fall-through gaps.
]]
function HubService:IsPositionSupportedByFloor(position: Vector3): boolean
	for _, floorPart in ipairs(self._collidableFloorParts) do
		if floorPart.Parent and floorPart.Anchored and floorPart.CanCollide then
			local center = floorPart.Position
			local halfX = floorPart.Size.X * 0.5
			local halfY = floorPart.Size.Y * 0.5
			local halfZ = floorPart.Size.Z * 0.5
			local topY = center.Y + halfY

			if
				position.X >= (center.X - halfX - 0.05)
				and position.X <= (center.X + halfX + 0.05)
				and position.Z >= (center.Z - halfZ - 0.05)
				and position.Z <= (center.Z + halfZ + 0.05)
			then
				local verticalClearance = position.Y - topY
				if verticalClearance >= -0.5 and verticalClearance <= 6.0 then
					return true
				end
			end
		end
	end
	return false
end

function HubService:IsPositionBlockedByWall(position: Vector3, playerRadius: number?): boolean
	local radius = playerRadius or 1.0
	local checkList: { BasePart } = table.clone(self._collidableWallParts)
	for _, doorPart in ipairs(self._trainDoorParts) do
		if doorPart.CanCollide then
			table.insert(checkList, doorPart)
		end
	end

	for _, wallPart in ipairs(checkList) do
		if wallPart.Parent and wallPart.Anchored and wallPart.CanCollide then
			local center = wallPart.Position
			local halfX = wallPart.Size.X * 0.5 + radius
			local halfY = wallPart.Size.Y * 0.5
			local halfZ = wallPart.Size.Z * 0.5 + radius

			if
				position.X > (center.X - halfX)
				and position.X < (center.X + halfX)
				and position.Z > (center.Z - halfZ)
				and position.Z < (center.Z + halfZ)
				and position.Y >= (center.Y - halfY)
				and position.Y <= (center.Y + halfY)
			then
				return true
			end
		end
	end
	return false
end

function HubService:IsPathWalkable(
	fromPos: Vector3,
	toPos: Vector3,
	stepStuds: number?
): (boolean, string)
	local step = stepStuds or 1.0
	local delta = toPos - fromPos
	local totalDist = delta.Magnitude
	local steps = math.max(1, math.ceil(totalDist / step))

	for i = 0, steps do
		local alpha = i / steps
		local samplePos = Vector3.new(
			fromPos.X + (delta.X * alpha),
			fromPos.Y + (delta.Y * alpha),
			fromPos.Z + (delta.Z * alpha)
		)
		if not self:IsPositionSupportedByFloor(samplePos) then
			return false,
				string.format(
					"UnsupportedFloorAt(%.1f, %.1f, %.1f)",
					samplePos.X,
					samplePos.Y,
					samplePos.Z
				)
		end
		if self:IsPositionBlockedByWall(samplePos, 0.6) then
			return false,
				string.format(
					"BlockedByWallAt(%.1f, %.1f, %.1f)",
					samplePos.X,
					samplePos.Y,
					samplePos.Z
				)
		end
	end

	return true, "WalkablePathVerified"
end

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
	return self:_pivotLivingCharacter(player, spawnPad.CFrame + Vector3.new(0, 2.9, 0))
end

function HubService:SpawnEliminatedPlayerInHub(player: Player, slotIndex: number?): boolean
	local count = #self._eliminatedSpawnParts
	if count == 0 then
		return self:SpawnPlayerInHub(player, slotIndex)
	end
	local resolvedSlot = slotIndex or self:GetPlayerSpawnSlot(player.UserId)
	local berth = self._eliminatedSpawnParts[((resolvedSlot - 1) % count) + 1]
	return self:_pivotLivingCharacter(player, berth.CFrame + Vector3.new(0, 2.9, 0))
end

function HubService:GetActiveStationSpawnPosition(slotIndex: number): Vector3
	local spawns = GameConfig.STATION_ENTRY_SPAWNS
	local chosenIndex = ((slotIndex - 1) % #spawns) + 1
	return spawns[chosenIndex]
end

function HubService:SpawnPlayerInActiveStation(player: Player, slotIndex: number?): boolean
	if not self._stationModel or not self._stationModel.Parent then
		self:BuildStation001Environment()
	end
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
		self:_pivotLivingCharacter(player, marker.CFrame + Vector3.new(0, 2.9, 0))
	end
end

function HubService:ReturnAllPlayersToHub(players: { Player })
	for _, player in ipairs(players) do
		local slotIndex = self:GetPlayerSpawnSlot(player.UserId)
		self:SpawnPlayerInHub(player, slotIndex)
	end
end

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
		and self:IsPositionSupportedByFloor(position)
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
	self:SetStationDoorsOpen(false)
	local activeStation = self._activeStationFolder
	if activeStation then
		activeStation:ClearAllChildren()
	end
	self._stationModel = nil
	self._extractionZonePart = nil
	table.clear(self._stationEntrySpawnParts)
	table.clear(self._stationObjectiveParts)
	table.clear(self._stationObjectivePartsByName)
	table.clear(self._hidingSpotParts)
	table.clear(self._hidingSpotPartsById)
	table.clear(self._stationWaypointParts)
	table.clear(self._stationWaypointGraph)

	-- Retain only Train Hub floor/wall parts in the collision registries
	local keptFloors: { BasePart } = {}
	for _, p in ipairs(self._collidableFloorParts) do
		if p.Parent and p.Parent ~= activeStation then
			table.insert(keptFloors, p)
		end
	end
	self._collidableFloorParts = keptFloors

	local keptWalls: { BasePart } = {}
	for _, p in ipairs(self._collidableWallParts) do
		if p.Parent and p.Parent ~= activeStation then
			table.insert(keptWalls, p)
		end
	end
	self._collidableWallParts = keptWalls
end

return HubService
