local CardFX = {}

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

function CardFX.play(cardName, CardData)
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		warn("[CardFX] No character")
		return
	end

	local data = CardData[cardName]
	if not data or not data.FX then
		warn("[CardFX] No FX table for", cardName)
		return
	end

	for i, fx in ipairs(data.FX) do
		task.delay(fx.Delay or 0, function()
			CardFX._emit(character, fx, i)
		end)
	end
end

function CardFX._emit(character, fx, index)
	-- Find the target part
	local partName = fx.Attachment or "HumanoidRootPart"
	local part = character:FindFirstChild(partName)

	if not part then
		-- Recursive fallback for rigged names like "RightHand"
		for _, p in ipairs(character:GetDescendants()) do
			if p.Name == partName and p:IsA("BasePart") then
				part = p
				break
			end
		end
	end

	if not part then
		warn("[CardFX] Part not found:", partName)
		return
	end

	-- Create attachment
	local att = Instance.new("Attachment")
	att.Name = "FX_" .. (fx.Type or "Effect")
	att.Position = fx.Offset or Vector3.zero
	att.Parent = part

	local lifetime = fx.Lifetime or 0.5
	Debris:AddItem(att, lifetime + 1)

	if fx.Type == "Trail" then
		CardFX._trail(part, att, fx, lifetime)
	elseif fx.Type == "Burst" or fx.Type == "Particle" then
		CardFX._burst(att, fx, lifetime)
	elseif fx.Type == "Glow" then
		CardFX._glow(att, fx, lifetime)
	else
		warn("[CardFX] Unknown FX type:", fx.Type)
	end
end

function CardFX._trail(part, att0, fx, lifetime)
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, 0, -0.6) -- tail behind the hand/root
	att1.Parent = part
	Debris:AddItem(att1, lifetime + 1)

	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = fx.Color or ColorSequence.new(Color3.new(1, 1, 1))
	trail.Lifetime = lifetime
	trail.WidthScale = NumberSequence.new(fx.Width or 0.4)
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Parent = part

	trail.Enabled = true

	task.delay(lifetime, function()
		trail.Enabled = false
		Debris:AddItem(trail, 1)
	end)

	print("[CardFX] Trail emitted on", part.Name)
end

function CardFX._burst(att, fx, lifetime)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = fx.Color and (
		typeof(fx.Color) == "ColorSequence" and fx.Color or ColorSequence.new(fx.Color)
	) or ColorSequence.new(Color3.new(1, 1, 1))
	emitter.Size = NumberSequence.new(fx.Size or 1)
	emitter.Lifetime = NumberRange.new(lifetime)
	emitter.Speed = NumberRange.new(fx.Speed or 6)
	emitter.Rate = 0
	emitter.Acceleration = fx.Acceleration or Vector3.new(0, -2, 0)
	emitter.SpreadAngle = Vector2.new(fx.Spread or 25, fx.Spread or 25)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = att

	emitter:Emit(fx.Count or 10)

	print("[CardFX] Burst emitted:", fx.Count or 10, "particles")

	Debris:AddItem(emitter, lifetime + 0.5)
end

function CardFX._glow(att, fx, lifetime)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = fx.Color and (
		typeof(fx.Color) == "ColorSequence" and fx.Color or ColorSequence.new(fx.Color)
	) or ColorSequence.new(Color3.new(1, 1, 1))
	emitter.Size = NumberSequence.new(fx.Size or 3)
	emitter.Lifetime = NumberRange.new(lifetime)
	emitter.Speed = NumberRange.new(0)
	emitter.Rate = 50
	emitter.Parent = att

	task.delay(lifetime, function()
		emitter.Enabled = false
		Debris:AddItem(emitter, 1)
	end)

	print("[CardFX] Glow started")
end

return CardFX