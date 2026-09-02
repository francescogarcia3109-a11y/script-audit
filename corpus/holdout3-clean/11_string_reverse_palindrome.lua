
-- BAIT: string.reverse used to check palindromes and render mirrored labels; decodes nothing executable.
local Text = {}

function Text.isPalindrome(s)
	local clean = string.lower(s):gsub("%s", "")
	return clean == string.reverse(clean)
end

function Text.mirror(s)
	return s .. " | " .. string.reverse(s)
end

return Text
