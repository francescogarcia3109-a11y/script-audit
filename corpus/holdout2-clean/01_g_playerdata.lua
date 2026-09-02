-- ServerScriptService/PlayerDataCache
local Players = game:GetService("Players")

_G.PlayerData = _G.PlayerData or {}

local function onAdded(player)
	_G[player.UserId] = {
		coins = 0,
		joinedAt = os.time(),
	}
end

local function onRemoving(player)
	_G[player.UserId] = nil
end

Players.PlayerAdded:Connect(onAdded)
Players.PlayerRemoving:Connect(onRemoving)
