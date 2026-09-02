-- Caesar-ish scramble for a word game; also builds control chars for a terminal UI.
local function shift(word, n)
	local out = {}
	for i = 1, #word do
		out[i] = string.char(((word:byte(i) - 65 + n) % 26) + 65)
	end
	return table.concat(out)
end
local ESC = string.char(27)
return { shift = shift, ESC = ESC }
