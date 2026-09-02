-- ServerScriptService/Boot
local function onError(err)
	warn("module failed: " .. tostring(err))
	return nil
end

local ok, Analytics = xpcall(require, onError, script.Parent.Analytics)
if ok and Analytics then
	Analytics.start()
end
