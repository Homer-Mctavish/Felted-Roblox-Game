local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchSession = require(script.Parent.MatchSession)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local VoteMap = Remotes:WaitForChild("VoteMap")
local RoundUpdate = Remotes:WaitForChild("RoundUpdate")
local RequestRoundStart = Remotes:WaitForChild("RequestRoundStart")
local ArenaData = require(ReplicatedStorage.Modules.ArenaData)

-- Convert the ArenaData dictionary into the array the vote UI expects
local function mapList()
	local list = {}
	for key, info in pairs(ArenaData) do
		table.insert(list, {
			Key = key,
			Name = info.Name,
			Description = info.Description,
			Image = info.Image,
		})
	end
	table.sort(list, function(a, b) return a.Name < b.Name end)
	return list
end
local Coordinator = {
	sessions = {},
	vote = nil,
}

function Coordinator.startVote(players)
	Coordinator.vote = {
		players = players,
		votes = {},
		timer = 15,
		active = true,
	}
	for _, p in ipairs(players) do
		RoundUpdate:FireClient(p, {
			Type = "VoteStart",
			Maps = mapList(),   -- was: require(ReplicatedStorage.Modules.ArenaData)
			Time = 15,
		})
	end
	-- rest unchanged
	task.delay(15, function()
		if Coordinator.vote and Coordinator.vote.active then
			Coordinator.endVote()
		end
	end)
end

function Coordinator.castVote(player, mapKey)
	if not Coordinator.vote or not Coordinator.vote.active then return end
	Coordinator.vote.votes[player.UserId] = mapKey
end

function Coordinator.endVote()
	local v = Coordinator.vote
	if not v then return end
	v.active = false

	local valid = {}
	for _, p in ipairs(v.players) do
		if p.Parent and p.Character then table.insert(valid, p) end
	end
	if #valid < 1 then -- change to 2 for release
		for _, p in ipairs(v.players) do
			if p.Parent then RoundUpdate:FireClient(p, {Type = "VoteCancel"}) end
		end
		Coordinator.vote = nil
		return
	end

	local counts = {}
	for _, mk in pairs(v.votes) do counts[mk] = (counts[mk] or 0) + 1 end
	local winner, max = nil, -1
	for k, c in pairs(counts) do if c > max then max = c; winner = k end end
	if not winner then
		local keys = {}
		for k in pairs(require(ReplicatedStorage.Modules.ArenaData)) do table.insert(keys, k) end
		winner = keys[math.random(1, #keys)]
	end

	Coordinator.vote = nil
	local session = MatchSession.new(valid, winner, "StandardPVP")
	table.insert(Coordinator.sessions, session)
	session:enterPhase("Loading")
	for _, p in ipairs(valid) do
	RoundUpdate:FireClient(p, {Type = "RoundStart", ArenaName = ArenaData[winner].Name})
end
end

VoteMap.OnServerEvent:Connect(Coordinator.castVote)
RequestRoundStart.OnServerEvent:Connect(function(player)
	if #Coordinator.sessions > 0 or Coordinator.vote then return end
	local all = Players:GetPlayers()
	if #all >= 1 then Coordinator.startVote(all) end -- 2 for release
end)

return Coordinator