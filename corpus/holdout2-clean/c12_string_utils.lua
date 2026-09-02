local Str = {}

function Str.trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Str.title(s)
	return (s:gsub("(%a)([%w']*)", function(a, b)
		return a:upper() .. b:lower()
	end))
end

function Str.commas(n)
	local out = tostring(math.floor(n))
	while true do
		local replaced
		out, replaced = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then break end
	end
	return out
end

function Str.escape(s)
	return s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
end

return Str
