--!strict
--[[
	Janitor.lua
	Deterministic cleanup utility for RoundService and StationService.
	Tracks Instances, RBXScriptConnections, custom Connections, threads, and cleanup callbacks.
]]

export type CleanableTask =
	Instance
	| RBXScriptConnection
	| thread
	| (() -> ())
	| { Disconnect: (self: any) -> () }
	| { Destroy: (self: any) -> () }

export type JanitorObject = {
	Add: <T>(self: JanitorObject, object: T) -> T,
	Cleanup: (self: JanitorObject) -> (),
	Destroy: (self: JanitorObject) -> (),
}

local Janitor = {}
Janitor.__index = Janitor

function Janitor.new(): JanitorObject
	local self = setmetatable({
		_tasks = {} :: { any },
	}, Janitor)
	return (self :: any) :: JanitorObject
end

function Janitor:Add<T>(object: T): T
	assert(object ~= nil, "Janitor:Add cannot track nil")
	table.insert(self._tasks, object)
	return object
end

function Janitor:Cleanup()
	local tasks = self._tasks
	for index = #tasks, 1, -1 do
		local item: any = tasks[index]
		tasks[index] = nil

		local itemType = typeof(item)
		if itemType == "function" then
			item()
		elseif itemType == "RBXScriptConnection" then
			if item.Connected then
				item:Disconnect()
			end
		elseif itemType == "thread" then
			pcall(task.cancel, item)
		elseif itemType == "Instance" then
			item:Destroy()
		elseif itemType == "table" then
			if type(item.Destroy) == "function" then
				item:Destroy()
			elseif type(item.Disconnect) == "function" then
				item:Disconnect()
			elseif type(item.DisconnectAll) == "function" then
				item:DisconnectAll()
			end
		end
	end
end

function Janitor:Destroy()
	self:Cleanup()
end

return table.freeze(Janitor)
