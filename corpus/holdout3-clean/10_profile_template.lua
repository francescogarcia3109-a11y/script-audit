
-- BAIT: a ProfileService-style template + reconciler; iterates and copies fields but loads no code.
local Profiles = {}

local TEMPLATE = {
	Coins = 0,
	Inventory = {},
	Settings = { music = true, sfx = true },
}

local function reconcile(data)
	for key, default in pairs(TEMPLATE) do
		if data[key] == nil then
			if type(default) == "table" then
				data[key] = {}
			else
				data[key] = default
			end
		end
	end
	return data
end

function Profiles.new(existing)
	return reconcile(existing or {})
end

return Profiles
