local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CardData = require(ReplicatedStorage.Modules.CardData)
local Deck = require(ReplicatedStorage.Modules.Deck)
local GameModeRegistry = require(ReplicatedStorage.Modules.GameModeRegistry)
local RoundPresets = require(ReplicatedStorage.Modules.RoundPresets)
local PlayerDecks = require(ReplicatedStorage.Modules.PlayerDecks)

-- ============================================================================
-- INLINED COMBAT MANAGER
-- ============================================================================
local CombatManager = {}
local combatStates = {}
local playerDecks = {} -- [userId] = Deck instance
local playDebounce = {}



-- ============================================================================
-- REMOTES
-- ============================================================================

-- Ensure Remotes folder exists
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

-- Create PlayCard if missing
local PlayCard = remotes:FindFirstChild("PlayCard")
if not PlayCard then
	PlayCard = Instance.new("RemoteEvent")
	PlayCard.Name = "PlayCard"
	PlayCard.Parent = remotes
end

-- Create UpdateHand if missing
local UpdateHand = remotes:FindFirstChild("UpdateHand")
if not UpdateHand then
	UpdateHand = Instance.new("RemoteEvent")
	UpdateHand.Name = "UpdateHand"
	UpdateHand.Parent = remotes
end
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


local function dealHand(player, presetName)
	local preset = RoundPresets[presetName] or RoundPresets.StandardPVP
	GameModeRegistry.set(player, presetName, preset)

	local cardPool = PlayerDecks.get(player)
	local deck = Deck.new(preset)
	deck:build(cardPool)
	deck:draw(preset.handSize)

	playerDecks[player.UserId] = deck
	CombatManager.Reset(player.UserId)
	-- Notify client
	local full = deck:getFullIds()
	local public = deck:getPublic()

	UpdateHand:FireClient(player, {
		fullHand = full,
		publicCards = public,
		selectableCount = preset.publicCardCount,
		deckCount = #deck.deck,
		isOwner = true,
		slotLocks = {false, false, false},
		extraPlays = 0,
	})

	UpdateHand:FireAllClients({
		player = player,
		publicCards = public,
		isOwner = false,
	})
end

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
-- EFFECT RESOLUTION
-- ============================================================================
local function resolveEffects(player, cardName, targetCharacter, deck)
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
			local before = #deck.hand
			deck:draw(effect.Amount)
			local drawn = #deck.hand - before
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

	local deck = playerDecks[player.UserId]
	if not deck then return end

	-- Find card in hand
	local index = nil
	for i, card in ipairs(deck.hand) do
		if card.id == cardName then
			index = i
			break
		end
	end
	if not index then return end

	local preset = GameModeRegistry.get(player)
	if not preset then return end

	-- Respect public slots unless extra plays are active
	if index > preset.publicCardCount and CombatManager.GetExtraPlays(player.UserId) <= 0 then
		return
	end

	-- Check slot locks (only for public slots 1-3)
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

	humanoid.AutoRotate = false
	local attackYaw = math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z)

	-- =====================================================================
	-- PLAY CARD & COMBAT
	-- =====================================================================
	local playedCard = deck:play(index)
	if not playedCard then return end

	if index > preset.publicCardCount then
		CombatManager.ConsumeExtraPlay(player.UserId)
	end

	local effectResults = resolveEffects(player, cardName, targetCharacter, deck)

	local hitLanded = false
	for _, res in ipairs(effectResults) do
		if res.Type == "Damage" and res.Result and res.Result.Damage > 0 then
			hitLanded = true
		end
	end
	deck:recordPlay(cardName, hitLanded)

	-- =====================================================================
	-- ANIMATION
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
	-- DISPLACEMENT
	-- =====================================================================
	local disp = CardData[cardName] and CardData[cardName].Displacement
	if disp then
		task.delay(disp.Delay or 0, function()
			if not root.Parent then return end

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

				local newY = startPos.Y
				if disp.Height then
					local heightT = math.sin(t * math.pi)
					newY = startPos.Y + disp.Height * heightT
				end

				local rx, ry, rz = root.CFrame:ToOrientation()
				root.CFrame = CFrame.new(newX, newY, newZ) * CFrame.Angles(rx, ry, rz)

				task.wait()
			end

			if disp.LockInput then
				humanoid.WalkSpeed = oldWalkSpeed
			end
		end)
	end

	-- =====================================================================
	-- CLEANUP
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
	local full = deck:getFullIds()
	local public = deck:getPublic()
	local slotLocks = CombatManager.GetSlotLocks(player.UserId)

	UpdateHand:FireClient(player, {
		fullHand = full,
		publicCards = public,
		selectableCount = math.min(preset.publicCardCount, #deck.hand),
		deckCount = #deck.deck,
		isOwner = true,
		slotLocks = slotLocks,
		extraPlays = CombatManager.GetExtraPlays(player.UserId),
		effectResults = effectResults,
	})

	UpdateHand:FireAllClients({
		player = player,
		publicCards = public,
		isOwner = false,
	})
end)

-- ============================================================================
-- LIFECYCLE
-- ============================================================================
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		dealHand(player, "InfiniteHub") -- uses player's equipped deck, but infinite redraw rules
	end)
end)

-- Add to HandManager.lua, near the bottom
function IsPlayerOutOfCards(player)
	local deck = playerDecks[player.UserId]
	return not deck or deck:isDepleted()
end

-- Round system integration

RoundSignal.Event:Connect(function(action, targetPlayer, presetName)
	if action == "Deal" then
		dealHand(targetPlayer, presetName or "StandardPVP")
	elseif action == "Clear" then
		playerDecks[targetPlayer.UserId] = nil
		UpdateHand:FireClient(targetPlayer, {
			fullHand = {}, publicCards = {}, selectableCount = 0,
			deckCount = 0, isOwner = true,
			slotLocks = {false, false, false}, extraPlays = 0,
		})
		UpdateHand:FireAllClients({
			player = targetPlayer, publicCards = {}, isOwner = false,
		})
	end
end)



-- RoundSignal.Event:Connect(function(action, targetPlayer)
-- 	if action == "Deal" then
-- 		dealStartingHand(targetPlayer)
-- 	elseif action == "Clear" then
-- 		playerHands[targetPlayer.UserId] = nil
-- 		UpdateHand:FireClient(targetPlayer, {
-- 			fullHand = {},
-- 			publicCards = {},
-- 			selectableCount = 0,
-- 			deckCount = 0,
-- 			isOwner = true,
-- 			slotLocks = {false, false, false},
-- 			extraPlays = 0,
-- 		})
-- 		UpdateHand:FireAllClients({
-- 			player = targetPlayer,
-- 			publicCards = {},
-- 			isOwner = false,
-- 		})
-- 	end
-- end)