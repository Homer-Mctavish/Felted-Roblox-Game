local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CardData = require(ReplicatedStorage.Modules.CardData)

-- ============================================================================
-- INLINED COMBAT MANAGER (no external module required)
-- ============================================================================
local CombatManager = {}
local combatStates = {}

function CombatManager.Reset(userId)
	combatStates[userId] = {
		Health = 100,
		MaxHealth = 100,
		BlockStacks = 0,
		DodgeUntil = 0,
		SlotLocks = {false, false, false},
		SlotLockUntil = {0, 0, 0},
		ExtraPlays = 0,
	}
end

function CombatManager.GetState(userId)
	if not combatStates[userId] then
		CombatManager.Reset(userId)
	end
	return combatStates[userId]
end

function CombatManager.TakeDamage(userId, amount, attackerId)
	local state = CombatManager.GetState(userId)
	local now = os.clock()

	if now < state.DodgeUntil then
		state.DodgeUntil = 0
		return {Dodged = true, Damage = 0}
	end

	if state.BlockStacks > 0 then
		state.BlockStacks -= 1
		return {Blocked = true, Damage = 0}
	end

	state.Health = math.clamp(state.Health - amount, 0, state.MaxHealth)
	return {Dodged = false, Blocked = false, Damage = amount, RemainingHealth = state.Health}
end

function CombatManager.AddBlock(userId, stacks)
	CombatManager.GetState(userId).BlockStacks += stacks
end

function CombatManager.SetDodge(userId, duration)
	CombatManager.GetState(userId).DodgeUntil = os.clock() + duration
end

function CombatManager.GrantExtraPlays(userId, amount)
	CombatManager.GetState(userId).ExtraPlays += amount
end

function CombatManager.ConsumeExtraPlay(userId)
	local state = CombatManager.GetState(userId)
	if state.ExtraPlays > 0 then
		state.ExtraPlays -= 1
		return true
	end
	return false
end

function CombatManager.GetExtraPlays(userId)
	return CombatManager.GetState(userId).ExtraPlays
end

function CombatManager.LockSlot(userId, slotIndex, duration)
	local state = CombatManager.GetState(userId)
	local now = os.clock()
	if slotIndex == "random" then
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
	local state = CombatManager.GetState(userId)
	local now = os.clock()
	local active = {}
	for i = 1, 3 do
		active[i] = now < state.SlotLockUntil[i]
		state.SlotLocks[i] = active[i]
	end
	return active
end

Players.PlayerRemoving:Connect(function(player)
	combatStates[player.UserId] = nil
end)

-- ============================================================================
-- REMOTES
-- ============================================================================
local PlayCard = ReplicatedStorage.Remotes.PlayCard
local UpdateHand = ReplicatedStorage.Remotes.UpdateHand
local LeanTowardRemote = ReplicatedStorage.Remotes:WaitForChild("LeanToward")

local CombatUpdate = ReplicatedStorage.Remotes:FindFirstChild("CombatUpdate")
if not CombatUpdate then
	CombatUpdate = Instance.new("RemoteEvent")
	CombatUpdate.Name = "CombatUpdate"
	CombatUpdate.Parent = ReplicatedStorage.Remotes
end

-- ============================================================================
-- STATE
-- ============================================================================
local playerHands = {}
local playDebounce = {}

-- ============================================================================
-- DECK
-- ============================================================================
local function createDeck()
	local deck = {}
	local function add(cardId, count)
		local info = CardData[cardId]
		for i = 1, count do
			table.insert(deck, {
				id = cardId,
				canRecycle = info and info.Recycles or false,
			})
		end
	end

	add("Strike", 6)
	add("Block", 4)
	add("HeavyStrike", 2)
	add("Dodge", 2)
	add("Draw", 2)
	add("Recycle", 2)

	for i = #deck, 2, -1 do
		local j = math.random(i)
		deck[i], deck[j] = deck[j], deck[i]
	end
	return deck
end

-- ============================================================================
-- HELPERS
-- ============================================================================
local function dealStartingHand(player)
	local deck = createDeck()
	local hand = {}
	for i = 1, 5 do
		if #deck > 0 then
			table.insert(hand, table.remove(deck, 1))
		end
	end

	playerHands[player.UserId] = {
		deck = deck,
		hand = hand,
		selectableCount = 3,
	}

	CombatManager.Reset(player.UserId)

	local fullHandIds = {}
	for i, card in ipairs(hand) do
		fullHandIds[i] = card.id
	end

	local publicCards = {}
	for i = 1, math.min(3, #hand) do
		publicCards[i] = hand[i].id
	end

	UpdateHand:FireClient(player, {
		fullHand = fullHandIds,
		publicCards = publicCards,
		selectableCount = 3,
		deckCount = #deck,
		isOwner = true,
		slotLocks = {false, false, false},
		extraPlays = 0,
	})

	UpdateHand:FireAllClients({
		player = player,
		publicCards = publicCards,
		isOwner = false,
	})
end

local function buildHandPayload(data)
	local fullHandIds = {}
	for i, card in ipairs(data.hand) do
		fullHandIds[i] = card.id
	end
	local publicCards = {}
	for i = 1, math.min(3, #data.hand) do
		publicCards[i] = data.hand[i].id
	end
	return fullHandIds, publicCards
end

local function drawUpToFive(data)
	while #data.hand < 5 and #data.deck > 0 do
		table.insert(data.hand, table.remove(data.deck, 1))
	end
end

-- ============================================================================
-- EFFECT RESOLUTION
-- ============================================================================
local function resolveEffects(player, cardName, targetCharacter)
	local data = CardData[cardName]
	if not data or not data.Effects then return {} end

	local results = {}
	local targetPlayer = nil
	if targetCharacter then
		local hum = targetCharacter:FindFirstChildOfClass("Humanoid")
		if hum then
			targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
		end
	end

	for _, effect in ipairs(data.Effects) do
		if effect.Type == "Damage" then
			if targetPlayer then
				local res = CombatManager.TakeDamage(targetPlayer.UserId, effect.Amount, player.UserId)
				table.insert(results, {Type = "Damage", Result = res})
				CombatUpdate:FireClient(targetPlayer, {Type = "Hit", Data = res})
			end

		elseif effect.Type == "Block" then
			CombatManager.AddBlock(player.UserId, effect.Stacks)
			table.insert(results, {Type = "Block", Stacks = effect.Stacks})

		elseif effect.Type == "Dodge" then
			CombatManager.SetDodge(player.UserId, effect.Duration)
			table.insert(results, {Type = "Dodge", Duration = effect.Duration})

		elseif effect.Type == "Draw" then
			local handData = playerHands[player.UserId]
			local drawn = 0
			for i = 1, effect.Amount do
				if #handData.deck > 0 and #handData.hand < 5 then
					table.insert(handData.hand, table.remove(handData.deck, 1))
					drawn += 1
				end
			end
			table.insert(results, {Type = "Draw", Amount = drawn})

		elseif effect.Type == "GrantExtraPlays" then
			CombatManager.GrantExtraPlays(player.UserId, effect.Amount)
			table.insert(results, {Type = "ExtraPlays", Amount = effect.Amount})

		elseif effect.Type == "LockSlot" then
			if targetPlayer then
				local lockedSlot = CombatManager.LockSlot(targetPlayer.UserId, effect.SlotIndex, effect.Duration)
				if lockedSlot then
					table.insert(results, {Type = "LockSlot", Slot = lockedSlot, Duration = effect.Duration})
					UpdateHand:FireClient(targetPlayer, {
						slotLocks = CombatManager.GetSlotLocks(targetPlayer.UserId),
						isOwner = true,
						isSlotUpdate = true,
					})
				end
			end

		elseif effect.Type == "SelfStun" then
			table.insert(results, {Type = "SelfStun", Duration = effect.Duration})
		end
	end

	return results
end

-- ============================================================================
-- PLAY CARD HANDLER
-- ============================================================================
PlayCard.OnServerEvent:Connect(function(player, cardName, targetCharacter)
	if playDebounce[player.UserId] then return end
	playDebounce[player.UserId] = true
	task.delay(0.35, function()
		playDebounce[player.UserId] = nil
	end)

	local data = playerHands[player.UserId]
	if not data then return end

	-- Find card in hand
	local index = nil
	for i, card in ipairs(data.hand) do
		if card.id == cardName then
			index = i
			break
		end
	end
	if not index then return end

	-- Check selectable / extra plays
	local extra = CombatManager.GetExtraPlays(player.UserId)
	if index > data.selectableCount and extra <= 0 then
		return
	end

	-- Check slot locks (only for public slots 1-3)
	if index <= 3 then
		local locks = CombatManager.GetSlotLocks(player.UserId)
		if locks[index] then
			return
		end
	end

	local playedCard = data.hand[index]
	table.remove(data.hand, index)

	-- Consume extra play if used
	if index > data.selectableCount and extra > 0 then
		CombatManager.ConsumeExtraPlay(player.UserId)
	end

	-- Recycling
	if playedCard.canRecycle then
		playedCard.canRecycle = false   -- consumed permanently
		table.insert(data.deck, playedCard)
	end
	
	-- Resolve effects
	local effectResults = resolveEffects(player, cardName, targetCharacter)

	-- Refill hand
	drawUpToFive(data)

	-- Build payloads
	local fullHandIds, publicCards = buildHandPayload(data)
	local slotLocks = CombatManager.GetSlotLocks(player.UserId)

	-- Animation
	local character = player.Character
	local validTarget = typeof(targetCharacter) == "Instance"
		and targetCharacter:IsA("Model")
		and targetCharacter:FindFirstChildOfClass("Humanoid")
		and targetCharacter ~= character

	if character and CardData[cardName] and CardData[cardName].AnimationId then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
			local animation = Instance.new("Animation")
			animation.AnimationId = CardData[cardName].AnimationId
			local track = animator:LoadAnimation(animation)
			track.Looped = false
			track.Priority = Enum.AnimationPriority.Action
			track:Play()

			if validTarget then
				local duration = (track.Length > 0 and track.Length) or 0.5
				LeanTowardRemote:FireClient(player, targetCharacter, duration, 12)
			end
		end
	end

	-- Notify owner
	UpdateHand:FireClient(player, {
		fullHand = fullHandIds,
		publicCards = publicCards,
		selectableCount = math.min(data.selectableCount, #data.hand),
		deckCount = #data.deck,
		isOwner = true,
		slotLocks = slotLocks,
		extraPlays = CombatManager.GetExtraPlays(player.UserId),
		effectResults = effectResults,
	})

	-- Notify others
	UpdateHand:FireAllClients({
		player = player,
		publicCards = publicCards,
		isOwner = false,
	})
end)

-- ============================================================================
-- LIFECYCLE
-- ============================================================================
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		dealStartingHand(player)
	end)
end)