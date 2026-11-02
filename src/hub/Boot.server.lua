local Players = game:GetService("Players")
local PlayerData = require(game.ReplicatedStorage.Modules.PlayerData)

require(script.Parent.Matchmaking) -- wires remote handlers

Players.PlayerAdded:Connect(function(player)
	PlayerData.load(player)
end)