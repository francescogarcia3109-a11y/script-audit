local modules = script.Parent.Modules
local cache = {}

local function get(name)
	if not cache[name] then
		cache[name] = require(modules[name])
	end
	return cache[name]
end

return get
