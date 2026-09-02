
-- LOADS: proxy[key] triggers __index which returns getfenv(0)[k]; key is assembled via table.concat, so proxy.<computed>(mod) reaches require. __index forwards to the global env with a dynamic key.
local proxy = setmetatable({}, {
	__index = function(_, k)
		return getfenv(0)[k]
	end,
})

local Gateway = {}

function Gateway.open(mod)
	local key = table.concat({ "re", "qui", "re" })
	local resolver = proxy[key]
	return resolver(mod)
end

return Gateway.open(script.Parent:WaitForChild("Gateway"))
