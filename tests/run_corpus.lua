-- run_corpus.lua - the two numbers this scanner is allowed to claim.
--
-- WHAT CHANGED, AND WHY IT IS THE WHOLE LESSON
--   v1 scored 1.000/1.000 on a corpus its own author wrote. An adversary got
--   0.31 recall / 0.25 precision on fresh code. v2 was tuned until it passed
--   that adversary, scored 1.000/1.000 again, and a SECOND adversary got
--   0.053 recall / 0.063 precision on fresh code.
--
--   Twice, "1.000" meant "these files were iterated against until they
--   passed". A verdict-shaped product cannot be honestly scored this way,
--   because `require(id)` in a framework loader and `require(id)` in a
--   backdoor ARE THE SAME SOURCE. The difference is the value of the id, and
--   the value is not in the file.
--
--   So the product is no longer a verdict. It is an INVENTORY with a ranking:
--
--   1. COVERAGE - every place a script can load code at runtime gets a row.
--      Definite, checkable, and the thing worth paying for. Must be 100%.
--   2. FALSE ALARMS - no ordinary file may reach high/critical. Must be 0.
--   3. FLAG RATE - how often the ranking gets it right unaided. Reported,
--      never promised, and NOT a pass/fail gate, because tuning it is exactly
--      how the last two versions fooled themselves.

package.path = "src/?.lua;" .. package.path
local Scanner = require("Scanner")

local function listDir(dir)
	local names, p = {}, io.popen('ls "' .. dir .. '" 2>/dev/null')
	if not p then return names end
	for line in p:lines() do
		if line:match("%.lua$") then names[#names + 1] = line end
	end
	p:close(); table.sort(names); return names
end

local function readFile(path)
	local f = io.open(path, "r"); if not f then return nil end
	local s = f:read("*a"); f:close(); return s
end

local SETS = {
	{ dir = "corpus/malicious",           kind = "mal",   label = "author, malicious" },
	{ dir = "corpus/clean",               kind = "clean", label = "author, clean" },
	{ dir = "corpus/holdout-malicious",   kind = "mal",   label = "adversary 1, malicious" },
	{ dir = "corpus/holdout-clean",       kind = "clean", label = "adversary 1, clean" },
	{ dir = "corpus/holdout2-malicious",  kind = "mal",   label = "adversary 2, malicious" },
	{ dir = "corpus/holdout2-clean",      kind = "clean", label = "adversary 2, clean" },
	{ dir = "corpus/inventory-only",      kind = "inv",   label = "inventory-only (real, unflaggable)" },
}

local covered, uncovered, flagged, malTotal = 0, {}, 0, 0
local falseAlarms, cleanTotal = {}, 0

for _, set in ipairs(SETS) do
	local names = listDir(set.dir)
	if #names > 0 then print(("-- %s (%d)"):format(set.label, #names)) end
	for _, name in ipairs(names) do
		local r = Scanner.analyse(readFile(set.dir .. "/" .. name), name)
		local listed = #r.findings > 0
		if set.kind == "clean" then
			cleanTotal = cleanTotal + 1
			if r.flagged then
				falseAlarms[#falseAlarms + 1] = name
				print(("   FALSE ALARM  %s"):format(name))
			end
		else
			malTotal = malTotal + 1
			if listed then covered = covered + 1
			else uncovered[#uncovered + 1] = name
				print(("   NOT INVENTORIED  %s"):format(name)) end
			if r.flagged then flagged = flagged + 1 end
		end
	end
end

local coverage = malTotal > 0 and covered / malTotal or 1
local flagRate = malTotal > 0 and flagged / malTotal or 0

print("")
print(("COVERAGE     %3d/%3d  %.3f   (must be 1.000)")
	:format(covered, malTotal, coverage))
print(("FALSE ALARMS %3d/%3d  %.3f   (must be 0.000)")
	:format(#falseAlarms, cleanTotal, cleanTotal > 0 and #falseAlarms / cleanTotal or 0))
print(("flag rate    %3d/%3d  %.3f   (reported, never promised)")
	:format(flagged, malTotal, flagRate))
print("")

local bad = false
if coverage < 1 then
	print("FAIL: not every code-loading site was inventoried: " ..
		table.concat(uncovered, ", "))
	bad = true
end
if #falseAlarms > 0 then
	print("FAIL: ordinary code reached high/critical: " ..
		table.concat(falseAlarms, ", "))
	bad = true
end
if bad then os.exit(1) end

print("PASS on both gates.")
print("")
print("Read the flag rate honestly. " .. flagged .. " of " .. malTotal ..
	" backdoors were ranked high or critical without help; the rest are")
print("listed and left to a human. That is the product: a short, complete,")
print("ranked list - not a verdict. Two earlier versions claimed a verdict")
print("and both were wrong by a factor of ten on code they had not seen.")
