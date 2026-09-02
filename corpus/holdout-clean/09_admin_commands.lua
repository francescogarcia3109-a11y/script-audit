-- Command framework: each command is a ModuleScript under Commands/
local Commands = {}
local folder = script.Parent.Commands

for _, cmd in ipairs(folder:GetDescendants()) do
	if cmd:IsA("ModuleScript") then
		local def = require(cmd)
		Commands[def.Name:lower()] = def
	end
end

return Commands
