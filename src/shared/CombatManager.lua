local CombatManager = {}

local Players = game:GetService("Players")

-- Combat state per player
local combatStates = {} -- [userId] = state

local function getState(userId)
	if not combatStates[userId] then
		combatStates[userId] = {
			Health = 100,
			MaxHealth = 100,
			BlockStacks = 0,
			DodgeUntil = 0,          -- os.clock() timestamp
			SlotLocks = {false, false, false}, -- which of the 3 public slots are frozen
			SlotLockUntil = {0, 0, 0},
			ExtraPlays = 0,          -- from DoubleStrike-type cards
		}
	end
	return combatStates[userId]
end

function CombatManager.Reset(userId)
	combatStates[userId] = nil
end

function CombatManager.GetHealth(userId)
	return getState(userId).Health
end

function CombatManager.TakeDamage(userId, amount, attackerId)
	local state = getState(userId)
	local now = os.clock()

	-- Dodge check
	if now < state.DodgeUntil then
		state.DodgeUntil = 0
		return {Dodged = true, Damage = 0}
	end

	-- Block check
	if state.BlockStacks > 0 then
		state.BlockStacks -= 1
		return {Blocked = true, Damage = 0}
	end

	state.Health = math.clamp(state.Health - amount, 0, state.MaxHealth)
	return {Dodged = false, Blocked = false, Damage = amount, RemainingHealth = state.Health}
end

function CombatManager.AddBlock(userId, stacks)
	getState(userId).BlockStacks += stacks
end

function CombatManager.SetDodge(userId, duration)
	getState(userId).DodgeUntil = os.clock() + duration
end

function CombatManager.GrantExtraPlays(userId, amount)
	getState(userId).ExtraPlays += amount
end

function CombatManager.ConsumeExtraPlay(userId)
	local state = getState(userId)
	if state.ExtraPlays > 0 then
		state.ExtraPlays -= 1
		return true
	end
	return false
end

function CombatManager.GetExtraPlays(userId)
	return getState(userId).ExtraPlays
end

function CombatManager.LockSlot(userId, slotIndex, duration)
	local state = getState(userId)
	local now = os.clock()
	if slotIndex == "random" then
		-- pick from currently unlocked slots
		local unlocked = {}
		for i = 1, 3 do
			if now >= state.SlotLockUntil[i] then
				table.insert(unlocked, i)
			end
		end
		if #unlocked == 0 then return nil end
		slotIndex = unlocked[math.random(1, #unlocked)]
	end
	state.SlotLocks[slotIndex] = true
	state.SlotLockUntil[slotIndex] = now + duration
	return slotIndex
end

function CombatManager.GetSlotLocks(userId)
	local state = getState(userId)
	local now = os.clock()
	local active = {}
	for i = 1, 3 do
		active[i] = now < state.SlotLockUntil[i]
	end
	return active
end

-- Cleanup on leave
Players.PlayerRemoving:Connect(function(player)
	combatStates[player.UserId] = nil
end)

return CombatManager