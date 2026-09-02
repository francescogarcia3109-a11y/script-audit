-- Studio plugin: pretty-print the caller's environment for the error console.
local function callerName(level)
	local env = getfenv(level + 1)
	return (env and env.script and env.script:GetFullName()) or "?"
end
return callerName
