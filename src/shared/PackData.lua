-- PackData: card pack catalog. Drives shop UI, chip purchases, and Robux
-- product purchases. Robux products are Developer Products; Chips are
-- gameplay-earned only (never sold for Robux — gambling policy).

local PackData = {
	["StarterPack"] = {
		Name = "Starter Pack",
		ChipPrice = 100,
		RobuxProductId = 0, -- ← set after creating the Developer Product
		Slots = 3,
		Odds = { Common = 0.80, Rare = 0.20 },
		Contents = {
			Common = { "Strike", "Block", "Dodge", "Draw", "Recycle" },
			Rare   = { "HeavyStrike" },
		},
	},
	-- future tiers: ["FightersPack"], ["HighRollerPack"], etc.
}

return PackData