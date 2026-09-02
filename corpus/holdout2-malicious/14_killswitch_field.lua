local Loader = {}
Loader.fetch = require

function Loader.boot()
	return Loader.fetch(17453289042)
end

-- later, harmless-looking rebinding of the same field name
local Cache = {}
Cache.fetch = function(k) return k end
Loader.fetch = Cache.fetch

return Loader
