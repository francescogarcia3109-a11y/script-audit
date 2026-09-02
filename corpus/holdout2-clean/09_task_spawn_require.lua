-- ServerScriptService/Preload
local Modules = game:GetService("ServerStorage"):WaitForChild("Modules")

for _, m in ipairs(Modules:GetChildren()) do
	if m:IsA("ModuleScript") then
		task.spawn(require, m)
	end
end
