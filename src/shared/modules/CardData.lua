local CardData = {
	["Strike"] = {
		Name = "Strike",
		Image = "rbxassetid://105145678621523",
		Type = "Attack",
		Rarity = "Common",
		Description = "Deal 3 damage",
		AnimationId = "rbxassetid://135603995194805",
		Effects = {
			{ Type = "Damage", Amount = 3 }
		},
		Displacement = {
			Type = "Step",      -- "Step" | "Launch" | "Dash"
			Distance = 4,     -- studs forward
			Duration = 0.12,    -- how long the slide takes
			Delay = 0.06,       -- seconds after anim starts (sync with punch extension)
			Easing = "OutQuad", -- feels like weight shifting
			LockInput = true    -- optional: freeze WASD during the commit
		},    
		FX = {
			{
				Type = "Burst",
				Attachment = "RightHand",
				Offset = Vector3.new(0, 0, -0.3),  -- slightly forward of the wrist
				Color = Color3.fromRGB(255, 200, 80),
				Size = 0.4,           -- small, sharp sparks
				Count = 14,
				Lifetime = 0.12,      -- disappears fast
				Speed = 12,           -- explosive
				Spread = 15,          -- tight forward cone (degrees)
				Acceleration = Vector3.new(0, -5, 0),  -- slight gravity drop
				Delay = 0.05
			},
			{
				Type = "Trail",
				Attachment = "RightHand",
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 100)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 50))
				}),
				Lifetime = 0.61,
				Width = 0.9,
				Delay = 0.05
			}
		}
	},

	["Block"] = {
		Name = "Block",
		Image = "rbxassetid://135663875383645",
		Type = "Defense",
		Rarity = "Common",
		Description = "Block the next attack",
		Recycles = true,
		Effects = {
			{ Type = "Block", Stacks = 1 }
		},
		Displacement = {
			Type = "Step",
			Distance = -4,
			Duration = 0.25,
			Delay = 0.15,
			Easing = "InOutQuad",
			LockInput = true
		}
	},

	["HeavyStrike"] = {
		Name = "Heavy Strike",
		Image = "rbxassetid://79967441550801",
		Type = "Attack",
		Description = "A stronger, slower attack.",
		AnimationId = "rbxassetid://86697598017292",
		Effects = {
			{ Type = "Damage", Amount = 6 }
		},
		Displacement = {
			Type = "Dash",
			Distance = 6,
			Height = 3,           -- peak height of the arc
			Duration = 0.4,
			Delay = 0.06,
			Easing = "OutQuad",
			LockInput = true
		}
	},

	["Dodge"] = {
		Name = "Dodge",
		Image = "rbxassetid://74713671631899",
		Type = "Defense",
		Description = "Avoids the next attack.",
		AnimationId = "rbxassetid://75930605946900",
		Effects = {
			{ Type = "Dodge", Duration = 1.0 }
		},
		Displacement = {
			Type = "Dash",
			Distance = -6,
			Duration = 0.18,
			Delay = 0,
			Easing = "OutQuad",
			LockInput = false
		}
	},

	["Draw"] = {
		Name = "Draw",
		Image = "rbxassetid://132270704620248",
		Type = "Special",
		Description = "Draw an extra card.",
		Effects = {
			{ Type = "Draw", Amount = 1 }
		}
	},

	["Recycle"] = {
		Name = "Recycle",
		Image = "rbxassetid://135138731084986",
		Type = "Special",
		Description = "This card returns to your deck when played.",
		Recycles = true,
		Effects = {}
	},
}

return CardData