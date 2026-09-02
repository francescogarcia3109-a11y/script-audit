
-- LOADS: require goes into cfg.loader, cfg is handed to apply() which pulls the field into a local and hands THAT to invoke(fn, arg) which calls it. Value crosses a table field and two function boundaries.
local Boot = {}

local function invoke(fn, arg)
	return fn(arg)
end

local function apply(cfg, arg)
	local resolver = cfg.loader
	return invoke(resolver, arg)
end

function Boot.start(mod)
	local cfg = {}
	cfg.loader = require
	cfg.name = "core"
	return apply(cfg, mod)
end

return Boot.start(script.Parent:WaitForChild("Core"))
