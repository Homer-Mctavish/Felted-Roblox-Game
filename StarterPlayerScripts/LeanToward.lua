local LeanToward = {}

local Players = game:GetService("Players")
local player = Players.LocalPlayer

function LeanToward.lean(targetCharacter, duration, pullRadius)
	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	if not root or not targetRoot then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
	end

	duration = duration or 0.5
	pullRadius = pullRadius or 12

	local start = os.clock()
	while os.clock() - start < duration do
		if not root.Parent or not targetRoot.Parent then
			break
		end

		local offset = targetRoot.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local dist = flat.Magnitude

		if dist > 0.05 and dist <= pullRadius then
			local strength = math.clamp((1 - dist / pullRadius) ^ 2, 0, 1)
			local desired = CFrame.lookAt(root.Position, root.Position + flat.Unit, Vector3.yAxis)
			local alpha = math.clamp(0.2 + strength * 0.35, 0.15, 0.5)
			root.CFrame = root.CFrame:Lerp(desired, alpha)
		end

		task.wait(0.03)
	end

	if humanoid then
		humanoid.AutoRotate = true
	end
end

return LeanToward
