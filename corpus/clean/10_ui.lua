local gui = script.Parent
local button = gui:WaitForChild("Play")
button.MouseButton1Click:Connect(function()
	gui.Enabled = false
	game:GetService("ReplicatedStorage").StartGame:FireServer()
end)
