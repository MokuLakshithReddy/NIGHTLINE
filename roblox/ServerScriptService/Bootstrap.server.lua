--!strict
--[[
	Bootstrap.server.lua
	Authoritative server bootstrap for NIGHTLINE: LAST TRAIN (Section 9.4 & Section 10).
	1. Creates and validates ReplicatedStorage.Remotes.
	2. Initializes server services in dependency order (including ObjectiveService and MonsterService).
	3. Starts all services and logs readiness.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemotesRegistry = require(ReplicatedStorage.Remotes.RemotesRegistry)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local ServicesFolder = ServerScriptService:WaitForChild("Services")
local SecurityService = require(ServicesFolder.SecurityService)
local MovementService = require(ServicesFolder.MovementService)
local HubService = require(ServicesFolder.HubService)
local InventoryService = require(ServicesFolder.InventoryService)
local ObjectiveService = require(ServicesFolder.ObjectiveService)
local MonsterService = require(ServicesFolder.MonsterService)
local RoundService = require(ServicesFolder.RoundService)
local InteractionService = require(ServicesFolder.InteractionService)

local function bootstrapServer()
	print(
		string.format(
			"[NIGHTLINE Server] Bootstrapping %s (%s)...",
			GameConfig.GAME_TITLE,
			GameConfig.VERSION
		)
	)

	-- 1. Create and validate all RemoteEvents
	local remotes = RemotesRegistry.InitializeServerRemotes()

	-- 2. Initialize services in strict dependency order
	SecurityService:Init()
	MovementService:Init({
		remotes = remotes,
		securityService = SecurityService,
	})
	HubService:Init()
	HubService:SetMovementService(MovementService)

	InventoryService:Init({
		remotes = remotes,
		securityService = SecurityService,
	})

	ObjectiveService:Init({
		remotes = remotes,
		securityService = SecurityService,
		hubService = HubService,
		inventoryService = InventoryService,
	})

	MonsterService:Init({
		securityService = SecurityService,
		hubService = HubService,
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
	MovementService:SetMonsterService(MonsterService)
	HubService:SetMonsterService(MonsterService)
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

	-- 3. Start services
	SecurityService:Start()
	MovementService:Start()
	HubService:Start()
	InventoryService:Start()
	ObjectiveService:Start()
	MonsterService:Start()
	RoundService:Start()
	InteractionService:Start()

	print(
		"[NIGHTLINE Server] All server services (including ObjectiveService & MonsterService interfaces) initialized and running."
	)
end

local ok, err = pcall(function()
	bootstrapServer()
end)
if not ok then
	warn("[NIGHTLINE Server] Fatal error during server bootstrap:", err)
end
