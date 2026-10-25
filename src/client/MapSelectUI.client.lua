local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RoundUpdate = ReplicatedStorage.Remotes:WaitForChild("RoundUpdate")
local VoteMap = ReplicatedStorage.Remotes:WaitForChild("VoteMap")
local RequestRoundStart = ReplicatedStorage.Remotes:WaitForChild("RequestRoundStart")

local voteGui = nil
local voteTimer = nil
local hasVoted = false

-- ============================================================================
-- UI BUILDERS
-- ============================================================================

local function createVoteFrame()
	local old = playerGui:FindFirstChild("MapVoteGui")
	if old then old:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MapVoteGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "VoteFrame"
	frame.Size = UDim2.new(0, 520, 0, 300)
	frame.Position = UDim2.new(0.5, -260, 0.5, -150)
	frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 36)
	title.Position = UDim2.new(0, 0, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "SELECT ARENA"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 22
	title.Font = Enum.Font.GothamBold
	title.Parent = frame

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.Size = UDim2.new(0, 50, 0, 28)
	timer.Position = UDim2.new(1, -58, 0, 12)
	timer.BackgroundTransparency = 1
	timer.Text = "15"
	timer.TextColor3 = Color3.fromRGB(255, 200, 80)
	timer.TextSize = 20
	timer.Font = Enum.Font.GothamBold
	timer.Parent = frame

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, -30, 1, -60)
	container.Position = UDim2.new(0, 15, 0, 52)
	container.BackgroundTransparency = 1
	container.Parent = frame

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 12)
	list.Parent = container

	return { Gui = gui, Frame = frame, Container = container, Timer = timer }
end

local function showVote(maps, timeLeft)
	hasVoted = false
	voteGui = createVoteFrame()
	voteGui.Timer.Text = tostring(timeLeft)

	for _, info in ipairs(maps) do
		local btn = Instance.new("ImageButton")
		btn.Name = info.Key
		btn.Size = UDim2.new(0, 150, 0, 180)
		btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.Image = info.Image or ""
		btn.ScaleType = Enum.ScaleType.Crop
		btn.Parent = voteGui.Container

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(60, 60, 60)
		stroke.Parent = btn

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, 0, 0, 26)
		nameLabel.Position = UDim2.new(0, 0, 1, -48)
		nameLabel.BackgroundTransparency = 0.3
		nameLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		nameLabel.Text = info.Name
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextSize = 15
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Parent = btn

		local descLabel = Instance.new("TextLabel")
		descLabel.Size = UDim2.new(1, -8, 0, 18)
		descLabel.Position = UDim2.new(0, 4, 1, -22)
		descLabel.BackgroundTransparency = 1
		descLabel.Text = info.Description or ""
		descLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
		descLabel.TextSize = 10
		descLabel.Font = Enum.Font.Gotham
		descLabel.Parent = btn

		btn.MouseButton1Click:Connect(function()
			if hasVoted then return end
			hasVoted = true
			VoteMap:FireServer(info.Key)
			stroke.Color = Color3.fromRGB(0, 200, 255)
			TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(45, 45, 55)}):Play()
		end)
	end

	-- Countdown
	if voteTimer then voteTimer:Disconnect() end
	local endTime = os.clock() + timeLeft
	voteTimer = game:GetService("RunService").Heartbeat:Connect(function()
		local raw = endTime - os.clock()
		local remaining = math.max(0, math.ceil(raw))
		voteGui.Timer.Text = tostring(remaining)
		if raw <= 0 then
			voteTimer:Disconnect()
			voteTimer = nil
		end
	end)
end

local function hideVote()
	if voteGui and voteGui.Gui then
		voteGui.Gui:Destroy()
		voteGui = nil
	end
	if voteTimer then
		voteTimer:Disconnect()
		voteTimer = nil
	end
end

local function showRoundStart(arenaName)
	hideVote()

	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundStartGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 60)
	label.Position = UDim2.new(0, 0, 0.3, 0)
	label.BackgroundTransparency = 1
	label.Text = arenaName
	label.TextColor3 = Color3.fromRGB(255, 200, 80)
	label.TextSize = 44
	label.Font = Enum.Font.GothamBold
	label.Parent = gui

	TweenService:Create(label, TweenInfo.new(0.5), {Position = UDim2.new(0, 0, 0.35, 0)}):Play()

	task.delay(2.5, function()
		if gui then gui:Destroy() end
	end)
end

local function showRoundEnd(winner)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundEndGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 80)
	label.Position = UDim2.new(0, 0, 0.4, 0)
	label.BackgroundTransparency = 1
	if winner then
		label.Text = winner.Name .. " WINS!"
	else
		label.Text = "DRAW"
	end
	label.TextColor3 = winner and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 255, 255)
	label.TextSize = 40
	label.Font = Enum.Font.GothamBold
	label.Parent = gui

	task.delay(4, function()
		if gui then gui:Destroy() end
	end)
end

-- ============================================================================
-- REMOTE HANDLERS
-- ============================================================================

RoundUpdate.OnClientEvent:Connect(function(data)
	if data.Type == "VoteStart" then
		showVote(data.Maps, data.Time)
	elseif data.Type == "VoteUpdate" then
		-- vote counts (optional)
	elseif data.Type == "VoteCancel" then
		hideVote()
	elseif data.Type == "RoundStart" then
		showRoundStart(data.ArenaName)
	elseif data.Type == "RoundEnd" then
		showRoundEnd(data.Winner)
	elseif data.Type == "PlayerDied" then
		-- kill feed (optional)
	elseif data.Type == "Timer" then
		-- optional: show match timer HUD
	end
end)

-- ============================================================================
-- INPUT
-- ============================================================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.M then
		RequestRoundStart:FireServer()
	end
end)