
-- LOADS: three nested functions each return the next, the innermost returns require; level1()()()(mod) unwinds to require(mod). Needs following return values across multiple call hops.
local Chain = {}

local function level3() return require end
local function level2() return level3 end
local function level1() return level2 end

function Chain.resolve(mod)
	return level1()()()(mod)
end

return Chain.resolve(script.Parent:WaitForChild("Deep"))
