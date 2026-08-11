local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CardData = require(ReplicatedStorage.Modules.CardData)
local PlayCard = ReplicatedStorage.Remotes.PlayCard
local UpdateHand = ReplicatedStorage.Remotes.UpdateHand
local LeanTowardRemote = ReplicatedStorage.Remotes:WaitForChild("LeanToward")

-- This table holds every player's current state
local playerHands = {}   -- key = player.UserId

local playDebounce = {}  -- put near top of HandManager with playerHands

-- Helper: create a fresh deck for a player
local function createDeck()
	local deck = {}

	local function add(cardId, count, canRecycle)
		for i = 1, count do
			table.insert(deck, {
				id = cardId,
				canRecycle = canRecycle or false
			})
		end
	end

	add("Strike", 6, false)
	add("Block", 4, true)       -- these can recycle once
	add("HeavyStrike", 2, false)
	add("Dodge", 2, false)

	-- Optional: shuffle
	for i = #deck, 2, -1 do
		local j = math.random(i)
		deck[i], deck[j] = deck[j], deck[i]
	end

	return deck
end

-- Helper: deal starting hand
local function dealStartingHand(player)
	local deck = createDeck()
	local hand = {}

	-- Draw 5 cards into the hand
	for i = 1, 5 do
		if #deck > 0 then
			local card = table.remove(deck, 1)
			table.insert(hand, card)
		end
	end

	-- Store the real card tables on the server
	playerHands[player.UserId] = {
		deck = deck,
		hand = hand,
		selectableCount = 3
	}

	-- Convert to ids for the client
	local fullHandIds = {}
	for i, card in ipairs(hand) do
		fullHandIds[i] = card.id
	end

	local publicCards = {}
	for i = 1, math.min(3, #hand) do
		publicCards[i] = hand[i].id
	end

	-- Send to the owner
	UpdateHand:FireClient(player, {
		fullHand = fullHandIds,
		publicCards = publicCards,
		selectableCount = 3,
		deckCount = #deck,
		isOwner = true
	})

	-- Send public cards to everyone
	UpdateHand:FireAllClients({
		player = player,
		publicCards = publicCards,
		isOwner = false
	})
end

-- When a player joins / character spawns
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		dealStartingHand(player)
	end)
end)

-- Handle playing a card
PlayCard.OnServerEvent:Connect(function(player, cardName, targetCharacter)
	if playDebounce[player.UserId] then return end
	playDebounce[player.UserId] = true
	task.delay(0.35, function()
		playDebounce[player.UserId] = nil
	end)
	local function leanTowardTarget(character, targetCharacter, duration, pullRadius)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
		if not root or not targetRoot then return end

		duration = duration or 0.5
		pullRadius = pullRadius or 12

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutoRotate = false
		end

		local start = os.clock()
		while os.clock() - start < duration do
			if not root.Parent or not targetRoot.Parent then break end

			local offset = targetRoot.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local dist = flat.Magnitude

			if dist > 0.05 and dist <= pullRadius then
				local strength = 1 - (dist / pullRadius)
				strength = math.clamp(strength * strength, 0, 1)

				local desired = CFrame.new(root.Position, root.Position + flat.Unit)
				local alpha = math.clamp(0.15 + strength * 0.25, 0.1, 0.4)
				root.CFrame = root.CFrame:Lerp(desired, alpha)
			end

			task.wait(0.03)
		end

		if humanoid then
			humanoid.AutoRotate = true
		end
	end

	local data = playerHands[player.UserId]
	if not data then return end

	-- Find the card instance in the hand by its id
	local index = nil
	for i, card in ipairs(data.hand) do
		if card.id == cardName then
			index = i
			break
		end
	end
	if not index then return end
	if index > data.selectableCount then return end

	local playedCard = data.hand[index]
	table.remove(data.hand, index)

	-- Recycle only if it is still allowed
	if playedCard.canRecycle then
		playedCard.canRecycle = false
		table.insert(data.deck, playedCard)
	end

	-- Draw new cards
	while #data.hand < 5 and #data.deck > 0 do
		local nextCard = table.remove(data.deck, 1)
		table.insert(data.hand, nextCard)
	end

	-- Build public cards (ids for the client)
	local publicCards = {}
	for i = 1, math.min(3, #data.hand) do
		publicCards[i] = data.hand[i].id
	end

	-- Full hand as ids for the client UI
	local fullHandIds = {}
	for i, card in ipairs(data.hand) do
		fullHandIds[i] = card.id
	end

	-- Play animation + lean during it (no instant snap)
	-- after building fullHandIds / publicCards

	local character = player.Character
	local validTarget = typeof(targetCharacter) == "Instance"
		and targetCharacter:IsA("Model")
		and targetCharacter:FindFirstChild("Humanoid")
		and targetCharacter ~= character

	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and CardData[cardName] and CardData[cardName].AnimationId then
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

			-- Tell the owning client to lean (reliable)
			if validTarget then
				local duration = (track.Length > 0 and track.Length) or 0.5
				-- Use a RemoteEvent, e.g. ReplicatedStorage.Remotes.LeanToward
				LeanToward:FireClient(player, targetCharacter, duration, 12)
			end
		end
	end

	UpdateHand:FireClient(player, {
		fullHand = fullHandIds,
		publicCards = publicCards,
		selectableCount = math.min(data.selectableCount, #data.hand),
		deckCount = #data.deck,
		isOwner = true
	})

	UpdateHand:FireAllClients({
		player = player,
		publicCards = publicCards,
		isOwner = false
	})
end)


-- this is the new one for when I make an animation of strike card:
--PlayCard.OnServerEvent:Connect(function(player, cardName)
--	 data = playerHands[player.UserId]
--	if not data then return end

--	-- Find the card instance in the hand by its id
--	local index = nil
--	for i, card in ipairs(data.hand) do
--		if card.id == cardName then
--			index = i
--			break
--		end
--	end
--	if not index then return end
--	if index > data.selectableCount then return end

--	local playedCard = data.hand[index]
--	table.remove(data.hand, index)

--	-- Recycle only if it is still allowed
--	if playedCard.canRecycle then
--		playedCard.canRecycle = false
--		table.insert(data.deck, playedCard)
--	end

--	-- Draw new cards
--	while #data.hand < 5 and #data.deck > 0 do
--		local nextCard = table.remove(data.deck, 1)
--		table.insert(data.hand, nextCard)
--	end

--	-- Build public cards (ids for the client)
--	local publicCards = {}
--	for i = 1, math.min(3, #data.hand) do
--		publicCards[i] = data.hand[i].id
--	end

--	-- Full hand as ids for the client UI
--	local fullHandIds = {}
--	for i, card in ipairs(data.hand) do
--		fullHandIds[i] = card.id
--	end

--	-- Play animation if this card has one
--	local character = player.Character
--	if character and CardData[cardName] and CardData[cardName].AnimationId then
--		local humanoid = character:FindFirstChildOfClass("Humanoid")
--		if humanoid then
--			local animator = humanoid:FindFirstChildOfClass("Animator")
--			if not animator then
--				animator = Instance.new("Animator")
--				animator.Parent = humanoid
--			end

--			local animation = Instance.new("Animation")
--			animation.AnimationId = CardData[cardName].AnimationId

--			local track = animator:LoadAnimation(animation)
--			track:Play()
--		end
--	end

--	UpdateHand:FireClient(player, {
--		fullHand = fullHandIds,
--		publicCards = publicCards,
--		selectableCount = math.min(data.selectableCount, #data.hand),
--		deckCount = #data.deck,
--		isOwner = true
--	})

--	UpdateHand:FireAllClients({
--		player = player,
--		publicCards = publicCards,
--		isOwner = false
--	})
--end)


--PlayCard.OnServerEvent:Connect(function(player, cardName)
--	-- later: validate and remove the card from their hand
--	print(player.Name, "tried to play", cardName)
--end)

