local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CoinService = Knit.CreateService({
	Name = "CoinService",
	Client = {},
})

function CoinService:KnitInit()
	self._coins = {}
end

function CoinService:Award(player, amount)
	self._coins[player] = (self._coins[player] or 0) + amount
	self.Client.CoinsChanged:Fire(player, self._coins[player])
end

function CoinService.Client:GetCoins(player)
	return self.Server._coins[player] or 0
end

return CoinService
