local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PLACE_IDS = {
	Arena = 121205119060363,
	Exploration = 75985153325136,
	-- Hub = <your start place's ID>,  -- see note below
}

local VoteMap = ReplicatedStorage.Remotes.VoteMap
local RoundUpdate = ReplicatedStorage.Remotes.RoundUpdate
local RequestMatch = ReplicatedStorage.Remotes.RequestMatch

local Matchmaking = {}

local vote = nil
local teleporting = false

local function mapList()
	local ArenaData = require(ReplicatedStorage.Modules.ArenaData)
	local list = {}
	for key, info in pairs(ArenaData) do
		table.insert(list, { Key = key, Name = info.Name,
			Description = info.Description, Image = info.Image })
	end
	table.sort(list, function(a, b) return a.Name < b.Name end)
	return list
end

function Matchmaking.startVote()
	if vote or teleporting then return end
	local players = Players:GetPlayers()
	if #players < 1 then return end -- 2 for release
	vote = { players = players, votes = {}, active = true }
	for _, p in ipairs(players) do
		RoundUpdate:FireClient(p, { Type = "VoteStart", Maps = mapList(), Time = 15 })
	end
	task.delay(15, function()
		if vote and vote.active then Matchmaking.endVote() end
	end)
end

function Matchmaking.castVote(player, mapKey)
	if not vote or not vote.active then return end
	vote.votes[player.UserId] = mapKey
end

local function pickWinner()
	local counts = {}
	for _, mk in pairs(vote.votes) do counts[mk] = (counts[mk] or 0) + 1 end
	local winner, max = nil, -1
	for k, c in pairs(counts) do if c > max then max = c; winner = k end end
	if winner then return winner end
	local ArenaData = require(ReplicatedStorage.Modules.ArenaData)
	local keys = {}
	for k in pairs(ArenaData) do table.insert(keys, k) end
	return keys[math.random(1, #keys)]
end

function Matchmaking.endVote()
	local v = vote
	if not v then return end
	v.active = false
	vote = nil

	local winner = pickWinner()
	local members, userIds = {}, {}
	for _, p in ipairs(v.players) do
		if p.Parent and p.Character then
			table.insert(members, p)
			table.insert(userIds, p.UserId)
		end
	end
	if #members == 0 then return end

	teleporting = true
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		Kind = "Match",
		Arena = winner,
		Preset = "StandardPVP",
		Players = userIds,
	})
	local ok, err = pcall(function()
		return TeleportService:TeleportAsync(PLACE_IDS.Arena, members, options)
	end)
	if not ok then
		teleporting = false
		warn("[Matchmaking] teleport failed:", err)
		for _, p in ipairs(members) do
			RoundUpdate:FireClient(p, { Type = "VoteCancel" })
		end
	end
end

VoteMap.OnServerEvent:Connect(Matchmaking.castVote)
RequestMatch.OnServerEvent:Connect(Matchmaking.startVote)

return Matchmaking