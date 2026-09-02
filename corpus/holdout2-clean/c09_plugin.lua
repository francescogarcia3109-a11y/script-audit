local toolbar = plugin:CreateToolbar("Level Tools")
local button = toolbar:CreateButton("Snap", "Snap selection to grid", "rbxassetid://4458901886")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local GRID = 4

local function snap()
	ChangeHistoryService:SetWaypoint("Snap begin")
	for _, part in ipairs(Selection:Get()) do
		if part:IsA("BasePart") then
			local p = part.Position
			part.Position = Vector3.new(
				math.round(p.X / GRID) * GRID,
				p.Y,
				math.round(p.Z / GRID) * GRID
			)
		end
	end
	ChangeHistoryService:SetWaypoint("Snap end")
end

button.Click:Connect(snap)
