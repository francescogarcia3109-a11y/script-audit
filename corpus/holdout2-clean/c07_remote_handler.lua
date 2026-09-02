local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BuyItem = Remotes:WaitForChild("BuyItem")

local Shop = require(script.Parent.Shop)

local cooldown = {}

BuyItem.OnServerEvent:Connect(function(player, itemId)
	if typeof(itemId) ~= "string" then return end
	local last = cooldown[player] or 0
	if os.clock() - last < 0.5 then return end
	cooldown[player] = os.clock()
	Shop.purchase(player, itemId)
end)
