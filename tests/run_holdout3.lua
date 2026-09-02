package.path = "src/?.lua;" .. package.path
local Scanner = require("Scanner")
local SEV = Scanner.SEV

-- holdout3: 23 malicious + 16 clean written by a BLIND adversary that never saw
-- Scanner.lua, Lexer.lua or any existing corpus file - only the tool's stated
-- promise. This is the test that measured v1 at 0.31 recall and v2 at 0.053.
-- v3 scored 23/23 coverage with 0 false alarms on 2026-09-02.
--
-- These are no longer a FRESH adversary - they are in the repo now, so a v4
-- would need a new blind pass. What they guard against is a future change
-- quietly breaking what v3 already catches.

local function ls(dir)
  local t, p = {}, io.popen('ls "'..dir..'"/*.lua 2>/dev/null | sort')
  if p then for l in p:lines() do t[#t+1]=l end p:close() end
  return t
end
local function read(p) local f=io.open(p); local s=f:read("*a"); f:close(); return s end

local function worst(findings)
  local w = 0
  for _, f in ipairs(findings) do w = math.max(w, SEV[f.severity] or 0) end
  return w
end

-- COVERAGE: a malicious file passes if the scanner listed AT LEAST ONE
-- code-loading site (siteCount > 0). That is the promise - list the site,
-- ranking is secondary.
print("=== MALICIOUS (coverage: was any load site listed at all?) ===")
local mtotal, mcovered, mflagged = 0, 0, 0
local missed = {}
for _, path in ipairs(ls("corpus/holdout3-malicious")) do
  local r = Scanner.analyse(read(path), path)
  mtotal = mtotal + 1
  local covered = (r.siteCount or 0) > 0 or #r.findings > 0
  local high = worst(r.findings) >= SEV.high
  if covered then mcovered = mcovered + 1 end
  if high then mflagged = mflagged + 1 end
  local name = path:match("([^/]+)$")
  print(string.format("  %-34s sites=%d findings=%d %s%s",
    name, r.siteCount or 0, #r.findings,
    covered and "LISTED" or "*** MISSED ***",
    high and " [ranked high+]" or ""))
  if not covered then missed[#missed+1] = name end
end

print()
print("=== CLEAN (false alarm: did ordinary code get ranked high/critical?) ===")
local ctotal, cfalse = 0, 0
local falsepos = {}
for _, path in ipairs(ls("corpus/holdout3-clean")) do
  local r = Scanner.analyse(read(path), path)
  ctotal = ctotal + 1
  local high = worst(r.findings) >= SEV.high
  if high then cfalse = cfalse + 1; falsepos[#falsepos+1] = path:match("([^/]+)$") end
  local name = path:match("([^/]+)$")
  print(string.format("  %-34s sites=%d findings=%d %s",
    name, r.siteCount or 0, #r.findings,
    high and "*** FALSE ALARM ***" or "ok"))
end

print()
print("================= SCORE (v3 vs a fresh adversary) =================")
print(string.format("  COVERAGE      %d/%d  = %.3f   (the promise; must be high)", mcovered, mtotal, mcovered/mtotal))
print(string.format("  FALSE ALARMS  %d/%d  = %.3f   (must be 0)", cfalse, ctotal, cfalse/ctotal))
print(string.format("  flag rate     %d/%d  = %.3f   (ranked high unaided; reported only)", mflagged, mtotal, mflagged/mtotal))
if #missed > 0 then
  print()
  print("  MISSED entirely (coverage failures):")
  for _, m in ipairs(missed) do print("    - "..m) end
end
if #falsepos > 0 then
  print()
  print("  FALSE ALARMS:")
  for _, m in ipairs(falsepos) do print("    - "..m) end
end

-- Gate. Coverage is the promise, so it is pass/fail. The flag rate is reported
-- and never gated - tuning against a corpus you can see is precisely how the
-- first two versions scored 1.000 and were wrong by a factor of ten.
if mcovered < mtotal or cfalse > 0 then
  print()
  print("FAIL: coverage must be 100% and false alarms must be zero.")
  os.exit(1)
end
print()
print("PASS on both gates.")
