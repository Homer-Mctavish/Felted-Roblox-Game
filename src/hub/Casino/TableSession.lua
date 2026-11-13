-- TableSession: one seated player vs one dealer. Owns all hand state;
-- never touches remotes or workspace directly — the caller (Casino.server)
-- passes callbacks for presentation and UI pushes.
--
-- Anti-cheat invariants:
--   * The dealer's move is committed at clash START, before the player's
--     choice arrives (DealerAI contract). The player can never affect it.
--   * The client sends only a PLAYABLE SLOT INDEX (1..3). The move, damage,
--     and speed are derived server-side from CardData. Move names are
--     never accepted from the client.
--   * All chip movement runs through PlayerData (ProfileService lock).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CasinoData = require(ReplicatedStorage.Modules.CasinoData)
local CardData = require(ReplicatedStorage.Modules.CardData)
local Deck = require(ReplicatedStorage.Modules.Deck)
local CombatTriangle = require(script.Parent.CombatTriangle)
local DealerAI = require(script.Parent.DealerAI)
local CardInventory = require(ReplicatedStorage.Modules.CardInventory)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData)

local TableSession = {}
TableSession.__index = TableSession

local DODGE_BONUS = 1.5 -- winning damage multiplier granted by a successful Dodge

-- ============================================================================
-- CARD → MOVE/STATS (server-side derivation; client never sends these)
-- ============================================================================
local function cardMoveAndStats(cardId)
	local data = CardData[cardId]
	if not data or not data.Move then return nil end
	local damage = 0
	for _, e in ipairs(data.Effects or {}) do
		if e.Type == "Damage" then damage = e.Amount; break end
	end
	return data.Move, {
		Damage = damage,
		Speed = data.Speed or CombatTriangle.defaultSpeed(data.Move),
	}
end

local function playableMoves(deck)
	-- Moves available from the front PlayableCount cards, deduped, order-stable.
	local seen, out = {}, {}
	local n = math.min(CasinoData.HandConfig.PlayableCount, #deck.hand)
	for i = 1, n do
		local move = cardMoveAndStats(deck.hand[i].id)
		if move and not seen[move] then
			seen[move] = true
			table.insert(out, move)
		end
	end
	return out
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================
-- callbacks = {
--   onState(session)      -- fired after every state mutation; push UI snapshot
--   onTell(info, session) -- tell payload {Animation=...} or {Text=...}; play it
--   onReveal(p, session)  -- clash result payload (below)
--   onHandEnd(p, session) -- hand result: winner, chips delta, mastery, rewards
--   onClosed(session)     -- player left / cleaned up
-- }
function TableSession.new(player, tableId, callbacks)
	local tableInfo = CasinoData[tableId]
	assert(tableInfo, ("TableSession: unknown table '%s'"):format(tostring(tableId)))
	assert(CasinoData.TellSets[tableInfo.Personality],
		("TableSession: personality '%s' has no TellSets"):format(tableInfo.Personality))

	local self = setmetatable({}, TableSession)
	self.player = player
	self.tableId = tableId
	self.info = tableInfo
	self.callbacks = callbacks or {}

	self.phase = "Ante"          -- Ante | Choose | HandEnd | Closed
	self.ante = tableInfo.MinAnte
	self.rideCount = 0

	-- per-hand state (nil until startHand)
	self.rng = nil
	self.playerDeck = nil
	self.dealerDeck = nil
	self.playerHealth = 0
	self.dealerHealth = 0
	self.playerFocus = 0
	self.dealerFocus = 0
	self.dodgeBuff = { player = false, dealer = false }
	self.playerRecent = {}     -- player's chosen moves, oldest → newest
	self.clashIndex = 0        -- clashes completed this hand
	self.suddenDeath = false
	self.previousTell = nil
	self.committedMove = nil   -- dealer's hidden commitment for the open clash

	return self
end

-- ============================================================================
-- UI SNAPSHOT (sent via onState → Casino.server → client)
-- ============================================================================
function TableSession:getState()
	local state = {
		TableId = self.tableId,
		Phase = self.phase,
		Ante = self.ante,
		MinAnte = self.info.MinAnte,
		MaxAnte = self.info.MaxAnte,
		RideCount = self.rideCount,
	}
	if self.phase ~= "Ante" and self.playerDeck then
		state.ClashIndex = self.clashIndex
		state.SuddenDeath = self.suddenDeath
		state.PlayerHealth = self.playerHealth
		state.DealerHealth = self.dealerHealth
		state.PlayerFocus = self.playerFocus
		state.PlayerFocusThreshold = 3
		state.DodgeReady = self.dodgeBuff.player
		state.PlayerHand = self.playerDeck:getFullIds()
		state.PlayerPlayableCount = math.min(CasinoData.HandConfig.PlayableCount, #self.playerDeck.hand)
		state.PlayerDeckCount = #self.playerDeck.deck
		-- Dealer's public cards are visible — that's the counter-play basis
		-- (same "public hand" convention as the arena's FloatingHand).
		state.DealerPublic = self.dealerDeck:getPublic()
	end
	return state
end

local function emit(self)
	if self.callbacks.onState then self.callbacks.onState(self) end
end

-- ============================================================================
-- HAND FLOW
-- ============================================================================
-- Validates and sets the ante (clamped to table bounds). Phase: Ante/HandEnd.
function TableSession:setAnte(amount)
	if self.phase ~= "Ante" and self.phase ~= "HandEnd" then return false end
	amount = math.floor(tonumber(amount) or 0)
	if amount < self.info.MinAnte or amount > self.info.MaxAnte then return false end
	self.ante = amount
	emit(self)
	return true
end

function TableSession:startHand()
	if self.phase ~= "Ante" and self.phase ~= "HandEnd" then return false end

	local data = PlayerData.get(self.player)
	if (data.currency or 0) < self.ante then return false, "not enough chips" end
	data.currency -= self.ante

	self.rng = Random.new() -- per-hand seed; replays stay possible
	local cfg = CasinoData.HandConfig

	self.playerDeck = Deck.new({ handSize = cfg.HandSize, publicCardCount = cfg.PlayableCount, loopCount = 1 })
	self.playerDeck:build(CardInventory.getEquippedPool(self.player))
	self.playerDeck:draw(cfg.HandSize)

	self.dealerDeck = Deck.new({ handSize = cfg.HandSize, publicCardCount = cfg.PlayableCount, loopCount = 1 })
	self.dealerDeck:build(self.info.Deck)
	self.dealerDeck:draw(cfg.HandSize)

	self.playerHealth = cfg.StartingHealth
	self.dealerHealth = cfg.StartingHealth
	self.playerFocus = 0
	self.dealerFocus = 0
	self.dodgeBuff = { player = false, dealer = false }
	self.playerRecent = {}
	self.clashIndex = 0
	self.suddenDeath = false
	self.previousTell = nil

	self:_beginClash()
	return true
end

-- Dealer commits + tell BEFORE the player's choice lands. Never reorder.
function TableSession:_beginClash()
	self.phase = "Choose"
	self.committedMove = DealerAI.commit({
		availableMoves = playableMoves(self.dealerDeck),
		playerRecent = self.playerRecent,
		behind = math.clamp((self.playerHealth - self.dealerHealth) / 100, -1, 1)
			+ self.rideCount * (CasinoData.Ride.AggressionPerRide or 0), -- Let It Ride pressure
		clashIndex = self.clashIndex + 1,
	}, self.info.Personality, self.rng)

	local tellName = DealerAI.nextTell(self.info.Personality, self.committedMove, self.previousTell, self.rng)
	self.previousTell = tellName
	local info = DealerAI.tellInfo(self.info.Personality, tellName)
	if info and self.callbacks.onTell then self.callbacks.onTell(info, self) end

	emit(self)
end

-- The player's pick: an INDEX into their playable slots (1..3). Never a move name.
function TableSession:choose(slotIndex)
	if self.phase ~= "Choose" then return false, "no clash open" end
	slotIndex = math.floor(tonumber(slotIndex) or 0)
	local playableCount = math.min(CasinoData.HandConfig.PlayableCount, #self.playerDeck.hand)
	if slotIndex < 1 or slotIndex > playableCount then return false, "invalid slot" end

	-- Dealer's concrete card: first playable dealer card matching the commitment.
	local dealerMove, dealerCardIndex = nil, nil
	local n = math.min(CasinoData.HandConfig.PlayableCount, #self.dealerDeck.hand)
	for i = 1, n do
		local mv = cardMoveAndStats(self.dealerDeck.hand[i].id)
		if mv == self.committedMove then dealerMove, dealerCardIndex = mv, i; break end
	end
	if not dealerCardIndex then -- commitment couldn't be honored (hand changed): fold to first playable
		dealerCardIndex = 1
		dealerMove = cardMoveAndStats(self.dealerDeck.hand[1].id)
	end

	local playerCard = self.playerDeck.hand[slotIndex]
	local playerMove, pStats = cardMoveAndStats(playerCard.id)
	local _, dStats = cardMoveAndStats(self.dealerDeck.hand[dealerCardIndex].id)

	-- Dodge buffs modify the WINNING side's damage before resolution applies it.
	local pBuffed = pStats
	if self.dodgeBuff.player then
		pBuffed = { Damage = math.ceil(pStats.Damage * DODGE_BONUS), Speed = pStats.Speed }
	end
	local dBuffed = dStats
	if self.dodgeBuff.dealer then
		dBuffed = { Damage = math.ceil(dStats.Damage * DODGE_BONUS), Speed = dStats.Speed }
	end
	self.dodgeBuff.player, self.dodgeBuff.dealer = false, false -- consumed either way

	local outcome = CombatTriangle.resolve(playerMove, dealerMove, pBuffed, dBuffed)

	-- Apply damage.
	self.playerHealth = math.max(0, self.playerHealth - outcome.DamageA)
	self.dealerHealth = math.max(0, self.dealerHealth - outcome.DamageB)

	-- Apply events. Deck:play() refills the slot automatically (draw 1);
	-- the doc's "temporary extra playable" is a v1+ feature and intentionally absent here.
	for side, ev in pairs({ player = outcome.EventA, dealer = outcome.EventB }) do
		if ev == "Blocked" then
			if side == "player" then self.playerFocus += 1 else self.dealerFocus += 1 end
		elseif ev == "Dodged" then
			self.dodgeBuff[side] = true
		end
	end

	-- Consume the played cards (both decks refill themselves).
	self.playerDeck:play(slotIndex)
	self.dealerDeck:play(dealerCardIndex)

	table.insert(self.playerRecent, playerMove)
	self.clashIndex += 1

	local reveal = {
		ClashIndex = self.clashIndex,
		SuddenDeath = self.suddenDeath,
		PlayerCard = playerCard.id,
		PlayerMove = playerMove,
		DealerCard = self.dealerDeck.discard[#self.dealerDeck.discard] and self.dealerDeck.discard[#self.dealerDeck.discard].id or nil,
		DealerMove = dealerMove,
		Winner = outcome.Winner, -- "A" = player, "B" = dealer, "None"
		DamageToPlayer = outcome.DamageA,
		DamageToDealer = outcome.DamageB,
		EventPlayer = outcome.EventA,
		EventDealer = outcome.EventB,
		PlayerHealth = self.playerHealth,
		DealerHealth = self.dealerHealth,
		PlayerFocus = self.playerFocus,
	}
	if self.callbacks.onReveal then self.callbacks.onReveal(reveal, self) end

	-- Hand end?
	local cfg = CasinoData.HandConfig
	local handOver = self.clashIndex >= cfg.ClashesPerHand
	if handOver and self.playerHealth == self.dealerHealth and cfg.SuddenDeath and not self.suddenDeath then
		self.suddenDeath = true
		handOver = false
	end
	-- A death ends the hand immediately, whatever the clash count.
	if self.playerHealth == 0 or self.dealerHealth == 0 then handOver = true end

	if handOver then
		self:_endHand()
	else
		self:_beginClash()
	end
	return true
end

function TableSession:_endHand()
	self.phase = "HandEnd"

	local data = PlayerData.get(self.player)
	local p = CasinoData.Payout
	local result, chipsDelta, masteryGain

	if self.playerHealth > self.dealerHealth then
		result = "Win"
		chipsDelta = self.ante * p.WinMultiplier      -- ante was pre-deducted → net +1 ante
		data.currency += chipsDelta
		masteryGain = p.MasteryOnWin
	elseif self.playerHealth < self.dealerHealth then
		result = "Loss"
		chipsDelta = 0                                   -- ante stays with the house
		masteryGain = p.MasteryOnLoss
	else
		result = "Tie"
		if p.TieRefund then data.currency += self.ante end
		chipsDelta = p.TieRefund and self.ante or 0
		masteryGain = p.MasteryOnLoss
	end

	-- Mastery + threshold rewards.
	local casino = data.casino
	casino.mastery[self.tableId] = casino.mastery[self.tableId] or 0
	local before = casino.mastery[self.tableId]
	casino.mastery[self.tableId] = math.min(before + masteryGain, p.MaxMastery)

	local granted = {}
	for threshold, reward in pairs(self.info.MasteryRewards or {}) do
		if before < threshold and casino.mastery[self.tableId] >= threshold then
			if reward.Currency then data.currency += reward.Currency end
			if reward.Pack then
				local results = CardInventory.openPack(self.player, reward.Pack)
				table.insert(granted, { Pack = reward.Pack, Results = results })
			end
			if reward.Cosmetic then table.insert(granted, { Cosmetic = reward.Cosmetic }) end -- cosmetics system later
		end
	end

	if result == "Win" then
		casino.lifetimeChipsWon = (casino.lifetimeChipsWon or 0) + (chipsDelta - self.ante)
	end

	local payload = {
		Result = result,
		ChipsDelta = chipsDelta,
		Currency = data.currency,
		Mastery = casino.mastery[self.tableId],
		MaxMastery = p.MaxMastery,
		RewardsGranted = granted,
		SuddenDeath = self.suddenDeath,
	}
	if self.callbacks.onHandEnd then self.callbacks.onHandEnd(payload, self) end
	emit(self)
end

-- ============================================================================
-- POST-HAND CHOICES
-- ============================================================================
function TableSession:rematch()
	if self.phase ~= "HandEnd" then return false end
	return self:startHand()
end

-- Let It Ride: raise the next ante (and the dealer's heat), capped.
function TableSession:ride()
	if self.phase ~= "HandEnd" then return false end
	local r = CasinoData.Ride
	if self.rideCount >= r.MaxRide then return false, "ride cap reached" end
	local newAnte = math.floor(self.ante * r.Step)
	if newAnte > self.info.MaxAnte then return false, "ante cap reached" end
	self.ante = newAnte
	self.rideCount += 1
	emit(self)
	return self:startHand()
end

function TableSession:cleanup()
	if self.phase == "Closed" then return end
	-- Mid-hand departure: ante stays with the house (house rule, v0).
	self.phase = "Closed"
	if self.callbacks.onClosed then self.callbacks.onClosed(self) end
end

return TableSession