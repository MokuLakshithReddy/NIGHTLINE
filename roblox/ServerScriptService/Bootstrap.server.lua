--!strict
--[[
	Bootstrap.server.lua
	Authoritative server bootstrap for NIGHTLINE: LAST TRAIN (Section 9.4 & Section 10).
	1. Creates and validates ReplicatedStorage.Remotes.
	2. Initializes server services in dependency order (including MovementService).
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

	-- 3. Start services
	SecurityService:Start()
	MovementService:Start()
	HubService:Start()
	InventoryService:Start()
	RoundService:Start()
	InteractionService:Start()

	print("[NIGHTLINE Server] All Milestone 0 & Milestone 1 services initialized and running.")
end

local ok, err = pcall(function()
	bootstrapServer()
end)
if not ok then
	warn("[NIGHTLINE Server] Fatal error during server bootstrap:", err)
end
