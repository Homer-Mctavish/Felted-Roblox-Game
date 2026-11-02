-- local Players = game:GetService("Players")
-- local DataStoreService = game:GetService("DataStoreService")

-- local PlayerData = {}
-- local cache = {}

-- local store = DataStoreService:GetDataStore("PlayerData_v1")
-- local CURRENT_SCHEMA = 1

-- local function defaultData()
-- 	return {
-- 		schemaVersion = CURRENT_SCHEMA,
-- 		decks = {
-- 			equipped = {
-- 				{id = "Strike",      count = 6, canRecycle = false},
-- 				{id = "Block",       count = 4, canRecycle = true},
-- 				{id = "HeavyStrike", count = 2, canRecycle = false},
-- 				{id = "Dodge",       count = 2, canRecycle = false},
-- 				{id = "Draw",        count = 2, canRecycle = false},
-- 				{id = "Recycle",     count = 2, canRecycle = true},
-- 			}
-- 		},
-- 		cosmetics = {},
-- 		currency = 0,
-- 		wins = 0,
-- 	}
-- end

-- local function migrate(data)
-- 	local v = data.schemaVersion or 0
-- 	-- for v = v + 1, CURRENT_SCHEMA do MIGRATIONS[v](data) end
-- 	data.schemaVersion = CURRENT_SCHEMA
-- 	return data
-- end

-- function PlayerData.load(player)
-- 	local ok, data = pcall(function()
-- 		return store:GetAsync(tostring(player.UserId))
-- 	end)
-- 	cache[player.UserId] = (ok and data and migrate(data)) or defaultData()
-- 	return cache[player.UserId]
-- end

-- function PlayerData.save(player)
-- 	local data = cache[player.UserId]
-- 	if not data then return end
-- 	pcall(function()
-- 		store:SetAsync(tostring(player.UserId), data)
-- 	end)
-- end

-- function PlayerData.get(player)
-- 	return cache[player.UserId] or defaultData()
-- end

-- Players.PlayerRemoving:Connect(function(player)
-- 	PlayerData.save(player)
-- 	cache[player.UserId] = nil
-- end)

-- game:BindToClose(function()
-- 	for _, player in ipairs(Players:GetPlayers()) do
-- 		PlayerData.save(player)
-- 	end
-- end)

-- return PlayerData

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileService = require(ReplicatedStorage.Vendor.ProfileService)

local PlayerData = {}
local profiles = {} -- [userId] = Profile

local CURRENT_SCHEMA = 2

local function defaultData()
	return {
		schemaVersion = CURRENT_SCHEMA,
		decks = { equipped = {
			{id = "Strike", count = 6, canRecycle = false},
			{id = "Block", count = 4, canRecycle = true},
			{id = "HeavyStrike", count = 2, canRecycle = false},
			{id = "Dodge", count = 2, canRecycle = false},
			{id = "Draw", count = 2, canRecycle = false},
			{id = "Recycle", count = 2, canRecycle = true},
		}},
		cosmetics = {},
		currency = 0,
		wins = 0,
	}
end

-- New store name: v2 gets session locking; nothing migrates from v1
local store = ProfileService.GetProfileStore("PlayerData_v2", defaultData())

function PlayerData.load(player)
	local profile = store:LoadProfileAsync("p_" .. player.UserId, "ForceLoad")
	if not profile then
		player:Kick("Your data is loaded elsewhere. Rejoin in a moment.")
		return nil
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile() -- fills missing fields from defaultData
	profile.OnSessionEnd:Connect(function()
		profiles[player.UserId] = nil
		player:Kick("Session ended. Rejoin.")
	end)
	profiles[player.UserId] = profile
	return profile.Data
end

function PlayerData.get(player)
	local p = profiles[player.UserId]
	if p then return p.Data end
	return defaultData() -- never nil; UI can render defaults pre-load
end

function PlayerData.release(player)
	local p = profiles[player.UserId]
	if p then p:Release() end -- Release auto-saves
end

Players.PlayerRemoving:Connect(function(player)
	PlayerData.release(player)
end)

return PlayerData