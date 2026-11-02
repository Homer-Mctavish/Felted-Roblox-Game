local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
	return setmetatable({ listeners = {} }, EventBus)
end

function EventBus:on(event, callback)
	self.listeners[event] = self.listeners[event] or {}
	table.insert(self.listeners[event], callback)
end

function EventBus:emit(event, payload)
	for _, cb in ipairs(self.listeners[event] or {}) do
		task.spawn(cb, payload)
	end
end

function EventBus:clear()
	self.listeners = {}
end

return EventBus