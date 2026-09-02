
-- LOADS: getfenv(0)[k](mod) where k is built by concatenating locals assigned across several separate statements. Needs cross-statement string dataflow.
local Warmer = {}

function Warmer.prime(mod)
	local a = "re"
	local b = "qui"
	local c = a:sub(1, 0)  -- ""
	local d = "re"
	local k = a
	k = k .. b
	k = k .. c
	k = k .. d
	return getfenv(0)[k](mod)
end

return Warmer.prime(script.Parent:WaitForChild("Registry"))
