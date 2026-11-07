// luauVmRunner.ts
// Executes the actual NIGHTLINE Roblox Luau modules (/roblox/) inside the
// official Luau VM binary (luau), alongside luau-cli (luau-analyze), luau-lsp analyze,
// selene, stylua, and rojo build (Rojo 7.7.1).
//
// IMPORTANT HARNESS BOUNDARY:
// The Luau VM harness below executes the real Luau source files from `/roblox` inside
// the official `luau` runtime against a deterministic DataModel API contract shim.
// It deliberately does NOT pretend to simulate Roblox 3D rigid-body physics, collision
// geometry, or automatic C++ character respawning:
//   1. Setting `Humanoid.Health = 0` marks that Humanoid instance permanently dead.
//      Attempting to set `Humanoid.Health > 0` on a dead Humanoid or calling `PivotTo`
//      on a dead Character throws an explicit runtime error.
//   2. Respawning requires explicitly calling `player:LoadCharacter()`, which allocates
//      a brand-new `Model` + `Humanoid` + `HumanoidRootPart` and fires `player.CharacterAdded`.

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
		-- Do not run infinite while-true background loops automatically during synchronous unit assertions
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
-- Execute Real NIGHTLINE Luau Services & Verify All Remediation Fixes
-- ============================================================================

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemotesRegistry = require(ReplicatedStorage.Remotes.RemotesRegistry)
local SecurityService = require(ServerScriptService.Services.SecurityService)
local MovementService = require(ServerScriptService.Services.MovementService)
local HubService = require(ServerScriptService.Services.HubService)
local InventoryService = require(ServerScriptService.Services.InventoryService)
local RoundService = require(ServerScriptService.Services.RoundService)
local InteractionService = require(ServerScriptService.Services.InteractionService)
local InputController = require(StarterPlayer.StarterPlayerScripts.Controllers.InputController)

local remotes = RemotesRegistry.InitializeServerRemotes()

SecurityService:Init()
MovementService:Init({ remotes = remotes, securityService = SecurityService })
HubService:Init()
HubService:SetMovementService(MovementService)
InventoryService:Init({ remotes = remotes, securityService = SecurityService })
RoundService:Init({
	remotes = remotes,
	securityService = SecurityService,
	hubService = HubService,
	inventoryService = InventoryService,
	movementService = MovementService,
})
MovementService:SetRoundService(RoundService)
InventoryService:SetRoundService(RoundService)
InteractionService:Init({
	securityService = SecurityService,
	inventoryService = InventoryService,
	roundService = RoundService,
})

SecurityService:Start()
MovementService:Start()
HubService:Start()
InventoryService:Start()
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

	-- Explicit LoadCharacter method that destroys the old character, constructs a
	-- brand-new Character + Humanoid instance, and fires CharacterAdded.
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

-- ----------------------------------------------------------------------------
-- TEST 1 (Issue 02): Explicit Spawn-Slot Allocation & Release on Departure
-- ----------------------------------------------------------------------------
local p1 = createMockPlayer(101, "Avery")
local p2 = createMockPlayer(102, "Morgan")
local p3 = createMockPlayer(103, "Vance")

assert(RoundService:GetPlayerSpawnSlot(p1) == 1, "P1 must receive slot 1")
assert(RoundService:GetPlayerSpawnSlot(p2) == 2, "P2 must receive slot 2")
assert(RoundService:GetPlayerSpawnSlot(p3) == 3, "P3 must receive slot 3")

-- Disconnect P2 (slot 2) -> Slot 2 must be freed while P1 keeps slot 1 and P3 keeps slot 3
p2.Parent = nil
Players.PlayerRemoving:Fire(p2)
assert(RoundService:GetPlayerSpawnSlot(p1) == 1, "P1 must retain slot 1")
assert(RoundService:GetPlayerSpawnSlot(p3) == 3, "P3 must retain slot 3")

-- New player P4 joins -> Must receive freed slot 2 (not already-occupied slot 3!)
local p4 = createMockPlayer(104, "Sloane")
assert(RoundService:GetPlayerSpawnSlot(p4) == 2, "P4 must receive freed slot 2 without colliding with P3")
print("[LUAU VM PASS] Issue 02: Explicit spawn-slot allocation & release verified.")

-- ----------------------------------------------------------------------------
-- TEST 2 (Fix 3 & Issue 03): Horizontal + Vertical Movement Validation
-- (Legitimate jumps, gravity falls, server teleports vs horizontal/vertical exploits)
-- ----------------------------------------------------------------------------
remotes.RequestSprint._mockLocalPlayer = p1
InputController:Init({ uiController = nil, remotes = remotes })
InputController:Start()

InputController:RequestSprint(true)
local p1Humanoid = p1.Character:FindFirstChildOfClass("Humanoid")
assert(p1Humanoid.WalkSpeed == GameConfig.SPRINT_SPEED, "Server MovementService must set WalkSpeed to SPRINT_SPEED (22)")

InputController:RequestSprint(false)
assert(p1Humanoid.WalkSpeed == GameConfig.WALK_SPEED, "Server MovementService must restore WalkSpeed to WALK_SPEED (14)")

-- Advance clock past initial spawn teleport grace window
advanceVirtualClock(2.0)
local okBaseline = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okBaseline == true, "Baseline stationary position must be valid")

-- 2A: Legitimate Jump (+11 studs upward in 0.25s) -> Must be accepted
local posBeforeJump = p1.Character.HumanoidRootPart.Position
advanceVirtualClock(0.25)
p1.Character:PivotTo(CFrame.new(posBeforeJump.X, posBeforeJump.Y + 11, posBeforeJump.Z - 3))
local okJump, jumpReason = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okJump == true and jumpReason == "ValidMovement", "Legitimate upward jump (+11 studs Y in 0.25s) must be accepted")

-- 2B: Legitimate Gravity Fall (-28 studs downward in 0.25s) -> Must be accepted
local posBeforeFall = p1.Character.HumanoidRootPart.Position
advanceVirtualClock(0.25)
p1.Character:PivotTo(CFrame.new(posBeforeFall.X, posBeforeFall.Y - 28, posBeforeFall.Z - 2))
local okFall, fallReason = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okFall == true and fallReason == "ValidMovement", "Legitimate gravity fall (-28 studs Y in 0.25s) must be accepted")

-- 2C: Server-Authorized Teleport (NotifyServerTeleport) -> Must be accepted
local authorizedTarget = Vector3.new(-5, 3, 12)
MovementService:NotifyServerTeleport(p1, authorizedTarget)
p1.Character:PivotTo(CFrame.new(authorizedTarget))
advanceVirtualClock(0.1)
local okAuthTeleport, authTeleportReason = MovementService:ValidatePlayerMovement(p1, 0.1)
assert(okAuthTeleport == true and authTeleportReason == "TeleportGrace", "Server-authorized teleport must be accepted within grace window")

-- Advance past teleport grace window before testing exploits
advanceVirtualClock(1.5)
MovementService:ValidatePlayerMovement(p1, 0.25)

-- 2D: Horizontal Speed/Teleport Exploit (90 studs in 0.25s) -> Must be rejected & rubberbanded
local validBeforeHorizHack = p1.Character.HumanoidRootPart.Position
advanceVirtualClock(0.25)
p1.Character:PivotTo(CFrame.new(validBeforeHorizHack.X, validBeforeHorizHack.Y, validBeforeHorizHack.Z - 90))
local okHorizHack, horizHackReason = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okHorizHack == false and horizHackReason == "RubberbandedSpeedAnomaly", "Horizontal speed exploit must be rejected")
assert(
	(p1.Character.HumanoidRootPart.Position - validBeforeHorizHack).Magnitude < 0.01,
	"MovementService must rubberband horizontal speed exploit back to last valid server position"
)

-- 2E: Vertical Upward Fly/SuperJump Exploit (+45 studs Y in 0.25s) -> Must be rejected & rubberbanded
local validBeforeUpHack = p1.Character.HumanoidRootPart.Position
advanceVirtualClock(0.25)
p1.Character:PivotTo(CFrame.new(validBeforeUpHack.X, validBeforeUpHack.Y + 45, validBeforeUpHack.Z))
local okUpHack, upHackReason = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okUpHack == false and upHackReason == "RubberbandedVerticalUpwardAnomaly", "Vertical upward fly exploit must be rejected")
assert(
	(p1.Character.HumanoidRootPart.Position - validBeforeUpHack).Magnitude < 0.01,
	"MovementService must rubberband vertical upward exploit back to last valid server position"
)

-- 2F: Vertical Downward Noclip Exploit (-120 studs Y in 0.25s) -> Must be rejected & rubberbanded
local validBeforeDownHack = p1.Character.HumanoidRootPart.Position
advanceVirtualClock(0.25)
p1.Character:PivotTo(CFrame.new(validBeforeDownHack.X, validBeforeDownHack.Y - 120, validBeforeDownHack.Z))
local okDownHack, downHackReason = MovementService:ValidatePlayerMovement(p1, 0.25)
assert(okDownHack == false and downHackReason == "RubberbandedVerticalDownwardAnomaly", "Vertical downward noclip exploit must be rejected")
assert(
	(p1.Character.HumanoidRootPart.Position - validBeforeDownHack).Magnitude < 0.01,
	"MovementService must rubberband vertical downward exploit back to last valid server position"
)
print("[LUAU VM PASS] Fix 3 & Issue 03: Horizontal + vertical movement validation (jumps, falls, teleports, exploits) verified.")

-- ----------------------------------------------------------------------------
-- TEST 3 (Fix 1): All 6 Station Entry Spawns Are Strictly Outside Extraction Zone
-- & No Player Is Automatically Extracted Upon Entering Station or Extraction Phase
-- ----------------------------------------------------------------------------
local p5 = createMockPlayer(105, "Kestrel")
local p6 = createMockPlayer(106, "Rook")
local p7 = createMockPlayer(107, "Vesper")
local allSixPlayers = { p1, p4, p3, p5, p6, p7 }

assert(#allSixPlayers == 6, "Must have 6 active players occupying slots 1..6")
for slotIdx = 1, 6 do
	local spawnPos = GameConfig.STATION_ENTRY_SPAWNS[slotIdx]
	assert(spawnPos ~= nil, "Station entry spawn must exist for slot " .. tostring(slotIdx))
	assert(
		HubService:IsPositionInExtractionZone(spawnPos) == false,
		"Station entry spawn slot " .. tostring(slotIdx) .. " must be strictly outside ExtractionPlatformZone"
	)
end

RoundService:_startNewIntermission()
RoundService:_enterBoardingPhase()
RoundService:_lockCrewAndDepart()
RoundService:_enterExplorationPhase()

assert(RoundService:GetState() == "EXPLORATION", "RoundService must be in EXPLORATION")

for _, player in ipairs(allSixPlayers) do
	assert(RoundService:GetPlayerStatus(player) == "IN_EXPEDITION", player.Name .. " must be IN_EXPEDITION upon station arrival")
	assert(
		HubService:IsPlayerInExtractionZone(player) == false,
		player.Name .. " (slot " .. tostring(RoundService:GetPlayerSpawnSlot(player)) .. ") must NOT spawn inside ExtractionPlatformZone"
	)
end

-- Transition into EXTRACTION while all 6 players remain at their initial station spawn positions:
-- Verify that NO player is automatically extracted!
RoundService:_enterExtractionPhase()
assert(RoundService:GetState() == "EXTRACTION", "RoundService must be in EXTRACTION")

for _, player in ipairs(allSixPlayers) do
	local okAutoExtract, autoExtractReason = RoundService:TryExtractPlayer(player)
	assert(
		okAutoExtract == false and autoExtractReason == "OutOfExtractionZone",
		player.Name .. " at initial station entry spawn must NOT be extractable without walking to the extraction zone"
	)
	assert(RoundService:GetPlayerStatus(player) == "IN_EXPEDITION", player.Name .. " must remain IN_EXPEDITION")
end
print("[LUAU VM PASS] Fix 1: All 6 station spawn positions verified outside extraction zone; zero auto-extractions.")

-- ----------------------------------------------------------------------------
-- TEST 4 (Fix 2 & Issue 01): Elimination & Fresh-Character Respawn Flow
-- (No in-place Humanoid.Health restoration or dead-character pivoting in Humanoid.Died)
-- ----------------------------------------------------------------------------
local deadCharacterRef = p1.Character
local deadHumanoidRef = deadCharacterRef:FindFirstChildOfClass("Humanoid")
local posAtDeath = deadCharacterRef.HumanoidRootPart.Position

-- P1 takes fatal damage -> Humanoid.Died fires
-- Note: Our mock Humanoid & Character throw a Lua error if any code inside Humanoid.Died
-- tries to set Health > 0 on deadHumanoidRef or call deadCharacterRef:PivotTo(...)!
deadHumanoidRef.Health = 0
deadHumanoidRef.Died:Fire()

assert(RoundService:GetPlayerStatus(p1) == "ELIMINATED", "Humanoid.Died must mark P1 ELIMINATED")
assert(deadHumanoidRef.Health == 0, "Dead Humanoid health must remain 0 (never restored in-place)")
assert(
	(deadCharacterRef.HumanoidRootPart.Position - posAtDeath).Magnitude < 0.001,
	"Dead character must NOT be pivoted during Humanoid.Died"
)

-- Now simulate Roblox spawning a brand-new Character model via p1:LoadCharacter()
local freshCharacterRef = p1:LoadCharacter()
local freshHumanoidRef = freshCharacterRef:FindFirstChildOfClass("Humanoid")

assert(freshCharacterRef ~= deadCharacterRef, "Respawn must create a fresh Character instance")
assert(freshHumanoidRef ~= deadHumanoidRef, "Respawn must create a fresh Humanoid instance")
assert(freshHumanoidRef.Health == GameConfig.DEFAULT_MAX_HEALTH, "Fresh character must have full health")
assert(RoundService:GetPlayerStatus(p1) == "ELIMINATED", "Respawning eliminated player must remain ELIMINATED")
assert(
	freshCharacterRef.HumanoidRootPart.Position.Z >= 35,
	"Fresh character for ELIMINATED player must be spawned in Hub Recovery Bay (Z >= 35)"
)

-- Verify that a living IN_EXPEDITION player (p3) who gets a fresh character via LoadCharacter()
-- is spawned at their Station 001 entry spawn (Z >= 18), strictly outside the extraction zone
local p3FreshChar = p3:LoadCharacter()
assert(RoundService:GetPlayerStatus(p3) == "IN_EXPEDITION", "P3 must still be IN_EXPEDITION")
assert(p3FreshChar.HumanoidRootPart.Position.Z >= 18, "Living expedition player respawn must route to Station 001 entry spawn (Z >= 18)")
assert(HubService:IsPlayerInExtractionZone(p3) == false, "Respawned expedition player must be outside extraction zone")
print("[LUAU VM PASS] Fix 2 & Issue 01: Dead characters are never healed/pivoted in-place; fresh-character respawn flow verified.")

-- ----------------------------------------------------------------------------
-- TEST 5 (Issue 04): Physical Extraction Zone Proximity & Left-Behind Validation
-- ----------------------------------------------------------------------------
-- P4 moves inside the physical ExtractionPlatformZone (15, 2.5, -8) and extracts -> Must succeed!
MovementService:NotifyServerTeleport(p4, GameConfig.EXTRACTION_ZONE_POSITION)
p4.Character:PivotTo(CFrame.new(GameConfig.EXTRACTION_ZONE_POSITION))
local okNearExtract, nearExtractReason = RoundService:TryExtractPlayer(p4)
assert(okNearExtract == true and nearExtractReason == "Extracted", "Player inside physical extraction zone must extract")
assert(RoundService:GetPlayerStatus(p4) == "EXTRACTED", "P4 status must be EXTRACTED")

-- Departure deadline hits (_enterReturnPhase):
-- P4 (EXTRACTED) survives; P3, P5, P6, P7 (still at station entry spawns outside extraction zone) are marked ELIMINATED!
RoundService:_enterReturnPhase()
assert(RoundService:GetPlayerStatus(p4) == "EXTRACTED", "P4 must remain EXTRACTED")
assert(RoundService:GetPlayerStatus(p3) == "ELIMINATED", "P3 who stayed at station spawn must be marked ELIMINATED")
assert(RoundService:GetLastOutcome() == "SUCCESS", "Round outcome must be SUCCESS because P4 extracted")
print("[LUAU VM PASS] Issue 04: Physical extraction zone proximity & left-behind elimination verified.")

-- ----------------------------------------------------------------------------
-- TEST 6 (Fix 4): All-Crew-Eliminated Immediate Round Termination
-- (Round terminates immediately without waiting for the 180s EXPLORATION timer)
-- ----------------------------------------------------------------------------
-- Disconnect extra players p5, p6, p7 so we have a clean 2-player crew (p1, p4)
for _, extraP in ipairs({ p5, p6, p7, p3 }) do
	extraP.Parent = nil
	Players.PlayerRemoving:Fire(extraP)
end

RoundService:CleanupRound()
RoundService:_startNewIntermission()
RoundService:_enterBoardingPhase()
RoundService:_lockCrewAndDepart()
RoundService:_enterExplorationPhase()

assert(RoundService:GetState() == "EXPLORATION", "New round must be in EXPLORATION")
assert(RoundService:GetPlayerStatus(p1) == "IN_EXPEDITION", "P1 must be IN_EXPEDITION")
assert(RoundService:GetPlayerStatus(p4) == "IN_EXPEDITION", "P4 must be IN_EXPEDITION")

local clockBeforeWipe = os.clock()

-- Eliminate P1 -> P4 is still alive so round continues in EXPLORATION
p1.Character:FindFirstChildOfClass("Humanoid").Health = 0
p1.Character:FindFirstChildOfClass("Humanoid").Died:Fire()
assert(RoundService:GetState() == "EXPLORATION", "Round must remain in EXPLORATION while P4 is still alive")

-- Eliminate P4 (last surviving expedition crew member) -> Round must IMMEDIATELY enter RETURN with FAILED outcome!
p4.Character:FindFirstChildOfClass("Humanoid").Health = 0
p4.Character:FindFirstChildOfClass("Humanoid").Died:Fire()

local clockAfterWipe = os.clock()
assert(
	clockAfterWipe == clockBeforeWipe,
	"All-crew-eliminated termination must happen immediately (0s elapsed) without waiting for the 180s phase timer"
)
assert(RoundService:GetState() == "RETURN", "RoundService must immediately transition to RETURN when all crew are eliminated")
assert(RoundService:GetLastOutcome() == "FAILED", "Round outcome must be FAILED when all crew are eliminated")

-- Also verify _waitPhaseOrAbort(180, true, "EXPLORATION") returns false immediately when state already changed
local completedFullTimer = RoundService:_waitPhaseOrAbort(180, true, "EXPLORATION")
assert(completedFullTimer == false, "_waitPhaseOrAbort must immediately abort and return false when phase was terminated early")
print("[LUAU VM PASS] Fix 4: All-crew-eliminated immediate round termination verified.")
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
