
-- LOADS: require sits in a table beside a decoy and is extracted via table.unpack(t, 2, 2), then called. Needs unpack index tracking.
local Extract = {}

function Extract.go(mod)
	local slots = { print, require, warn }
	local resolver = (table.unpack(slots, 2, 2))
	return resolver(mod)
end

return Extract.go(script.Parent:WaitForChild("Slotted"))
