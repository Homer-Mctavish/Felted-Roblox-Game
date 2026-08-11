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

-- example: nearest other player’s character
local function getTargetCharacter()
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not myRoot then return nil end

	local closest, closestDist = nil, 50 -- max range in studs
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


-- Called when the player confirms a card
local function onPlayCard(cardName, index)
	print("Playing card:", cardName)
	PlayCard:FireServer(cardName)
	local targetCharacter = getTargetCharacter()
	PlayCard:FireServer(cardName, targetCharacter)
	-- Server will later update the hand after validating
end


-- Create the private hand UI once
LocalHand.create(CardData, onPlayCard)


-- Character spawn → floating cards
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

-- Handle updates from server
local function onHandUpdated(data)
	if data.isOwner then
		-- Update private hand (bottom of screen) + deck count
		LocalHand.update(data.fullHand, CardData, data.selectableCount, data.deckCount)
		print("CLIENT fullHand:", table.concat(data.fullHand or {}, ", "))
		for i, cardName in ipairs(data.fullHand or {}) do
			if CardData[cardName] then
				print(i, cardName, "→ FOUND in CardData")
			else
				print(i, cardName, "→ MISSING from CardData")
			end
		end
		-- Update floating public cards above your head
		if player.Character then
			FloatingHand.update(player.Character, data.publicCards, CardData)
		end
	else
		-- Other players only update the floating cards
		local otherPlayer = data.player
		if otherPlayer and otherPlayer.Character then
			FloatingHand.update(otherPlayer.Character, data.publicCards, CardData)
		end
	end
end

UpdateHand.OnClientEvent:Connect(onHandUpdated)

-- Desktop number keys (1-6)
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


