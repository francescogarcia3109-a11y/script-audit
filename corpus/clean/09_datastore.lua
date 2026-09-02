local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("PlayerCoins")
local function save(plr, coins)
	local ok, err = pcall(function()
		store:SetAsync(tostring(plr.UserId), coins)
	end)
	if not ok then warn("save failed: " .. tostring(err)) end
end
return save
