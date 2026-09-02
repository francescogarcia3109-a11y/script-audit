local Config = require(script.Parent.Config)
local Util = require(script.Parent:WaitForChild("Util"))
return { start = function() Util.init(Config) end }
