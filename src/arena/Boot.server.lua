local Players = game:GetService("Players")
local PlayerData = require(game.ReplicatedStorage.Modules.PlayerData)
local MatchCoordinator = require(script.Parent.MatchCoordinator)

local expected = nil -- { userIds = {...}, data = teleportData, deadline = os.clock() + 15 }

Players.PlayerAdded:Connect(function(player)
	PlayerData.load(player)
	local joinData = player:GetJoinData()
	local td = joinData and joinData.TeleportData
	if td and td.Kind == "Match" then
		if not expected then
			expected = { userIds = td.Players, data = td, deadline = os.clock() + 20 }
		end
		MatchCoordinator.noteArrival(player.UserId)
	end
end)