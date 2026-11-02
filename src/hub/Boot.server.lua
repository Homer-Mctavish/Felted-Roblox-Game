local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(ReplicatedStorage.Modules.PlayerData)
local CardServer = require(ReplicatedStorage.Modules.CardServer)

-- Matchmaking wires RequestMatch/VoteMap/RoundUpdate and teleports the
-- party to the arena place when a vote completes.
require(script.Parent.Matchmaking)

Players.PlayerAdded:Connect(function(player)
	PlayerData.load(player)
end)

-- Hub rules: cards are a sandbox here. Full hand UI, no combat state,
-- no damage, deck rebuilds when it runs dry.
CardServer.start({
	presetName = "InfiniteHub",
	getCombat = function(player) return nil end,
	canDamage = function(attacker, targetCharacter) return false end,
	damage = function(targetCharacter, amount, attacker) return {Damage = 0} end,
	refillDepleted = true,
})