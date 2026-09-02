
-- BAIT: an admin command system with a dispatch table selected by user input; every handler is a local function, none load code.
local Admin = {}

local function kick(player, args)
	player:Kick(args[1] or "Removed by staff")
end

local function speed(player, args)
	local char = player.Character
	if char and char:FindFirstChild("Humanoid") then
		char.Humanoid.WalkSpeed = tonumber(args[1]) or 16
	end
end

local commands = { kick = kick, speed = speed }

function Admin.run(player, message)
	local parts = string.split(message, " ")
	local name = string.sub(parts[1], 2)
	local handler = commands[name]
	if handler then
		table.remove(parts, 1)
		handler(player, parts)
	end
end

return Admin
