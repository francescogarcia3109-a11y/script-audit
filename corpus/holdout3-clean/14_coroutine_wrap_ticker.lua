
-- BAIT: coroutine.wrap drives an animation ticker (real coroutine use); the wrapped function only tweens numbers.
local Ticker = {}

function Ticker.countdown(seconds)
	return coroutine.wrap(function()
		for t = seconds, 0, -1 do
			coroutine.yield(t)
		end
	end)
end

function Ticker.demo()
	local next_val = Ticker.countdown(3)
	local total = 0
	local v = next_val()
	while v do
		total = total + v
		v = next_val()
	end
	return total
end

return Ticker
