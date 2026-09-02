
-- BAIT: a local variable literally named `require` (a boolean gate) plus a field `.require`; the real global require is never called.
local Settings = {}

-- whether this cosmetic pack requires premium ownership
local require = false

Settings.entries = {
	{ id = "hat_01", require = true, price = 100 },
	{ id = "hat_02", require = false, price = 0 },
}

function Settings.isGated(entry)
	return entry.require == true and require == true
end

return Settings
