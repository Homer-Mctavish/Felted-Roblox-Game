local PlayerDecks = {}

local defaultPool = {
	{id = "Strike",      count = 6, canRecycle = false},
	{id = "Block",       count = 4, canRecycle = true},
	{id = "HeavyStrike", count = 2, canRecycle = false},
	{id = "Dodge",       count = 2, canRecycle = false},
	{id = "Draw",        count = 2, canRecycle = false},
	{id = "Recycle",     count = 2, canRecycle = true},
}

function PlayerDecks.get(player)
	-- Later: load from DataStore based on player.UserId
	return defaultPool
end

return PlayerDecks