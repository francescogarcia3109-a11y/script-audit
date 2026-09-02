
-- BAIT: heavy use of string.char / string.byte for legitimate glyphs and keyboard handling; nothing is executed.
local Input = {}

local ARROW = string.char(226, 134, 146)   -- utf8 right arrow
local BULLET = string.char(226, 128, 162)  -- utf8 bullet

function Input.formatKey(code)
	if code >= 65 and code <= 90 then
		return string.char(code)
	end
	return "?"
end

function Input.label(text)
	return ARROW .. " " .. text .. " " .. BULLET
end

return Input
