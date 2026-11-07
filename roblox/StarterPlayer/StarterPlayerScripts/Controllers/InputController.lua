--!strict
--[[
	InputController.lua
	Handles cross-platform player input across Keyboard/Mouse, Mobile Touch, and Gamepad (Section 8.2).
	Issue 03 Fix: Sends sprint intents to the server via RequestSprint RemoteEvent so MovementService
	validates sprint eligibility and owns authoritative Humanoid.WalkSpeed on the server.
]]

local ContextActionService = game:GetService("ContextActionService")

local ACTION_SPRINT = "NightlineSprintAction"
local ACTION_SLOT_1 = "NightlineSlot1Action"
local ACTION_SLOT_2 = "NightlineSlot2Action"

local InputController: { [string]: any } = {
	Name = "InputController",
	_uiController = nil :: any,
	_remotes = nil :: { [string]: RemoteEvent }?,
	_isSprinting = false,
}

function InputController:Init(dependencies: {
	uiController: any,
	remotes: { [string]: RemoteEvent }?,
})
	self._uiController = dependencies.uiController
	self._remotes = dependencies.remotes
	self._isSprinting = false
end

function InputController:Start()
	ContextActionService:BindAction(
		ACTION_SPRINT,
		function(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
			if inputState == Enum.UserInputState.Begin then
				self:RequestSprint(true)
			elseif
				inputState == Enum.UserInputState.End
				or inputState == Enum.UserInputState.Cancel
			then
				self:RequestSprint(false)
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

function InputController:RequestSprint(wantsSprint: boolean)
	if self._isSprinting == wantsSprint then
		return
	end
	self._isSprinting = wantsSprint
	local remotes = self._remotes
	if remotes and remotes.RequestSprint then
		remotes.RequestSprint:FireServer(wantsSprint)
	end
end

return InputController
