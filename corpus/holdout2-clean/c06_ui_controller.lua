local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
local panel = gui:WaitForChild("Panel")

local OPEN = UDim2.fromScale(0.5, 0.5)
local SHUT = UDim2.fromScale(0.5, 1.5)
local INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local open = false

local function toggle()
	open = not open
	TweenService:Create(panel, INFO, { Position = open and OPEN or SHUT }):Play()
end

gui:WaitForChild("ToggleButton").Activated:Connect(toggle)
