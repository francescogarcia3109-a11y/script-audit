-- ReplicatedStorage/Modules/SafeLoader
local Modules = script.Parent:WaitForChild("Modules")

local loaded = {}

for _, child in ipairs(Modules:GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if ok then
			loaded[child.Name] = result
		else
			warn(("failed to load %s: %s"):format(child.Name, tostring(result)))
		end
	end
end

return loaded
