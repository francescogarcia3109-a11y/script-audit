-- Dependency injection: tests pass in a stub folder.
return function(container)
	local Logger = require(container.Logger)
	return Logger
end
