--!strict
--[[
	RemotesRegistry.lua
	Authoritative contract for Client-Server RemoteEvents (Section 11).
	Creates RemoteEvents on the server during bootstrap and resolves them safely on the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type RemoteName =
	"RoundStateChanged"
	| "ObjectiveUpdated"
	| "PlayerStatusUpdated"
	| "InventoryUpdated"
	| "Notification"
	| "RequestEquipment"
	| "RequestDestinationVote"
	| "RequestSprint"

local REMOTE_NAMES: { RemoteName } = table.freeze({
	"RoundStateChanged" :: RemoteName,
	"ObjectiveUpdated" :: RemoteName,
	"PlayerStatusUpdated" :: RemoteName,
	"InventoryUpdated" :: RemoteName,
	"Notification" :: RemoteName,
	"RequestEquipment" :: RemoteName,
	"RequestDestinationVote" :: RemoteName,
	"RequestSprint" :: RemoteName,
})

local RemotesRegistry = {
	Names = table.freeze({
		RoundStateChanged = "RoundStateChanged" :: RemoteName,
		ObjectiveUpdated = "ObjectiveUpdated" :: RemoteName,
		PlayerStatusUpdated = "PlayerStatusUpdated" :: RemoteName,
		InventoryUpdated = "InventoryUpdated" :: RemoteName,
		Notification = "Notification" :: RemoteName,
		RequestEquipment = "RequestEquipment" :: RemoteName,
		RequestDestinationVote = "RequestDestinationVote" :: RemoteName,
		RequestSprint = "RequestSprint" :: RemoteName,
	}),
	AllNames = REMOTE_NAMES,
}

function RemotesRegistry.GetOrCreateFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		return existing
	end

	assert(
		RunService:IsServer(),
		"Remotes folder must be created by the server before client access"
	)
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	return folder
end

function RemotesRegistry.InitializeServerRemotes(): { [string]: RemoteEvent }
	assert(RunService:IsServer(), "InitializeServerRemotes can only be called on the server")
	local folder = RemotesRegistry.GetOrCreateFolder()
	local map: { [string]: RemoteEvent } = {}

	for _, remoteName in ipairs(REMOTE_NAMES) do
		local existing = folder:FindFirstChild(remoteName)
		if existing and existing:IsA("RemoteEvent") then
			map[remoteName] = existing
		else
			if existing then
				existing:Destroy()
			end
			local remote = Instance.new("RemoteEvent")
			remote.Name = remoteName
			remote.Parent = folder
			map[remoteName] = remote
		end
	end

	return map
end

function RemotesRegistry.WaitForClientRemotes(timeoutSeconds: number?): { [string]: RemoteEvent }
	local timeout = timeoutSeconds or 10
	local folder = ReplicatedStorage:WaitForChild("Remotes", timeout)
	assert(
		folder and folder:IsA("Folder"),
		"Timed out waiting for ReplicatedStorage.Remotes folder"
	)

	local map: { [string]: RemoteEvent } = {}
	for _, remoteName in ipairs(REMOTE_NAMES) do
		local remote = folder:WaitForChild(remoteName, timeout)
		assert(
			remote and remote:IsA("RemoteEvent"),
			string.format("Missing RemoteEvent: %s", remoteName)
		)
		map[remoteName] = remote :: RemoteEvent
	end

	return map
end

return table.freeze(RemotesRegistry)
