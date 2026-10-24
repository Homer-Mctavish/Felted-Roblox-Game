local FloatingHand = {}

function FloatingHand.create(character)
	local head = character:WaitForChild("Head", 5)
	if not head then return end

	-- Remove old one if it exists
	local existing = head:FindFirstChild("FloatingHand")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FloatingHand"
	billboard.Adornee = head
	billboard.Size = UDim2.new(0, 180, 0, 80)
	billboard.StudsOffset = Vector3.new(0, 2.8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Parent = head

	local container = Instance.new("Frame")
	container.Name = "CardContainer"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = billboard

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.Parent = container

	for i = 1, 3 do
		local card = Instance.new("ImageLabel")
		card.Name = "Card" .. i
		card.Size = UDim2.new(0, 52, 0, 72)
		card.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		card.BorderSizePixel = 0
		card.Image = ""
		card.ScaleType = Enum.ScaleType.Fit
		card.Parent = container

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = Color3.fromRGB(80, 80, 80)
		stroke.Parent = card
	end

	return billboard
end

function FloatingHand.update(character, publicCards, CardData)
	local head = character:FindFirstChild("Head")
	if not head then return end

	local billboard = head:FindFirstChild("FloatingHand")
	if not billboard then
		billboard = FloatingHand.create(character)
	end

	local container = billboard:FindFirstChild("CardContainer")
	if not container then return end

	for i = 1, 3 do
		local cardLabel = container:FindFirstChild("Card" .. i)
		if cardLabel then
			local cardName = publicCards[i]
			if cardName and CardData[cardName] then
				cardLabel.Image = CardData[cardName].Image
			else
				cardLabel.Image = ""
			end
		end
	end
end

return FloatingHand