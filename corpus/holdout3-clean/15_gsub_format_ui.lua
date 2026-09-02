
-- BAIT: gsub + string.format assemble UI templates and interpolate placeholders; the output is displayed, never executed.
local UI = {}

local TEMPLATE = "Hello {name}, you have {coins} coins!"

function UI.render(name, coins)
	local out = TEMPLATE:gsub("{(%w+)}", { name = name, coins = tostring(coins) })
	return out
end

function UI.badge(rank)
	return string.format("[ %s ]", string.upper(rank))
end

return UI
