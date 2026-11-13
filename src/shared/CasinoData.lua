-- CasinoData: the casino catalog. Declarative only — no behavior here.
-- Read by TableSession (server), DealerAI (server), and CasinoUI (client).
--
-- Move vocabulary note: dealer "moves" map onto the same card ids players
-- use (Strike = Attack, HeavyStrike = Heavy Attack, Block/Dodge/Draw direct).
-- TableSession performs the mapping; this file stays card-shaped so house
-- decks and player decks stay interchangeable.

local CasinoData = {

	-- Ladder order for UI rendering and unlock chaining.
	Order = { "LobbyTable", "VelvetTable", "HighRoller", "HouseChampion" },

	-- =========================================================================
	-- TABLE CONSTANTS (apply to every table)
	-- =========================================================================
	HandConfig = {
		ClashesPerHand = 3,      -- normal hand length
		StartingHealth = 100,
		SuddenDeath = true,      -- equal health after N clashes → one extra clash
		HandSize = 5,            -- cards dealt per side (3 playable + 2 queued)
		PlayableCount = 3,
	},

	-- Payout + progression primitives. Mastery advances even on losses so a
	-- bad streak never feels like pure waste.
	Payout = {
		WinMultiplier = 2,       -- win pays ante * this (net profit = 1 ante)
		TieRefund = true,        -- tie → ante returned
		MasteryOnWin = 3,
		MasteryOnLoss = 1,
		MaxMastery = 100,        -- per-dealer track; rewards at thresholds
	},

	-- Let It Ride (v2 primitive): each ride multiplies next ante AND payout,
	-- and bumps the dealer's aggression. Capped so a run can't spiral.
	Ride = {
		Step = 1.5,
		MaxRide = 4,
		AggressionPerRide = 0.1,
	},

	-- =========================================================================
	-- DEALER PERSONALITIES (weights used by DealerAI; need not sum to 1 —
	-- DealerAI normalizes). Adaptivity = how much they punish repeated player
	-- moves; BluffChance = how often their tell lies.
	-- =========================================================================
	Personalities = {
		Grinder = {
			Attack = 0.55, HeavyAttack = 0.15,
			Block = 0.10, Dodge = 0.10, Throw = 0.0, Draw = 0.10,
			Adaptivity = 0.10, BluffChance = 0.0,
		},
		Collector = {
			Attack = 0.20, HeavyAttack = 0.05,
			Block = 0.35, Dodge = 0.20, Throw = 0.0, Draw = 0.20,
			Adaptivity = 0.20, BluffChance = 0.0,
		},
		Shark = {
			Attack = 0.30, HeavyAttack = 0.20,
			Block = 0.15, Dodge = 0.15, Throw = 0.0, Draw = 0.20,
			Adaptivity = 0.60, BluffChance = 0.25,
		},
		Boss = { -- phases handled by DealerAI; these are the base weights
			Attack = 0.35, HeavyAttack = 0.25,
			Block = 0.15, Dodge = 0.15, Throw = 0.0, Draw = 0.10,
			Adaptivity = 0.40, BluffChance = 0.15,
		},
	},

	-- =========================================================================
	-- TABLES / DEALERS
	-- =========================================================================
	["LobbyTable"] = {
		Name = "Lobby Table",
		DealerName = "The Grinder",
		Personality = "Grinder",

		-- House deck: same shape as a player pool entry list.
		Deck = {
			{id = "Strike",      count = 8, canRecycle = true},
			{id = "Block",       count = 4, canRecycle = true},
			{id = "Dodge",       count = 4, canRecycle = true},
			{id = "HeavyStrike", count = 2, canRecycle = true},
		},

		MinAnte = 10,
		MaxAnte = 100,

		Unlock = { Free = true }, -- first table is always open

		-- Mastery thresholds grant rewards as the track fills.
		MasteryRewards = {
			[25]  = { Currency = 100 },
			[50]  = { Currency = 250 },
			[100] = { Pack = "StarterPack" },
		},
	},

	["VelvetTable"] = {
		Name = "Velvet Table",
		DealerName = "The Collector",
		Personality = "Collector",
		Deck = {
			{id = "Strike",      count = 6, canRecycle = true},
			{id = "Block",       count = 6, canRecycle = true},
			{id = "Dodge",       count = 6, canRecycle = true},
			{id = "Draw",        count = 4, canRecycle = true},
			{id = "HeavyStrike", count = 3, canRecycle = true},
		},
		MinAnte = 50,
		MaxAnte = 500,
		Unlock = { PrevTable = "LobbyTable", MinMastery = 50, MinLifetimeWon = 500 },
		MasteryRewards = {
			[50]  = { Currency = 1000 },
			[100] = { Pack = "StarterPack" },
		},
	},

	["HighRoller"] = {
		Name = "High Roller",
		DealerName = "The Shark",
		Personality = "Shark",
		Deck = {
			{id = "Strike",      count = 8, canRecycle = true},
			{id = "Block",       count = 4, canRecycle = true},
			{id = "Dodge",       count = 6, canRecycle = true},
			{id = "Draw",        count = 4, canRecycle = true},
			{id = "HeavyStrike", count = 6, canRecycle = true},
		},
		MinAnte = 250,
		MaxAnte = 2500,
		Unlock = { PrevTable = "VelvetTable", MinMastery = 60, MinLifetimeWon = 5000 },
		MasteryRewards = {
			[50]  = { Currency = 5000 },
			[100] = { Pack = "StarterPack" }, -- swap for a higher tier pack later
		},
	},

	["HouseChampion"] = {
		Name = "House Champion",
		DealerName = "The House Boss",
		Personality = "Boss",
		Deck = { -- small scripted deck: the boss runs a deliberate pattern
			{id = "Strike",      count = 6, canRecycle = true},
			{id = "HeavyStrike", count = 6, canRecycle = true},
			{id = "Block",       count = 3, canRecycle = true},
			{id = "Dodge",       count = 3, canRecycle = true},
			{id = "Draw",        count = 2, canRecycle = true},
		},
		MinAnte = 1000,
		MaxAnte = 10000,
		Unlock = { PrevTable = "HighRoller", MinMastery = 75, MinLifetimeWon = 25000 },
		MasteryRewards = {
			[100] = { Currency = 25000, Cosmetic = "HouseChampionSleeves" },
		},
	},
}

-- Convenience: is this table id valid?
function CasinoData.isValidTable(id)
	return CasinoData[id] ~= nil
end

return CasinoData