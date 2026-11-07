--!strict
--[[
	InteractionController.lua
	Provides client-side visual highlight feedback when a player approaches a ProximityPrompt in the Train Hub.
	Authoritative validation remains on the server in InteractionService (Section 6.2).
]]

local ProximityPromptService = game:GetService("ProximityPromptService")

local InteractionController: { [string]: any } = {
	Name = "InteractionController",
	_activeHighlight = nil :: Highlight?,
}

function InteractionController:Init()
	self._activeHighlight = nil
end

function InteractionController:Start()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		self:_onPromptShown(prompt)
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		self:_onPromptHidden(prompt)
	end)
end

function InteractionController:_onPromptShown(prompt: ProximityPrompt)
	self:_clearHighlight()
	local adornee = prompt.Parent
	if not adornee or not adornee:IsA("BasePart") then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "NightlinePromptHighlight"
	highlight.Adornee = adornee
	highlight.FillColor = Color3.fromRGB(56, 189, 248)
	highlight.FillTransparency = 0.78
	highlight.OutlineColor = Color3.fromRGB(245, 158, 11)
	highlight.OutlineTransparency = 0.1
	highlight.Parent = adornee
	self._activeHighlight = highlight
end

function InteractionController:_onPromptHidden(_prompt: ProximityPrompt)
	self:_clearHighlight()
end

function InteractionController:_clearHighlight()
	if self._activeHighlight then
		self._activeHighlight:Destroy()
		self._activeHighlight = nil
	end
end

return InteractionController
