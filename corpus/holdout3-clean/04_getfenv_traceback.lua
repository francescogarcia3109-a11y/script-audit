
-- BAIT: getfenv is used to read the caller's script name for logging; it never indexes a loader.
local Log = {}

function Log.write(level, msg)
	local env = getfenv(2)
	local source = "unknown"
	if type(env) == "table" and env.script then
		source = env.script.Name
	end
	print(("[%s][%s] %s"):format(level, source, msg))
end

return Log
