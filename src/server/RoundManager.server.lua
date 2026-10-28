local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local ArenaData = require(ReplicatedStorage.Modules.ArenaData)
local RoundSignal = ReplicatedStorage:WaitForChild("RoundSignal")

-- Remotes
local VoteMap = ReplicatedStorage.Remotes:FindFirstChild("VoteMap") or Instance.new("RemoteEvent")
local RoundUpdate = ReplicatedStorage.Remotes:FindFirstChild("RoundUpdate") or Instance.new("RemoteEvent")
local RequestRoundStart = ReplicatedStorage.Remotes:FindFirstChild("RequestRoundStart") or Instance.new("RemoteEvent")

if not VoteMap.Parent then VoteMap.Name = "VoteMap"; VoteMap.Parent = ReplicatedStorage.Remotes end
if not RoundUpdate.Parent then RoundUpdate.Name = "RoundUpdate"; RoundUpdate.Parent = ReplicatedStorage.Remotes end
if not RequestRoundStart.Parent then RequestRoundStart.Name = "RequestRoundStart"; RequestRoundStart.Parent = ReplicatedStorage.Remotes end



local RoundManager = {
	currentRound = nil,
	voteState = nil,
	LOBBY_SPAWN = CFrame.new(0, 10, 0),
	ROUND_TIME = 60, -- seconds
	MIN_PLAYERS = 1, -- set to 2 for release
	MATCH_Y = 500,
	MATCH_SPACING = 500,
}

local usedSlots = {} -- [slotIndex] = true when occupied

function RoundManager.AllocateSlot()
	for i = 0, 99 do
		if not usedSlots[i] then
			usedSlots[i] = true
			return i
		end
	end
	return 0 -- fallback
end

function RoundManager.FreeSlot(index)
	usedSlots[index] = nil
end

-- ============================================================================
-- VOTING (unchanged logic, included for completeness)
-- ============================================================================

function RoundManager.GetMapList()
	local list = {}
	for key, data in pairs(ArenaData) do
		table.insert(list, {
			Key = key,
			Name = data.Name,
			Image = data.Image,
			Description = data.Description,
		})
	end
	return list
end

function RoundManager.StartVote(players)
	if #players < RoundManager.MIN_PLAYERS then return end

	RoundManager.voteState = {
		votes = {},
		players = players,
		timer = 15,
		active = true,
	}

	for _, p in ipairs(players) do
		RoundManager.voteState.votes[p.UserId] = nil
	end

	for _, p in ipairs(players) do
		RoundUpdate:FireClient(p, {
			Type = "VoteStart",
			Maps = RoundManager.GetMapList(),
			Time = RoundManager.voteState.timer,
		})
	end

	task.delay(RoundManager.voteState.timer, function()
		if RoundManager.voteState and RoundManager.voteState.active then
			RoundManager.EndVote()
		end
	end)
end

function RoundManager.CastVote(player, mapKey)
	if not RoundManager.voteState or not RoundManager.voteState.active then return end
	if not ArenaData[mapKey] then return end

	RoundManager.voteState.votes[player.UserId] = mapKey

	local counts = {}
	for _, v in pairs(RoundManager.voteState.votes) do
		counts[v] = (counts[v] or 0) + 1
	end

	for _, p in ipairs(RoundManager.voteState.players) do
		RoundUpdate:FireClient(p, {
			Type = "VoteUpdate",
			Counts = counts,
		})
	end
end

function RoundManager.EndVote()
	if not RoundManager.voteState then return end
	RoundManager.voteState.active = false

	-- Filter to players who are still connected AND have a character
	local validPlayers = {}
	for _, p in ipairs(RoundManager.voteState.players) do
		if p.Parent and p.Character then
			table.insert(validPlayers, p)
		end
	end

	-- NOT ENOUGH PLAYERS: cancel cleanly
	if #validPlayers < RoundManager.MIN_PLAYERS then
		for _, p in ipairs(RoundManager.voteState.players) do
			if p.Parent then
				RoundUpdate:FireClient(p, {
					Type = "VoteCancel",
					Reason = "Not enough players",
				})
			end
		end
		RoundManager.voteState = nil
		return
	end

	-- Pick winner from votes (only valid voters count)
	local counts = {}
	for _, v in pairs(RoundManager.voteState.votes) do
		counts[v] = (counts[v] or 0) + 1
	end

	local winner = nil
	local maxVotes = -1
	for map, count in pairs(counts) do
		if count > maxVotes then
			maxVotes = count
			winner = map
		end
	end

	if not winner then
		local keys = {}
		for k in pairs(ArenaData) do table.insert(keys, k) end
		winner = keys[math.random(1, #keys)]
	end

	RoundManager.voteState = nil
	RoundManager.StartRound(validPlayers, winner)
end

-- ============================================================================
-- ROUND
-- ============================================================================

function RoundManager.StartRound(players, arenaKey)
	local info = ArenaData[arenaKey]
	if not info then return end

	local template = ServerStorage.Arenas:FindFirstChild(info.ModelName)
	if not template then
		warn("Arena model missing:", info.ModelName)
		return
	end

	-- Final safety: abort if everyone left during the vote
	local validPlayers = {}
	for _, p in ipairs(players) do
		if p.Parent and p.Character then
			table.insert(validPlayers, p)
		end
	end

	if #validPlayers < RoundManager.MIN_PLAYERS then
		for _, p in ipairs(players) do
			if p.Parent then
				RoundUpdate:FireClient(p, {
					Type = "VoteCancel",
					Reason = "Not enough players",
				})
			end
		end
		return
	end

		players = validPlayers  -- use the filtered list from here on


	-- Clone and anchor EVERYTHING before parenting to Workspace
	local arena = template:Clone()
	arena.Name = "ActiveArena"

	for _, part in ipairs(arena:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	-- Position arena in a sky slot (supports multiple simultaneous matches)
	local activeFolder = workspace:FindFirstChild("ActiveMatches") or Instance.new("Folder")
	activeFolder.Name = "ActiveMatches"
	activeFolder.Parent = workspace

	local slotIndex = RoundManager.AllocateSlot()

	local matchCF = CFrame.new(slotIndex * 500, 500, 0) * CFrame.Angles(math.rad(90), 0, 0)
	arena:PivotTo(matchCF)
	arena.Parent = activeFolder

	-- Collect spawn points AFTER positioning (world-space CFrames)
	local spawns = {}
	for _, child in ipairs(arena:GetDescendants()) do
		if child:IsA("BasePart") and child.Name:match("^Spawn%d+$") then
			table.insert(spawns, child.CFrame)
		end
	end

	RoundManager.currentRound = {
		arena = arena,
		arenaKey = arenaKey,
		players = {},
		active = true,
		startTime = os.clock(),
		initialPlayerCount = #players,
		slotIndex = slotIndex,
	}

	-- Teleport and reset
	for i, p in ipairs(players) do
		if p.Character then
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = hum.MaxHealth
				hum.WalkSpeed = 16
			end

			local spawnCF = spawns[i] or spawns[1] or matchCF
			-- Lift slightly so they don't spawn inside floor
			p.Character:PivotTo(spawnCF + Vector3.new(0, 7, 0))

			RoundManager.currentRound.players[p.UserId] = {
				player = p,
				alive = true,
			}

			-- Fresh hand for the round
			-- RoundSignal:Fire("Deal", p)
			RoundSignal:Fire("Deal", p, "StandardPVP")
		end
	end

	for _, p in ipairs(players) do
		RoundUpdate:FireClient(p, {
			Type = "RoundStart",
			Arena = arenaKey,
			ArenaName = info.Name,
			Time = RoundManager.ROUND_TIME,
		})
	end

	task.spawn(RoundManager.MonitorRound)
end

function RoundManager.MonitorRound()
	local round = RoundManager.currentRound
	if not round then return end

	local endTime = round.startTime + RoundManager.ROUND_TIME

	while round.active do
		local now = os.clock()
		local timeLeft = math.max(0, endTime - now)

		-- Check health / death
		local aliveCount = 0
		local lastAlive = nil

		for userId, data in pairs(round.players) do
			local p = data.player
			if p.Parent and p.Character then
				local hum = p.Character:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					aliveCount += 1
					lastAlive = p
				elseif data.alive then
					data.alive = false
					for _, other in pairs(round.players) do
						RoundUpdate:FireClient(other.player, {
							Type = "PlayerDied",
							Player = p,
						})
					end
				end
			else
				data.alive = false
			end
		end

		-- END CONDITION 1: Time expired
		if timeLeft <= 0 then
			RoundManager.EndRound(nil) -- draw / timeout
			return
		end

		-- END CONDITION 2: Only one survivor AND we started with 2+
		if aliveCount <= 1 and round.initialPlayerCount >= 2 then
			RoundManager.EndRound(lastAlive)
			return
		end

		-- END CONDITION 3: All players out of cards (optional)
		-- This requires HandManager to expose deck state; skip for now
		-- or implement by checking playerHands if you expose it

		-- Broadcast timer every second
		local broadcastTime = math.ceil(timeLeft)
		if broadcastTime ~= round.lastBroadcast then
			round.lastBroadcast = broadcastTime
			for _, data in pairs(round.players) do
				RoundUpdate:FireClient(data.player, {
					Type = "Timer",
					TimeLeft = broadcastTime,
				})
			end
		end
		
		task.wait(0.5)
	end
end

function RoundManager.EndRound(winner)
	local round = RoundManager.currentRound
	if not round then return end
	round.active = false

	for userId, data in pairs(round.players) do
		RoundUpdate:FireClient(data.player, {
			Type = "RoundEnd",
			Winner = winner,
		})
	end

	task.wait(5)

	-- Return to lobby
	for userId, data in pairs(round.players) do
		local p = data.player
		if p.Character then
			p.Character:PivotTo(RoundManager.LOBBY_SPAWN)
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.Health = hum.MaxHealth end
		end
		RoundSignal:Fire("Clear", p)
	end

	if round.arena then
		round.arena:Destroy()
	end
	if round.slotIndex then
		RoundManager.FreeSlot(round.slotIndex)
	end

	RoundManager.currentRound = nil
end

-- ============================================================================
-- REMOTES
-- ============================================================================

VoteMap.OnServerEvent:Connect(function(player, mapKey)
	RoundManager.CastVote(player, mapKey)
end)

RequestRoundStart.OnServerEvent:Connect(function(player)
	if RoundManager.currentRound then return end
	if RoundManager.voteState then return end

	local all = Players:GetPlayers()
	if #all >= RoundManager.MIN_PLAYERS then
		RoundManager.StartVote(all)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if RoundManager.currentRound and RoundManager.currentRound.players[player.UserId] then
		RoundManager.currentRound.players[player.UserId].alive = false
	end
	if RoundManager.voteState then
		RoundManager.voteState.votes[player.UserId] = nil
	end
end)