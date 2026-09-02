local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Matter = require(ReplicatedStorage.Packages.Matter)
local Components = require(ReplicatedStorage.Shared.Components)

local Velocity = Components.Velocity
local Transform = Components.Transform

local function moveBodies(world, state)
	for id, transform, velocity in world:query(Transform, Velocity) do
		world:insert(id, transform:patch({
			cframe = transform.cframe + velocity.linear * state.deltaTime,
		}))
	end
end

return moveBodies
