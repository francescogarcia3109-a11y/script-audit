
-- LOADS: task.defer(require, mod) schedules require ITSELF as the callback with mod as its argument. The loader is invoked by the scheduler, not wrapped in a closure.
local Preloader = {}

function Preloader.queue(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("ModuleScript") then
			-- run each module's require on the next resumption cycle
			task.defer(require, child)
		end
	end
end

Preloader.queue(script.Parent:WaitForChild("Modules"))
return Preloader
