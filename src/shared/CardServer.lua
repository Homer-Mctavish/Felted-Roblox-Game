local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CardData = require(ReplicatedStorage.Modules.CardData)
local Deck = require(ReplicatedStorage.Modules.Deck)
local EffectCommands = require(ReplicatedStorage.Modules.EffectCommands)
local CardInventory = require(ReplicatedStorage.Modules.CardInventory)

local CardServer = {}

function CardServer.start(rules)
	-- rules: {
	--   presetName: string,
	--   getCombat(player) -> combatState | nil,   -- nil = hands only, no combat
	--   canDamage(attacker, targetCharacter) -> boolean,
	--   damage(targetCharacter, amount, attacker) -> result,
	-- }

	local remotes = ReplicatedStorage.Remotes
	local PlayCard, UpdateHand, CombatUpdate = remotes.PlayCard, remotes.UpdateHand, remotes.CombatUpdate

	local playerDecks = {}
	local debounce = {}

	local function pushHand(player) -- same payload as today
		local deck = playerDecks[player.UserId]
		UpdateHand:FireClient(player, {
			fullHand = deck:getFullIds(), publicCards = deck:getPublic(),
			selectableCount = rules.preset.publicCardCount, deckCount = #deck.deck,
			isOwner = true, slotLocks = {false, false, false},
			extraPlays = rules.getCombat(player) and rules.getCombat(player).extraPlays or 0,
		})
		UpdateHand:FireAllClients({ player = player, publicCards = deck:getPublic(), isOwner = false })
	end

	function CardServer.deal(player)
		local preset = require(ReplicatedStorage.Modules.RoundPresets)[rules.presetName]
		local deck = Deck.new(preset)
		deck:build(CardInventory.getEquippedPool(player))
		deck:draw(preset.handSize)
		playerDecks[player.UserId] = deck
		pushHand(player)
	end

	PlayCard.OnServerEvent:Connect(function(player, cardName, targetCharacter)
		if debounce[player.UserId] then return end
		debounce[player.UserId] = true
		task.delay(0.35, function() debounce[player.UserId] = nil end)

		local deck = playerDecks[player.UserId]
		if not deck then return end
		-- find index, validate slot rules (same as today, using rules.getCombat(player))

		local combat = rules.getCombat(player)

		-- run effects through EffectCommands with a resolver ctx
		local ctx = {
			attacker = player,
			targetPlayer = targetCharacter and Players:GetPlayerFromCharacter(targetCharacter),
			targetCharacter = targetCharacter,
			deck = deck,
			combat = combat,                    -- attacker's own CombatState
			canDamage = rules.canDamage,
			damage = rules.damage,
			-- effect params (amount/stacks/duration) filled per effect
		}
		for _, def in ipairs(CardData[cardName].Effects or {}) do
			local cmd = EffectCommands[def.Type]
			if cmd then
				ctx.amount, ctx.stacks, ctx.duration = def.Amount, def.Stacks, def.Duration
				pcall(cmd, ctx)
			end
		end

		-- animation + displacement + pushHand (unchanged from current handler)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			CardServer.deal(player)
		end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(CardServer.deal, p) end

	return CardServer
end

return CardServer