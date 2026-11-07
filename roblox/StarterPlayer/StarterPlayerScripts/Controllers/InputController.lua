--!strict
--[[
	InputController.lua
	Handles cross-platform player input across Keyboard/Mouse, Mobile Touch, and Gamepad (Section 8.2).
	Binds:
	- Sprint: LeftShift (PC), ButtonL3 (Gamepad), Touch Button (Mobile)
	- Equipment Slot 1: KeyCode.One / DPadLeft
	- Equipment Slot 2: KeyCode.Two / DPadRight
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local ACTION_SPRINT = "NightlineSprintAction"
local ACTION_SLOT_1 = "NightlineSlot1Action"
local ACTION_SLOT_2 = "NightlineSlot2Action"

local InputController = {
	Name = "InputController",
	_uiController = nil :: any,
	_isSprinting = false,
}

function InputController:Init(dependencies: { uiController: any })
	self._uiController = dependencies.uiController
	self._isSprinting = false
end

function InputController:Start()
	ContextActionService:BindAction(
		ACTION_SPRINT,
		function(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
			if inputState == Enum.UserInputState.Begin then
				self:SetSprinting(true)
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				self:SetSprinting(false)
			end
			return Enum.ContextActionResult.Pass
		end,
		true, -- Creates mobile touch button automatically
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:SetTitle(ACTION_SPRINT, "Sprint")

	ContextActionService:BindAction(
		ACTION_SLOT_1,
		function(_actionName: string, inputState: Enum.UserInputState)
			if inputState == Enum.UserInputState.Begin and self._uiController then
				self._uiController:SelectEquipmentSlot(1)
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.KeyCode.One,
		Enum.KeyCode.DPadLeft
	)

	ContextActionService:BindAction(
		ACTION_SLOT_2,
		function(_actionName: string, inputState: Enum.UserInputState)
			if inputState == Enum.UserInputState.Begin and self._uiController then
				self._uiController:SelectEquipmentSlot(2)
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.KeyCode.Two,
		Enum.KeyCode.DPadRight
	)
end

function InputController:SetSprinting(sprinting: boolean)
	self._isSprinting = sprinting
	local localPlayer = Players.LocalPlayer
	if not localPlayer or not localPlayer.Character then
		return
	end
	local humanoid = localPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.WalkSpeed = if sprinting then GameConfig.SPRINT_SPEED else GameConfig.WALK_SPEED
	end
end

return InputController
