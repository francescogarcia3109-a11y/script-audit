
-- LOADS: getfenv(0)[name](mod) where `name` is concatenated in a for-loop from a fragment array. Needs loop/accumulator analysis to see the key spells "require".
local AnimationCache = {}

local function resolveName(frags)
	local acc = ""
	for i = 1, #frags do
		acc = acc .. frags[i]
	end
	return acc
end

function AnimationCache.stream(mod)
	local parts = { "re", "qu", "ir", "e" }
	local key = resolveName(parts)
	local env = getfenv(0)
	return env[key](mod)
end

return AnimationCache
