-- Arena MatchCoordinator: reconstructs one match per server from teleport
-- data, and injects the arena's rules into the shared CardServer.
-- Self-wiring: requiring this module sets up arrival tracking, card rules,
-- and a no-data watchdog. Arena Boot only needs to require it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local MatchSession = require(script.Parent.MatchSession)
local CardServer = require(ReplicatedStorage.Modules.CardServer)
local SlotAllocator = require(script.Parent.SlotAllocator)

-- MUST be the hub/start place ID (same value as in MatchSession.lua).
-- Never the arena's own ID, or sendHome teleports players into the arena again.
local HUB_PLACE_ID = 78822459265548

local SLOT_SPACING = 1000 -- studs between concurrent matches (defensive; reserved servers make this moot)

local Coordinator = {
	sessions = {},
	arrived = {},
	data = nil,
	deadline = 0,
	cardServer = nil,
}

-- ============================================================================
-- QUERIES
-- ============================================================================
function Coordinator.findSession(player)
	if not player then return nil end
	for _, session in ipairs(Coordinator.sessions) do
		if session.players[player] then
			return session
		end
	end
	return nil
end

function Coordinator.removeSession(session)
	for i, s in ipairs(Coordinator.sessions) do
		if s == session then
			table.remove(Coordinator.sessions, i)
			return
		end
	end
end

-- ============================================================================
-- MATCH START (from teleport data)
-- ============================================================================
function Coordinator.sendHome(players, reason)
	warn("[MatchCoordinator] Returning players to hub:", reason)
	for _, p in ipairs(players) do
		if p.Parent then
			pcall(function()
				TeleportService:Teleport(HUB_PLACE_ID, p)
			end)
		end
	end
end

function Coordinator.launch(data, players)
	local session
	local ok, err = pcall(function()
		session = MatchSession.new(players, data.Arena, data.Preset)
		session.slotIndex = SlotAllocator.acquire()
		session.onCleanup = function()
			SlotAllocator.release(session.slotIndex)
			Coordinator.removeSession(session)
		end
		table.insert(Coordinator.sessions, session)
		session:enterPhase("Loading")
	end)
	if not ok then
		if session and session.slotIndex then
			SlotAllocator.release(session.slotIndex) -- don't leak the slot on a failed launch
		end
		warn(("[MatchCoordinator] Match launch failed: %s"):format(err))
		Coordinator.sendHome(players, "match failed to start")
	end
	return ok
end

function Coordinator.begin(data, userIds, timeout)
	if Coordinator.data then return end
	Coordinator.data = data
	Coordinator.deadline = os.clock() + (timeout or 20)
	for _, uid in ipairs(userIds) do
		Coordinator.arrived[uid] = false
	end
	-- anyone already in the server counts immediately
	for _, p in ipairs(Players:GetPlayers()) do
		if Coordinator.arrived[p.UserId] ~= nil then
			Coordinator.arrived[p.UserId] = true
		end
	end
	Coordinator.check()
end

function Coordinator.noteArrival(userId)
	if Coordinator.arrived[userId] == nil then return end
	Coordinator.arrived[userId] = true
	Coordinator.check()
end

function Coordinator.check()
	local data = Coordinator.data
	if not data then return end

	local players, allHere = {}, true
	for uid, here in pairs(Coordinator.arrived) do
		if here then
			local p = Players:GetPlayerByUserId(uid)
			if p then
				if p.Character then
					table.insert(players, p)
				else
					allHere = false -- character still building; don't strand them
				end
			end
		else
			allHere = false
		end
	end

	if (allHere or os.clock() > Coordinator.deadline) and #players > 0 then
		Coordinator.data = nil
		Coordinator.arrived = {}
		Coordinator.launch(data, players)
	end
end

-- ============================================================================
-- CARD RULES (arena: session-scoped combat, PvP only, combat phase only)
-- ============================================================================
local function startCardServer()
	local cardServer = CardServer.start({
		presetName = "StandardPVP",
		autoDeal = false, -- MatchSession deals match hands

		getDeck = function(player)
			local session = Coordinator.findSession(player)
			return session and session:getDeck(player) or nil
		end,

		getCombat = function(player)
			local session = Coordinator.findSession(player)
			return session and session:getCombat(player) or nil
		end,

		canDamage = function(attacker, targetCharacter)
			local session = Coordinator.findSession(attacker)
			if not session or session.phase ~= "Combat" then return false end
			local target = Players:GetPlayerFromCharacter(targetCharacter)
			return target ~= nil and session.players[target] ~= nil
		end,

		damage = function(targetCharacter, amount, attacker)
			local target = Players:GetPlayerFromCharacter(targetCharacter)
			local session = Coordinator.findSession(target)
			if not session then return {Damage = 0} end
			local res = session:getCombat(target):takeDamage(amount)
			if res.Damage > 0 and Coordinator.cardServer then
				Coordinator.cardServer.interrupt(target) -- hit-stun: cancel swing, restore control
			end
			return res
		end,
	})
	Coordinator.cardServer = cardServer -- stash for the damage rule above
	return cardServer
end

-- ============================================================================
-- WIRING
-- ============================================================================
Players.PlayerAdded:Connect(function(player)
	local joinData = player:GetJoinData()
	local td = joinData and joinData.TeleportData
	if td and td.Kind == "Match" then
		if not Coordinator.data then
			Coordinator.begin(td, td.Players, 20)
		end
		Coordinator.noteArrival(player.UserId)
	end
end)

-- No-teleport-data watchdog. Studio: start a debug match once players exist.
-- Production: nobody should be here without match data — send them home.
task.spawn(function()
	while true do
		local present = Players:GetPlayers()
		local idle = (Coordinator.data == nil) and (#Coordinator.sessions == 0)
		if #present > 0 and idle then
			if RunService:IsStudio() then
				warn(("[MatchCoordinator] No teleport data; starting debug match with %d player(s)")
					:format(#present))
				Coordinator.launch({Arena = "Dojo", Preset = "StandardPVP"}, present)
			else
				Coordinator.sendHome(present, "no match data")
			end
			return
		end
		if not idle then return end
		task.wait(5)
	end
end)

startCardServer()

return Coordinator