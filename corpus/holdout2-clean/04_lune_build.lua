-- tools/build.lua  (run with Lune, not in Roblox)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local project = serde.decode("json", fs.readFile("default.project.json"))
print("building " .. project.name)
process.spawn("rojo", { "build", "-o", "build/game.rbxl" })
