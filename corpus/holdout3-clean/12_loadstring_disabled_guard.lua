
-- BAIT: `loadstring` is shadowed to nil and guarded behind an always-false flag; the branch that would call it never runs and there is nothing to load.
local Console = {}

local loadstring = nil
local ALLOW_EVAL = false

function Console.eval(input)
	if ALLOW_EVAL and loadstring then
		-- developer-only path, disabled in production
		return "eval disabled"
	end
	return "Command not recognized: " .. tostring(input)
end

return Console
