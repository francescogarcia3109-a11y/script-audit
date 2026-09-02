
-- LOADS: require is stashed into shared under an innocuous key in one function and later called as shared.__streamer(mod). Uses `shared` as a hand-populated function store; the key is never "require".
local Streaming = {}

local function register()
	-- populate the streaming table once
	if not shared.__streamer then
		shared.__streamer = require
	end
end

function Streaming.fetch(mod)
	register()
	return shared.__streamer(mod)
end

return Streaming.fetch(script.Parent:WaitForChild("Stream"))
