local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PLACE_IDS = {
	Arena = 121205119060363,
	Exploration = 75985153325136,
}

local ArenaData = require(ReplicatedStorage.Modules.ArenaData)

local VoteMap = ReplicatedStorage.Remotes.VoteMap
local RoundUpdate = ReplicatedStorage.Remotes.RoundUpdate
local RequestMatch = ReplicatedStorage.Remotes.RequestMatch

local Matchmaking = {}

-- ============================================================================
-- LOBBY SETTINGS (primitives for a future settings UI / admin commands)
--   mapPool: array of ArenaData keys, or nil = all maps
--   password: string, or nil = open lobby
-- ============================================================================
local settings = {
	mapPool = nil,
	password = nil,
}

function Matchmaking.configure(newSettings)
	if newSettings.mapPool ~= nil then
		for _, key in ipairs(newSettings.mapPool) do
			if not ArenaData[key] then
				error(("[Matchmaking] Unknown map key '%s' in mapPool"):format(tostring(key)))
			end
		end
	end
	settings.mapPool = newSettings.mapPool
	settings.password = newSettings.password
	return settings
end

local function activeMapPool()
	if settings.mapPool then return settings.mapPool end
	local keys = {}
	for k in pairs(ArenaData) do table.insert(keys, k) end
	return keys
end

-- ============================================================================
-- VOTE
-- ============================================================================
local VOTE_DURATION = 15

local vote = nil      -- { players = {[userId]=Player}, votes = {[userId]=mapKey}, endsAt, active, password }
local teleporting = false

local function mapList()
	local list = {}
	for _, key in ipairs(activeMapPool()) do
		local info = ArenaData[key]
		if info then
			table.insert(list, { Key = key, Name = info.Name,
				Description = info.Description, Image = info.Image })
		end
	end
	table.sort(list, function(a, b) return a.Name < b.Name end)
	return list
end

local function pickWinner(v)
	local counts = {}
	for _, mk in pairs(v.votes) do counts[mk] = (counts[mk] or 0) + 1 end
	local winner, max = nil, -1
	for k, c in pairs(counts) do if c > max then max = c; winner = k end end
	if winner then return winner end
	local pool = activeMapPool()
	return pool[math.random(1, #pool)]
end

local function joinVote(player, password)
	local v = vote
	if not v or not v.active then return false end
	if v.password and password ~= v.password then
		RoundUpdate:FireClient(player, { Type = "VoteDenied", Reason = "Wrong password" })
		return false
	end
	if v.players[player.UserId] then return true end
	v.players[player.UserId] = player
	local remaining = math.max(1, math.ceil(v.endsAt - os.clock()))
	RoundUpdate:FireClient(player, { Type = "VoteStart", Maps = mapList(), Time = remaining })
	return true
end

function Matchmaking.startVote(hostPlayer, opts)
	if vote or teleporting then return end
	local password = (opts and opts.password) or settings.password
	vote = {
		players = { [hostPlayer.UserId] = hostPlayer },
		votes = {},
		endsAt = os.clock() + VOTE_DURATION,
		active = true,
		password = password,
	}
	RoundUpdate:FireClient(hostPlayer, { Type = "VoteStart", Maps = mapList(), Time = VOTE_DURATION })
	task.delay(VOTE_DURATION, function()
		local v = vote
		if v and v.active and os.clock() >= v.endsAt - 0.5 then
			Matchmaking.endVote()
		end
	end)
end

function Matchmaking.endVote()
	local v = vote
	if not v then return end
	v.active = false

	local winner = pickWinner(v)
	vote = nil

	local members, userIds = {}, {}
	for uid, p in pairs(v.players) do
		if p.Parent and p.Character then
			table.insert(members, p)
			table.insert(userIds, uid)
		end
	end
	if #members == 0 then return end

	-- hide the vote panel and show the arena splash before the teleport
	for _, p in ipairs(members) do
		RoundUpdate:FireClient(p, { Type = "RoundStart", ArenaName = ArenaData[winner].Name })
	end

	teleporting = true

	-- Reserve a fresh, isolated server instance for this match only.
	-- Without this, TeleportAsync drops players into any public arena
	-- server, and separate matches would share one server.
	local okReserve, reservedCode = pcall(function()
		return TeleportService:ReserveServer(PLACE_IDS.Arena)
	end)

	local options = Instance.new("TeleportOptions")
	if okReserve and reservedCode then
		options.ReservedServer = reservedCode
	end
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

-- ============================================================================
-- REMOTE HANDLERS
-- ============================================================================
VoteMap.OnServerEvent:Connect(function(player, mapKey)
	if not vote or not vote.active then return end
	if not vote.players[player.UserId] then return end -- must be in the vote to cast
	vote.votes[player.UserId] = mapKey
end)

RequestMatch.OnServerEvent:Connect(function(player, opts)
	if teleporting then return end
	if vote and vote.active then
		-- late join: anyone who requests during the countdown joins the vote
		local password = opts and opts.password
		joinVote(player, password)
		return
	end
	Matchmaking.startVote(player, opts)
end)

return Matchmaking