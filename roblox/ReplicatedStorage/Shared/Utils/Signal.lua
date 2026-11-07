--!strict
--[[
	Signal.lua
	Lightweight, dependency-free Luau Signal implementation for internal service decoupling.
	Supports Connect, Fire, and DisconnectAll for deterministic round cleanup.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({
		_listeners = {} :: { [Connection]: (...any) -> () },
	}, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(callback: (...any) -> ()): Connection
	assert(type(callback) == "function", "Signal:Connect expects a function callback")
	local listeners = self._listeners
	local connection: Connection
	connection = {
		Connected = true,
		Disconnect = function(conn: Connection)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			listeners[conn] = nil
		end,
	}
	listeners[connection] = callback
	return connection
end

function Signal:Fire(...: any)
	for connection, callback in pairs(self._listeners) do
		if connection.Connected then
			task.spawn(callback, ...)
		end
	end
end

function Signal:DisconnectAll()
	for connection in pairs(self._listeners) do
		connection.Connected = false
	end
	table.clear(self._listeners)
end

return table.freeze(Signal)
