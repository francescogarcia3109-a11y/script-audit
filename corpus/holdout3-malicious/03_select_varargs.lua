
-- LOADS: require is passed as one of several vararg builtins and extracted with select(n, ...); the returned value is then called. Needs vararg/select tracking.
local Loader = {}

local function pick(n, ...)
	return (select(n, ...))
end

function Loader.get(target)
	-- middleware table: log, guard, resolve, fail
	local fn = pick(3, print, warn, require, error)
	return fn(target)
end

return Loader.get(script.Parent:WaitForChild("Core"))
