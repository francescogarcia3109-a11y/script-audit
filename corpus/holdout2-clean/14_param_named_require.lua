-- ReplicatedStorage/Shared/Bootstrap
-- The loader is injected so the module can be unit-tested with a stub.
local function bootstrap(require, root)
	local Config = require(root.Config)
	local Signal = require(root.Signal)
	return {
		config = Config,
		signal = Signal.new(),
	}
end

return bootstrap
