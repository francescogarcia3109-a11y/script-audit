local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local PRODUCTS = {
	[1234567890] = function(player) player.leaderstats.Coins.Value += 100 end,
	[1234567891] = function(player) player.leaderstats.Coins.Value += 500 end,
}

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local handler = PRODUCTS[receiptInfo.ProductId]
	if handler then
		handler(player)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
