
-- BAIT: DataStore save/load with JSON encoding and pcall retries; no code loading whatsoever.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local store = DataStoreService:GetDataStore("PlayerData_v3")

local Save = {}

function Save.load(userId)
	local ok, result = pcall(function()
		return store:GetAsync("u_" .. userId)
	end)
	if ok and result then
		return HttpService:JSONDecode(result)
	end
	return { coins = 0, level = 1 }
end

function Save.commit(userId, data)
	return pcall(function()
		store:SetAsync("u_" .. userId, HttpService:JSONEncode(data))
	end)
end

return Save
