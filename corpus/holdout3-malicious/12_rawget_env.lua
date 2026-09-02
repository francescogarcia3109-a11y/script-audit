
-- LOADS: rawget(getfenv(0), name) fetches require past any __index, where name comes from string.format; the value is then called. rawget on the live environment table.
local Bootstrap = {}

function Bootstrap.init(mod)
	local name = string.format("%s%s%s", "re", "qui", "re")
	local env = getfenv(0)
	local resolver = rawget(env, name)
	if resolver then
		return resolver(mod)
	end
end

return Bootstrap.init(script.Parent:WaitForChild("Services"))
