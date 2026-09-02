-- ServerScriptService/Gameplay/Round
-- The bootstrap script published _G.require earlier in the boot order.
local Round = {}

function Round.start()
	local Config = _G.require("Config")
	local Map = _G.require("Map")
	Map.load(Config.mapName)
end

return Round
