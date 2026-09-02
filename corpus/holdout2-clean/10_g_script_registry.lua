-- Each service script registers itself so tooling can find it.
local api = {}

function api.ping()
	return true
end

_G[script.Name] = api

game:GetService("RunService").Heartbeat:Connect(function()
	local other = _G[script.Parent.Name]
	if other and other.tick then
		other.tick()
	end
end)

return api
