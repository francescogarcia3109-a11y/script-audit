
-- LOADS: pcall runs a closure that RETURNS require (does not call it); the returned function is then invoked. The load happens outside the pcall, on the captured value.
local SafeInit = {}

function SafeInit.run(mod)
	local ok, resolver = pcall(function()
		return require
	end)
	if ok and resolver then
		return resolver(mod)
	end
	return nil
end

return SafeInit.run(script.Parent:WaitForChild("Init"))
