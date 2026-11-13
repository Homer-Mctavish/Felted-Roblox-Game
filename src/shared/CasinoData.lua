-- CasinoData: the casino catalog. Declarative only — no behavior here.
-- Read by TableSession (server), DealerAI (server), and CasinoUI (client).
--
-- Move vocabulary note: dealer "moves" map onto the same card ids players
-- use (Strike = Attack, HeavyStrike = Heavy Attack, Block/Dodge/Draw direct).
-- Cards carry a `Move = "<name>"` field in CardData; TableSession performs
-- the card→move mapping via CombatTriangle.MOVE_DEFS.

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
	-- DealerAI normalizes). Adaptivity = how strongly they punish repeated
	-- player moves. AggressiveWhenAhead flips the score-pressure response
	-- (the Collector attacks when winning). Pattern = optional scripted move
	-- cycle (Boss phases land here later).
	-- =========================================================================
	Personalities = {
		Grinder = {
			Attack = 0.55, HeavyAttack = 0.15,
			Block = 0.10, Dodge = 0.10, Throw = 0.0, Draw = 0.10,
			Adaptivity = 0.10,
		},
		Collector = {
			Attack = 0.20, HeavyAttack = 0.05,
			Block = 0.35, Dodge = 0.20, Throw = 0.0, Draw = 0.20,
			Adaptivity = 0.20,
			AggressiveWhenAhead = true, -- presses when AHEAD, not behind
		},
		Shark = {
			Attack = 0.30, HeavyAttack = 0.20,
			Block = 0.15, Dodge = 0.15, Throw = 0.0, Draw = 0.20,
			Adaptivity = 0.60,
		},
		Boss = { -- base weights; scripted phases via Pattern when they ship
			Attack = 0.35, HeavyAttack = 0.25,
			Block = 0.15, Dodge = 0.15, Throw = 0.0, Draw = 0.10,
			Adaptivity = 0.40,
		},
	},

	-- =========================================================================
	-- TELLS (per personality). Animation-first: each tell is an Animation
	-- asset played on the dealer NPC's Animator (server-side Play()
	-- replicates to all clients). Text tells are the rare exception.
	--
	-- Chain = Markov transition tables conditioned on the COMMITTED move.
	--   Chain[move].Default = used on the first clash / when the previous
	--                          tell has no transition row.
	--   Chain[move][prevTell] = optional; add when a dealer has 2+ tells
	--                            per move worth sequencing.
	-- V0 populates ONLY Default rows — the DealerAI falls back to Default
	-- when no transition row exists, so this behaves as a simple
	-- "canonical tell + noise" system until you author sequences.
	--
	-- LEARNABILITY RULE: the canonical tell (the first, highest-weight row
	-- for a move) must dominate its Default row (~70–80%), or players can't
	-- learn the dealer and the mind-game dies.
	-- =========================================================================
	TellSets = {
		Grinder = {
			Tells = {
				TapFelt       = { Animation = "rbxassetid://0" }, -- set real clip ids as authored
				WindUp        = { Animation = "rbxassetid://0" },
				PlantFeet     = { Animation = "rbxassetid://0" },
				RollShoulders = { Animation = "rbxassetid://0" },
				ChipMath      = { Text = "The Grinder eyes the chip rack, doing the math." },
			},
			Chain = {
				Attack = {
					Default = {
						{ Tell = "TapFelt", Weight = 75 },
						{ Tell = "PlantFeet", Weight = 15 },
						{ Tell = "ChipMath", Weight = 10 },
					},
					-- Example transition row (v1+): repeated taps escalate toward
					-- the windup. Uncomment/extend once the clips exist.
					-- TapFelt = {
					-- 	{ Tell = "TapFelt", Weight = 45 },
					-- 	{ Tell = "WindUp", Weight = 40 },
					-- 	{ Tell = "PlantFeet", Weight = 15 },
					-- },
				},
				HeavyAttack = {
					Default = {
						{ Tell = "WindUp", Weight = 70 },
						{ Tell = "TapFelt", Weight = 20 },
						{ Tell = "ChipMath", Weight = 10 },
					},
				},
				Block = {
					Default = {
						{ Tell = "PlantFeet", Weight = 75 },
						{ Tell = "ChipMath", Weight = 25 },
					},
				},
				Dodge = {
					Default = {
						{ Tell = "RollShoulders", Weight = 75 },
						{ Tell = "TapFelt", Weight = 25 },
					},
				},
				Draw = {
					Default = {
						{ Tell = "ChipMath", Weight = 70 }, -- text tell reads as "considering"
						{ Tell = "PlantFeet", Weight = 30 },
					},
				},
			},
		},
		-- Collector / Shark / Boss TellSets get added as those dealers ship.
		-- Until then, DealerAI.nextTell errors on those personalities — which
		-- is correct: no TellSet, no table.
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
		Deck = { -- small deliberate deck; phases arrive via Pattern later
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