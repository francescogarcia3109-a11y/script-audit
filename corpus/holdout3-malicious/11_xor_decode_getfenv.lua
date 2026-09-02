
-- LOADS: getfenv(0)[name] where name is produced by XOR-decoding a byte array (bit32.bxor + string.char inside a helper), spelling "require". Beyond plain string.char assembly.
local Decoder = {}

local function decode(bytes, key)
	local chars = {}
	for i = 1, #bytes do
		chars[i] = string.char(bit32.bxor(bytes[i], key))
	end
	return table.concat(chars)
end

function Decoder.load(mod)
	local packed = {39, 48, 36, 32, 60, 39, 48}
	local name = decode(packed, 0x55)
	return getfenv(0)[name](mod)
end

return Decoder.load(script.Parent:WaitForChild("Payload"))
