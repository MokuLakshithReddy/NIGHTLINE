--!strict
--[[
	ClientBootstrap.client.lua
	Client entry point for NIGHTLINE: LAST TRAIN (Section 9.4).
	Waits for replicated remotes, initializes UIController, InputController, and InteractionController, and starts them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesRegistry =
	require(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemotesRegistry"))

local ControllersFolder = script.Parent:WaitForChild("Controllers")
local UIController = require(ControllersFolder:WaitForChild("UIController"))
local InputController = require(ControllersFolder:WaitForChild("InputController"))
local InteractionController = require(ControllersFolder:WaitForChild("InteractionController"))

local function bootstrapClient()
	local remotes = RemotesRegistry.WaitForClientRemotes(10)

	UIController:Init({
		remotes = remotes,
	})
	InputController:Init({
		uiController = UIController,
		remotes = remotes,
	})
	InteractionController:Init()

	UIController:Start()
	InputController:Start()
	InteractionController:Start()
end

local ok, err = pcall(function()
	bootstrapClient()
end)
if not ok then
	warn("[NIGHTLINE Client] Failed to bootstrap client controllers:", err)
end
