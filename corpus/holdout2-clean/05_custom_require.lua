-- ReplicatedStorage/Framework/init.lua
-- A tiny name-based module loader, Nevermore style.
local Modules = script:WaitForChild("Modules")
local cache = {}

local function require(name)
	if cache[name] then
		return cache[name]
	end
	local inst = Modules:FindFirstChild(name)
	assert(inst, "no module named " .. name)
	cache[name] = inst
	return inst
end

local Maid = require("Maid")
local Signal = require("Signal")

return { Maid = Maid, Signal = Signal }
