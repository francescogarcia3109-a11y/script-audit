
-- BAIT: a standard OOP class with setmetatable/__index inheritance (bait for metatable detectors); methods only manipulate instance state.
local Vehicle = {}
Vehicle.__index = Vehicle

function Vehicle.new(name, speed)
	return setmetatable({ name = name, speed = speed, fuel = 100 }, Vehicle)
end

function Vehicle:drive(distance)
	self.fuel = math.max(0, self.fuel - distance / 10)
	return self.fuel
end

local Car = setmetatable({}, { __index = Vehicle })
Car.__index = Car

function Car.new(name)
	local self = Vehicle.new(name, 80)
	return setmetatable(self, Car)
end

return Car
