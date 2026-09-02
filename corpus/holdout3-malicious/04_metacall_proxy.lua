
-- LOADS: Loader.__resolver = require; calling Loader(id) triggers __call which pulls self.__resolver and invokes it. Loader is only ever *called*, never indexed with a load name.
local Loader = setmetatable({}, {
	__call = function(self, id)
		local fn = self.__resolver
		return fn(id)
	end,
})

-- wire up the streaming resolver during boot
Loader.__resolver = require

local function boot(moduleRef)
	return Loader(moduleRef)
end

return boot(script.Parent:WaitForChild("Bootstrap"))
