local M = {}

function M.withLoader(require)
	return function(name)
		return require(name)
	end
end

return M
