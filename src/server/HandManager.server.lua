local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CardData = require(ReplicatedStorage.Modules.CardData)

-- ============================================================================
-- INLINED COMBAT MANAGER
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
local RoundSignal = Instance.new("BindableEvent")
RoundSignal.Name = "RoundSignal"
RoundSignal.Parent = ReplicatedStorage
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

	local index = nil
	for i, card in ipairs(data.hand) do
		if card.id == cardName then
			index = i
			break
		end
	end
	if not index then return end

	local extra = CombatManager.GetExtraPlays(player.UserId)
	if index > data.selectableCount and extra <= 0 then return end

	if index <= 3 then
		local locks = CombatManager.GetSlotLocks(player.UserId)
		if locks[index] then return end
	end

	-- =====================================================================
	-- CHARACTER SETUP
	-- =====================================================================
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end

	-- Stop physics from rotating the character
	humanoid.AutoRotate = false

	-- Capture current yaw silently. NEVER write it back to root.CFrame.
	local attackYaw = math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z)

	-- =====================================================================
	-- HAND STATE
	-- =====================================================================
	local playedCard = data.hand[index]
	table.remove(data.hand, index)

	if index > data.selectableCount and extra > 0 then
		CombatManager.ConsumeExtraPlay(player.UserId)
	end

	if playedCard.canRecycle then
		playedCard.canRecycle = false
		table.insert(data.deck, playedCard)
	end

	local effectResults = resolveEffects(player, cardName, targetCharacter)
	drawUpToFive(data)

	-- =====================================================================
	-- ANIMATION (server loads and plays; client replicates visually)
	-- =====================================================================
	local track = nil
	if CardData[cardName] and CardData[cardName].AnimationId then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end

		local animation = Instance.new("Animation")
		animation.AnimationId = CardData[cardName].AnimationId

		track = animator:LoadAnimation(animation)
		track.Looped = false
		track.Priority = Enum.AnimationPriority.Action
		track:Play()
	end

	-- =====================================================================
	-- DISPLACEMENT (position ONLY; preserves exact rotation)
	-- =====================================================================
	local disp = CardData[cardName] and CardData[cardName].Displacement

	local function runDisplacement()
		if not root.Parent then return end

		-- Kill momentum
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		local oldWalkSpeed = humanoid.WalkSpeed
		if disp.LockInput then
			humanoid.WalkSpeed = 0
		end

		local forward = Vector3.new(math.sin(attackYaw), 0, math.cos(attackYaw))
		local startPos = root.Position
		local goalPos = startPos + forward * disp.Distance

		local startTime = os.clock()
		while os.clock() - startTime < disp.Duration do
			if not root.Parent then break end

			local t = (os.clock() - startTime) / disp.Duration
			if disp.Easing == "OutQuad" then
				t = 1 - (1 - t) * (1 - t)
			elseif disp.Easing == "InOutQuad" then
				t = t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
			end

			local newX = startPos.X + (goalPos.X - startPos.X) * t
			local newZ = startPos.Z + (goalPos.Z - startPos.Z) * t

			-- Height arc (single write, no double-CFrame)
			local newY = startPos.Y
			if disp.Height then
				local heightT = math.sin(t * math.pi)
				newY = startPos.Y + disp.Height * heightT
			end

			-- Preserve exact rotation (read fresh each frame)
			local rx, ry, rz = root.CFrame:ToOrientation()
			root.CFrame = CFrame.new(newX, newY, newZ) * CFrame.Angles(rx, ry, rz)

			task.wait()
		end

		if disp.LockInput then
			humanoid.WalkSpeed = oldWalkSpeed
		end
	end

	if disp then
		local markerTriggered = false

		-- Try marker sync first (add a "Lunge" marker in Animation Editor)
		local markerConn
		if track then
			markerConn = track:GetMarkerReachedSignal("Lunge"):Once(function()
				markerTriggered = true
				runDisplacement()
			end)
		end

		-- Fallback: use Delay if no marker or marker never fires
		task.delay(disp.Delay or 0, function()
			if not markerTriggered then
				if markerConn then
					markerConn:Disconnect()
				end
				runDisplacement()
			end
		end)
	end

	-- =====================================================================
	-- CLEANUP: restore AutoRotate after attack + displacement finish
	-- =====================================================================
	local animLen = track and track.Length or 0.5
	local dispTotal = disp and ((disp.Delay or 0) + disp.Duration) or 0
	local restoreDelay = math.max(animLen, dispTotal) + 0.1

	task.delay(restoreDelay, function()
		if humanoid and humanoid.Parent then
			humanoid.AutoRotate = true
		end
	end)

	-- =====================================================================
	-- NOTIFY CLIENTS
	-- =====================================================================
	local fullHandIds, publicCards = buildHandPayload(data)
	local slotLocks = CombatManager.GetSlotLocks(player.UserId)

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

-- Add to HandManager.lua, near the bottom
function IsPlayerOutOfCards(player)
	local data = playerHands[player.UserId]
	if not data then return true end
	return #data.hand == 0 and #data.deck == 0
end

-- Round system integration
RoundSignal.Event:Connect(function(action, targetPlayer)
	if action == "Deal" then
		dealStartingHand(targetPlayer)
	elseif action == "Clear" then
		playerHands[targetPlayer.UserId] = nil
		UpdateHand:FireClient(targetPlayer, {
			fullHand = {},
			publicCards = {},
			selectableCount = 0,
			deckCount = 0,
			isOwner = true,
			slotLocks = {false, false, false},
			extraPlays = 0,
		})
		UpdateHand:FireAllClients({
			player = targetPlayer,
			publicCards = {},
			isOwner = false,
		})
	end
end)