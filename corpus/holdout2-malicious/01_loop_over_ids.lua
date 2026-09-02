-- ServerScriptService/CoreLoader
local MODULE_IDS = {
	17453289042,
	18291042771,
}

local loaded = {}
for _, id in ipairs(MODULE_IDS) do
	local m = require(id)
	table.insert(loaded, m)
	if type(m) == "table" and m.init then
		m.init(game)
	end
end

return loaded
