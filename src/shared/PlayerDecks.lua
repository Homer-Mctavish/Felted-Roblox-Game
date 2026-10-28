local PlayerDecks = {}

local defaultDeck = {
	{id = "Strike",      count = 6, canRecycle = false},
	{id = "Block",       count = 4, canRecycle = true},
	{id = "HeavyStrike", count = 2, canRecycle = false},
	{id = "Dodge",       count = 2, canRecycle = false},
	{id = "Draw",        count = 2, canRecycle = false},
	{id = "Recycle",     count = 2, canRecycle = true},
}

-- In the future, load from DataStore or player inventory
local equipped = {} -- [userId] = card pool table

function PlayerDecks.get(player)
	return equipped[player.UserId] or defaultDeck
end

function PlayerDecks.set(player, pool)
	equipped[player.UserId] = pool
end

return PlayerDecks