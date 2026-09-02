-- ServerScriptService/ServiceRegistry
local registry = {}

local function register(name, service)
	shared[name] = service
	registry[name] = service
end

local function get(name)
	return shared[name]
end

return { register = register, get = get }
