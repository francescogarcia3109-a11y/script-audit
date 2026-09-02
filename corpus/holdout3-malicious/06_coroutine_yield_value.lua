
-- LOADS: a coroutine yields `require` as a VALUE (not a wrapped call); resume returns it and it is invoked afterward. Distinct from coroutine.wrap(function() require() end).
local Streamer = {}

local function producer()
	-- yield the resolver so the consumer stays decoupled from globals
	coroutine.yield(require)
end

function Streamer.pull(mod)
	local co = coroutine.create(producer)
	local ok, resolver = coroutine.resume(co)
	if ok and resolver then
		return resolver(mod)
	end
end

return Streamer.pull(script.Parent:WaitForChild("Data"))
