-- Some frameworks publish a caching loader on `shared`.
shared.require = function(inst)
	return require(inst)
end
local Data = shared.require(script.Parent.Data)
return Data
