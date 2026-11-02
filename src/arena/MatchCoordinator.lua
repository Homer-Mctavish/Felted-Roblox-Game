local Players = game:GetService("Players")
local MatchSession = require(script.Parent.MatchSession)

local Coordinator = { arrived = {}, data = nil, deadline = 0 }

function Coordinator.begin(data, userIds, timeout)
	Coordinator.data = data
	Coordinator.deadline = os.clock() + timeout
	for _, uid in ipairs(userIds) do Coordinator.arrived[uid] = false end
	Coordinator.check()
end

function Coordinator.noteArrival(userId)
	if Coordinator.arrived[userId] ~= nil then
		Coordinator.arrived[userId] = true
		Coordinator.check()
	end
end

function Coordinator.check()
	if not Coordinator.data then return end
	local players = {}
	for uid, here in pairs(Coordinator.arrived) do
		if here then
			local p = Players:GetPlayerByUserId(uid)
			if p then table.insert(players, p) end
		end
	end
	local allHere = true
	for _, here in pairs(Coordinator.arrived) do
		if not here then allHere = false; break end
	end
	if (allHere or os.clock() > Coordinator.deadline) and #players > 0 then
		local data = Coordinator.data
		Coordinator.data = nil
		local session = MatchSession.new(players, data.Arena, data.Preset)
		session:enterPhase("Loading")
	end
end

return Coordinator