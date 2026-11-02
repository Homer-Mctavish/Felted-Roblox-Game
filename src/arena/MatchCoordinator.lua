-- Arena MatchCoordinator: reconstructs one match per server from teleport
-- data, and injects the arena's rules into the shared CardServer.
-- Self-wiring: requiring this module sets up arrival tracking, card rules,
-- and a debug fallback. Arena Boot only needs to require it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchSession = require(script.Parent.MatchSession)
local CardServer = require(ReplicatedStorage.Modules.CardServer)

local Coordinator = {
	sessions = {},
	arrived = {},
	data = nil,
	deadline = 0,
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
function Coordinator.launch(data, players)
	local session = MatchSession.new(players, data.Arena, data.Preset)
	session.onCleanup = function()
		Coordinator.removeSession(session)
	end
	table.insert(Coordinator.sessions, session)
	session:enterPhase("Loading")
	return session
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
			if p and p.Character then
				table.insert(players, p)
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
	CardServer.start({
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
			return session:getCombat(target):takeDamage(amount)
		end,
	})
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

-- DEV ONLY: no teleport data (testing arena.rbxl directly) → start a debug
-- match with whoever is present. Delete this block once the hub chain works.
task.delay(5, function()
	if Coordinator.data or #Coordinator.sessions > 0 then return end
	local present = Players:GetPlayers()
	if #present == 0 then return end
	warn("[MatchCoordinator] No teleport data; starting debug match")
	Coordinator.launch({Arena = "Dojo", Preset = "StandardPVP"}, present)
end)

startCardServer()

return Coordinator