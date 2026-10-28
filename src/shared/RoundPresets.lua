local RoundPresets = {
	StandardPVP = {
		mode = "PVP",
		handSize = 5,
		publicCardCount = 3,
		loopCount = 1,
		comboRegainDiscarded = false,
		maxRecycles = 1,
		roundTime = 60,
		canDealDamage = true,
	},
	InfiniteHub = {
		mode = "Hub",
		handSize = 5,
		publicCardCount = 3,
		loopCount = math.huge,
		comboRegainDiscarded = false,
		maxRecycles = 999,
		roundTime = nil,
		canDealDamage = false,
	},
	ComboPVP = {
		mode = "PVP",
		handSize = 5,
		publicCardCount = 3,
		loopCount = 2,
		comboRegainDiscarded = true,
		maxRecycles = 1,
		roundTime = 90,
		canDealDamage = true,
	},
}

return RoundPresets