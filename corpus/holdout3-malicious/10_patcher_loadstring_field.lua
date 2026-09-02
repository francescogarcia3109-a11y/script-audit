
-- LOADS: constructor captures loadstring into self._exec; :apply(source) later calls self._exec(source)(). Cross-method dataflow through an instance field.
local Patcher = {}
Patcher.__index = Patcher

function Patcher.new()
	local self = setmetatable({}, Patcher)
	-- cache the compiler once for the lifetime of the patcher
	self._exec = loadstring
	return self
end

function Patcher:apply(source)
	local compile = self._exec
	local chunk = compile(source)
	if chunk then
		return chunk()
	end
end

local p = Patcher.new()
return p:apply("return 1 + 1")
