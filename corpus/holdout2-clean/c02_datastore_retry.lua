local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("PlayerSave_v3")

local MAX_TRIES = 4

local function retry(fn, ...)
	local args = table.pack(...)
	for attempt = 1, MAX_TRIES do
		local ok, res = pcall(fn, table.unpack(args, 1, args.n))
		if ok then
			return res
		end
		task.wait(2 ^ attempt)
	end
	error("gave up after " .. MAX_TRIES .. " tries")
end

local Save = {}

function Save.load(userId)
	return retry(function()
		return store:GetAsync("u_" .. userId)
	end)
end

function Save.write(userId, data)
	return retry(function()
		return store:SetAsync("u_" .. userId, data)
	end)
end

return Save
