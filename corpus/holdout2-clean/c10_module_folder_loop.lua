local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local exports = {}

for _, child in ipairs(Shared:GetChildren()) do
	if child:IsA("ModuleScript") then
		exports[child.Name] = require(child)
	end
end

setmetatable(exports, {
	__index = function(_, key)
		error("no shared module named " .. tostring(key), 2)
	end,
})

return exports
