local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local UpdateHand = ReplicatedStorage.Remotes.UpdateHand
local PlayCard = ReplicatedStorage.Remotes.PlayCard
local CardData = require(ReplicatedStorage.Modules.CardData)
local FloatingHand = require(script.Parent.FloatingHand)
local LocalHand = require(script.Parent.LocalHand)
local LeanToward = require(script.Parent.LeanToward)
local LeanTowardRemote = ReplicatedStorage.Remotes:WaitForChild("LeanToward")

-- ---------------------------------------------------------------------------
-- TARGETING
-- ---------------------------------------------------------------------------
local function getTargetCharacter()
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not myRoot then return nil end

	local closest, closestDist = nil, 50
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			local root = other.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local d = (root.Position - myRoot.Position).Magnitude
				if d < closestDist then
					closestDist = d
					closest = other.Character
				end
			end
		end
	end
	return closest
end

-- ---------------------------------------------------------------------------
-- PLAY CARD (single FireServer — fixed double-fire bug)
-- ---------------------------------------------------------------------------
local function onPlayCard(cardName, index)
	print("Playing card:", cardName)
	local target = getTargetCharacter()
	PlayCard:FireServer(cardName, target)
end

-- ---------------------------------------------------------------------------
-- UI SETUP
-- ---------------------------------------------------------------------------
LocalHand.create(CardData, onPlayCard)

local function onCharacterAdded(character)
	task.wait(0.3)
	FloatingHand.create(character)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

LeanTowardRemote.OnClientEvent:Connect(function(targetCharacter, duration, pullRadius)
	task.spawn(function()
		LeanToward.lean(targetCharacter, duration, pullRadius)
	end)
end)

-- ---------------------------------------------------------------------------
-- HAND UPDATES
-- ---------------------------------------------------------------------------
local function onHandUpdated(data)
	if data.isOwner then
		-- Slot locks always update if present
		if data.slotLocks then
			LocalHand.setSlotLocks(data.slotLocks)
		end

		-- If this is ONLY a slot update, don't rebuild the whole hand
		if data.isSlotUpdate then
			return
		end

		-- Full hand update
		LocalHand.update(data.fullHand, CardData, data.selectableCount, data.deckCount)

		-- Extra plays
		if data.extraPlays then
			LocalHand.setExtraPlays(data.extraPlays)
		end

		-- Effect feedback
		if data.effectResults then
			for _, res in ipairs(data.effectResults) do
				if res.Type == "ExtraPlays" then
					LocalHand.showToast("+" .. res.Amount .. " free plays!")
				end
			end
		end

		-- Floating public cards above own head
		if player.Character then
			FloatingHand.update(player.Character, data.publicCards, CardData)
		end
	else
		-- Other player: just update their floating cards
		local otherPlayer = data.player
		if otherPlayer and otherPlayer.Character then
			FloatingHand.update(otherPlayer.Character, data.publicCards, CardData)
		end
	end
end

UpdateHand.OnClientEvent:Connect(onHandUpdated)

-- ---------------------------------------------------------------------------
-- INPUT
-- ---------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	local keyMap = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4,
		[Enum.KeyCode.Five] = 5,
		[Enum.KeyCode.Six] = 6,
	}

	local index = keyMap[input.KeyCode]
	if index then
		LocalHand.selectCard(index)
	end
end)