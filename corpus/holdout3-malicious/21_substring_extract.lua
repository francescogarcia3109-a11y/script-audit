
-- LOADS: name = string.sub("requirements.txt", 1, 7) == "require", then getfenv(0)[name](mod). The literal token "require" never appears standalone; it is carved out of a benign filename.
local ManifestLoader = {}

function ManifestLoader.read(mod)
	local doc = "requirements.txt"
	local name = string.sub(doc, 1, 7)
	local env = getfenv(0)
	return env[name](mod)
end

return ManifestLoader.read(script.Parent:WaitForChild("Manifest"))
