local function letterFor(index)
	return string.char(64 + index)
end
local out = {}
for i = 1, 26 do out[#out + 1] = letterFor(i) end
return table.concat(out)
