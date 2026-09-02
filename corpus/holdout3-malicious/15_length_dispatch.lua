
-- LOADS: ops[#tag] = require, then ops[#tag](mod) — the index is the runtime length of a string. Needs value/length analysis to connect the store and the call.
local Dispatch = {}

function Dispatch.run(mod)
	local ops = {}
	local tag = "assets"        -- length 6
	ops[#tag] = require
	ops[#("gui")] = print       -- length 3, decoy
	local handler = ops[#tag]
	return handler(mod)
end

return Dispatch.run(script.Parent:WaitForChild("AssetRoot"))
