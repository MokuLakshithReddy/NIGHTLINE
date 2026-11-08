// luauVmRunner.ts
// Executes the actual NIGHTLINE Roblox Luau modules (/roblox/) inside the
// official Luau VM binary (luau), alongside luau-cli (luau-analyze), luau-lsp analyze,
// selene, stylua, and rojo build (Rojo 7.7.1).
//
// IMPORTANT HARNESS BOUNDARY:
// The Luau VM harness below executes the real Luau source files from `/roblox` inside
// the official `luau` runtime against a deterministic DataModel API contract shim.
// It deliberately does NOT pretend to simulate Roblox 3D rigid-body physics, collision
// solver dynamics, or automatic C++ character respawning:
//   1. Setting `Humanoid.Health = 0` marks that Humanoid instance permanently dead.
//      Attempting to set `Humanoid.Health > 0` on a dead Humanoid or calling `PivotTo`
//      on a dead Character throws an explicit runtime error.
//   2. Respawning requires explicitly calling `player:LoadCharacter()`, which allocates
//      a brand-new `Model` + `Humanoid` + `HumanoidRootPart` and fires `player.CharacterAdded`.
//   3. Floor support (`IsPositionSupportedByFloor`) and wall collision (`IsPositionBlockedByWall`)
//      inspect the actual `Anchored` + `CanCollide` `Part` geometry constructed by `HubService.lua`,
//      while live 6-player 3D physics replication requires manual testing in desktop Roblox Studio.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT_DIR = process.cwd();
const TOOLS_DIR = process.env.NIGHTLINE_TOOLCHAIN_DIR || '/tmp/roblox-tools';

export function ensureToolchainInstalled(): {
  luauBin: string;
  luauAnalyzeBin: string;
  luauLspBin: string;
  rojoBin: string;
  seleneBin: string;
  styluaBin: string;
  globalTypesPath: string;
} {
  const luauBin = path.join(TOOLS_DIR, 'luau');
  const luauAnalyzeBin = path.join(TOOLS_DIR, 'luau-analyze');
  const luauLspBin = path.join(TOOLS_DIR, 'luau-lsp');
  const rojoBin = path.join(TOOLS_DIR, 'rojo');
  const seleneBin = path.join(TOOLS_DIR, 'selene');
  const styluaBin = path.join(TOOLS_DIR, 'stylua');
  const globalTypesPath = path.join(TOOLS_DIR, 'globalTypes.d.luau');

  const requiredFiles = [
    luauBin,
    luauAnalyzeBin,
    luauLspBin,
    rojoBin,
    seleneBin,
    styluaBin,
    globalTypesPath,
  ];

  const missingAny = requiredFiles.some((filePath) => !fs.existsSync(filePath));
  if (missingAny) {
    const bootstrapScript = path.join(ROOT_DIR, 'scripts', 'bootstrap-toolchain.sh');
    if (!fs.existsSync(bootstrapScript)) {
      throw new Error(
        `Missing toolchain binaries in ${TOOLS_DIR} and bootstrap script not found at ${bootstrapScript}.`
      );
    }
    execFileSync('bash', [bootstrapScript], {
      cwd: ROOT_DIR,
      stdio: 'inherit',
      env: {
        ...process.env,
        NIGHTLINE_TOOLCHAIN_DIR: TOOLS_DIR,
      },
    });
  }

  return {
    luauBin,
    luauAnalyzeBin,
    luauLspBin,
    rojoBin,
    seleneBin,
    styluaBin,
    globalTypesPath,
  };
}

/**
 * Reads the real `.lua` files from `/roblox/...`, embeds them verbatim into a
 * self-contained Luau DataModel harness, and executes the test suite inside the
 * official `luau` VM binary.
 */
export function runActualLuauModulesInVm(): {
  passed: boolean;
  stdout: string;
  stdoutLines: string[];
  assertionsSummary: string;
} {
  const { luauBin } = ensureToolchainInstalled();

  const moduleEntries: Array<{ key: string; relPath: string }> = [
    {
      key: 'ReplicatedStorage.Shared.Types.NetworkTypes',
      relPath: 'roblox/ReplicatedStorage/Shared/Types/NetworkTypes.lua',
    },
    {
      key: 'ReplicatedStorage.Shared.Config.GameConfig',
      relPath: 'roblox/ReplicatedStorage/Shared/Config/GameConfig.lua',
    },
    {
      key: 'ReplicatedStorage.Shared.Config.ItemConfig',
      relPath: 'roblox/ReplicatedStorage/Shared/Config/ItemConfig.lua',
    },
    {
      key: 'ReplicatedStorage.Shared.Config.StationConfig',
      relPath: 'roblox/ReplicatedStorage/Shared/Config/StationConfig.lua',
    },
    {
      key: 'ReplicatedStorage.Shared.Config.MonsterConfig',
      relPath: 'roblox/ReplicatedStorage/Shared/Config/MonsterConfig.lua',
    },
    {
      key: 'ReplicatedStorage.Shared.Config.ObjectiveConfig',
      relPath: 'roblox/ReplicatedStorage/Shared/Config/ObjectiveConfig.lua',
    },
    {
      key: 'ReplicatedStorage.Shared.Config.RewardConfig',
      relPath: 'roblox/ReplicatedStorage/Shared/Config/RewardConfig.lua',
    },
    {
      key: 'ReplicatedStorage.Shared.Utils.Signal',
      relPath: 'roblox/ReplicatedStorage/Shared/Utils/Signal.lua',
    },
    {
      key: 'ReplicatedStorage.Shared.Utils.Janitor',
      relPath: 'roblox/ReplicatedStorage/Shared/Utils/Janitor.lua',
    },
    {
      key: 'ReplicatedStorage.Remotes.RemotesRegistry',
      relPath: 'roblox/ReplicatedStorage/Remotes/RemotesRegistry.lua',
    },
    {
      key: 'ServerScriptService.Services.SecurityService',
      relPath: 'roblox/ServerScriptService/Services/SecurityService.lua',
    },
    {
      key: 'ServerScriptService.Services.MovementService',
      relPath: 'roblox/ServerScriptService/Services/MovementService.lua',
    },
    {
      key: 'ServerScriptService.Services.HubService',
      relPath: 'roblox/ServerScriptService/Services/HubService.lua',
    },
    {
      key: 'ServerScriptService.Services.InventoryService',
      relPath: 'roblox/ServerScriptService/Services/InventoryService.lua',
    },
    {
      key: 'ServerScriptService.Services.ObjectiveService',
      relPath: 'roblox/ServerScriptService/Services/ObjectiveService.lua',
    },
    {
      key: 'ServerScriptService.Services.MonsterService',
      relPath: 'roblox/ServerScriptService/Services/MonsterService.lua',
    },
    {
      key: 'ServerScriptService.Services.RoundService',
      relPath: 'roblox/ServerScriptService/Services/RoundService.lua',
    },
    {
      key: 'ServerScriptService.Services.InteractionService',
      relPath: 'roblox/ServerScriptService/Services/InteractionService.lua',
    },
    {
      key: 'StarterPlayer.StarterPlayerScripts.Controllers.InputController',
      relPath: 'roblox/StarterPlayer/StarterPlayerScripts/Controllers/InputController.lua',
    },
  ];

  const robloxEnvPreamble = `
-- Mock Roblox DataModel API Contract Environment for Standalone Luau VM Execution
-- Note: Does NOT simulate 3D rigid-body physics or automatic character respawning.
local VirtualClock = 1000.0
local VirtualTime = 1700000000
local warn = function(...)
	-- Roblox global warn() polyfill for standalone Luau CLI VM
end

local os = setmetatable({
	clock = function() return VirtualClock end,
	time = function() return math.floor(VirtualTime) end,
}, { __index = _G.os })

local function advanceVirtualClock(dt)
	VirtualClock += dt
	VirtualTime += dt
end

local Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z)
	local v = { X = x or 0, Y = y or 0, Z = z or 0 }
	v.Magnitude = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	return setmetatable(v, Vector3)
end
function Vector3.__add(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
function Vector3.__sub(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
function Vector3.__mul(a, b)
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3.zero = Vector3.new(0, 0, 0)

local Vector2 = {}
function Vector2.new(x, y)
	return { X = x or 0, Y = y or 0 }
end

local CFrame = {}
CFrame.__index = CFrame
function CFrame.new(posOrX, y, z)
	if type(posOrX) == "table" and posOrX.X ~= nil then
		return setmetatable({ Position = posOrX }, CFrame)
	end
	return setmetatable({ Position = Vector3.new(posOrX or 0, y or 0, z or 0) }, CFrame)
end
function CFrame.Angles(_rx, _ry, _rz)
	return CFrame.new(0, 0, 0)
end
function CFrame.__mul(a, _b)
	return a
end
function CFrame.__add(a, v)
	return CFrame.new(a.Position + v)
end

local Color3 = {
	fromRGB = function(r, g, b) return { R = r, G = g, B = b } end,
}

local Enum = {
	Material = { Metal = "Metal", DiamondPlate = "DiamondPlate", Neon = "Neon", SmoothPlastic = "SmoothPlastic" },
	SurfaceType = { Smooth = "Smooth" },
	KeyCode = { E = "E", ButtonX = "ButtonX", LeftShift = "LeftShift", ButtonL3 = "ButtonL3", One = "One", Two = "Two", DPadLeft = "DPadLeft", DPadRight = "DPadRight" },
	UserInputState = { Begin = "Begin", End = "End", Cancel = "Cancel" },
	ContextActionResult = { Pass = "Pass" },
	ZIndexBehavior = { Sibling = "Sibling" },
	Font = { GothamBold = "GothamBold", GothamMedium = "GothamMedium", Code = "Code" },
	TextXAlignment = { Left = "Left", Right = "Right", Center = "Center" },
	SortOrder = { LayoutOrder = "LayoutOrder" },
}

local task = {
	spawn = function(fn, ...)
		return coroutine.create(fn)
	end,
	defer = function(fn, ...)
		fn(...)
	end,
	wait = function(seconds)
		advanceVirtualClock(seconds or 0.1)
		return seconds or 0.1
	end,
	cancel = function(_thread) end,
}

local function createSignal()
	local listeners = {}
	return {
		Connect = function(_self, callback)
			local conn = {
				Connected = true,
				Disconnect = function(c) c.Connected = false end,
			}
			table.insert(listeners, { conn = conn, cb = callback })
			return conn
		end,
		Fire = function(_self, ...)
			for _, item in ipairs(table.clone(listeners)) do
				if item.conn.Connected then
					item.cb(...)
				end
			end
		end,
	}
end

local Instance = {}
function Instance.new(className)
	local children = {}
	local attributes = {}
	local state = {
		Parent = nil,
		CFrame = CFrame.new(0, 0, 0),
		Position = Vector3.new(0, 0, 0),
		Health = 100,
		IsDead = false,
	}
	local inst = {
		ClassName = className,
		Name = className,
		Size = Vector3.new(1, 1, 1),
		Anchored = false,
		CanCollide = true,
		Transparency = 0,
		Enabled = true,
		MaxHealth = 100,
		WalkSpeed = 14,
		Died = createSignal(),
		CharacterAdded = createSignal(),
		OnServerEvent = createSignal(),
		OnClientEvent = createSignal(),
		_serverListeners = nil,
		_children = children,
		_attributes = attributes,
		_state = state,
		IsA = function(self, targetClass)
			if self.ClassName == targetClass then return true end
			if targetClass == "BasePart" and (self.ClassName == "Part" or self.ClassName == "SpawnLocation") then return true end
			if targetClass == "Instance" then return true end
			return false
		end,
		FindFirstChild = function(self, name)
			for _, child in ipairs(self._children) do
				if child.Name == name then return child end
			end
			return nil
		end,
		FindFirstChildOfClass = function(self, targetClass)
			for _, child in ipairs(self._children) do
				if child.ClassName == targetClass then return child end
			end
			return nil
		end,
		WaitForChild = function(self, name)
			return self:FindFirstChild(name)
		end,
		GetChildren = function(self)
			return table.clone(self._children)
		end,
		ClearAllChildren = function(self)
			for _, child in ipairs(self._children) do
				child._state.Parent = nil
			end
			table.clear(self._children)
		end,
		SetAttribute = function(self, k, v)
			self._attributes[k] = v
		end,
		GetAttribute = function(self, k)
			return self._attributes[k]
		end,
		PivotTo = function(self, targetCFrame)
			local hum = self:FindFirstChildOfClass("Humanoid")
			if hum and hum._state.IsDead then
				error("Forbidden: Attempted to PivotTo a dead Character model (" .. tostring(self.Name) .. ")")
			end
			self.CFrame = targetCFrame
			local hrp = self:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = targetCFrame
			end
		end,
		FireClient = function(_self, _player, _payload) end,
		FireAllClients = function(_self, _payload) end,
		FireServer = function(self, ...)
			self.OnServerEvent:Fire(self._mockLocalPlayer, ...)
		end,
		Destroy = function(self)
			local parent = self._state.Parent
			if parent and parent._children then
				for i, c in ipairs(parent._children) do
					if c == self then
						table.remove(parent._children, i)
						break
					end
				end
			end
			self._state.Parent = nil
		end,
	}

	return setmetatable(inst, {
		__index = function(t, k)
			if k == "Parent" or k == "CFrame" or k == "Position" or k == "Health" then
				return t._state[k]
			end
			local raw = rawget(t, k)
			if raw ~= nil then return raw end
			for _, child in ipairs(t._children) do
				if child.Name == k then return child end
			end
			return nil
		end,
		__newindex = function(t, k, v)
			if k == "Parent" then
				local oldParent = t._state.Parent
				if oldParent and oldParent._children then
					for i, c in ipairs(oldParent._children) do
						if c == t then
							table.remove(oldParent._children, i)
							break
						end
					end
				end
				t._state.Parent = v
				if v and v._children then
					table.insert(v._children, t)
				end
			elseif k == "CFrame" then
				t._state.CFrame = v
				if type(v) == "table" and v.Position then
					t._state.Position = v.Position
				end
			elseif k == "Position" then
				t._state.Position = v
				t._state.CFrame = CFrame.new(v)
			elseif k == "Health" then
				if t.ClassName == "Humanoid" and t._state.IsDead and v > 0 then
					error("Forbidden: Attempted to restore Health on a dead Humanoid instance")
				end
				t._state.Health = v
				if t.ClassName == "Humanoid" and v <= 0 then
					t._state.IsDead = true
				end
			else
				rawset(t, k, v)
			end
		end,
	})
end

local oldTypeof = typeof
local function typeof(val)
	if type(val) == "table" and val.ClassName ~= nil then
		return "Instance"
	end
	if type(val) == "table" and val.Connected ~= nil and val.Disconnect ~= nil then
		return "RBXScriptConnection"
	end
	return oldTypeof(val)
end

-- Build Services & DataModel Hierarchy
local Workspace = Instance.new("Workspace")
local ReplicatedStorage = Instance.new("ReplicatedStorage")
local ServerScriptService = Instance.new("ServerScriptService")
local StarterPlayer = Instance.new("StarterPlayer")
local StarterPlayerScripts = Instance.new("StarterPlayerScripts")
StarterPlayerScripts.Name = "StarterPlayerScripts"
StarterPlayerScripts.Parent = StarterPlayer

local Players = Instance.new("Players")
Players.PlayerAdded = createSignal()
Players.PlayerRemoving = createSignal()
Players.LocalPlayer = nil
function Players:GetPlayers()
	local list = {}
	for _, child in ipairs(self._children) do
		if child.ClassName == "Player" then
			table.insert(list, child)
		end
	end
	return list
end

local CollectionServiceTags = {}
local CollectionService = {
	AddTag = function(_self, inst, tag)
		CollectionServiceTags[inst] = CollectionServiceTags[inst] or {}
		CollectionServiceTags[inst][tag] = true
	end,
	HasTag = function(_self, inst, tag)
		return CollectionServiceTags[inst] ~= nil and CollectionServiceTags[inst][tag] == true
	end,
}

local ProximityPromptService = {
	PromptTriggered = createSignal(),
	PromptShown = createSignal(),
	PromptHidden = createSignal(),
}

local BoundContextActions = {}
local ContextActionService = {
	BindAction = function(_self, actionName, callback, _createTouchButton, ...)
		BoundContextActions[actionName] = callback
	end,
	SetTitle = function(_self, _actionName, _title) end,
}

local RunService = {
	IsServer = function(_self) return true end,
	Heartbeat = createSignal(),
}

local ServicesMap = {
	Workspace = Workspace,
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	StarterPlayer = StarterPlayer,
	Players = Players,
	CollectionService = CollectionService,
	ProximityPromptService = ProximityPromptService,
	ContextActionService = ContextActionService,
	RunService = RunService,
}

local game = {
	GetService = function(_self, name)
		return assert(ServicesMap[name], "Unknown service: " .. tostring(name))
	end,
}

local function ensureFolderPath(root, parts)
	local curr = root
	for i = 1, #parts - 1 do
		local name = parts[i]
		local nextFolder = curr:FindFirstChild(name)
		if not nextFolder then
			nextFolder = Instance.new("Folder")
			nextFolder.Name = name
			nextFolder.Parent = curr
		end
		curr = nextFolder
	end
	local leafName = parts[#parts]
	local leaf = curr:FindFirstChild(leafName)
	if not leaf then
		leaf = Instance.new("ModuleScript")
		leaf.Name = leafName
		leaf.Parent = curr
	end
	return leaf
end

local MODULE_LOADERS = {}
local MODULE_CACHE = {}

local function require(moduleInstance)
	assert(type(moduleInstance) == "table" and moduleInstance._moduleKey, "require expects a registered ModuleScript instance")
	local key = moduleInstance._moduleKey
	if MODULE_CACHE[key] ~= nil then
		return MODULE_CACHE[key]
	end
	local loader = assert(MODULE_LOADERS[key], "No loader registered for " .. tostring(key))
	local result = loader(moduleInstance)
	MODULE_CACHE[key] = result
	return result
end
`;

  const moduleBlocks: string[] = [];
  for (const entry of moduleEntries) {
    const fullPath = path.join(ROOT_DIR, entry.relPath);
    const rawCode = fs.readFileSync(fullPath, 'utf8').replace(/^--!strict\s*/, '');
    const pathParts = entry.key.split('.');
    const rootName = pathParts[0];
    const subPartsLiteral = pathParts
      .slice(1)
      .map((p) => `"${p}"`)
      .join(', ');

    moduleBlocks.push(`
do
	local modInst = ensureFolderPath(${rootName}, { ${subPartsLiteral} })
	modInst._moduleKey = "${entry.key}"
	MODULE_LOADERS["${entry.key}"] = function(script)
${rawCode}
	end
end
`);
  }

  const luauAssertions = `
-- ============================================================================
-- Execute Real NIGHTLINE Luau Services & Verify Mission-Specific Objectives,
-- ObjectiveService Architecture, Hollow AI Interfaces, and Round Lifecycle
-- ============================================================================

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemotesRegistry = require(ReplicatedStorage.Remotes.RemotesRegistry)
local SecurityService = require(ServerScriptService.Services.SecurityService)
local MovementService = require(ServerScriptService.Services.MovementService)
local HubService = require(ServerScriptService.Services.HubService)
local InventoryService = require(ServerScriptService.Services.InventoryService)
local ObjectiveService = require(ServerScriptService.Services.ObjectiveService)
local MonsterService = require(ServerScriptService.Services.MonsterService)
local RoundService = require(ServerScriptService.Services.RoundService)
local InteractionService = require(ServerScriptService.Services.InteractionService)
local InputController = require(StarterPlayer.StarterPlayerScripts.Controllers.InputController)

local remotes = RemotesRegistry.InitializeServerRemotes()

SecurityService:Init()
MovementService:Init({ remotes = remotes, securityService = SecurityService })
HubService:Init()
HubService:SetMovementService(MovementService)
InventoryService:Init({ remotes = remotes, securityService = SecurityService })
ObjectiveService:Init({
	remotes = remotes,
	securityService = SecurityService,
	hubService = HubService,
	inventoryService = InventoryService,
})
MonsterService:Init({
	securityService = SecurityService,
	hubService = HubService,
	movementService = MovementService,
})
RoundService:Init({
	remotes = remotes,
	securityService = SecurityService,
	hubService = HubService,
	inventoryService = InventoryService,
	movementService = MovementService,
	objectiveService = ObjectiveService,
	monsterService = MonsterService,
})
MovementService:SetRoundService(RoundService)
InventoryService:SetRoundService(RoundService)
ObjectiveService:SetRoundService(RoundService)
ObjectiveService:SetMonsterService(MonsterService)
MonsterService:SetRoundService(RoundService)
InteractionService:Init({
	securityService = SecurityService,
	inventoryService = InventoryService,
	roundService = RoundService,
	objectiveService = ObjectiveService,
	monsterService = MonsterService,
})

SecurityService:Start()
MovementService:Start()
HubService:Start()
InventoryService:Start()
ObjectiveService:Start()
MonsterService:Start()
RoundService:Start()
InteractionService:Start()

local CharacterSpawnCounter = 0

local function buildFreshCharacterModel(playerName)
	CharacterSpawnCounter += 1
	local char = Instance.new("Model")
	char.Name = string.format("%s_Character_%d", playerName, CharacterSpawnCounter)
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Parent = char
	local hum = Instance.new("Humanoid")
	hum.Name = "Humanoid"
	hum.Health = GameConfig.DEFAULT_MAX_HEALTH
	hum.MaxHealth = GameConfig.DEFAULT_MAX_HEALTH
	hum.WalkSpeed = GameConfig.WALK_SPEED
	hum.Parent = char
	char.PrimaryPart = hrp
	return char
end

local function createMockPlayer(userId, name)
	local p = Instance.new("Player")
	p.UserId = userId
	p.Name = name
	p.DisplayName = name

	function p:LoadCharacter()
		if self.Character then
			self.Character:Destroy()
		end
		local freshChar = buildFreshCharacterModel(self.Name)
		self.Character = freshChar
		freshChar.Parent = Workspace
		self.CharacterAdded:Fire(freshChar)
		return freshChar
	end

	local initialChar = buildFreshCharacterModel(name)
	p.Character = initialChar
	initialChar.Parent = Workspace

	p.Parent = Players
	Players.PlayerAdded:Fire(p)
	return p
end

-- Helper to walk a player along a path in legal server-validated steps
local function walkPlayerAlongPath(player, targetPos)
	local okWalkable, walkReason = HubService:IsPathWalkable(
		player.Character.HumanoidRootPart.Position,
		targetPos,
		1.0
	)
	assert(
		okWalkable == true,
		string.format("Path for %s to (%.1f, %.1f, %.1f) must be walkable: %s", player.Name, targetPos.X, targetPos.Y, targetPos.Z, walkReason)
	)

	local startPos = player.Character.HumanoidRootPart.Position
	local delta = targetPos - startPos
	local dist = delta.Magnitude
	local stepDistance = 3.0
	local steps = math.max(1, math.ceil(dist / stepDistance))

	for i = 1, steps do
		local alpha = i / steps
		local nextPos = Vector3.new(
			startPos.X + delta.X * alpha,
			startPos.Y + delta.Y * alpha,
			startPos.Z + delta.Z * alpha
		)
		advanceVirtualClock(0.25)
		player.Character:PivotTo(CFrame.new(nextPos))
		local okStep, stepReason = MovementService:ValidatePlayerMovement(player, 0.25)
		assert(
			okStep == true,
			string.format("Step %d/%d for %s rejected by MovementService: %s", i, steps, player.Name, stepReason)
		)
	end
end

-- ----------------------------------------------------------------------------
-- TEST 1 (Issue 02): Explicit Spawn-Slot Allocation & Release on Departure
-- ----------------------------------------------------------------------------
local p1 = createMockPlayer(101, "Avery")
local p2 = createMockPlayer(102, "Morgan")
local p3 = createMockPlayer(103, "Vance")

assert(RoundService:GetPlayerSpawnSlot(p1) == 1, "P1 must receive slot 1")
assert(RoundService:GetPlayerSpawnSlot(p2) == 2, "P2 must receive slot 2")
assert(RoundService:GetPlayerSpawnSlot(p3) == 3, "P3 must receive slot 3")

p2.Parent = nil
Players.PlayerRemoving:Fire(p2)
assert(RoundService:GetPlayerSpawnSlot(p1) == 1, "P1 must retain slot 1")
assert(RoundService:GetPlayerSpawnSlot(p3) == 3, "P3 must retain slot 3")

local p4 = createMockPlayer(104, "Sloane")
assert(RoundService:GetPlayerSpawnSlot(p4) == 2, "P4 must receive freed slot 2 without colliding with P3")
print("[LUAU VM PASS] Issue 02: Explicit spawn-slot allocation & release verified.")

-- ----------------------------------------------------------------------------
-- TEST 2 (Fix 3 & Issue 03): Horizontal + Vertical Movement Validation
-- ----------------------------------------------------------------------------
remotes.RequestSprint._mockLocalPlayer = p1
InputController:Init({ uiController = nil, remotes = remotes })
InputController:Start()

InputController:RequestSprint(true)
local p1Humanoid = p1.Character:FindFirstChildOfClass("Humanoid")
assert(p1Humanoid.WalkSpeed == GameConfig.SPRINT_SPEED, "Server MovementService must set WalkSpeed to SPRINT_SPEED (22)")

InputController:RequestSprint(false)
assert(p1Humanoid.WalkSpeed == GameConfig.WALK_SPEED, "Server MovementService must restore WalkSpeed to WALK_SPEED (14)")

advanceVirtualClock(2.0)
local okBaseline = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okBaseline == true, "Baseline stationary position must be valid")

-- 2A: Legitimate Jump (+11 studs upward in 0.25s)
local posBeforeJump = p1.Character.HumanoidRootPart.Position
advanceVirtualClock(0.25)
p1.Character:PivotTo(CFrame.new(posBeforeJump.X, posBeforeJump.Y + 11, posBeforeJump.Z - 3))
local okJump, jumpReason = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okJump == true and jumpReason == "ValidMovement", "Legitimate upward jump (+11 studs Y in 0.25s) must be accepted")

-- 2B: Legitimate Gravity Fall (-28 studs downward in 0.25s)
local posBeforeFall = p1.Character.HumanoidRootPart.Position
advanceVirtualClock(0.25)
p1.Character:PivotTo(CFrame.new(posBeforeFall.X, posBeforeFall.Y - 28, posBeforeFall.Z - 2))
local okFall, fallReason = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okFall == true and fallReason == "ValidMovement", "Legitimate gravity fall (-28 studs Y in 0.25s) must be accepted")

-- 2C: Server-Authorized Teleport (NotifyServerTeleport)
local authorizedTarget = Vector3.new(-5, 3.75, 12)
MovementService:NotifyServerTeleport(p1, authorizedTarget)
p1.Character:PivotTo(CFrame.new(authorizedTarget))
advanceVirtualClock(0.1)
local okAuthTeleport, authTeleportReason = MovementService:ValidatePlayerMovement(p1, 0.1)
assert(okAuthTeleport == true and authTeleportReason == "TeleportGrace", "Server-authorized teleport must be accepted within grace window")

advanceVirtualClock(1.5)
MovementService:ValidatePlayerMovement(p1, 0.25)

-- 2D: Horizontal Speed/Teleport Exploit (90 studs in 0.25s)
local validBeforeHorizHack = p1.Character.HumanoidRootPart.Position
advanceVirtualClock(0.25)
p1.Character:PivotTo(CFrame.new(validBeforeHorizHack.X, validBeforeHorizHack.Y, validBeforeHorizHack.Z - 90))
local okHorizHack, horizHackReason = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okHorizHack == false and horizHackReason == "RubberbandedSpeedAnomaly", "Horizontal speed exploit must be rejected")

-- 2E: Vertical Upward Fly/SuperJump Exploit (+45 studs Y in 0.25s)
local validBeforeUpHack = p1.Character.HumanoidRootPart.Position
advanceVirtualClock(0.25)
p1.Character:PivotTo(CFrame.new(validBeforeUpHack.X, validBeforeUpHack.Y + 45, validBeforeUpHack.Z))
local okUpHack, upHackReason = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okUpHack == false and upHackReason == "RubberbandedVerticalUpwardAnomaly", "Vertical upward fly exploit must be rejected")

-- 2F: Vertical Downward Noclip Exploit (-120 studs Y in 0.25s)
local validBeforeDownHack = p1.Character.HumanoidRootPart.Position
advanceVirtualClock(0.25)
p1.Character:PivotTo(CFrame.new(validBeforeDownHack.X, validBeforeDownHack.Y - 120, validBeforeDownHack.Z))
local okDownHack, downHackReason = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okDownHack == false and downHackReason == "RubberbandedVerticalDownwardAnomaly", "Vertical downward noclip exploit must be rejected")
print("[LUAU VM PASS] Fix 3 & Issue 03: Horizontal + vertical movement validation (jumps, falls, teleports, exploits) verified.")

-- ----------------------------------------------------------------------------
-- TEST 3: Physically Playable Station 001 Environment & CanCollide=true Spawns
-- ----------------------------------------------------------------------------
local p5 = createMockPlayer(105, "Kestrel")
local p6 = createMockPlayer(106, "Rook")
local p7 = createMockPlayer(107, "Vesper")
local allSixPlayers = { p1, p4, p3, p5, p6, p7 }
assert(#allSixPlayers == 6, "Must have 6 active players occupying slots 1..6")

local stationModel = HubService:BuildStation001Environment()
assert(stationModel ~= nil, "Station001_ForgottenTerminal model must exist")

local requiredCollidableParts = {
	"TrainToStationBridge",
	"StationPlatformFloor",
	"MainConcourseFloor",
	"MaintenanceRoomFloor",
	"ControlRoomFloor",
	"CargoStorageFloor",
	"ExtractionPlatformDeck",
	"StationEntrySpawn_01",
	"StationEntrySpawn_02",
	"StationEntrySpawn_03",
	"StationEntrySpawn_04",
	"StationEntrySpawn_05",
	"StationEntrySpawn_06",
	"FusePickup_01",
	"FusePickup_02",
	"FusePickup_03",
	"FuseSocket_01",
	"FuseSocket_02",
	"FuseSocket_03",
	"CargoContainer_01",
	"CargoContainer_02",
	"CargoDropPoint_01",
	"SignalTerminal_01",
	"SignalTerminal_02",
	"SignalTerminal_03",
}

for _, partName in ipairs(requiredCollidableParts) do
	local part = stationModel:FindFirstChild(partName)
	assert(part ~= nil, "Station 001 must contain physical part: " .. partName)
	assert(part.CanCollide == true, partName .. " must have CanCollide = true (never false)")
	assert(part.Anchored == true, partName .. " must have Anchored = true")
end

for slotIdx = 1, 6 do
	local spawnPos = GameConfig.STATION_ENTRY_SPAWNS[slotIdx]
	assert(spawnPos ~= nil, "Station entry spawn must exist for slot " .. tostring(slotIdx))
	assert(
		HubService:IsPositionSupportedByFloor(spawnPos) == true,
		"Station entry spawn slot " .. tostring(slotIdx) .. " must be supported underneath by solid CanCollide=true floor"
	)
	assert(
		HubService:IsPositionInExtractionZone(spawnPos) == false,
		"Station entry spawn slot " .. tostring(slotIdx) .. " must be strictly outside ExtractionPlatformZone"
	)
end
print("[LUAU VM PASS] Priority 2 & Fix 1: Physically playable Station 001 environment, CanCollide=true spawns, and collision walls verified.")

-- ----------------------------------------------------------------------------
-- TEST 4 (Priority 1, 2 & 3 — Mission 1): RestorePower Independent & Cooperative Verification
-- (3 Individual Fuses -> Pick Up & Carry -> Install into 3 Maintenance Sockets)
-- ----------------------------------------------------------------------------
RoundService:_startNewIntermission("RestorePower")
assert(RoundService:GetState() == "INTERMISSION", "Round 1 must start in INTERMISSION")
assert(ObjectiveService:GetActiveMissionId() == "RestorePower", "Round 1 mission must be RestorePower")
assert(HubService:AreStationDoorsOpen() == false, "Train bulkhead doors must be closed while in Hub")

-- P1 equips Flare, votes Station 001, and boards
advanceVirtualClock(1.0)
walkPlayerAlongPath(p1, Vector3.new(-6, 3.75, -4))
local flareLocker = Workspace.World.Hub.Train:FindFirstChild("EquipmentLocker_Flare")
local okEquip = InteractionService:HandlePromptTriggered(flareLocker:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okEquip == true, "P1 must equip Flare at locker")

advanceVirtualClock(1.0)
walkPlayerAlongPath(p1, Vector3.new(0, 3.75, -28))
local destConsole = Workspace.World.Hub.Train:FindFirstChild("DestinationConsole")
local okVote = InteractionService:HandlePromptTriggered(destConsole:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okVote == true, "P1 must confirm Station 001 route")

advanceVirtualClock(1.0)
walkPlayerAlongPath(p1, Vector3.new(6, 3.75, -14))
local boardingGate = Workspace.World.Hub.Train:FindFirstChild("BoardingReadyGate")
local okBoard = InteractionService:HandlePromptTriggered(boardingGate:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okBoard == true, "P1 must toggle BOARDED at BoardingReadyGate")

RoundService:_enterBoardingPhase()
RoundService:_lockCrewAndDepart()
RoundService:_enterExplorationPhase()
assert(RoundService:GetState() == "EXPLORATION", "Must enter EXPLORATION")

local activeStationModel = Workspace.World.Runtime.ActiveStation:FindFirstChild("Station001_ForgottenTerminal")
assert(activeStationModel ~= nil, "ActiveStation must contain Station001_ForgottenTerminal")

-- Verify remote distance abuse is rejected when P1 tries to interact with FusePickup_01 from far away
local fuse1Part = activeStationModel:FindFirstChild("FusePickup_01")
local fuse2Part = activeStationModel:FindFirstChild("FusePickup_02")
local fuse3Part = activeStationModel:FindFirstChild("FusePickup_03")
local socket1Part = activeStationModel:FindFirstChild("FuseSocket_01")
local socket2Part = activeStationModel:FindFirstChild("FuseSocket_02")
local socket3Part = activeStationModel:FindFirstChild("FuseSocket_03")
local cargo1Part = activeStationModel:FindFirstChild("CargoContainer_01")
local signal1Part = activeStationModel:FindFirstChild("SignalTerminal_01")

advanceVirtualClock(1.0)
local okRemoteAbuse, remoteAbuseReason = ObjectiveService:HandleObjectiveInteraction(p1, fuse1Part)
assert(okRemoteAbuse == false and remoteAbuseReason == "OutOfRange", "Remote interaction with distant fuse must be rejected with OutOfRange")

-- Verify cross-mission interactions (RecoverCargo / RepairSignal objects) are rejected during RestorePower
walkPlayerAlongPath(p1, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p1, Vector3.new(41, 3.75, 52))
advanceVirtualClock(1.0)
local okWrongCargo, wrongCargoReason = ObjectiveService:HandleObjectiveInteraction(p1, cargo1Part)
assert(okWrongCargo == false and wrongCargoReason == "MissionMismatch", "CargoContainer interaction must be rejected during RestorePower")

walkPlayerAlongPath(p1, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p1, Vector3.new(76, 3.75, -6))
advanceVirtualClock(1.0)
local okWrongSignal, wrongSignalReason = ObjectiveService:HandleObjectiveInteraction(p1, signal1Part)
assert(okWrongSignal == false and wrongSignalReason == "MissionMismatch", "SignalTerminal interaction must be rejected during RestorePower")

-- Verify installing into FuseSocket_01 without carrying a fuse is rejected
walkPlayerAlongPath(p1, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p1, Vector3.new(44, 3.75, -52))
advanceVirtualClock(1.0)
local okNoFuse, noFuseReason = InteractionService:HandlePromptTriggered(socket1Part:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okNoFuse == false and noFuseReason == "MissingRequiredFuse", "Installing into socket without a Fuse must be rejected")

-- Cooperative Fuse Collection & Socket Installation:
-- P1 walks out through Maintenance doorway (47, -36) to FusePickup_01 (38, 2.2, -24) and picks it up
walkPlayerAlongPath(p1, Vector3.new(47, 3.75, -36))
walkPlayerAlongPath(p1, Vector3.new(38, 3.75, -24))
advanceVirtualClock(1.0)
local okFuse1, fuse1Reason = InteractionService:HandlePromptTriggered(fuse1Part:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okFuse1 == true and fuse1Reason == "FuseCollected", "P1 must collect FusePickup_01")
assert(InventoryService:GetMissionItemCount(p1, "Fuse") == 1, "P1 must carry 1 Fuse in InventoryService")

-- Duplicate pickup of FusePickup_01 must be rejected
advanceVirtualClock(1.0)
local okDupFuse1, dupFuse1Reason = ObjectiveService:HandleObjectiveInteraction(p1, fuse1Part)
assert(okDupFuse1 == false and dupFuse1Reason == "FuseAlreadyCollected", "Duplicate collection of FusePickup_01 must be rejected")

-- P4 walks to FusePickup_02 (74, 2.2, -10) in Control Room and picks it up
walkPlayerAlongPath(p4, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p4, Vector3.new(74, 3.75, -6))
advanceVirtualClock(1.0)
local okFuse2, fuse2Reason = InteractionService:HandlePromptTriggered(fuse2Part:FindFirstChildOfClass("ProximityPrompt"), p4)
assert(okFuse2 == true and fuse2Reason == "FuseCollected", "P4 must collect FusePickup_02")
assert(InventoryService:GetMissionItemCount(p4, "Fuse") == 1, "P4 must carry 1 Fuse in InventoryService")

-- P3 walks to FusePickup_03 (40, 2.2, 50) in Cargo Storage and picks it up
walkPlayerAlongPath(p3, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p3, Vector3.new(43, 3.75, 48))
advanceVirtualClock(1.0)
local okFuse3, fuse3Reason = InteractionService:HandlePromptTriggered(fuse3Part:FindFirstChildOfClass("ProximityPrompt"), p3)
assert(okFuse3 == true and fuse3Reason == "FuseCollected", "P3 must collect FusePickup_03")
assert(InventoryService:GetMissionItemCount(p3, "Fuse") == 1, "P3 must carry 1 Fuse in InventoryService")

-- P1 walks to FuseSocket_01 (41, 3.0, -58) and installs Fuse #1 -> progress 1/3
walkPlayerAlongPath(p1, Vector3.new(44, 3.75, -52))
advanceVirtualClock(1.0)
local okInstall1, install1Reason = InteractionService:HandlePromptTriggered(socket1Part:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okInstall1 == true and install1Reason == "FuseInstalled", "P1 must install Fuse into FuseSocket_01")
assert(InventoryService:GetMissionItemCount(p1, "Fuse") == 0, "P1 carried Fuse must be consumed on socket install")

local rpProg1, rpReq1, rpDone1 = RoundService:GetObjectiveProgress()
assert(rpProg1 == 1 and rpReq1 == 3 and rpDone1 == false, "RestorePower progress must be 1/3 after Socket #1")

-- Duplicate install on FuseSocket_01 must be rejected
advanceVirtualClock(1.0)
local okDupSocket1, dupSocket1Reason = ObjectiveService:HandleObjectiveInteraction(p4, socket1Part)
assert(okDupSocket1 == false, "Duplicate installation on FuseSocket_01 must be rejected: " .. tostring(dupSocket1Reason))

-- P4 walks from Control Room to FuseSocket_02 (47, 3.0, -58) and installs Fuse #2 -> progress 2/3
walkPlayerAlongPath(p4, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p4, Vector3.new(47, 3.75, -52))
advanceVirtualClock(1.0)
local okInstall2, install2Reason = InteractionService:HandlePromptTriggered(socket2Part:FindFirstChildOfClass("ProximityPrompt"), p4)
assert(okInstall2 == true and install2Reason == "FuseInstalled", "P4 must install Fuse into FuseSocket_02")

-- Test carrier elimination recovery: P3 is carrying Fuse_03 when P3 dies -> FusePickup_03 is restored so P1 can pick it up!
local p3DeadChar = p3.Character
local p3DeadHum = p3DeadChar:FindFirstChildOfClass("Humanoid")
p3DeadHum.Health = 0
p3DeadHum.Died:Fire()
assert(RoundService:GetPlayerStatus(p3) == "ELIMINATED", "P3 must be ELIMINATED on death")
assert(fuse3Part:GetAttribute("Collected") == false, "Eliminating P3 must restore carried FusePickup_03 so teammates are not soft-locked")
assert(fuse3Part:FindFirstChildOfClass("ProximityPrompt").Enabled == true, "Restored FusePickup_03 prompt must be re-enabled")

local p3FreshChar = p3:LoadCharacter()
assert(p3FreshChar ~= p3DeadChar, "P3 respawn must create a fresh Character instance")
assert(p3FreshChar.HumanoidRootPart.Position.Z >= 35, "Eliminated P3 fresh character must spawn in Hub Recovery Bay")
print("[LUAU VM PASS] Fix 2 & Issue 01: Dead characters are never healed/pivoted in-place; fresh-character respawn flow verified.")

-- P1 walks from Maintenance Room to Cargo Storage (43, 3.75, 48), picks up restored FusePickup_03, and installs it into FuseSocket_03
walkPlayerAlongPath(p1, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p1, Vector3.new(43, 3.75, 48))
advanceVirtualClock(1.0)
local okRePick3, rePick3Reason = InteractionService:HandlePromptTriggered(fuse3Part:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okRePick3 == true and rePick3Reason == "FuseCollected", "P1 must pick up recovered FusePickup_03")

walkPlayerAlongPath(p1, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p1, Vector3.new(50, 3.75, -52))
advanceVirtualClock(1.0)
local okInstall3, install3Reason = InteractionService:HandlePromptTriggered(socket3Part:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okInstall3 == true and install3Reason == "ObjectiveCompleted", "P1 must install Fuse #3 into FuseSocket_03 and complete RestorePower")

local rpProg3, rpReq3, rpDone3 = RoundService:GetObjectiveProgress()
assert(rpProg3 == 3 and rpReq3 == 3 and rpDone3 == true, "RestorePower must be 3/3 completed")
print("[LUAU VM PASS] Priority 1 & 3 (RestorePower): 3 fuses, carry/install, duplicate & mismatch rejection, and carrier recovery verified.")

-- Complete Round 1 extraction lifecycle
RoundService:_enterExtractionPhase()
for _, unextractedP in ipairs({ p1, p4, p5, p6, p7 }) do
	local okAuto, autoReason = RoundService:TryExtractPlayer(unextractedP)
	assert(okAuto == false and autoReason == "OutOfExtractionZone", unextractedP.Name .. " must not auto-extract outside zone")
end
print("[LUAU VM PASS] Fix 1: All 6 station spawn positions verified outside extraction zone; zero auto-extractions.")

walkPlayerAlongPath(p1, Vector3.new(47, 3.75, -8))
walkPlayerAlongPath(p1, Vector3.new(16, 3.75, -8))
local extractionZonePart = HubService:GetExtractionZonePart()
advanceVirtualClock(1.0)
local okExtractP1, extractReasonP1 = InteractionService:HandlePromptTriggered(extractionZonePart:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okExtractP1 == true and extractReasonP1 == "Extracted", "P1 must extract via ExtractionPlatformPrompt")

walkPlayerAlongPath(p4, Vector3.new(47, 3.75, -8))
walkPlayerAlongPath(p4, Vector3.new(16, 3.75, -8))

RoundService:_enterReturnPhase()
assert(RoundService:GetState() == "RETURN", "Must transition to RETURN")
assert(RoundService:GetPlayerStatus(p1) == "EXTRACTED", "P1 must remain EXTRACTED")
assert(RoundService:GetPlayerStatus(p4) == "EXTRACTED", "P4 standing inside extraction zone at departure must be EXTRACTED")
assert(RoundService:GetPlayerStatus(p5) == "ELIMINATED", "P5 left behind at station spawn must be marked ELIMINATED")
assert(RoundService:GetLastOutcome() == "SUCCESS", "Round outcome must be SUCCESS when >= 1 player extracted")
print("[LUAU VM PASS] Issue 04: Physical extraction zone proximity & left-behind elimination verified.")

RoundService:_enterResultsPhase()
RoundService:CleanupRound()

-- Verify objectives reset cleanly between rounds
local resetProg, _, resetDone = RoundService:GetObjectiveProgress()
assert(resetProg == 0 and resetDone == false, "Objectives must reset to 0 between rounds on CleanupRound")

-- ----------------------------------------------------------------------------
-- TEST 5 (Priority 1, 2 & 3 — Mission 2): RecoverCargo Independent & Cooperative Verification
-- (Locate 2 Sealed Cargo Containers -> Pick Up & Carry -> Deliver to Platform Drop Point)
-- ----------------------------------------------------------------------------
p3:LoadCharacter()
RoundService:_startNewIntermission("RecoverCargo")
assert(ObjectiveService:GetActiveMissionId() == "RecoverCargo", "Round 2 mission must be RecoverCargo")
RoundService:_enterBoardingPhase()
RoundService:_lockCrewAndDepart()
RoundService:_enterExplorationPhase()

local stationModelR2 = Workspace.World.Runtime.ActiveStation:FindFirstChild("Station001_ForgottenTerminal")
local r2Cargo1 = stationModelR2:FindFirstChild("CargoContainer_01")
local r2Cargo2 = stationModelR2:FindFirstChild("CargoContainer_02")
local r2DropPoint = stationModelR2:FindFirstChild("CargoDropPoint_01")
local r2Fuse1 = stationModelR2:FindFirstChild("FusePickup_01")
local r2Signal3 = stationModelR2:FindFirstChild("SignalTerminal_03")

-- Verify unrelated mission interactions are rejected during RecoverCargo
walkPlayerAlongPath(p1, Vector3.new(38, 3.75, -24))
advanceVirtualClock(1.0)
local okMisFuse, misFuseReason = ObjectiveService:HandleObjectiveInteraction(p1, r2Fuse1)
assert(okMisFuse == false and misFuseReason == "MissionMismatch", "FusePickup must be rejected during RecoverCargo")

walkPlayerAlongPath(p1, Vector3.new(56, 3.75, 0))
advanceVirtualClock(1.0)
local okMisSig, misSigReason = ObjectiveService:HandleObjectiveInteraction(p1, r2Signal3)
assert(okMisSig == false and misSigReason == "MissionMismatch", "SignalTerminal must be rejected during RecoverCargo")

-- Verify invalid delivery at CargoDropPoint_01 when carrying 0 cargo is rejected
walkPlayerAlongPath(p1, Vector3.new(23, 3.75, -8))
advanceVirtualClock(1.0)
local okEmptyDrop, emptyDropReason = InteractionService:HandlePromptTriggered(r2DropPoint:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okEmptyDrop == false and emptyDropReason == "MissingCarriedCargo", "Delivering without carrying cargo must be rejected")

-- P1 walks to Cargo Storage (44, 3.75, 52) and picks up CargoContainer_01
walkPlayerAlongPath(p1, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p1, Vector3.new(44, 3.75, 52))
advanceVirtualClock(1.0)
local okPickCargo1, pickCargo1Reason = InteractionService:HandlePromptTriggered(r2Cargo1:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okPickCargo1 == true and pickCargo1Reason == "CargoCollected", "P1 must pick up CargoContainer_01")
assert(InventoryService:GetMissionItemCount(p1, "CargoContainer") == 1, "P1 must carry 1 CargoContainer")

-- Duplicate pickup of CargoContainer_01 must be rejected
advanceVirtualClock(1.0)
local okDupCargo1, dupCargo1Reason = ObjectiveService:HandleObjectiveInteraction(p1, r2Cargo1)
assert(okDupCargo1 == false and dupCargo1Reason == "CargoAlreadyCollected", "Duplicate pickup of CargoContainer_01 must be rejected")

-- Attempting to pick up CargoContainer_02 while P1 is already carrying CargoContainer_01 must be rejected
walkPlayerAlongPath(p1, Vector3.new(50, 3.75, 52))
advanceVirtualClock(1.0)
local okTwoCargo, twoCargoReason = InteractionService:HandlePromptTriggered(r2Cargo2:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okTwoCargo == false and twoCargoReason == "AlreadyCarryingCargo", "Carrying two heavy cargo containers simultaneously must be rejected")

-- Cooperative teammate P4 walks to Cargo Storage and picks up CargoContainer_02
walkPlayerAlongPath(p4, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p4, Vector3.new(50, 3.75, 52))
advanceVirtualClock(1.0)
local okPickCargo2, pickCargo2Reason = InteractionService:HandlePromptTriggered(r2Cargo2:FindFirstChildOfClass("ProximityPrompt"), p4)
assert(okPickCargo2 == true and pickCargo2Reason == "CargoCollected", "P4 must pick up CargoContainer_02")
assert(InventoryService:GetMissionItemCount(p4, "CargoContainer") == 1, "P4 must carry 1 CargoContainer")

-- P1 walks back to CargoDropPoint_01 (23, 2.2, -8) on Station Platform and delivers CargoContainer_01 -> progress 1/2
walkPlayerAlongPath(p1, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p1, Vector3.new(23, 3.75, -8))
advanceVirtualClock(1.0)
local okDeliver1, deliver1Reason = InteractionService:HandlePromptTriggered(r2DropPoint:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okDeliver1 == true and deliver1Reason == "CargoDelivered", "P1 must deliver CargoContainer_01 at CargoDropPoint_01")
assert(InventoryService:GetMissionItemCount(p1, "CargoContainer") == 0, "P1 carried CargoContainer must be consumed on delivery")

local rcProg1, rcReq1, rcDone1 = RoundService:GetObjectiveProgress()
assert(rcProg1 == 1 and rcReq1 == 2 and rcDone1 == false, "RecoverCargo progress must be 1/2 after first delivery")

-- Prevent duplicate delivery: P1 interacting with CargoDropPoint_01 again with 0 cargo must be rejected
advanceVirtualClock(1.0)
local okDupDeliver, dupDeliverReason = InteractionService:HandlePromptTriggered(r2DropPoint:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okDupDeliver == false and dupDeliverReason == "MissingCarriedCargo", "Duplicate delivery without cargo must be rejected")

-- P4 walks to CargoDropPoint_01 (23, 2.2, -8) and delivers CargoContainer_02 -> progress 2/2 (ObjectiveCompleted)
walkPlayerAlongPath(p4, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p4, Vector3.new(23, 3.75, -8))
advanceVirtualClock(1.0)
local okDeliver2, deliver2Reason = InteractionService:HandlePromptTriggered(r2DropPoint:FindFirstChildOfClass("ProximityPrompt"), p4)
assert(okDeliver2 == true and deliver2Reason == "ObjectiveCompleted", "P4 must deliver CargoContainer_02 and complete RecoverCargo")

local rcProg2, rcReq2, rcDone2 = RoundService:GetObjectiveProgress()
assert(rcProg2 == 2 and rcReq2 == 2 and rcDone2 == true, "RecoverCargo must be 2/2 completed")
print("[LUAU VM PASS] Priority 1 & 3 (RecoverCargo): 2 cargo containers, pickup/carry/delivery, and anti-duplication verified.")

RoundService:CleanupRound()

-- ----------------------------------------------------------------------------
-- TEST 6 (Priority 1, 2 & 3 — Mission 3): RepairSignal Independent & Cooperative Verification
-- (Activate 3 Communication Terminals)
-- ----------------------------------------------------------------------------
RoundService:_startNewIntermission("RepairSignal")
assert(ObjectiveService:GetActiveMissionId() == "RepairSignal", "Round 3 mission must be RepairSignal")
RoundService:_enterBoardingPhase()
RoundService:_lockCrewAndDepart()
RoundService:_enterExplorationPhase()

local stationModelR3 = Workspace.World.Runtime.ActiveStation:FindFirstChild("Station001_ForgottenTerminal")
local r3Sig1 = stationModelR3:FindFirstChild("SignalTerminal_01")
local r3Sig2 = stationModelR3:FindFirstChild("SignalTerminal_02")
local r3Sig3 = stationModelR3:FindFirstChild("SignalTerminal_03")
local r3Fuse1 = stationModelR3:FindFirstChild("FusePickup_01")
local r3Cargo1 = stationModelR3:FindFirstChild("CargoContainer_01")

-- Verify unrelated mission objects are rejected during RepairSignal
walkPlayerAlongPath(p1, Vector3.new(38, 3.75, -24))
advanceVirtualClock(1.0)
local okSigMis1, sigMis1Reason = ObjectiveService:HandleObjectiveInteraction(p1, r3Fuse1)
assert(okSigMis1 == false and sigMis1Reason == "MissionMismatch", "FusePickup must be rejected during RepairSignal")

walkPlayerAlongPath(p1, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p1, Vector3.new(44, 3.75, 52))
advanceVirtualClock(1.0)
local okSigMis2, sigMis2Reason = ObjectiveService:HandleObjectiveInteraction(p1, r3Cargo1)
assert(okSigMis2 == false and sigMis2Reason == "MissionMismatch", "CargoContainer must be rejected during RepairSignal")

-- P1 activates SignalTerminal_03 in Main Concourse (56, 3.0, 0) -> 1/3
walkPlayerAlongPath(p1, Vector3.new(54, 3.75, 0))
advanceVirtualClock(1.0)
local okTerm3, term3Reason = InteractionService:HandlePromptTriggered(r3Sig3:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okTerm3 == true and term3Reason == "SignalTerminalActivated", "P1 must activate SignalTerminal_03")

-- Duplicate activation of SignalTerminal_03 must be rejected
advanceVirtualClock(1.0)
local okDupTerm3, dupTerm3Reason = ObjectiveService:HandleObjectiveInteraction(p1, r3Sig3)
assert(okDupTerm3 == false and dupTerm3Reason == "TerminalAlreadyActivated", "Duplicate activation of SignalTerminal_03 must be rejected")

-- P4 walks into Control Room and activates SignalTerminal_01 (82, 3.0, -8) -> 2/3
walkPlayerAlongPath(p4, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p4, Vector3.new(78, 3.75, -6))
advanceVirtualClock(1.0)
local okTerm1, term1Reason = InteractionService:HandlePromptTriggered(r3Sig1:FindFirstChildOfClass("ProximityPrompt"), p4)
assert(okTerm1 == true and term1Reason == "SignalTerminalActivated", "P4 must activate SignalTerminal_01")

-- P4 walks to SignalTerminal_02 (82, 3.0, 8) and activates it -> 3/3 (ObjectiveCompleted)
walkPlayerAlongPath(p4, Vector3.new(78, 3.75, 6))
advanceVirtualClock(1.0)
local okTerm2, term2Reason = InteractionService:HandlePromptTriggered(r3Sig2:FindFirstChildOfClass("ProximityPrompt"), p4)
assert(okTerm2 == true and term2Reason == "ObjectiveCompleted", "P4 must activate SignalTerminal_02 and complete RepairSignal")

local rsProg, rsReq, rsDone = RoundService:GetObjectiveProgress()
assert(rsProg == 3 and rsReq == 3 and rsDone == true, "RepairSignal must be 3/3 completed")
print("[LUAU VM PASS] Priority 1 & 3 (RepairSignal): 3 communication terminals, duplicate & mismatch rejection verified.")

-- ----------------------------------------------------------------------------
-- TEST 7 (Priority 4): Verify Prepared Interfaces for The Hollow (MonsterService)
-- (State management, Noise events, Station navigation, Hiding locations,
--  Player detection, and Validated player elimination)
-- ----------------------------------------------------------------------------
-- 7A: The Hollow is spawned by the authoritative expedition lifecycle.
assert(MonsterService:IsEncounterActive() == true, "Hollow encounter must start when Station 001 exploration begins")
assert(MonsterService:GetState() == "PATROL", "Hollow must begin in PATROL")
local spawnedHollow = MonsterService:GetNpcModel()
assert(spawnedHollow ~= nil and spawnedHollow.Parent == HubService:GetActiveStationModel(), "Hollow rig must be parented to the active Station 001 model")
assert(spawnedHollow:FindFirstChild("HumanoidRootPart") ~= nil, "Hollow rig must expose a root part")
assert(spawnedHollow:FindFirstChildOfClass("Humanoid") ~= nil, "Hollow rig must expose a Humanoid")
local hollowStartPosition = MonsterService:GetCurrentPosition()
assert(MonsterService:StepAutonomousAI(0.2) == true, "A bounded AI decision step must run during exploration")
assert(MonsterService:IsEncounterActive() == true, "Single AI step must not terminate the encounter")
local okTrans1 = MonsterService:TransitionState("PATROL")
assert(okTrans1 == true and MonsterService:GetState() == "PATROL", "Must transition INACTIVE -> PATROL")
local okInvalidTrans = MonsterService:TransitionState("SEARCH")
assert(okInvalidTrans == false, "Must reject direct PATROL -> SEARCH transition")
local okTrans2 = MonsterService:TransitionState("INVESTIGATE", p1.UserId, Vector3.new(47, 3.75, 0))
assert(okTrans2 == true and MonsterService:GetState() == "INVESTIGATE", "Must transition PATROL -> INVESTIGATE")
local okTrans3 = MonsterService:TransitionState("CHASE", p1.UserId, Vector3.new(47, 3.75, 0))
assert(okTrans3 == true and MonsterService:GetState() == "CHASE", "Must transition INVESTIGATE -> CHASE")
local okTrans4 = MonsterService:TransitionState("SEARCH")
assert(okTrans4 == true and MonsterService:GetState() == "SEARCH", "Must transition CHASE -> SEARCH")
local okTrans5 = MonsterService:TransitionState("RETURN")
assert(okTrans5 == true and MonsterService:GetState() == "RETURN", "Must transition SEARCH -> RETURN")
local okTrans6 = MonsterService:TransitionState("PATROL")
assert(okTrans6 == true and MonsterService:GetState() == "PATROL", "Must transition RETURN -> PATROL")

-- 7B: Noise Events
MonsterService:EmitNoiseEvent(p1, "Walk", Vector3.new(47, 3.75, 10))
local flareNoise = MonsterService:EmitNoiseEvent(p4, "FlareDistraction", Vector3.new(50, 3.75, -10))
local strongestNoise = MonsterService:SelectStrongestNoiseStimulus(Vector3.new(47, 3.75, 0))
assert(strongestNoise ~= nil and strongestNoise.id == flareNoise.id, "SelectStrongestNoiseStimulus must prioritize high-intensity FlareDistraction")

-- 7C: Station Navigation Graph & Route Computation
local navGraph = MonsterService:GetStationNavigationGraph()
assert(navGraph["WP_PlatformSouth"] ~= nil and navGraph["WP_Control"] ~= nil, "Station 001 waypoint graph must be populated")
local routeToControl = MonsterService:ComputeWaypointRoute("WP_PlatformSouth", "WP_Control")
assert(#routeToControl >= 3, "ComputeWaypointRoute must find a multi-node path from PlatformSouth to ControlRoom")
assert(routeToControl[1].id == "WP_PlatformSouth" and routeToControl[#routeToControl].id == "WP_Control", "Route endpoints must match start and goal")

-- 7D: Hiding Locations & Player Detection
local hidingLocker2 = stationModelR3:FindFirstChild("HidingLocker_02_ConcourseNorth")
assert(hidingLocker2 ~= nil, "HidingLocker_02_ConcourseNorth must exist in Station 001")

walkPlayerAlongPath(p1, Vector3.new(36, 3.75, -30))
advanceVirtualClock(1.0)

-- Before hiding: P1 is in clear line-of-sight and FOV of an observer at (47, 3.75, -30) looking West (-1, 0, 0)
local detVisible = MonsterService:EvaluatePlayerDetection(
	Vector3.new(47, 3.75, -30),
	Vector3.new(-1, 0, 0),
	p1
)
assert(detVisible.detected == true and detVisible.hasLineOfSight == true and detVisible.isHidden == false, "Visible player in FOV and LOS must be detected")

-- P1 enters HidingLocker_02_ConcourseNorth -> P1 becomes hidden and immune to visual detection
local okHide, hideReason = InteractionService:HandlePromptTriggered(hidingLocker2:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okHide == true and hideReason == "EnteredHidingSpot", "P1 must enter hiding spot")
assert(MonsterService:IsPlayerHidden(p1) == true, "MonsterService must report P1 as hidden")
assert(p1.Character.HumanoidRootPart.Anchored == true, "Hidden player root must be server-anchored inside the locker")
assert((p1.Character.HumanoidRootPart.Position - Vector3.new(34, 3.5, -34)).Magnitude <= 0.01, "Hidden player must be moved into the locker interior")
assert(p1.Character.Humanoid.WalkSpeed == 0, "Hidden player must have movement disabled")

local detHidden = MonsterService:EvaluatePlayerDetection(
	Vector3.new(47, 3.75, -30),
	Vector3.new(-1, 0, 0),
	p1
)
assert(detHidden.detected == false and detHidden.isHidden == true, "Hidden player inside locker must NOT be visually detected")

-- Second player P4 attempting to enter the same occupied hiding locker must be rejected
walkPlayerAlongPath(p4, Vector3.new(47, 3.75, 0))
walkPlayerAlongPath(p4, Vector3.new(38, 3.75, -30))
advanceVirtualClock(1.0)
local okOccupied, occupiedReason = InteractionService:HandlePromptTriggered(hidingLocker2:FindFirstChildOfClass("ProximityPrompt"), p4)
assert(okOccupied == false and occupiedReason == "HidingSpotOccupied", "Occupied hiding spot must reject a second player")

-- Attacking a hidden player must be rejected
local canHitHidden, hitHiddenReason = MonsterService:CanEliminateTarget(Vector3.new(36, 3.75, -30), p1)
assert(canHitHidden == false and hitHiddenReason == "TargetHidden", "MonsterService must not eliminate a hidden player")

-- P1 exits hiding spot
advanceVirtualClock(1.0)
local okUnhide, unhideReason = InteractionService:HandlePromptTriggered(hidingLocker2:FindFirstChildOfClass("ProximityPrompt"), p1)
assert(okUnhide == true and unhideReason == "ExitedHidingSpot", "P1 must exit hiding spot")
assert(MonsterService:IsPlayerHidden(p1) == false, "P1 must no longer be hidden after exiting")
assert(p1.Character.HumanoidRootPart.Anchored == false, "Exiting must restore the character's original anchored state")
assert(p1.Character.Humanoid.WalkSpeed == GameConfig.WALK_SPEED, "Exiting must restore the character's original walk speed")
assert((p1.Character.HumanoidRootPart.Position - Vector3.new(34, 3.5, -30)).Magnitude <= 0.01, "Exiting must place the character at the configured safe exit position")

-- Attacking through a solid wall must be rejected (BlockedByWall)
-- ConcourseWall_EastNorth is at X = 65.5, Z = -24 (spanning Z = -42..-6); ControlRoomFloor spans Z = -18..+18.
walkPlayerAlongPath(p1, Vector3.new(63.5, 3.75, -16))
local canHitThroughWall, wallHitReason = MonsterService:CanEliminateTarget(Vector3.new(67.5, 3.75, -16), p1)
assert(canHitThroughWall == false and wallHitReason == "BlockedByWall", "Attack through a solid station wall must be rejected with BlockedByWall (got " .. tostring(wallHitReason) .. ")")

-- Valid close-range unobstructed attack eliminates target and enforces attack cooldown
local okElim, elimReason = MonsterService:ExecuteValidatedElimination(Vector3.new(60.0, 3.75, -16), p1, "TheHollow")
assert(okElim == true and elimReason == "Eliminated", "Valid close-range LOS attack must eliminate target")
assert(RoundService:GetPlayerStatus(p1) == "ELIMINATED", "P1 must be marked ELIMINATED after validated Hollow attack")

local okCooldownHit, cooldownReason = MonsterService:CanEliminateTarget(Vector3.new(38, 3.75, -30), p4)
assert(okCooldownHit == false and cooldownReason == "AttackCooldownActive", "Immediate repeat attack within cooldown window must be rejected")
print("[LUAU VM PASS] Priority 4: Prepared Hollow AI interfaces (detection, noise, state machine, waypoints, hiding spots, elimination) verified.")

-- Encounter lifecycle cleanup: no NPC or AI controller may survive round reset.
MonsterService:StopEncounter()
assert(MonsterService:IsEncounterActive() == false, "StopEncounter must deactivate the Hollow")
assert(MonsterService:GetNpcModel() == nil, "StopEncounter must destroy the spawned Hollow rig")
assert(MonsterService:GetState() == "INACTIVE", "StopEncounter must return the Hollow state to INACTIVE")

-- ----------------------------------------------------------------------------
-- TEST 8 (Fix 4 & Stage 9): All-Crew-Eliminated Immediate Round Termination
-- ----------------------------------------------------------------------------
for _, extraP in ipairs({ p5, p6, p7, p3 }) do
	extraP.Parent = nil
	Players.PlayerRemoving:Fire(extraP)
end

RoundService:CleanupRound()
p1:LoadCharacter()
p4:LoadCharacter()
RoundService:_startNewIntermission("RestorePower")
RoundService:_enterBoardingPhase()
RoundService:_lockCrewAndDepart()
RoundService:_enterExplorationPhase()

assert(RoundService:GetState() == "EXPLORATION", "New round must be in EXPLORATION")
assert(RoundService:GetPlayerStatus(p1) == "IN_EXPEDITION", "P1 must be IN_EXPEDITION")
assert(RoundService:GetPlayerStatus(p4) == "IN_EXPEDITION", "P4 must be IN_EXPEDITION")

local clockBeforeWipe = os.clock()

p1.Character:FindFirstChildOfClass("Humanoid").Health = 0
p1.Character:FindFirstChildOfClass("Humanoid").Died:Fire()
assert(RoundService:GetState() == "EXPLORATION", "Round must remain in EXPLORATION while P4 is still alive")

p4.Character:FindFirstChildOfClass("Humanoid").Health = 0
p4.Character:FindFirstChildOfClass("Humanoid").Died:Fire()

local clockAfterWipe = os.clock()
assert(
	clockAfterWipe == clockBeforeWipe,
	"All-crew-eliminated termination must happen immediately (0s elapsed) without waiting for the 180s phase timer"
)
assert(RoundService:GetState() == "RETURN", "RoundService must immediately transition to RETURN when all crew are eliminated")
assert(RoundService:GetLastOutcome() == "FAILED", "Round outcome must be FAILED when all crew are eliminated")

local completedFullTimer = RoundService:_waitPhaseOrAbort(180, true, "EXPLORATION")
assert(completedFullTimer == false, "_waitPhaseOrAbort must immediately abort and return false when phase was terminated early")
print("[LUAU VM PASS] Fix 4: All-crew-eliminated immediate round termination verified.")
print("[LUAU VM PASS] Priority 3: Complete 10-stage round lifecycle verified end-to-end.")
-- Regression coverage for objective completion vs extraction outcome.
assert(RoundService:DetermineRoundOutcome(0, true) == "FAILED", "No extraction must fail even when the objective is complete")
assert(RoundService:DetermineRoundOutcome(0, false) == "FAILED", "No extraction and incomplete objective must fail")
assert(RoundService:DetermineRoundOutcome(1, true) == "SUCCESS", "Completed objective plus extraction must succeed")
assert(RoundService:DetermineRoundOutcome(1, false) == "PARTIAL", "Extraction without objective completion must be partial")
assert(RoundService:DetermineRoundOutcome(6, true) == "SUCCESS", "Full crew extraction with objective completion must succeed")
assert(RoundService:DetermineRoundOutcome(2, false) == "PARTIAL", "Mixed crew extraction without objective completion must be partial")
print("[LUAU VM PASS] Issue #1: objective/extraction result combinations verified.")
print("ALL_LUAU_VM_TESTS_PASSED")
`;

  const fullScript = [robloxEnvPreamble, ...moduleBlocks, luauAssertions].join('\n');
  const tempScriptPath = '/tmp/nightline_vm_test_bundle.luau';
  fs.writeFileSync(tempScriptPath, fullScript, 'utf8');

  const stdout = execFileSync(luauBin, [tempScriptPath], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
  });

  const stdoutLines = stdout
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);

  return {
    passed: stdoutLines.includes('ALL_LUAU_VM_TESTS_PASSED'),
    stdout,
    stdoutLines,
    assertionsSummary: stdoutLines.join(' | '),
  };
}

export function runRojoAndStaticToolchainChecks(): {
  rojoVersion: string;
  rojoBuildOk: boolean;
  rbxlSizeBytes: number;
  luauAnalyzeOk: boolean;
  luauLspOutput: string;
  styluaOk: boolean;
  seleneOk: boolean;
  seleneOutput: string;
} {
  const {
    luauAnalyzeBin,
    luauLspBin,
    rojoBin,
    seleneBin,
    styluaBin,
    globalTypesPath,
  } = ensureToolchainInstalled();

  const rojoVersion = execFileSync(rojoBin, ['--version'], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
  }).trim();

  const sourcemapPath = '/tmp/sourcemap.json';
  const rbxlPath = '/tmp/NIGHTLINE_Last_Train.rbxl';

  execFileSync(rojoBin, ['sourcemap', 'default.project.json', '-o', sourcemapPath], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
  });

  execFileSync(rojoBin, ['build', 'default.project.json', '-o', rbxlPath], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
  });

  const rbxlStats = fs.statSync(rbxlPath);

  // Verify official Luau CLI static analyzer binary works on pure Luau modules
  const luauAnalyzeOutput = execFileSync(
    luauAnalyzeBin,
    ['roblox/ReplicatedStorage/Shared/Types/NetworkTypes.lua'],
    {
      cwd: ROOT_DIR,
      encoding: 'utf8',
    }
  ).trim();

  // Run full Rojo-sourcemap-aware strict Luau typechecking with Roblox globalTypes.d.luau
  const luauLspOutput = execFileSync(
    luauLspBin,
    [
      'analyze',
      '--base-luaurc=.luaurc',
      `--sourcemap=${sourcemapPath}`,
      `--definitions=${globalTypesPath}`,
      'roblox',
    ],
    {
      cwd: ROOT_DIR,
      encoding: 'utf8',
    }
  ).trim();

  execFileSync(styluaBin, ['--check', 'roblox'], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
  });

  // Run selene using TOOLS_DIR as working directory so roblox.yml stays inside TOOLS_DIR
  // and never pollutes the git repository root.
  const toolsRobloxYml = path.join(TOOLS_DIR, 'roblox.yml');
  if (!fs.existsSync(toolsRobloxYml)) {
    execFileSync(seleneBin, ['generate-roblox-std'], {
      cwd: TOOLS_DIR,
      encoding: 'utf8',
    });
  }
  const toolsSeleneToml = path.join(TOOLS_DIR, 'selene.toml');
  fs.writeFileSync(
    toolsSeleneToml,
    fs.readFileSync(path.join(ROOT_DIR, 'selene.toml'), 'utf8'),
    'utf8'
  );

  const seleneOutput = execFileSync(
    seleneBin,
    ['--config', toolsSeleneToml, path.join(ROOT_DIR, 'roblox')],
    {
      cwd: TOOLS_DIR,
      encoding: 'utf8',
    }
  ).trim();

  return {
    rojoVersion,
    rojoBuildOk: rbxlStats.size > 0,
    rbxlSizeBytes: rbxlStats.size,
    luauAnalyzeOk: luauAnalyzeOutput === '',
    luauLspOutput,
    styluaOk: true,
    seleneOk: true,
    seleneOutput,
  };
}
