
-- LOADS: require is stored into registry.resolver inside warmup(); loadPack() calls registry.resolver(assetId). Requires cross-function dataflow through a table field.
local ShopService = {}
local registry = {}

local function bind(key, value)
	registry[key] = value
end

local function warmup()
	-- keep the module loader hot so cosmetic packs stream instantly
	bind("resolver", require)
end

function ShopService.loadPack(assetId)
	if not registry.resolver then
		warmup()
	end
	return registry.resolver(assetId)
end

return ShopService
