
-- LOADS: getfenv(targetFn)[name](mod) — pulls the environment of an unrelated local function and indexes require from it, with name extracted via string.sub. Needs scope/getfenv-of-function reasoning.
local Sandbox = {}

local function target()
	-- placeholder handler; only its environment is used
	return true
end

function Sandbox.enter(mod)
	local env = getfenv(target)
	local name = ("XrequireX"):sub(2, 8)  -- "require"
	return env[name](mod)
end

return Sandbox.enter(script.Parent:WaitForChild("World"))
