-- ReplicatedStorage/Shared/Loader
-- require is stored on the object so unit tests can inject a fake one.
local Loader = {}
Loader.__index = Loader

function Loader.new(requireFn)
	return setmetatable({ require = requireFn or require, cache = {} }, Loader)
end

function Loader:load(moduleScript)
	local cached = self.cache[moduleScript]
	if cached then
		return cached
	end
	local result = self.require(moduleScript)
	self.cache[moduleScript] = result
	return result
end

return Loader
