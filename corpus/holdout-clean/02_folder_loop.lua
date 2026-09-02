-- Loads every service module in a folder. The most common loader in Roblox.
local Services = script.Parent.Services
for _, module in ipairs(Services:GetChildren()) do
	if module:IsA("ModuleScript") then
		require(module)
	end
end
