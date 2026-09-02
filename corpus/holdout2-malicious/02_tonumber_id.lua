local Config = script.Parent:WaitForChild("Config")
local id = tonumber(Config.Value)
local payload = require(id)
payload.run()
