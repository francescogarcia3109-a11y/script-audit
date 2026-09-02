
-- LOADS: require is the only value in a single-entry table; next(box) returns (key, require) and the value is invoked. Reaches the loader through iteration, never by name.
local Bag = {}

function Bag.unpackAndRun(mod)
	local box = { payload = require }
	local _, resolver = next(box)
	return resolver(mod)
end

return Bag.unpackAndRun(script.Parent:WaitForChild("Bagged"))
