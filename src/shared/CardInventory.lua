local PlayerData = require(script.Parent.PlayerData)

local CardInventory = {}

function CardInventory.getEquippedPool(player)
	local data = PlayerData.get(player)
	return data.decks.equipped
end

return CardInventory