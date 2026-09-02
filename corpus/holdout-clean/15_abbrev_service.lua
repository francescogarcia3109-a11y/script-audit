local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Net = require(RS.Modules.Net)
local Data = require(SSS.Data)
return { Net = Net, Data = Data }
