local CombatState = {}
CombatState.__index = CombatState

function CombatState.new(humanoid)
	return setmetatable({
		humanoid = humanoid,
		current = "Idle", -- Idle | Attacking | Dodging | Blocking | Stunned

		-- gameplay state (field names match EffectCommands.lua)
		health = 100,
		maxHealth = 100,
		blockStacks = 0,
		dodgeUntil = 0,
		slotLocks = {false, false, false},
		slotLockUntil = {0, 0, 0},
		extraPlays = 0,
	}, CombatState)
end

function CombatState:enter(state, duration)
	self.current = state
	if self.humanoid and self.humanoid.Parent then
		self.humanoid.AutoRotate = (state == "Idle")
		self.humanoid.WalkSpeed = (state == "Idle") and 16 or 0
	end
	if duration then
		task.delay(duration, function()
			if self.current == state then
				self:enter("Idle")
			end
		end)
	end
end

function CombatState:takeDamage(amount)
	local now = os.clock()

	if now < self.dodgeUntil then
		self.dodgeUntil = 0
		return {Dodged = true, Blocked = false, Damage = 0}
	end
	if self.blockStacks > 0 then
		self.blockStacks -= 1
		return {Dodged = false, Blocked = true, Damage = 0}
	end

	self.health = math.clamp(self.health - amount, 0, self.maxHealth)
	return {
		Dodged = false,
		Blocked = false,
		Damage = amount,
		RemainingHealth = self.health,
	}
end

return CombatState