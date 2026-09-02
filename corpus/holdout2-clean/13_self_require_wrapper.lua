-- ServerScriptService/ModuleCache
local Cache = {}
Cache.__index = Cache
Cache.require = require   -- kept as a field so tests can swap it out

function Cache.new()
	return setmetatable({ loaded = {} }, Cache)
end

function Cache:get(moduleScript)
	if self.loaded[moduleScript] == nil then
		self.loaded[moduleScript] = self.require(moduleScript)
	end
	return self.loaded[moduleScript]
end

return Cache
