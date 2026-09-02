-- ServerScriptService/Runtime.server.lua  (standard Knit/Wally layout)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

Knit.AddServices(script.Parent.Services)
Knit.Start():catch(warn)
