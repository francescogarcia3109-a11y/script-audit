local part = workspace:WaitForChild("Spinner")
while task.wait(0.03) do
	part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(2), 0)
end
