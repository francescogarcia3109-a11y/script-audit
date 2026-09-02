-- ServerScriptService/Inventory
local ModuleCache = {}
ModuleCache.get = require   -- shorthand alias used by the loader below

local Inventory = {}
Inventory.__index = Inventory

function Inventory.new(player)
	return setmetatable({ player = player, items = {} }, Inventory)
end

function Inventory:get(slot)
	return self.items[slot]
end

function Inventory:describe(slot)
	local item = self.get(self, slot)
	return item and item.name or "empty"
end

return Inventory
