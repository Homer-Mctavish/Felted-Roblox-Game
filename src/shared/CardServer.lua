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
--
-- CardData governs presentation per card:
--   AnimationId : plays in place (root motion consumed & discarded)
--   Displacement: { Distance = +toward / -away from lock-on target (studs),
--                   Duration, Delay, Easing, Height = optional grounded arc,
--                   LockInput = false keeps player control during the move }
--   FX          : played client-side by CardFX

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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

	local activePlays = {} -- [userId] = {track, connection, humanoid, playId}

	local function restoreControl(userId, humanoid)
		local play = activePlays[userId]
		if not play then return end
		play.playId += 1 -- invalidates any in-flight loops
		if play.connection then play.connection:Disconnect() end
		if play.track and play.track.IsPlaying then play.track:Stop(0.1) end
		if humanoid and humanoid.Parent then
			humanoid.AutoRotate = true
			humanoid.WalkSpeed = 16
		end
		activePlays[userId] = nil
	end

	function CardServer.interrupt(player)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		restoreControl(player.UserId, hum)
	end

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

		-- can't play a new card mid-swing (interrupt clears this)
		if activePlays[player.UserId] then return end

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

		-- --- animation + displacement ---
		-- Cards without an AnimationId play instantly with no lock.
		if CardData[cardName].AnimationId then
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

			-- R15: "Root" Motor6D lives in LowerTorso. R6: "RootJoint".
			local rootJoint = (character:FindFirstChild("LowerTorso")
					and character.LowerTorso:FindFirstChild("Root"))
				or character:FindFirstChild("RootJoint", true)

			-- Displacement is separate from the animation, governed by
			-- CardData.Displacement. Direction comes from the lock-on target
			-- sent with the play; positive Distance = toward it, negative = away.
			local disp = CardData[cardName].Displacement
			local lockMove = not disp or disp.LockInput ~= false -- default: locked
			local arc = disp and disp.Height and disp.Height > 0

			if lockMove then
				humanoid.AutoRotate = false
				humanoid.WalkSpeed = 0
			end

			local dispDir, dispDist
			if disp and disp.Distance and disp.Distance ~= 0 then
				dispDist = math.abs(disp.Distance)
				local base
				local troot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
				if troot then
					local d = Vector3.new(troot.Position.X - root.Position.X, 0, troot.Position.Z - root.Position.Z)
					if d.Magnitude > 0.5 then base = d.Unit end
				end
				if not base then
					base = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
				end
				dispDir = (disp.Distance > 0) and base or -base
			end

			local playId = (activePlays[player.UserId] and activePlays[player.UserId].playId or 0) + 1
			local lastEased = 0
			local startTime = os.clock()
			local startY = root.Position.Y

			local function ease(t)
				if disp and disp.Easing == "OutQuad" then
					return 1 - (1 - t) * (1 - t)
				elseif disp and disp.Easing == "InOutQuad" then
					return t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
				end
				return t
			end

			local connection
			connection = RunService.Heartbeat:Connect(function()
				local play = activePlays[player.UserId]
				if not play or play.playId ~= playId or not track.IsPlaying then
					restoreControl(player.UserId, humanoid)
					return
				end

				-- Pin the animation: consume root motion so the CLIP never
				-- moves the character. Displacement below is the only mover.
				if rootJoint then
					rootJoint.Transform = CFrame.identity
				end

				-- Displacement from CardData, eased, horizontal (+ optional arc).
				if dispDir then
					local raw = (os.clock() - startTime - (disp.Delay or 0)) / (disp.Duration or 0.2)
					raw = math.clamp(raw, 0, 1)
					local eased = ease(raw)
					local step = eased - lastEased
					lastEased = eased
					if step ~= 0 or (arc and raw < 1) then
						local cf = root.CFrame
						local newPos = cf.Position + dispDir * (dispDist * step)
						if arc then
							newPos = Vector3.new(newPos.X,
								startY + disp.Height * math.sin(math.pi * eased),
								newPos.Z)
						end
						root.CFrame = CFrame.new(newPos) * (cf - cf.Position)
					end
				end

				-- Physics coordination: only fight physics when we've taken
				-- control (locked) or are holding an arc; otherwise the
				-- player keeps control (LockInput = false, e.g. Dodge).
				if lockMove or arc then
					root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
				end
			end)
			activePlays[player.UserId] = {track = track, connection = connection, humanoid = humanoid, playId = playId}

			-- control returns exactly when the swing ends — no guessing
			track.Ended:Connect(function()
				local play = activePlays[player.UserId]
				if play and play.track == track then
					restoreControl(player.UserId, humanoid)
				end
			end)

			track:Play()
		end

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
		restoreControl(player.UserId, nil)
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