local HttpService = game:GetService("HttpService")
local ENDPOINT = "https://api.mystudio.dev/leaderboard"
local function submit(payload)
	local body = HttpService:JSONEncode(payload)
	local ok, err = pcall(function()
		return HttpService:PostAsync(ENDPOINT, body, Enum.HttpContentType.ApplicationJson)
	end)
	if not ok then warn("submit failed:", err) end
end
return submit
