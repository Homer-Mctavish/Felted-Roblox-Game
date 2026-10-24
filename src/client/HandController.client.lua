local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local UpdateHand = ReplicatedStorage.Remotes.UpdateHand
local PlayCard = ReplicatedStorage.Remotes.PlayCard
local CardData = require(ReplicatedStorage.Modules.CardData)
local FloatingHand = require(script.Parent.FloatingHand)
local LocalHand = require(script.Parent.LocalHand)
local CardFX = require(ReplicatedStorage.Modules.CardFX)
local CombatUpdate = ReplicatedStorage.Remotes:WaitForChild("CombatUpdate")

-- ============================================================================
-- LOCK-ON SYSTEM
-- ============================================================================

local lockedTarget = nil
local lockOnRenderConnection = nil
local isAttacking = false

local LOCK_ON_RANGE = 35
local LOCK_ON_BREAK_RANGE = 45
local CAMERA_OFFSET = CFrame.new(0, 4, 10)

local function clearLockOnIndicator(character)
	if not character then return end
	local head = character:FindFirstChild("Head")
	if not head then return end
	local ind = head:FindFirstChild("LockOnIndicator")
	if ind then ind:Destroy() end
end

local function setLockOnIndicator(character)
	clearLockOnIndicator(character)
	local head = character:WaitForChild("Head", 5)
	if not head then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LockOnIndicator"
	billboard.Size = UDim2.new(0, 28, 0, 28)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(1, 0, 1, 0)
	dot.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	dot.BorderSizePixel = 0
	dot.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
end

local function getLockOnCandidate()
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not myRoot then return nil end

	local nearest, nearestDist = nil, LOCK_ON_RANGE
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			local root = other.Character:FindFirstChild("HumanoidRootPart")
			local hum = other.Character:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local d = (root.Position - myRoot.Position).Magnitude
				if d < nearestDist then
					nearestDist = d
					nearest = other.Character
				end
			end
		end
	end
	return nearest
end

local function breakLockOn()
	if lockOnRenderConnection then
		lockOnRenderConnection:Disconnect()
		lockOnRenderConnection = nil
	end
	if lockedTarget then
		clearLockOnIndicator(lockedTarget)
	end
	lockedTarget = nil
	camera.CameraType = Enum.CameraType.Custom

	if player.Character then
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.AutoRotate = true end
	end
end

local function updateLockOn()
	if not lockedTarget or not lockedTarget.Parent then
		breakLockOn()
		return
	end

	local targetRoot = lockedTarget:FindFirstChild("HumanoidRootPart")
	local targetHum = lockedTarget:FindFirstChildOfClass("Humanoid")
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local myHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")

	if not targetRoot or not targetHum or targetHum.Health <= 0 or not myRoot or not myHum then
		breakLockOn()
		return
	end

	local dist = (targetRoot.Position - myRoot.Position).Magnitude
	if dist > LOCK_ON_BREAK_RANGE then
		breakLockOn()
		return
	end

	myHum.AutoRotate = false

	-- FREEZE rotation during attacks so client doesn't fight server/animation
	if not isAttacking then
		local flatOffset = Vector3.new(
			targetRoot.Position.X - myRoot.Position.X,
			0,
			targetRoot.Position.Z - myRoot.Position.Z
		)
		if flatOffset.Magnitude > 0.1 then
			local desired = CFrame.lookAt(myRoot.Position, myRoot.Position + flatOffset.Unit, Vector3.yAxis)
			myRoot.CFrame = myRoot.CFrame:Lerp(desired, 0.3)
		end
	end

	-- Camera always updates
	local lookAtTarget = CFrame.lookAt(myRoot.Position, targetRoot.Position)
	camera.CFrame = lookAtTarget * CAMERA_OFFSET
end

local function toggleLockOn()
	if lockedTarget then
		breakLockOn()
		return
	end

	local target = getLockOnCandidate()
	if not target then return end

	lockedTarget = target
	setLockOnIndicator(target)
	camera.CameraType = Enum.CameraType.Scriptable
	lockOnRenderConnection = RunService.RenderStepped:Connect(updateLockOn)
end

player.CharacterRemoving:Connect(function()
	breakLockOn()
end)

-- ============================================================================
-- TARGETING FOR CARDS
-- ============================================================================

local function getTargetCharacter()
	-- ONLY return a target if we are actively locked on
	if lockedTarget and lockedTarget.Parent then
		local hum = lockedTarget:FindFirstChildOfClass("Humanoid")
		local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local theirRoot = lockedTarget:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 and myRoot and theirRoot then
			local d = (theirRoot.Position - myRoot.Position).Magnitude
			if d <= LOCK_ON_BREAK_RANGE then
				return lockedTarget
			end
		end
	end
	-- Unlocked: attack fires straight ahead. No fallback.
	return nil
end

-- ============================================================================
-- PLAY CARD
-- ============================================================================

local function onPlayCard(cardName, index)
	print("Playing card:", cardName)

	isAttacking = true
	local character = player.Character
	local myHum = character and character:FindFirstChildOfClass("Humanoid")
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")

	if myHum then
		myHum.AutoRotate = false
		myHum.WalkSpeed = 0
	end
	if myRoot then
		myRoot.AssemblyLinearVelocity = Vector3.zero
		myRoot.AssemblyAngularVelocity = Vector3.zero
	end

	local target = getTargetCharacter()
	print("TARGET:", target and target.Name or "nil", "| LOCKED:", lockedTarget and lockedTarget.Name or "nil")
	PlayCard:FireServer(cardName, target)

	-- CLIENT-SIDE FX
	if CardFX then
		CardFX.play(cardName, CardData)
	end

	-- Restore after attack window
	task.delay(0.8, function()
		isAttacking = false
		if myHum and myHum.Parent then
			myHum.AutoRotate = true
			myHum.WalkSpeed = 16  -- or your game's default walkspeed
		end
	end)
end

-- ============================================================================
-- UI SETUP
-- ============================================================================

LocalHand.create(CardData, onPlayCard)

local function onCharacterAdded(character)
	task.wait(0.3)
	FloatingHand.create(character)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

-- ============================================================================
-- HAND UPDATES
-- ============================================================================



CombatUpdate.OnClientEvent:Connect(function(data)
	if data.Type == "Hit" then
		local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not myRoot then return end

		-- Simple hit spark at player position
		local att = Instance.new("Attachment")
		att.Position = Vector3.new(0, 0, -1) -- slightly in front
		att.Parent = myRoot

		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = data.Data.Blocked and ColorSequence.new(Color3.fromRGB(100, 200, 255))
			or data.Data.Dodged and ColorSequence.new(Color3.fromRGB(200, 255, 100))
			or ColorSequence.new(Color3.fromRGB(255, 60, 60))
		emitter.Size = NumberSequence.new(1.5)
		emitter.Lifetime = NumberRange.new(0.2)
		emitter.Speed = NumberRange.new(6)
		emitter.Rate = 0
		emitter.Parent = att

		emitter:Emit(10)
		game:GetService("Debris"):AddItem(emitter, 0.5)
		game:GetService("Debris"):AddItem(att, 0.5)
	end
end)

local function onHandUpdated(data)
	if data.isOwner then
		if data.slotLocks then
			LocalHand.setSlotLocks(data.slotLocks)
		end
		if data.isSlotUpdate then
			return
		end

		LocalHand.update(data.fullHand, CardData, data.selectableCount, data.deckCount)

		if data.extraPlays then
			LocalHand.setExtraPlays(data.extraPlays)
		end

		if data.effectResults then
			for _, res in ipairs(data.effectResults) do
				if res.Type == "ExtraPlays" then
					LocalHand.showToast("+" .. res.Amount .. " free plays!")
				end
			end
		end

		if player.Character then
			FloatingHand.update(player.Character, data.publicCards, CardData)
		end
	else
		local otherPlayer = data.player
		if otherPlayer and otherPlayer.Character then
			FloatingHand.update(otherPlayer.Character, data.publicCards, CardData)
		end
	end
end

UpdateHand.OnClientEvent:Connect(onHandUpdated)

-- ============================================================================
-- INPUT
-- ============================================================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.Q then
		toggleLockOn()
		return
	end

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