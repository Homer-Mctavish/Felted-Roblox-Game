-- CardInventory: server-side card ownership and deck validation.
-- Required ONLY from server scripts (Boot/CardServer/Casino/Shops).
--
-- PlayerData v3 shape this depends on:
--   data.collection = { ["Strike"] = 4, ["HeavyStrike"] = 1, ... }  -- cards owned
--   data.currency   = chips
-- (decks.equipped remains a *composition*; getEquippedPool validates it
--  against collection so a deck can never reference unowned cards.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerData = require(script.Parent.PlayerData)
local PackData = require(script.Parent.PackData) -- pack tiers, odds, contents

local CardInventory = {}

-- ============================================================================
-- QUERIES
-- ============================================================================
local function getCollection(player)
	local data = PlayerData.get(player)
	if not data.collection then
		data.collection = {} -- defensive; Reconcile normally guarantees this
	end
	return data.collection
end

function CardInventory.owns(player, cardId)
	return getCollection(player)[cardId] ~= nil
end

function CardInventory.count(player, cardId)
	return getCollection(player)[cardId] or 0
end

-- The deck CardServer builds from. Validates each equipped entry against
-- the collection: unknown cards and cards you don't own are dropped (with a
-- warn), so a stale/malicious deck row can never inflate the pool.
function CardInventory.getEquippedPool(player)
	local data = PlayerData.get(player)
	local pool = {}
	for _, entry in ipairs((data.decks and data.decks.equipped) or {}) do
		local owned = getCollection(player)[entry.id] or 0
		if owned <= 0 then
			warn(("[CardInventory] %s equipped '%s' but doesn't own it; skipping")
				:format(player.Name, tostring(entry.id)))
		else
			table.insert(pool, {
				id = entry.id,
				count = math.min(entry.count or 1, owned),
				canRecycle = entry.canRecycle == true,
			})
		end
	end
	return pool
end

-- ============================================================================
-- MUTATIONS (server-only; ProfileService holds the session lock)
-- ============================================================================
function CardInventory.addCards(player, cardIds)
	local collection = getCollection(player)
	for _, cardId in ipairs(cardIds) do
		collection[cardId] = (collection[cardId] or 0) + 1
	end
	return cardIds
end

-- Opens a pack: rolls its contents server-side (seeded), grants the cards,
-- and returns the result list so the caller (Shops) can reveal it to the
-- client. Caller is responsible for price handling (chips or Robux receipt).
function CardInventory.openPack(player, packId)
	local pack = PackData[packId]
	if not pack then
		warn(("[CardInventory] Unknown pack '%s'"):format(tostring(packId)))
		return nil
	end

	local rng = Random.new() -- per-open seed; server-authoritative roll
	local results = {}

	for _ = 1, (pack.slots or 3) do
		local roll = rng:NextNumber()
		local cumulative = 0
		local chosenRarity = nil
		for rarity, weight in pairs(pack.odds) do
			cumulative += weight
			if roll <= cumulative then
				chosenRarity = rarity
				break
			end
		end
		chosenRarity = chosenRarity or next(pack.odds)

		local pool = pack.contents[chosenRarity]
		if pool and #pool > 0 then
			table.insert(results, pool[rng:NextInteger(1, #pool)])
		end
	end

	CardInventory.addCards(player, results)
	return results
end

-- Direct purchase helper for Shops: validates chip balance, deducts, opens.
-- Returns {ok, results or reason}.
function CardInventory.buyPackWithChips(player, packId)
	local pack = PackData[packId]
	if not pack then return {ok = false, reason = "unknown pack"} end

	local data = PlayerData.get(player)
	if (data.currency or 0) < pack.chipPrice then
		return {ok = false, reason = "not enough chips"}
	end

	data.currency -= pack.chipPrice
	local results = CardInventory.openPack(player, packId)
	return {ok = true, results = results, remaining = data.currency}
end

return CardInventory