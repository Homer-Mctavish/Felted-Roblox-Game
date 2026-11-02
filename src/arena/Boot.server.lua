local Players = game:GetService("Players")
local PlayerData = require(game.ReplicatedStorage.Modules.PlayerData)

require(script.Parent.MatchCoordinator) -- sessions, card rules, debug fallback

Players.PlayerAdded:Connect(function(player)
	PlayerData.load(player)
end)