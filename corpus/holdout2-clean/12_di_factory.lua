-- ReplicatedStorage/Shared/Container
-- Hands the caller whichever loader the container was built with.
local Container = {}

function Container.resolveLoader(deps)
	local loadstring = deps.loadstring
	return loadstring
end

function Container.resolveRequire(deps)
	local require = deps.require
	return require
end

return Container
