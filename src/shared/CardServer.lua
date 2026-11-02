-- CardServer: shared card-play engine for all places.
-- Each place calls CardServer.start(rules) once from its Boot script.
--
-- rules contract:
--   presetName        : string    — key into RoundPresets, used for dealing
--   autoDeal          : boolean?  — default true; deal a hand on spawn
--   getDeck           : (player) -> Deck?          — override deck storage
--                                    (arena: session-owned decks). Default:
--                                    internal per-place table
--   getCombat         : (player) -> CombatState?   — nil = hands only
--   canDamage         : (attacker, targetCharacter) -> boolean
--   damage            : (targetCharacter, amount, attacker) -> result table
--   refillDepleted    : boolean?  — default false; rebuild deck when it runs out

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CardData = require(ReplicatedStorage.Modules.CardData)
local Deck = require(ReplicatedStorage.Modules.Deck)
local EffectCommands = require(ReplicatedStorage.Modules.EffectCommands)
local CardInventory = require(ReplicatedStorage.Modules.CardInventory)
local RoundPresets = require(ReplicatedStorage.Modules.RoundPresets)

local CardServer = {}

function CardServer.start(rules)
	local preset = RoundPresets[rules.presetName]
	assert(preset, ("[CardServer] Unknown preset '%s'"):format(tostring(rules.presetName)))

	local autoDeal = rules.autoDeal ~= false
	local refillDepleted = rules.refillDepleted == true

	local remotes = ReplicatedStorage.Remotes
	local PlayCard = remotes.PlayCard
	local UpdateHand = remotes.UpdateHand
	local CombatUpdate = remotes.CombatUpdate

	local playerDecks = {} -- [userId] = Deck (used when rules.getDeck is absent)
	local debounce = {}    -- [userId] = bool

	local function getDeck(player)
		if rules.getDeck then
			return rules.getDeck(player)
		end
		return playerDecks[player.UserId]
	end

	local function getSlotLocks(combat)
		if not combat then return {false, false, false} end
		local now = os.clock()
		return {
			now < combat.slotLockUntil[1],
			now < combat.slotLockUntil[2],
			now < combat.slotLockUntil[3],
		}
	end

	local function pushHand(player)
		local deck = getDeck(player)
		if not deck then return end
		local combat = rules.getCombat(player)
		UpdateHand:FireClient(player, {
			fullHand = deck:getFullIds(),
			publicCards = deck:getPublic(),
			selectableCount = math.min(preset.publicCardCount, #deck.hand),
			deckCount = #deck.deck,
			isOwner = true,
			slotLocks = getSlotLocks(combat),
			extraPlays = combat and combat.extraPlays or 0,
		})
		UpdateHand:FireAllClients({
			player = player,
			publicCards = deck:getPublic(),
			isOwner = false,
		})
	end

	function CardServer.deal(player)
		local deck = Deck.new(preset)
		deck:build(CardInventory.getEquippedPool(player))
		deck:draw(preset.handSize)
		if not rules.getDeck then
			playerDecks[player.UserId] = deck
		end
		pushHand(player)
		return deck
	end

	-- =========================================================================
	-- PLAY CARD
	-- =========================================================================
	PlayCard.OnServerEvent:Connect(function(player, cardName, targetCharacter)
		-- --- remote arg validation ---
		if typeof(cardName) ~= "string" or not CardData[cardName] then return end
		if typeof(targetCharacter) ~= "Instance" or not targetCharacter:IsA("Model") then
			targetCharacter = nil
		end

		-- --- debounce ---
		if debounce[player.UserId] then return end
		debounce[player.UserId] = true
		task.delay(0.35, function() debounce[player.UserId] = nil end)

		-- --- deck + card lookup ---
		local deck = getDeck(player)
		if not deck then return end

		local index = nil
		for i, card in ipairs(deck.hand) do
			if card.id == cardName then index = i; break end
		end
		if not index then return end

		local combat = rules.getCombat(player)

		-- --- play gating ---
		-- hidden slots (beyond public count) require an extra play
		if index > preset.publicCardCount and (not combat or combat.extraPlays <= 0) then
			return
		end
		-- public slots can be locked (slot-jam effects)
		if combat and index <= 3 and os.clock() < combat.slotLockUntil[index] then
			return
		end

		-- --- character ---
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then return end

		humanoid.AutoRotate = false
		local attackYaw = math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z)

		-- --- consume the card ---
		local playedCard = deck:play(index)
		if not playedCard then return end

		if index > preset.publicCardCount and combat then
			combat.extraPlays = math.max(0, combat.extraPlays - 1)
		end

		-- --- effects (via command table + injected rules) ---
		local ctx = {
			attacker = player,
			targetPlayer = targetCharacter and Players:GetPlayerFromCharacter(targetCharacter) or nil,
			targetCharacter = targetCharacter,
			deck = deck,
			combat = combat,
			canDamage = rules.canDamage,
			damage = rules.damage,
		}

		local effectResults = {}
		for _, def in ipairs(CardData[cardName].Effects or {}) do
			local cmd = EffectCommands[def.Type]
			if cmd then
				ctx.amount = def.Amount
				ctx.stacks = def.Stacks
				ctx.duration = def.Duration
				ctx.slotIndex = def.SlotIndex
				local ok, res = pcall(cmd, ctx)
				if ok and res then table.insert(effectResults, res) end
			end
		end

		local hitLanded = false
		for _, res in ipairs(effectResults) do
			if res.Type == "Damage" and res.Result and res.Result.Damage > 0 then
				hitLanded = true
			end
		end
		deck:recordPlay(cardName, hitLanded)

		-- --- animation ---
		local track = nil
		if CardData[cardName].AnimationId then
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

		-- --- displacement ---
		local disp = CardData[cardName].Displacement
		if disp then
			task.delay(disp.Delay or 0, function()
				if not root.Parent then return end
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero

				local oldWalkSpeed = humanoid.WalkSpeed
				if disp.LockInput then humanoid.WalkSpeed = 0 end

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
						newY = startPos.Y + disp.Height * math.sin(t * math.pi)
					end

					local rx, ry, rz = root.CFrame:ToOrientation()
					root.CFrame = CFrame.new(newX, newY, newZ) * CFrame.Angles(rx, ry, rz)
					task.wait()
				end

				if disp.LockInput then humanoid.WalkSpeed = oldWalkSpeed end
			end)
		end

		-- --- restore character control ---
		local animLen = track and track.Length or 0.5
		local dispTotal = disp and ((disp.Delay or 0) + disp.Duration) or 0
		task.delay(math.max(animLen, dispTotal) + 0.1, function()
			if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
		end)

		-- --- notify ---
		pushHand(player)

		-- --- refill (hub-style sandbox) ---
		if refillDepleted and deck:isDepleted() then
			task.delay(0.3, function()
				if not player.Parent then return end
				deck:build(CardInventory.getEquippedPool(player))
				deck:draw(preset.handSize)
				pushHand(player)
			end)
		end
	end)

	-- =========================================================================
	-- LIFECYCLE
	-- =========================================================================
	Players.PlayerRemoving:Connect(function(player)
		playerDecks[player.UserId] = nil
		debounce[player.UserId] = nil
	end)

	if autoDeal then
		local function onPlayerJoined(player)
			player.CharacterAdded:Connect(function()
				task.wait(1)
				if getDeck(player) then return end -- don't clobber session hands
				CardServer.deal(player)
			end)
			if player.Character then
				task.spawn(function()
					task.wait(1)
					if not getDeck(player) then CardServer.deal(player) end
				end)
			end
		end
		Players.PlayerAdded:Connect(onPlayerJoined)
		for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerJoined, p) end
	end

	return CardServer
end

return CardServer