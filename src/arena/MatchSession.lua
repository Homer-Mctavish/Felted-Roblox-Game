local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")

local HUB_PLACE_ID = 78822459265548
local EventBus = require(ReplicatedStorage.Modules.EventBus)
local Deck = require(ReplicatedStorage.Modules.Deck)
local CardInventory = require(ReplicatedStorage.Modules.CardInventory)
local CombatState = require(script.Parent.CombatState)
local RoundPresets = require(ReplicatedStorage.Modules.RoundPresets)
local ArenaData = require(ReplicatedStorage.Modules.ArenaData)

local UpdateHand = ReplicatedStorage.Remotes.UpdateHand

local MatchSession = {}
MatchSession.__index = MatchSession

function MatchSession.new(players, arenaKey, presetName)
	local self = setmetatable({}, MatchSession)
	self.id = HttpService:GenerateGUID(false)
	self.arenaKey = arenaKey  -- FIX #1: was never stored, loadArena() read nil
	self.preset = RoundPresets[presetName] or RoundPresets.StandardPVP
	self.players = {}
	self.phase = "Loading"
	self.timer = 0
	self.events = EventBus.new()
	self.arena = nil
	-- self.slotIndex = nil
	self.winner = nil

	for _, p in ipairs(players) do
		if p.Parent and p.Character then
			self.players[p] = {
				alive = true,
				combat = CombatState.new(p.Character:FindFirstChildOfClass("Humanoid")),
				deck = nil,
			}
		end
	end

		self.playerCount = #players

	return self
end

function MatchSession:loadArena()
	local info = ArenaData[self.arenaKey]
	local template = ServerStorage.Arenas:FindFirstChild(info.ModelName)
	local arena = template:Clone()

	for _, part in ipairs(arena:GetDescendants()) do
		if part:IsA("BasePart") then part.Anchored = true end
	end

	local folder = workspace:FindFirstChild("ActiveMatches") or Instance.new("Folder")
	folder.Name = "ActiveMatches"
	folder.Parent = workspace

	-- self.slotIndex = self:allocateSlot()
	-- local cf = CFrame.new(self.slotIndex * 500, 500, 0) * CFrame.Angles(math.rad(90), 0, 0)
	-- arena:PivotTo(cf)
	arena.Parent = folder
	self.arena = arena

	local spawns = {}
	for _, c in ipairs(arena:GetDescendants()) do
		if c:IsA("BasePart") and c.Name:match("^Spawn%d+$") then
			table.insert(spawns, c.CFrame)
		end
	end

	local arenaCF = arena:GetPivot()

	local i = 1
	for player, data in pairs(self.players) do
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.Health = 100; hum.WalkSpeed = 16 end

		local spawn = spawns[i] or spawns[1]
		if not spawn then
			warn(("[MatchSession] Arena '%s' has no SpawnN parts; spawning above arena origin")
				:format(info.ModelName))
			spawn = arenaCF + Vector3.new(0, 10, 0)  -- derived, not magic: "near the arena"
		end
		player.Character:PivotTo(spawn + Vector3.new(0, 3, 0))
		i += 1

		data.deck = Deck.new(self.preset)
		data.deck:build(CardInventory.getEquippedPool(player))
		data.deck:draw(self.preset.handSize)
		self:pushHand(player)
	end
end

-- function MatchSession:allocateSlot()
-- 	_G._matchSlots = _G._matchSlots or {}
-- 	for idx = 0, 99 do
-- 		if not _G._matchSlots[idx] then
-- 			_G._matchSlots[idx] = true
-- 			return idx
-- 		end
-- 	end
-- 	return 0
-- end

-- function MatchSession:freeSlot()
-- 	if self.slotIndex then
-- 		_G._matchSlots[self.slotIndex] = nil
-- 	end
-- end

function MatchSession:pushHand(player)
	local data = self.players[player]
	if not data then return end
	UpdateHand:FireClient(player, {
		fullHand = data.deck:getFullIds(),
		publicCards = data.deck:getPublic(),
		selectableCount = self.preset.publicCardCount,
		deckCount = #data.deck.deck,
		isOwner = true,
		slotLocks = {false, false, false},
		extraPlays = data.combat.extraPlays,
	})
	UpdateHand:FireAllClients({
		player = player,
		publicCards = data.deck:getPublic(),
		isOwner = false,
	})
end

function MatchSession:getDeck(player)
	local data = self.players[player]
	return data and data.deck or nil
end

function MatchSession:getCombat(player)
	local data = self.players[player]
	return data and data.combat or nil
end

function MatchSession:enterPhase(phase)
	self.phase = phase
	if phase == "Loading" then
		self:loadArena()
		task.delay(2, function() self:enterPhase("Combat") end)
	elseif phase == "Combat" then
		self.timer = self.preset.roundTime
		task.spawn(function()
			while self.phase == "Combat" do
				self.timer -= 0.5
				if self.timer <= 0 then self:enterPhase("Ended"); return end
				self:checkWin()
				task.wait(0.5)
			end
		end)
	elseif phase == "Ended" then
		task.delay(5, function() self:cleanup() end)
	end
end

function MatchSession:checkWin()
	local alive, last = 0, nil
	for p, d in pairs(self.players) do
		if d.alive and d.combat.health > 0 then
			alive += 1; last = p
		elseif d.alive and d.combat.health <= 0 then
			d.alive = false
		end
	end
	if alive <= 1 and self.playerCount >= 2 then
		self.winner = last
		self:enterPhase("Ended")
	end
end

function MatchSession:cleanup()
	for p, d in pairs(self.players) do
		if p.Parent then
			pcall(function()
				TeleportService:Teleport(HUB_PLACE_ID, p)
			end)
		end
	end
	if self.arena then self.arena:Destroy() end
end

return MatchSession