local LocalHand = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- State
local selectedIndex = nil
local cardButtons = {}
local currentHand = {}
local currentSelectableCount = 3
local currentDeckCount = 0
local slotLocks = {false, false, false}
local extraPlays = 0
local onPlayCallback = nil
local CardDataRef = nil

-- Colors
local COLOR_SELECTABLE_BG = Color3.fromRGB(25, 25, 25)
local COLOR_SELECTABLE_STROKE = Color3.fromRGB(70, 70, 70)
local COLOR_SELECTABLE_STROKE_HOVER = Color3.fromRGB(160, 160, 160)

local COLOR_HIDDEN_BG = Color3.fromRGB(15, 15, 15)
local COLOR_HIDDEN_STROKE = Color3.fromRGB(40, 40, 40)

local COLOR_EXTRA_PLAY_BG = Color3.fromRGB(30, 20, 35)
local COLOR_EXTRA_PLAY_STROKE = Color3.fromRGB(180, 120, 255)
local COLOR_EXTRA_PLAY_STROKE_HOVER = Color3.fromRGB(220, 170, 255)

local COLOR_JAMMED_BG = Color3.fromRGB(35, 10, 10)
local COLOR_JAMMED_STROKE = Color3.fromRGB(200, 50, 50)

local COLOR_SELECTED_STROKE = Color3.fromRGB(0, 200, 255)

-- ============================================================================
-- TOAST SYSTEM
-- ============================================================================
local toastQueue = {}
local toastActive = false

local function processToastQueue()
	if toastActive or #toastQueue == 0 then return end
	toastActive = true

	local msg = table.remove(toastQueue, 1)
	local gui = playerGui:FindFirstChild("LocalHandGui")
	if not gui then
		toastActive = false
		return
	end

	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.Size = UDim2.new(0, 280, 0, 40)
	toast.Position = UDim2.new(0.5, -140, 0.85, 0)
	toast.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	toast.BackgroundTransparency = 1
	toast.Text = msg
	toast.TextColor3 = Color3.fromRGB(255, 255, 255)
	toast.TextSize = 18
	toast.Font = Enum.Font.GothamBold
	toast.TextTransparency = 1
	toast.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = toast

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 200, 255)
	stroke.Transparency = 1
	stroke.Parent = toast

	local inInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(toast, inInfo, {BackgroundTransparency = 0.3, TextTransparency = 0}):Play()
	TweenService:Create(stroke, inInfo, {Transparency = 0}):Play()

	task.wait(1.8)

	local outInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(toast, outInfo, {BackgroundTransparency = 1, TextTransparency = 1}):Play()
	TweenService:Create(stroke, outInfo, {Transparency = 1}):Play()

	task.wait(0.35)
	toast:Destroy()
	toastActive = false
	processToastQueue()
end

function LocalHand.showToast(message)
	table.insert(toastQueue, message)
	processToastQueue()
end

-- ============================================================================
-- CREATION
-- ============================================================================
function LocalHand.create(CardData, playCallback)
	onPlayCallback = playCallback

	local old = playerGui:FindFirstChild("LocalHandGui")
	if old then old:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LocalHandGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- Deck counter
	local deckFrame = Instance.new("Frame")
	deckFrame.Name = "DeckCounter"
	deckFrame.Size = UDim2.new(0, 90, 0, 90)
	deckFrame.Position = UDim2.new(1, -110, 1, -130)
	deckFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	deckFrame.BorderSizePixel = 0
	deckFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = deckFrame

	local deckLabel = Instance.new("TextLabel")
	deckLabel.Name = "Count"
	deckLabel.Size = UDim2.new(1, 0, 1, 0)
	deckLabel.BackgroundTransparency = 1
	deckLabel.Text = "0"
	deckLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	deckLabel.TextSize = 32
	deckLabel.Font = Enum.Font.GothamBold
	deckLabel.Parent = deckFrame

	local deckTitle = Instance.new("TextLabel")
	deckTitle.Size = UDim2.new(1, 0, 0, 20)
	deckTitle.Position = UDim2.new(0, 0, 0, 6)
	deckTitle.BackgroundTransparency = 1
	deckTitle.Text = "DECK"
	deckTitle.TextColor3 = Color3.fromRGB(160, 160, 160)
	deckTitle.TextSize = 12
	deckTitle.Font = Enum.Font.Gotham
	deckTitle.Parent = deckFrame

	-- Hand container
	local container = Instance.new("Frame")
	container.Name = "HandContainer"
	container.Size = UDim2.new(0, 480, 0, 120)
	container.Position = UDim2.new(0.5, -240, 1, -140)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.Parent = container

	for i = 1, 6 do
		local button = Instance.new("ImageButton")
		button.Name = "Card" .. i
		button.Size = UDim2.new(0, 64, 0, 90)
		button.BackgroundColor3 = COLOR_SELECTABLE_BG
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Visible = false
		button.Parent = container

		local cornerBtn = Instance.new("UICorner")
		cornerBtn.CornerRadius = UDim.new(0, 8)
		cornerBtn.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Thickness = 2
		stroke.Color = COLOR_SELECTABLE_STROKE
		stroke.Parent = button

		local label = Instance.new("TextLabel")
		label.Name = "StatusLabel"
		label.Size = UDim2.new(1, 0, 0, 18)
		label.Position = UDim2.new(0, 0, 1, -20)
		label.BackgroundTransparency = 0.3
		label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		label.Text = "UPCOMING"
		label.TextColor3 = Color3.fromRGB(180, 180, 180)
		label.TextSize = 11
		label.Font = Enum.Font.GothamBold
		label.Visible = false
		label.Parent = button

		button.MouseButton1Click:Connect(function()
			LocalHand.selectCard(i)
		end)

		button.MouseEnter:Connect(function()
			if selectedIndex == i then return end
			local isSelectable, isJammed = LocalHand._getSlotState(i)
			if isJammed then
				stroke.Color = Color3.fromRGB(255, 80, 80)
			elseif isSelectable then
				if extraPlays > 0 and i > 3 then
					stroke.Color = COLOR_EXTRA_PLAY_STROKE_HOVER
				else
					stroke.Color = COLOR_SELECTABLE_STROKE_HOVER
				end
			end
		end)

		button.MouseLeave:Connect(function()
			if selectedIndex == i then return end
			LocalHand._applyBaseStroke(i)
		end)

		cardButtons[i] = button
	end

	return screenGui
end

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================
function LocalHand._getSlotState(index)
	if index <= 3 and slotLocks[index] then
		return false, true
	end
	if index <= currentSelectableCount then
		return true, false
	end
	if extraPlays > 0 and currentHand[index] then
		return true, false
	end
	return false, false
end

function LocalHand._applyBaseStroke(index)
	local button = cardButtons[index]
	if not button then return end

	local isSelectable, isJammed = LocalHand._getSlotState(index)
	if selectedIndex == index then
		button.Stroke.Color = COLOR_SELECTED_STROKE
		button.Stroke.Thickness = 3
	elseif isJammed then
		button.Stroke.Color = COLOR_JAMMED_STROKE
		button.Stroke.Thickness = 2
	elseif isSelectable and index > 3 and extraPlays > 0 then
		button.Stroke.Color = COLOR_EXTRA_PLAY_STROKE
		button.Stroke.Thickness = 2
	elseif isSelectable then
		button.Stroke.Color = COLOR_SELECTABLE_STROKE
		button.Stroke.Thickness = 2
	else
		button.Stroke.Color = COLOR_HIDDEN_STROKE
		button.Stroke.Thickness = 2
	end
end

function LocalHand._updateCardVisuals()
	for i = 1, 6 do
		local button = cardButtons[i]
		local cardName = currentHand[i]
		local isSelectable, isJammed = LocalHand._getSlotState(i)

		if cardName then
			button.Visible = true
			button.ImageTransparency = 1
			button.BackgroundTransparency = 1
			button.Stroke.Transparency = 1
			button.StatusLabel.TextTransparency = 1
			button.StatusLabel.BackgroundTransparency = 1

			button.Image = (CardDataRef and CardDataRef[cardName] and CardDataRef[cardName].Image) or ""

			if isJammed then
				button.BackgroundColor3 = COLOR_JAMMED_BG
				button.StatusLabel.Visible = true
				button.StatusLabel.Text = "JAMMED"
				button.StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
			elseif isSelectable and i > 3 and extraPlays > 0 then
				button.BackgroundColor3 = COLOR_EXTRA_PLAY_BG
				button.StatusLabel.Visible = true
				button.StatusLabel.Text = "FREE PLAY"
				button.StatusLabel.TextColor3 = Color3.fromRGB(200, 150, 255)
			elseif not isSelectable then
				button.BackgroundColor3 = COLOR_HIDDEN_BG
				button.StatusLabel.Visible = true
				button.StatusLabel.Text = "UPCOMING"
				button.StatusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
			else
				button.BackgroundColor3 = COLOR_SELECTABLE_BG
				button.StatusLabel.Visible = false
			end

			LocalHand._applyBaseStroke(i)
		else
			button.Visible = false
			button.Image = ""
			button.StatusLabel.Visible = false
			button.Stroke.Color = COLOR_SELECTABLE_STROKE
			button.Stroke.Thickness = 2
		end
	end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================
function LocalHand.updateDeckCount(count)
	currentDeckCount = count
	local gui = playerGui:FindFirstChild("LocalHandGui")
	if not gui then return end
	local label = gui.DeckCounter:FindFirstChild("Count")
	if label then
		label.Text = tostring(count)
	end
end

function LocalHand.setSlotLocks(lockTable)
	slotLocks = lockTable or {false, false, false}
	LocalHand._updateCardVisuals()
end

function LocalHand.setExtraPlays(count)
	extraPlays = count or 0
	LocalHand._updateCardVisuals()
end

function LocalHand.update(hand, CardDataParam, selectableCountParam, deckCount, playedIndex)
	currentHand = hand or {}
	currentSelectableCount = selectableCountParam or 3
	CardDataRef = CardDataParam

	if deckCount then
		LocalHand.updateDeckCount(deckCount)
	end

	-- Fade out
	local fadeOutInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for i = 1, 6 do
		local button = cardButtons[i]
		if button and button.Visible then
			TweenService:Create(button, fadeOutInfo, {
				ImageTransparency = 1,
				BackgroundTransparency = 1
			}):Play()
			if button:FindFirstChild("Stroke") then
				TweenService:Create(button.Stroke, fadeOutInfo, {Transparency = 1}):Play()
			end
			if button:FindFirstChild("StatusLabel") then
				TweenService:Create(button.StatusLabel, fadeOutInfo, {
					TextTransparency = 1,
					BackgroundTransparency = 1
				}):Play()
			end
		end
	end

	task.wait(0.16)

	-- Update visuals
	LocalHand._updateCardVisuals()

	-- Clear invalid selection
	if selectedIndex then
		local isSelectable, isJammed = LocalHand._getSlotState(selectedIndex)
		if not isSelectable or isJammed or not currentHand[selectedIndex] then
			LocalHand.clearSelection()
		end
	end

	-- Fade in
	local fadeInInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for i = 1, 6 do
		local button = cardButtons[i]
		if button and button.Visible then
			local isSelectable, isJammed = LocalHand._getSlotState(i)
			local targetImageTransparency = (isSelectable and not isJammed) and 0 or 0.45
			local targetBgTransparency = 0

			TweenService:Create(button, fadeInInfo, {
				ImageTransparency = targetImageTransparency,
				BackgroundTransparency = targetBgTransparency
			}):Play()

			if button:FindFirstChild("Stroke") then
				TweenService:Create(button.Stroke, fadeInInfo, {Transparency = 0}):Play()
			end

			if button.StatusLabel.Visible then
				TweenService:Create(button.StatusLabel, fadeInInfo, {
					TextTransparency = 0,
					BackgroundTransparency = 0.3
				}):Play()
			end
		end
	end
end

function LocalHand.selectCard(index)
	local isSelectable, isJammed = LocalHand._getSlotState(index)
	if not isSelectable or isJammed then
		if isJammed then
			LocalHand.showToast("Slot jammed!")
		end
		return
	end

	if not currentHand[index] then return end

	if onPlayCallback then
		onPlayCallback(currentHand[index], index)
	end

	LocalHand.clearSelection()
	selectedIndex = index

	local button = cardButtons[index]
	if button then
		button.Stroke.Color = COLOR_SELECTED_STROKE
		button.Stroke.Thickness = 3
	end
end

function LocalHand.clearSelection()
	if selectedIndex and cardButtons[selectedIndex] then
		LocalHand._applyBaseStroke(selectedIndex)
	end
	selectedIndex = nil
end

function LocalHand.setSelectableCount(count)
	currentSelectableCount = count
	LocalHand._updateCardVisuals()
end

function LocalHand.getSelectedIndex()
	return selectedIndex
end

return LocalHand