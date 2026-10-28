local Players = game:GetService("Players")

local GameModeRegistry = {}
local states = {} -- [userId] = {mode="PVP", presetName="StandardPVP"}

function GameModeRegistry.set(player, presetName, preset)
	states[player.UserId] = {
		presetName = presetName,
		preset = preset,
	}
end

function GameModeRegistry.get(player)
	local s = states[player.UserId]
	return s and s.preset or nil
end

function GameModeRegistry.mode(player)
	local s = states[player.UserId]
	return s and s.preset.mode or "Hub"
end

function GameModeRegistry.canFight(player)
	local s = states[player.UserId]
	if not s then return false end
	return s.preset.canDealDamage == true
end

function GameModeRegistry.isInfinite(player)
	local s = states[player.UserId]
	return s and s.preset.infiniteDeck or false
end

Players.PlayerRemoving:Connect(function(p)
	states[p.UserId] = nil
end)

return GameModeRegistry