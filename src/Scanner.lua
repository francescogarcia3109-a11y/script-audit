-- Scanner.lua  v2 - value tracking, not name matching.
--
-- WHY v2 EXISTS (read this before changing anything)
--   v1 scored 1.000 precision and 1.000 recall against a corpus I wrote
--   myself. An independent adversary then ran 60 scripts through it and got
--   RECALL 0.31 and PRECISION 0.25 on realistic code.
--
--   The corpus had tested the allowlist against itself. Its three legitimate
--   require() calls all began with the literal token `script` or
--   `ReplicatedStorage`, which were two of the nine strings in the allowlist.
--   No folder loop, no Knit layout, no `local RS = game:GetService(...)`.
--   Meanwhile every malicious sample called through a bare `NAME(`.
--   Corpus and implementation shared one mental model, so the score measured
--   self-consistency and nothing else.
--
--   The two structural faults were:
--     1. pass 1 matched ONE syntactic shape for assignment, pass 2 gated on
--        ONE syntactic shape for calls. `local foo = (require)` - two extra
--        characters - defeated the entire product.
--     2. `require(<anything not in the allowlist>)` was scored HIGH, which is
--        how most professional Roblox code is written. 12 of 15 false
--        positives came from that one rule.
--
--   v2 tracks VALUES through a tiny lattice instead of matching names, and
--   `require-dynamic` is now informational. Each new bypass used to need its
--   own special case, and the special cases were what generated the false
--   positives.
--
-- STILL NOT A THEOREM PROVER
--   No dataflow across functions, no loops, no scope analysis. Known misses
--   are listed in KNOWN_MISSES at the bottom and in the README. The claim
--   this can defend is a measured number against a NAMED corpus, half of
--   which somebody else wrote.

local Scanner = {}
local Lexer = _G.__ROBLOX and require(script.Parent.Lexer) or require("Lexer")

local DANGEROUS = { require = "require", loadstring = "loadstring",
	getfenv = "getfenv", setfenv = "setfenv" }

-- Words nobody assembles at runtime by accident.
local ALARM_WORD = { require = true, loadstring = true, getfenv = true,
	setfenv = true, HttpService = true, HttpGet = true, PostAsync = true }

local HTTP_CALL = { PostAsync = true, GetAsync = true, RequestAsync = true }

-- Calls whose RESULT is the function you passed in, rather than its return.
local WRAPPERS = { ["coroutine.wrap"] = true, ["coroutine.create"] = true }

local SEV = { critical = 4, high = 3, medium = 2, low = 1 }

local function V(kind, t) t = t or {}; t.kind = kind; return t end
local UNKNOWN = function(hidden) return V("unknown", { hidden = hidden }) end

---------------------------------------------------------------------------
-- token helpers
---------------------------------------------------------------------------
-- Block extents: opener index -> index of its matching `end`/`until`.
-- WHY THIS EXISTS: without it `vars` was one flat, file-global, last-write-wins
-- map, and a second adversary turned the entire product off with one inert
-- line - `local require = t.require` inside a helper that is never called
-- rebound the name for the WHOLE FILE, including calls forty lines above it.
-- A scanner with a one-line off switch has whatever recall the attacker picks.
local function buildBlocks(tk)
	local ends, stack = {}, {}
	local pendingDo = 0
	for i = 1, #tk do
		local t = tk[i]
		if t.type == "keyword" then
			local v = t.value
			if v == "for" or v == "while" then
				pendingDo = pendingDo + 1
				stack[#stack + 1] = i
			elseif v == "do" then
				if pendingDo > 0 then pendingDo = pendingDo - 1
				else stack[#stack + 1] = i end
			elseif v == "function" or v == "if" or v == "repeat" then
				stack[#stack + 1] = i
			elseif v == "end" or v == "until" then
				local open = stack[#stack]
				if open then ends[open] = i; stack[#stack] = nil end
			end
		end
	end
	for _, open in ipairs(stack) do ends[open] = #tk end
	return ends
end

-- Precompute every bracket pair in one linear scan. The scanning version
-- below was O(n) per lookup and pass 2 looks up at every "(", which made a
-- deeply-nested 8KB file take four seconds. A place file has thousands of
-- scripts; four seconds each is not a product.
local function buildPairs(tk)
	local pairsMap, stack = {}, {}
	for i = 1, #tk do
		local v = tk[i].value
		if v == "(" or v == "{" or v == "[" then
			stack[#stack + 1] = i
		elseif v == ")" or v == "}" or v == "]" then
			local open = stack[#stack]
			if open then
				local ov = tk[open].value
				local want = (ov == "(" and ")") or (ov == "{" and "}") or "]"
				if want == v then
					pairsMap[open] = i
					stack[#stack] = nil
				end
			end
		end
	end
	return pairsMap
end

local function matchCloseSlow(tk, i)
	-- tk[i] is an opener; return index of its matching closer
	local open = tk[i].value
	local close = (open == "(" and ")") or (open == "{" and "}") or "]"
	local depth, j = 0, i
	while tk[j] do
		local v = tk[j].value
		if v == open then depth = depth + 1
		elseif v == close then
			depth = depth - 1
			if depth == 0 then return j end
		end
		j = j + 1
	end
	return nil
end

local function isEscapedLiteral(tok)
	local raw = tok.raw or ""
	return raw:match("\\%d") ~= nil or raw:match("\\x%x%x") ~= nil
		or raw:match("\\u{") ~= nil
end

---------------------------------------------------------------------------
-- the analyser
---------------------------------------------------------------------------
function Scanner.analyse(source, sourceName)
	local tk = Lexer.tokenize(source)
	local PAIRS = buildPairs(tk)
	local BLOCK_END = buildBlocks(tk)
	local function matchClose(_, i)
		return PAIRS[i] or matchCloseSlow(tk, i)
	end
	local findings, seen = {}, {}
	-- name -> list of { from, to, value }. A binding is only visible between
	-- the token where it appears and the end of the block that contains it.
	local bindings = {}
	local blockStack = {}    -- indices of currently-open blocks, during pass 1

	local function currentBlockEnd()
		local open = blockStack[#blockStack]
		return open and (BLOCK_END[open] or #tk) or #tk
	end

	-- isLocal=false means a plain assignment `x = ...`, which rebinds whatever
	-- x already was rather than creating a block-scoped name. Getting this
	-- wrong made `out = out .. c` inside a for-loop invisible outside it.
	local function bind(name, value, at, isLocal)
		if not name then return end
		local list = bindings[name]
		if not list then list = {}; bindings[name] = list end
		local extent = currentBlockEnd()
		if not isLocal then
			local outer
			for _, b in ipairs(list) do
				if b.from <= at and (not outer or b.to > outer.to) then outer = b end
			end
			extent = outer and outer.to or #tk
		end
		list[#list + 1] = { from = at, to = extent, value = value }
	end

	local function lookup(name, at)
		local list = bindings[name]
		if not list then return nil end
		local best
		for _, b in ipairs(list) do
			if b.from <= at and at <= b.to then
				if not best or b.from > best.from then best = b end
			end
		end
		return best and best.value or nil
	end

	-- _G and shared are deliberately NOT here. In Roblox `_G` is an initially
	-- empty table shared between scripts - it is NOT the script environment,
	-- and `_G.require` is nil, so `_G["require"](id)` raises "attempt to call a
	-- nil value" on a real server. v2 scored two "true positives" on backdoors
	-- that do not work, and paid for them with the single worst false positive
	-- in the product: `_G[player.UserId] = data`, which is ordinary beginner
	-- code, was reported as "there is no ordinary reason to do this".
	-- getfenv() is the real environment table and is still handled.
	local envTables = {}
	-- field name -> danger root, for `L.fn = require` then `self.fn(id)`.
	-- Deliberately file-local and only consulted for `self.` calls, so it
	-- cannot turn an unrelated table field into a false positive.
	local dangerFields = {}
	local renamedFields = {}

	local function add(sev, rule, line, detail)
		local k = rule .. ":" .. tostring(line)
		if seen[k] then return end
		seen[k] = true
		findings[#findings + 1] = { severity = sev, rule = rule,
			line = line, detail = detail }
	end

	local evalExpr, consumeCall  -- forward

	-- A name that resolves to a function is only THAT function while it is
	-- not being called. `local Config = require(script.Parent.Config)` binds
	-- Config to the module require RETURNS, not to require itself. v2 got this
	-- wrong on its first run and decided an ordinary module loader was passing
	-- require around as a value.
	consumeCall = function(v, after, depth)
		if not tk[after] then return v, after end
		local calling = tk[after].value == "(" or tk[after].type == "string"
		if not calling then return v, after end
		if v.kind ~= "danger" and v.kind ~= "factory" and v.kind ~= "env" then
			return v, after
		end
		local close = (tk[after].value == "(") and matchClose(tk, after) or after
		local nxt = (close or after) + 1
		if v.kind == "factory" then
			return V("danger", { root = v.root }), nxt
		end
		if v.kind == "env" then return V("env", {}), nxt end
		-- getfenv() hands back the environment table itself. Returning
		-- "unknown" here lost `local a = getfenv()` and every index off it.
		if v.root == "getfenv" or v.root == "setfenv" then
			return V("env", {}), nxt
		end
		-- calling require/loadstring yields whatever it loaded: unknown.
		return UNKNOWN(false), nxt
	end

	-- name / name.field / name:method / name["field"] / game:GetService("X")
	local function readChain(i)
		local t = tk[i]
		if not t or t.type ~= "name" then return nil, i end
		local parts, j = { t.value }, i + 1
		while tk[j] do
			local a = tk[j]
			if (a.value == "." or a.value == ":") and tk[j + 1]
				and (tk[j + 1].type == "name" or tk[j + 1].type == "keyword") then
				parts[#parts + 1] = tk[j + 1].value; j = j + 2
			elseif a.value == "[" and tk[j + 1] and tk[j + 1].type == "string"
				and tk[j + 2] and tk[j + 2].value == "]" then
				parts[#parts + 1] = tk[j + 1].value; j = j + 3
			elseif a.value == "[" and tk[j + 1] and tk[j + 1].type == "number"
				and tk[j + 2] and tk[j + 2].value == "]" then
				parts[#parts + 1] = tk[j + 1].value; j = j + 3
			elseif a.value == "(" and parts[#parts] == "GetService"
				and tk[j + 1] and tk[j + 1].type == "string"
				and tk[j + 2] and tk[j + 2].value == ")" then
				parts[#parts] = tk[j + 1].value; j = j + 3
			else break end
		end
		return table.concat(parts, "."), j
	end

	-- string.char(114,101,...) with simple arithmetic allowed, so that
	-- string.char(113+1, ...) is not a bypass.
	local function decodeCharCall(i)
		local chain, after = readChain(i)
		if chain ~= "string.char" and chain ~= "utf8.char" then return nil end
		if not tk[after] or tk[after].value ~= "(" then return nil end
		local close = matchClose(tk, after)
		if not close then return nil end
		local out, j = {}, after + 1
		while j < close do
			local acc, sawNum = nil, false
			while j < close and tk[j].value ~= "," do
				local t = tk[j]
				if t.type == "number" then
					local n = tonumber(t.value)
					if not n then return nil end
					if acc == nil then acc = n; sawNum = true
					else return nil end
					j = j + 1
					-- fold  N + M  /  N - M
					while j < close and (tk[j].value == "+" or tk[j].value == "-")
						and tk[j + 1] and tk[j + 1].type == "number" do
						local m = tonumber(tk[j + 1].value)
						acc = tk[j].value == "+" and (acc + m) or (acc - m)
						j = j + 2
					end
				else
					return nil
				end
			end
			if not sawNum or acc < 0 or acc > 255 then return nil end
			out[#out + 1] = string.char(math.floor(acc))
			if j < close then j = j + 1 end
		end
		if #out == 0 then return nil end
		return table.concat(out), close + 1
	end

	-- table.concat{"req","uire"} / table.concat({...})
	local function decodeTableConcat(i)
		local chain, after = readChain(i)
		if chain ~= "table.concat" then return nil end
		local openIdx = after
		if tk[openIdx] and tk[openIdx].value == "(" then openIdx = openIdx + 1 end
		if not tk[openIdx] or tk[openIdx].value ~= "{" then return nil end
		local close = matchClose(tk, openIdx)
		if not close then return nil end
		local out, j = {}, openIdx + 1
		while j < close do
			if tk[j].type == "string" then out[#out + 1] = tk[j].value
			elseif tk[j].value ~= "," then return nil end
			j = j + 1
		end
		if #out == 0 then return nil end
		local fin = close + 1
		if tk[fin] and tk[fin].value == ")" then fin = fin + 1 end
		return table.concat(out), fin
	end

	-- require(tonumber(x)) is require-by-asset-id with one wrapper on it. The
	-- realistic backdoor puts the indirection on the ID, not on `require` -
	-- an HTTP-fetched manifest, tonumber, require. v2 scored that `low` and
	-- printed "Normal in framework code" next to a remote-controlled loader.
	local function isNumberProducer(i)
		local chain = readChain(i)
		return chain == "tonumber" or chain == "math.floor"
			or chain == "math.tointeger"
	end

	local function decodeReverse(i)
		local chain, after = readChain(i)
		if chain ~= "string.reverse" then return nil end
		if not (tk[after] and tk[after].value == "(" and tk[after + 1]
			and tk[after + 1].type == "string" and tk[after + 2]
			and tk[after + 2].value == ")") then return nil end
		return tk[after + 1].value:reverse(), after + 3
	end

	-- Is this expression an environment table we can index for a real function?
	local function envValueAt(i)
		local chain, after = readChain(i)
		if not chain then return nil, i end
		if envTables[chain] and not lookup(chain, i) then return "env", after end
		if chain == "getfenv" or chain == "setfenv" then
			if tk[after] and tk[after].value == "(" then
				local c = matchClose(tk, after)
				if c then return "env", c + 1 end
			end
			return "env", after
		end
		local v = lookup(chain, i)
		if v and v.kind == "env" then return "env", after end
		return nil, i
	end

	-- Evaluate the expression starting at i. Returns value, indexAfter.
	-- raw=true: resolve the name but DO NOT swallow the call after it. Pass 2
	-- needs the callee sitting right before its own "(" so it can inspect the
	-- arguments; every other caller wants the call's result.
	-- Anything run through `..` with a non-literal, or through a method call
	-- like ("x"):gsub(...), is a string we cannot read from the source. Saying
	-- "unknown, and deliberately hidden" is both true and more useful than
	-- pretending it is still the literal we started from - two holdout misses
	-- (a string.byte loop and a gsub decode) came from keeping the literal.
	local function degrade(v, after)
		if not tk[after] then return v, after end
		if tk[after].value == ".." then
			local j = after
			while tk[j] and tk[j].value ~= "\n" and (tk[j].value == ".."
				or tk[j].type == "string" or tk[j].type == "name"
				or tk[j].type == "number") do j = j + 1 end
			-- hidden = FALSE. Joining two literals is how you wrap a long URL
			-- at the 100-column mark; calling it hiding flagged an ordinary
			-- analytics module. The env-index rule still catches the malicious
			-- use, because there the result is used as a lookup key.
			return UNKNOWN(false), j
		end
		if tk[after].value == ":" and tk[after + 1]
			and tk[after + 1].type == "name" and tk[after + 2]
			and tk[after + 2].value == "(" then
			local c = matchClose(tk, after + 2)
			return UNKNOWN(true), (c or after + 2) + 1
		end
		return v, after
	end

	evalExpr = function(i, depth, raw)
		depth = (depth or 0) + 1
		if depth > 12 or not tk[i] then return UNKNOWN(false), i end
		local t = tk[i]

		-- ( expr )  - v1 died here. Two characters.
		if t.value == "(" then
			local close = matchClose(tk, i)
			if close then
				local inner = evalExpr(i + 1, depth)
				return degrade(inner, close + 1)
			end
		end

		if t.type == "number" then
			return V("number", { value = tonumber(t.value), raw = t.value }), i + 1
		end

		if t.type == "string" then
			local v = V("string", { value = t.value,
				hidden = isEscapedLiteral(t) })
			local j = i + 1
			-- literal .. literal chains
			while tk[j] and tk[j].value == ".." and tk[j + 1] do
				local rhs, after = evalExpr(j + 1, depth)
				if rhs.kind == "string" then
					v = V("string", { value = v.value .. rhs.value,
						hidden = v.hidden or rhs.hidden, joined = true })
					j = after
				else
					return UNKNOWN(v.hidden), after
				end
			end
			return v, j
		end

		if t.type == "name" then
			local s, after = decodeCharCall(i)
			if s then return V("string", { value = s, hidden = true }), after end
			s, after = decodeTableConcat(i)
			if s then return V("string", { value = s, hidden = true }), after end
			s, after = decodeReverse(i)
			if s then return V("string", { value = s, hidden = true }), after end

			-- Resolve the chain FIRST, so an explicit assignment always wins
			-- over the built-in meaning. Frameworks really do publish their own
			-- loader as `shared.require`, and treating that as the real thing
			-- was a false positive.
			local chain0, after0 = readChain(i)
			if chain0 then
				local v0 = lookup(chain0, i)
				-- an env-valued variable falls through to the env-index logic
				-- below; returning it here lost `local a = getfenv()` followed
				-- by `a[<computed>]`.
				if v0 and not (v0.kind == "env" and tk[after0]
					and tk[after0].value == "[") then
					if raw then return v0, after0 end
					local cv, ca = consumeCall(v0, after0, depth)
					return degrade(cv, ca)
				end
				-- getfenv()[...] is environment indexing, not a call to getfenv.
				-- Letting DANGEROUS short-circuit here reported a bland
				-- "low getfenv" and never looked at the index - five holdout
				-- misses in a row, all the same cause.
				local envish = (chain0 == "getfenv" or chain0 == "setfenv")
					and tk[after0] and tk[after0].value == "("
				if envish then
					local c = matchClose(tk, after0)
					if not (c and tk[c + 1] and (tk[c + 1].value == "["
						or tk[c + 1].value == ".")) then envish = false end
				end
				if DANGEROUS[chain0] and not envish then
					local dv = V("danger", { root = DANGEROUS[chain0] })
					if raw then return dv, after0 end
					return consumeCall(dv, after0, depth)
				end
				-- _G["require"] / shared.loadstring / <envvar>.require
				local head, tail = chain0:match("^([%w_]+)%.(.+)$")
				if head and tail and DANGEROUS[tail] then
					local hv = lookup(head, i)
					if (envTables[head] and not lookup(head, i))
						or (hv and hv.kind == "env") then
						add("high", "env-index", t.line, string.format(
							"%s reaches %s through the environment table instead of "
							.. "naming it - a plain text search does not find this",
							chain0, tail))
						local dv = V("danger", { root = DANGEROUS[tail] })
						if raw then return dv, after0 end
						return consumeCall(dv, after0, depth)
					end
				end
			end

			local env, afterEnv = envValueAt(i)
			if env then
				-- env [ expr ]  or  env . name
				if tk[afterEnv] and tk[afterEnv].value == "[" then
					local close = matchClose(tk, afterEnv)
					local key = evalExpr(afterEnv + 1, depth)
					local nxt = (close or afterEnv) + 1
					if key.kind == "string" and DANGEROUS[key.value] then
						add("high", "env-index",
							t.line, string.format(
							"the environment table is indexed with %q to reach a "
							.. "function without ever naming it", key.value))
						return V("danger", { root = DANGEROUS[key.value] }), nxt
					end
					if key.kind ~= "string" then
						add("high", "env-dynamic-index", t.line,
							"the environment table is indexed with a value computed "
							.. "at runtime, so which function is called cannot be "
							.. "read from the source. There is no ordinary reason "
							.. "to do this.")
						return UNKNOWN(true), nxt
					end
					return UNKNOWN(true), nxt
				end
				local chain, afterChain = readChain(i)
				local tail = chain and chain:match("%.([%w_]+)$")
				if tail and DANGEROUS[tail] and not lookup(chain, i) then
					return V("danger", { root = DANGEROUS[tail] }), afterChain
				end
				return V("env", {}), afterEnv
			end

			local chain, afterChain = readChain(i)
			if chain then
				if chain:match("HttpService$") then
					return V("http", {}), afterChain
				end
				-- setmetatable({}, {__index = getfenv()}) behaves as the env
				if chain == "setmetatable" and tk[afterChain]
					and tk[afterChain].value == "(" then
					local close = matchClose(tk, afterChain)
					if close then
						local src = ""
						for k = afterChain, close do src = src .. tk[k].value .. " " end
						if src:match("getfenv") or src:match("_G") then
							return V("env", {}), close + 1
						end
					end
				end
				return UNKNOWN(false), afterChain
			end
		end

		if t.value == "{" then
			local close = matchClose(tk, i)
			return V("table", { open = i, close = close }), (close or i) + 1
		end

		return UNKNOWN(false), i + 1
	end

	---------------------------------------------------------------------
	-- record what a name holds
	---------------------------------------------------------------------
	local function noteString(name, v, line)
		if v.kind ~= "string" then return end
		if ALARM_WORD[v.value] then
			local built = v.hidden or v.joined
			add(built and "critical" or "low",
				built and "assembled-name" or "literal-name", line,
				string.format("%s is set to %q%s", name, v.value,
					built and " - spelled out at runtime from character codes, "
						.. "concatenation or escapes rather than simply written. "
						.. "Nothing does that by accident."
					or ""))
		end
	end

	-- table constructor fields:  { load = require }  /  { require }
	local function recordTableFields(prefix, openIdx)
		local close = matchClose(tk, openIdx)
		if not close then return end
		local j, arrayIdx = openIdx + 1, 1
		while j < close do
			if tk[j].type == "name" and tk[j + 1] and tk[j + 1].value == "=" then
				local key = tk[j].value
				local v, after = evalExpr(j + 2, 0)
				bind(prefix .. "." .. key, v, j, false)
				noteString(prefix .. "." .. key, v, tk[j].line)
				j = after
			elseif tk[j].value == "," then
				j = j + 1
			else
				local v, after = evalExpr(j, 0)
				if v.kind ~= "unknown" then
					bind(prefix .. "." .. tostring(arrayIdx), v, j, false)
				end
				arrayIdx = arrayIdx + 1
				j = (after > j) and after or (j + 1)
			end
		end
	end

	---------------------------------------------------------------------
	-- PASS 1 - assignments and simple factory functions
	---------------------------------------------------------------------
	local i = 1
	while tk[i] do
		local t = tk[i]
		if t.type == "keyword" then
			local v = t.value
			if v == "function" or v == "if" or v == "repeat" or v == "for"
				or v == "while" or v == "do" then
				if BLOCK_END[i] then blockStack[#blockStack + 1] = i end
			elseif v == "end" or v == "until" then
				blockStack[#blockStack] = nil
			end
		end

		-- local function f() return require end
		if t.type == "keyword" and t.value == "function"
			or (t.type == "keyword" and t.value == "local"
				and tk[i + 1] and tk[i + 1].value == "function") then
			local nameIdx = (t.value == "local") and i + 2 or i + 1
			local fname = readChain(nameIdx)
			local j = nameIdx
			local guard = 0
			while tk[j] and guard < 4000 do
				if tk[j].type == "keyword" and tk[j].value == "return" then
					local v = evalExpr(j + 1, 0)
					if v.kind == "danger" and fname then
						bind(fname, V("factory", { root = v.root }), j, true)
					end
					break
				end
				if tk[j].type == "keyword" and tk[j].value == "end" then break end
				j = j + 1; guard = guard + 1
			end
		end

		local start = i
		local isLocalDecl = false
		if t.type == "keyword" and t.value == "local" then
			start = i + 1; isLocalDecl = true
		end
		if tk[start] and tk[start].type == "name" then
			-- gather lhs list:  a, b, c =
			local names, j = {}, start
			while tk[j] and tk[j].type == "name" do
				-- `local loader: any = require` - readChain would fold ":any"
				-- into the name and bind "loader.any", leaving `loader` unknown.
				-- Every type-annotated local was invisible, which means a
				-- --!strict codebase defeated the alias tracker by accident.
				local chain, after
				if tk[j + 1] and tk[j + 1].value == ":" and start == i + 1 then
					chain = tk[j].value
					after = j + 1
					local depth = 0
					while tk[after] and not (depth == 0
						and (tk[after].value == "=" or tk[after].value == ","
							or tk[after].type == "keyword")) do
						local vv = tk[after].value
						if vv == "(" or vv == "{" or vv == "<" then depth = depth + 1 end
						if vv == ")" or vv == "}" or vv == ">" then depth = depth - 1 end
						after = after + 1
					end
				else
					chain, after = readChain(j)
				end
				names[#names + 1] = chain
				j = after
				if tk[j] and tk[j].value == "," then j = j + 1 else break end
			end
			if tk[j] and tk[j].value == "=" and tk[j + 1]
				and tk[j + 1].value ~= "=" then
				local r, n = j + 1, 1
				while tk[r] and n <= #names do
					if tk[r].value == "{" then
						recordTableFields(names[n], r)
						bind(names[n], V("table", {}), r, isLocalDecl)
						local c = matchClose(tk, r)
						r = (c or r) + 1
					else
						local v, after = evalExpr(r, 0)
						bind(names[n], v, r, isLocalDecl)
						noteString(names[n], v, tk[r].line)
						if v.kind == "danger" then
							local fld = names[n]:match("%.([%w_]+)$")
							if fld then
								dangerFields[fld] = v.root
								if fld ~= v.root then
									-- renamed on the way in. `Cache.require =
									-- require` keeps the name and is a normal
									-- injectable loader; `L.fn = require` hides it.
									renamedFields[fld] = v.root
									add("medium", "renamed-alias", tk[r].line,
										string.format("%s is set to %s - the same "
											.. "function under a different name, "
											.. "which a text search will not find",
											names[n], v.root))
								end
							end
						end
						r = after
					end
					if tk[r] and tk[r].value == "," then r = r + 1 else break end
					n = n + 1
				end
				i = j
			end
		end
		i = i + 1
	end

	---------------------------------------------------------------------
	-- PASS 2 - calls, in any syntactic form
	---------------------------------------------------------------------
	local function argValues(openIdx)
		local out = {}
		if not tk[openIdx] then return out end
		if tk[openIdx].type == "string" then
			out[1] = V("string", { value = tk[openIdx].value,
				hidden = isEscapedLiteral(tk[openIdx]) })
			return out
		end
		if tk[openIdx].value ~= "(" then return out end
		local close = matchClose(tk, openIdx)
		if not close then return out end
		local j = openIdx + 1
		local guard = 0
		while j < close and guard < 500 do
			local v, after = evalExpr(j, 0)
			out[#out + 1] = v
			j = (after > j) and after or (j + 1)
			while j < close and tk[j].value ~= "," do j = j + 1 end
			if j < close then j = j + 1 end
			guard = guard + 1
		end
		return out
	end

	local SAFE_ROOT = { script = true, game = true, workspace = true,
		Instance = true }

	i = 1
	local guard = 0
	while tk[i] and guard < 200000 do
		guard = guard + 1
		local t = tk[i]
		if t.type ~= "name" and t.value ~= "(" then i = i + 1
		elseif true then
			local callee, after = evalExpr(i, 0, true)
			if after <= i then i = i + 1
			else
				-- ALWAYS advance by one token at the end of this branch, never
				-- to `after`. Jumping to `after` skipped the whole body of
				-- `register(function() ... pcall(require, id) ... end)` - the
				-- single most realistic backdoor in the holdout set walked
				-- straight through because the paren group was stepped over.
				-- `function bootstrap(require, root)` is a DECLARATION. Scoring
				-- the parameter list as an argument list reported "require is
				-- passed as a value to bootstrap" on the definition line, and
				-- reported `critical loadstring` on a function that merely
				-- returns a local of that name.
				-- Walk back over the whole dotted/colon name, because pass 2
				-- visits every token: for `function M.withLoader(require)` it
				-- lands on `withLoader`, whose previous token is `.`, and only
				-- `M` sits directly after `function`. Checking one or two
				-- tokens back reported the DECLARATION as a call.
				local b = i - 1
				while tk[b] and (tk[b].value == "." or tk[b].value == ":"
					or tk[b].type == "name") do b = b - 1 end
				local isDecl = tk[b] and tk[b].type == "keyword"
					and tk[b].value == "function"
				local isCall = (not isDecl) and tk[after]
					and (tk[after].value == "("
						or tk[after].type == "string")
				-- Do NOT jump to `after` here. The outer loop already advances
				-- one token, so setting i = after skipped exactly one token -
				-- and in `local foo = require` / `foo(id)` the token skipped
				-- was `foo`. Recall fell from 0.83 to 0.67 on that one line.
				if not isCall then -- fall through; outer loop advances by one
				else
					local args = argValues(after)
					local a1 = args[1]
					local _ = a1
					local line = t.line

					-- a dangerous function passed as a VALUE:  pcall(require, id)
					local passedDanger, numberArg
					for _, a in ipairs(args) do
						if a.kind == "danger" then passedDanger = a.root end
						if a.kind == "number" then numberArg = a.value end
					end
					if passedDanger then
						local chain = readChain(i)
						if numberArg then
							add("critical", "danger-as-argument", line,
								string.format("%s is handed to %s together with the "
									.. "number %s - the call is made for it, so the "
									.. "text \"%s(\" never appears",
									passedDanger, tostring(chain or "a call"),
									tostring(numberArg), passedDanger))
						else
							-- `pcall(require, child)` / `xpcall(require, h, m)` /
							-- `task.spawn(require, m)` is how everyone writes
							-- fault-tolerant module loading. Only the version
							-- carrying an asset id is worth waking someone for.
							-- pcall/xpcall/task.* with a module Instance is the
							-- ordinary defensive-require idiom -> low.
							-- Handing it to a plain local function is not: that
							-- function is a trampoline whose only job is to make
							-- the call somewhere the text search is not looking.
							local ch2 = readChain(i) or ""
							local ordinary = ch2 == "pcall" or ch2 == "xpcall"
								or ch2:match("^task%.") or ch2:match("^coroutine%.")
							add(ordinary and "low" or "high", "danger-as-argument",
								line,
								string.format("%s is passed as a value to %s%s",
									passedDanger, tostring(chain or "a call"),
									ordinary and " rather than called by name"
										or " - a local function receiving require "
										.. "as an argument is a trampoline"))
						end
						local ch = readChain(i)
						if ch and WRAPPERS[ch] then
							callee = V("factory", { root = passedDanger })
						end
					end

					if callee.kind == "factory" then
						-- get()(id): the first call hands back the function,
						-- the second one is the call that matters.
						local close = (tk[after].value == "(")
							and matchClose(tk, after) or after
						if close and tk[close + 1] and tk[close + 1].value == "(" then
							after = close + 1
							args = argValues(after)
							a1 = args[1]
						end
						callee = V("danger", { root = callee.root })
					end

					if callee.kind == "danger" then
						local root = callee.root
						if root == "require" then
							local chain = readChain(i)
							if a1 and a1.kind == "number" then
								add("critical", "require-asset-id", line,
									string.format("require(%s) loads code from a "
										.. "Roblox asset id at runtime - the most "
										.. "common backdoor shape there is",
										tostring(a1.raw or a1.value)))
							elseif a1 and a1.kind == "string" then
								-- require("Maid") is a Nevermore-style name loader;
								-- require("@lune/fs") is a Lune build script. Both
								-- are ordinary. Only an ASSEMBLED string is a tell.
								add(a1.hidden and "critical" or "low",
									"require-string", line,
									"require() on a string" ..
									(a1.hidden and " assembled at runtime" or ""))
							else
								if isNumberProducer(after + 1) then
									add("critical", "require-asset-id", line,
										"require(tonumber(...)) - the argument is "
										.. "forced to a number, so this is loading "
										.. "an asset id chosen at runtime")
								end
								local argChain = readChain(after + 1)
								local root1 = argChain and argChain:match("^([%w_]+)")
								if root1 and SAFE_ROOT[root1] then
									-- require(script.Parent.X) - ordinary.
								else
									-- INFORMATIONAL ONLY, AND THIS IS THE POINT.
									-- Scoring this HIGH is how v1 flagged Knit,
									-- Rojo, folder loops and every OOP loader -
									-- 12 of 15 false positives from one rule.
									add("low", "require-dynamic", line,
										string.format("require(%s) - target decided "
											.. "at runtime. Normal in framework code; "
											.. "listed only for completeness.",
											tostring(argChain or "?")))
								end
							end
							if chain and chain ~= "require" then
								add("low", "aliased-require", line,
									string.format("%q is an alias for require",
										tostring(chain)))
							end
						elseif root == "loadstring" then
							add("critical", "loadstring", line,
								"loadstring() compiles a string as code at runtime")
						elseif root == "getfenv" or root == "setfenv" then
							add("low", root, line, root .. "() reads or replaces "
								.. "the environment table")
						end
					end

					-- self.fn(id) where somewhere above: L.fn = require
					do
						local ch = readChain(i)
						local selfField = ch and ch:match("^self%.([%w_]+)$")
						if selfField and dangerFields[selfField] then
							-- An injectable/mockable require (`Cache.require = require`,
							-- then `self.require(moduleScript)`) is a normal testing
							-- pattern, and dangerFields is keyed on the bare field
							-- name so unrelated `self.get(...)` collided with it.
							-- dangerFields is keyed on the bare field name with no
							-- receiver, so `ModuleCache.get = require` collided
							-- with an unrelated `Inventory:get`. Until the
							-- receiver is tracked properly this only reaches
							-- HIGH when it carries an asset id; otherwise it is
							-- an inventory row, not an alarm.
							local sev = (a1 and a1.kind == "number")
								and "critical" or "medium"
							add(sev, "field-alias", line, string.format(
								"self.%s was assigned %s earlier in this file%s",
								selfField, dangerFields[selfField],
								(a1 and a1.kind == "number")
									and (" and is called with the asset id "
										.. tostring(a1.raw or a1.value)) or ""))
						end
					end

					-- HttpService egress
					local chain = readChain(i)
					local tail = chain and chain:match("%.([%w_]+)$")
					if tail and HTTP_CALL[tail] then
						local base = chain:sub(1, #chain - #tail - 1)
						local bv = lookup(base, i)
						if base:match("HttpService") or (bv and bv.kind == "http") then
							-- Splitting a URL across two literals is line wrapping,
							-- not hiding. v1 called that HIGH and flagged an
							-- ordinary Discord webhook. Only character codes,
							-- escapes and reversal count as hiding.
							local hidden = (a1 and a1.hidden) and true or false
							add(hidden and "high" or "medium", "http-egress", line,
								string.format("HttpService:%s - data can leave the "
									.. "game here%s", tail,
									hidden and ". The address is built from "
										.. "character codes, which only defeats "
										.. "someone reading the source" or ""))
						end
					end

					local built = decodeCharCall(i)
					if built and ALARM_WORD[built] then
						add("critical", "assembled-name", line,
							string.format("character codes spell %q inline", built))
					end

				end
			end
			i = i + 1
		end
	end

	---------------------------------------------------------------------
	-- PASS 3 - the lexical backstop, and the reason the product works
	---------------------------------------------------------------------
	-- THE RESHAPE THAT CAME OUT OF THREE ROUNDS OF ADVERSARIES:
	-- a verdict ("is this malicious?") is not something static analysis can
	-- promise, because `require(id)` in a framework loader and `require(id)`
	-- in a backdoor are the SAME SOURCE. The only difference is the value of
	-- the id, and the value is not in the file.
	--
	-- An INVENTORY is promisable. "Here is every place this script can load
	-- code at runtime" has a definite, checkable answer, and a developer
	-- reading eight ranked lines decides in thirty seconds what a boolean
	-- never could.
	--
	-- So the value tracker above RANKS, and this pass GUARANTEES COVERAGE:
	-- every literal require/loadstring/InsertService token in an executable
	-- position gets a row, even when the tracker could not follow the value.
	-- Adversary #2 had seven samples the tracker never saw at all - an
	-- if-expression, an IIFE, `false or require`, a variable table index.
	-- Every one of them contains the word `require` in plain sight.
	local LOADERS = { require = true, loadstring = true,
		LoadAsset = true, LoadAssetVersion = true }
	local inventory = 0
	for n = 1, #tk do
		local t = tk[n]
		if t.type == "name" and LOADERS[t.value] then
			local prev = tk[n - 1]
			-- skip declarations, table keys and string mentions
			local isKey = tk[n + 1] and tk[n + 1].value == "="
				and not (tk[n + 2] and tk[n + 2].value == "=")
			local isDecl = prev and prev.type == "keyword"
				and (prev.value == "function" or prev.value == "local")
			if not isKey and not isDecl then
				inventory = inventory + 1
				add("low", "code-load-site", t.line, string.format(
					"%s appears here in an executable position. Every site is "
					.. "listed whether or not the analyser could follow what it "
					.. "loads - completeness is the promise, ranking is the "
					.. "best effort.", t.value))
			end
		end
	end

	table.sort(findings, function(a, b)
		if SEV[a.severity] ~= SEV[b.severity] then
			return SEV[a.severity] > SEV[b.severity]
		end
		return (a.line or 0) < (b.line or 0)
	end)

	local worst = 0
	for _, f in ipairs(findings) do
		if SEV[f.severity] > worst then worst = SEV[f.severity] end
	end

	return { source = sourceName or "?", findings = findings,
		flagged = worst >= SEV.high, worst = worst, tokenCount = #tk,
		-- how many places this script can load code at all
		siteCount = inventory,
		listed = #findings > 0 }
end

Scanner.SEV = SEV
-- Documented, deliberate misses. Do not pretend these are covered.
Scanner.KNOWN_MISSES = {
	"a value arriving through varargs (`local f = ...`)",
	"a field assigned inside a method and called through `self`",
	"decoding done in a loop the analyser does not execute",
	"anything that needs real cross-function dataflow",
}
return Scanner
