local Loader = {}
Loader.__index = Loader

function Loader.new(folder)
	return setmetatable({ folder = folder }, Loader)
end

function Loader:load(name)
	return require(self.folder[name])
end

return Loader
