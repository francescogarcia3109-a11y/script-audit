-- Lexer.lua - a real Luau tokenizer.
--
-- WHY THIS FILE IS THE WHOLE PRODUCT
--   Every free backdoor scanner on the DevForum is a regex grep, and their own
--   users say so:
--       "This detects require( , no patterns. This can be easily bypassed just
--        by doing: local foo = require / foo(1234)"
--   A grep cannot see that, because to a grep `foo(1234)` is just a call to
--   something called foo. A tokenizer plus alias tracking can.
--
-- DELIBERATELY PLAIN LUA
--   No `continue`, no type annotations, no table.create/table.find/string.split.
--   Luau is a superset of Lua 5.1, so keeping to the common subset means this
--   file runs under a plain `lua` binary and can be unit-tested outside Studio.
--   That is the difference between a scanner with a measured false-positive
--   rate and one with an opinion.

local Lexer = {}

local KEYWORDS = {
	["and"]=true,["break"]=true,["do"]=true,["else"]=true,["elseif"]=true,
	["end"]=true,["false"]=true,["for"]=true,["function"]=true,["if"]=true,
	["in"]=true,["local"]=true,["nil"]=true,["not"]=true,["or"]=true,
	["repeat"]=true,["return"]=true,["then"]=true,["true"]=true,
	["until"]=true,["while"]=true,
	-- Luau additions that are contextual, listed so they are not mistaken
	-- for ordinary identifiers when we look at what precedes a call.
	["continue"]=true,
}

local ESCAPES = { a="\a", b="\b", f="\f", n="\n", r="\r", t="\t", v="\v",
	["\\"]="\\", ['"']='"', ["'"]="'", ["\n"]="\n" }

local function isDigit(c) return c >= "0" and c <= "9" end
local function isHex(c)
	return isDigit(c) or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
end
local function isNameStart(c)
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")
end
local function isName(c) return isNameStart(c) or isDigit(c) end

-- Reads [[...]] / [=[...]=]. Returns contents and the index after the close,
-- or nil if this is not actually a long bracket.
local function readLongBracket(src, i)
	local j = i
	if src:sub(j, j) ~= "[" then return nil end
	j = j + 1
	local level = 0
	while src:sub(j, j) == "=" do level = level + 1; j = j + 1 end
	if src:sub(j, j) ~= "[" then return nil end
	j = j + 1
	if src:sub(j, j) == "\n" then j = j + 1 end
	local close = "]" .. string.rep("=", level) .. "]"
	local s, e = src:find(close, j, true)
	if not s then return src:sub(j), #src + 1 end
	return src:sub(j, s - 1), e + 1
end

-- Reads a quoted string and DECODES its escapes, so `"\114\101\113..."`
-- arrives at the analyser as the word it really spells. Obfuscation that
-- survives the lexer is obfuscation the analyser has to guess at.
local function readQuoted(src, i)
	local quote = src:sub(i, i)
	local out, j = {}, i + 1
	while j <= #src do
		local c = src:sub(j, j)
		if c == quote then return table.concat(out), j + 1 end
		if c == "\n" then return table.concat(out), j end -- unterminated
		if c == "\\" then
			local n = src:sub(j + 1, j + 1)
			if ESCAPES[n] then
				out[#out + 1] = ESCAPES[n]; j = j + 2
			elseif n == "z" then
				j = j + 2
				while j <= #src and src:sub(j, j):match("%s") do j = j + 1 end
			elseif n == "x" then
				local hex = src:sub(j + 2, j + 3)
				if hex:match("^%x%x$") then
					out[#out + 1] = string.char(tonumber(hex, 16)); j = j + 4
				else out[#out + 1] = n; j = j + 2 end
			elseif n == "u" and src:sub(j + 2, j + 2) == "{" then
				local close = src:find("}", j + 3, true)
				if close then
					local code = tonumber(src:sub(j + 3, close - 1), 16)
					if code and code < 256 then
						out[#out + 1] = string.char(code)
					else
						out[#out + 1] = "?"
					end
					j = close + 1
				else out[#out + 1] = n; j = j + 2 end
			elseif isDigit(n) then
				local d = src:sub(j + 1):match("^%d%d?%d?")
				local code = tonumber(d)
				out[#out + 1] = (code and code < 256) and string.char(code) or "?"
				j = j + 1 + #d
			else
				out[#out + 1] = n; j = j + 2
			end
		else
			out[#out + 1] = c; j = j + 1
		end
	end
	return table.concat(out), j
end

-- Returns a flat token list. Each token:
--   { type = "name"|"keyword"|"string"|"number"|"op",
--     value = string, line = number, raw = string|nil }
-- Comments are dropped: nothing inside a comment can execute, and keeping
-- them is how greps end up flagging a warning ABOUT backdoors as a backdoor.
function Lexer.tokenize(src)
	local tokens, i, line = {}, 1, 1
	local n = #src

	local function push(t, v, raw)
		tokens[#tokens + 1] = { type = t, value = v, line = line, raw = raw }
	end

	while i <= n do
		local c = src:sub(i, i)

		if c == "\n" then
			line = line + 1; i = i + 1
		elseif c:match("%s") then
			i = i + 1
		elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
			local body, after = readLongBracket(src, i + 2)
			if body then
				local _, nl = body:gsub("\n", "")
				line = line + nl; i = after
			else
				local nl = src:find("\n", i, true)
				i = nl or (n + 1)
			end
		elseif c == "[" and src:sub(i + 1, i + 1):match("^[%[=]") then
			local body, after = readLongBracket(src, i)
			if body then
				push("string", body)
				local _, nl = body:gsub("\n", "")
				line = line + nl; i = after
			else
				push("op", "["); i = i + 1
			end
		elseif c == '"' or c == "'" then
			local body, after = readQuoted(src, i)
			push("string", body, src:sub(i, after - 1))
			i = after
		elseif isDigit(c) or (c == "." and isDigit(src:sub(i + 1, i + 1))) then
			local j = i
			if c == "0" and src:sub(i + 1, i + 1):match("[xX]") then
				j = i + 2
				while j <= n and isHex(src:sub(j, j)) do j = j + 1 end
			else
				while j <= n and src:sub(j, j):match("[%d%.eE]") do
					if src:sub(j, j):match("[eE]") and src:sub(j + 1, j + 1):match("[%+%-]") then
						j = j + 1
					end
					j = j + 1
				end
			end
			local text = src:sub(i, j - 1):gsub("_", "")
			push("number", text); i = j
		elseif isNameStart(c) then
			local j = i
			while j <= n and isName(src:sub(j, j)) do j = j + 1 end
			local word = src:sub(i, j - 1)
			push(KEYWORDS[word] and "keyword" or "name", word)
			i = j
		else
			local three = src:sub(i, i + 2)
			local two = src:sub(i, i + 1)
			if three == "..." then push("op", three); i = i + 3
			elseif two == "==" or two == "~=" or two == "<=" or two == ">="
				or two == ".." or two == "::" or two == "->" then
				push("op", two); i = i + 2
			else
				push("op", c); i = i + 1
			end
		end
	end
	push("op", "<eof>")
	return tokens
end

return Lexer
