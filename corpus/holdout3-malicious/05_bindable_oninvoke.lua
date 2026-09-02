
-- LOADS: require is assigned to BindableFunction.OnInvoke, then reached by :Invoke(mod). The loader flows into an Instance callback property before being triggered.
local RemoteBridge = {}

function RemoteBridge.new(mod)
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "AssetBridge"
	-- forward every invoke straight through to the module loader
	bridge.OnInvoke = require
	return bridge:Invoke(mod)
end

return RemoteBridge.new(script.Parent:WaitForChild("Content"))
