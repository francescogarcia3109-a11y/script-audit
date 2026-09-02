local ServerScriptService = game:GetService("ServerScriptService")
local Modules = ServerScriptService:WaitForChild("Modules")
local ProfileService = require(Modules.ProfileService)
local ProfileTemplate = require(Modules.ProfileTemplate)

local ProfileStore = ProfileService.GetProfileStore("PlayerData", ProfileTemplate)
return ProfileStore
