#!/usr/bin/env lua
--[[
scriptaudit - the Script Audit engine, outside Roblox Studio.

WHY THIS EXISTS
    The Studio plugin can only tell you about a place that is already open on
    someone's machine. The thing teams actually need is the question asked
    automatically, on every pull request, before the code is merged:

        did this change add a new way to load code at runtime?

    That is the baseline diff, moved to where it does the most good. It needs
    no Roblox account, no Creator Store, and no Studio - it reads .lua/.luau
    files off disk with the same Scanner.lua the plugin uses and the corpus
    scores.

USAGE
    lua cli/scriptaudit.lua scan   <dir>              list every site
    lua cli/scriptaudit.lua bless  <dir> [-o FILE]    write a baseline
    lua cli/scriptaudit.lua check  <dir> [-b FILE]    fail if anything is new

EXIT CODES
    0   nothing new
    1   new or changed code-loading sites since the baseline
    2   the tool itself could not run (bad path, unreadable file, no baseline)

    2 is deliberately distinct from 1. "The check failed" and "the check could
    not run" are different facts, and a CI job that conflates them will one day
    go green because the scanner crashed.
]]

local HERE = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = HERE .. "/../src/?.lua;" .. HERE .. "/src/?.lua;src/?.lua;" .. package.path
local ok, Scanner = pcall(require, "Scanner")
if not ok then
  io.stderr:write("scriptaudit: cannot load Scanner.lua (looked next to " .. HERE .. ")\n")
  os.exit(2)
end

local BASELINE_DEFAULT = ".scriptaudit-baseline"

----------------------------------------------------------------------------
-- files
----------------------------------------------------------------------------

-- No lfs, no io.popen on Windows cmd. Try find first (Linux/macOS/CI), fall
-- back to dir. If neither works we say so rather than reporting zero files -
-- "found nothing" and "could not look" must never look the same.
local function listFiles(dir)
  local out = {}
  local cmds = {
    ('find "%s" -type f \\( -name "*.lua" -o -name "*.luau" \\) 2>/dev/null'):format(dir),
    ('dir /b /s "%s\\*.lua*" 2>nul'):format(dir),
  }
  for _, cmd in ipairs(cmds) do
    local p = io.popen(cmd)
    if p then
      for line in p:lines() do
        if line:match("%.luau?$") then out[#out + 1] = line end
      end
      p:close()
      if #out > 0 then break end
    end
  end
  table.sort(out)
  return out
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- Paths go into the baseline, so they must not depend on where the checkout
-- lives. Strip the scanned root and normalise separators.
local function relpath(path, root)
  local p = path:gsub("\\", "/")
  local r = root:gsub("\\", "/"):gsub("/+$", "")
  local pre = r .. "/"
  if p:sub(1, #pre) == pre then p = p:sub(#pre + 1) end
  return (p:gsub("^%./", ""))
end

----------------------------------------------------------------------------
-- scanning
----------------------------------------------------------------------------

local SEVS = { "critical", "high", "medium", "low" }

local function scan(dir)
  local files = listFiles(dir)
  if #files == 0 then
    io.stderr:write(("scriptaudit: no .lua or .luau files found under %q.\n"):format(dir))
    io.stderr:write("             If that is wrong, the directory walk failed rather than\n")
    io.stderr:write("             the directory being empty. Check the path.\n")
    os.exit(2)
  end
  local res = { files = {}, order = {}, sites = 0, findings = {}, unreadable = {} }
  for _, path in ipairs(files) do
    local rel = relpath(path, dir)
    local src = readFile(path)
    if not src then
      res.unreadable[#res.unreadable + 1] = rel
    else
      local okA, r = pcall(Scanner.analyse, src, rel)
      if not okA then
        res.unreadable[#res.unreadable + 1] = rel .. "  (analyser error: " .. tostring(r):sub(1, 90) .. ")"
      else
        res.sites = res.sites + (r.siteCount or 0)
        local sig = {}
        for _, f in ipairs(r.findings) do
          res.findings[#res.findings + 1] = { path = rel, f = f }
          sig[#sig + 1] = ("%s|%s|%s"):format(tostring(f.severity), tostring(f.line), tostring(f.rule))
        end
        table.sort(sig)
        res.files[rel] = table.concat(sig, ";")
        res.order[#res.order + 1] = rel
      end
    end
  end
  local rank = Scanner.SEV
  table.sort(res.findings, function(a, b)
    local sa, sb = rank[a.f.severity] or 0, rank[b.f.severity] or 0
    if sa ~= sb then return sa > sb end
    if a.path ~= b.path then return a.path < b.path end
    return (a.f.line or 0) < (b.f.line or 0)
  end)
  return res
end

----------------------------------------------------------------------------
-- baseline  (a plain text file, one record per line, so a human can read the
-- diff in a pull request instead of a blob of JSON)
----------------------------------------------------------------------------

local function writeBaseline(res, path)
  local f = io.open(path, "wb")
  if not f then
    io.stderr:write(("scriptaudit: cannot write %q\n"):format(path))
    os.exit(2)
  end
  f:write("# scriptaudit baseline v1 - one line per file: <path><TAB><signature>\n")
  f:write("# Regenerate with:  lua cli/scriptaudit.lua bless <dir>\n")
  for _, rel in ipairs(res.order) do
    f:write(rel, "\t", res.files[rel], "\n")
  end
  f:close()
  return #res.order
end

local function readBaseline(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local map, n = {}, 0
  for line in f:lines() do
    if line:sub(1, 1) ~= "#" and line ~= "" then
      local p, sig = line:match("^(.-)\t(.*)$")
      if p then map[p] = sig; n = n + 1 end
    end
  end
  f:close()
  return map, n
end

----------------------------------------------------------------------------
-- output
----------------------------------------------------------------------------

local function counts(res)
  local c = {}
  for _, e in ipairs(res.findings) do
    local s = tostring(e.f.severity or "unknown")
    c[s] = (c[s] or 0) + 1
  end
  local bits = {}
  for _, s in ipairs(SEVS) do
    if c[s] then bits[#bits + 1] = ("%d %s"):format(c[s], s) end
  end
  return table.concat(bits, ", ")
end

local function report(res, limit)
  print(("%d code-loading site(s) across %d file(s)."):format(res.sites, #res.order))
  print(("%d finding(s): %s"):format(#res.findings, counts(res)))
  print("Coverage is the promise: every site is listed. The ranking is best effort.")
  if #res.unreadable > 0 then
    print()
    print(("%d file(s) COULD NOT BE READ - coverage is incomplete:"):format(#res.unreadable))
    for _, u in ipairs(res.unreadable) do print("   " .. u) end
  end
  print()
  local shown = math.min(#res.findings, limit or #res.findings)
  for i = 1, shown do
    local e = res.findings[i]
    print(("[%s] %s:%s  %s"):format(
      tostring(e.f.severity):upper(), e.path, tostring(e.f.line), tostring(e.f.rule)))
    print("      " .. tostring(e.f.detail))
  end
  if shown < #res.findings then
    print(("... and %d more."):format(#res.findings - shown))
  end
end

----------------------------------------------------------------------------
-- commands
----------------------------------------------------------------------------

local function usage(code)
  io.stderr:write([[
scriptaudit - list every place a Roblox codebase can load code at runtime

  scan   <dir>                 report every site
  bless  <dir> [-o FILE]       record the current state as the baseline
  check  <dir> [-b FILE]       fail if anything is new since the baseline

exit: 0 clean   1 new sites   2 the tool could not run
]])
  os.exit(code or 2)
end

local cmd = arg[1]
local dir = arg[2]
if not cmd or not dir then usage(2) end

local flag = {}
for i = 3, #arg do
  if arg[i] == "-o" or arg[i] == "-b" then flag.file = arg[i + 1] end
end
local basefile = flag.file or (dir:gsub("/+$", "") .. "/" .. BASELINE_DEFAULT)

if cmd == "scan" then
  report(scan(dir), 200)
  os.exit(0)

elseif cmd == "bless" then
  local res = scan(dir)
  local n = writeBaseline(res, basefile)
  print(("baseline written: %s  (%d file(s), %d site(s))"):format(basefile, n, res.sites))
  print("Commit this file. The diff on it IS the security review.")
  os.exit(0)

elseif cmd == "check" then
  local base, nbase = readBaseline(basefile)
  if not base then
    io.stderr:write(("scriptaudit: no baseline at %q. Run `bless` first and commit it.\n"):format(basefile))
    os.exit(2)
  end
  local res = scan(dir)
  local added, changed, removed = {}, {}, {}
  local seen = {}
  for _, rel in ipairs(res.order) do
    seen[rel] = true
    local now, was = res.files[rel], base[rel]
    if was == nil then
      if now ~= "" then added[#added + 1] = rel end
    elseif was ~= now then
      changed[#changed + 1] = rel
    end
  end
  for rel in pairs(base) do
    if not seen[rel] then removed[#removed + 1] = rel end
  end
  table.sort(added); table.sort(changed); table.sort(removed)

  print(("%d code-loading site(s) across %d file(s). Baseline had %d file(s)."):format(
    res.sites, #res.order, nbase))
  if #res.unreadable > 0 then
    print(("WARNING: %d file(s) could not be read - coverage is incomplete."):format(#res.unreadable))
    for _, u in ipairs(res.unreadable) do print("   " .. u) end
  end

  if #added == 0 and #changed == 0 then
    if #removed > 0 then
      print(("%d file(s) gone since the baseline. Nothing new."):format(#removed))
    else
      print("No change since the baseline.")
    end
    os.exit(0)
  end

  print()
  print(("SINCE THE BASELINE: %d new, %d changed, %d gone."):format(#added, #changed, #removed))
  local function show(label, list)
    for _, rel in ipairs(list) do
      print(("  %-8s %s"):format(label, rel))
      for _, e in ipairs(res.findings) do
        if e.path == rel then
          print(("           [%s] line %s  %s"):format(
            tostring(e.f.severity):upper(), tostring(e.f.line), tostring(e.f.rule)))
        end
      end
    end
  end
  show("NEW", added)
  show("CHANGED", changed)
  for _, rel in ipairs(removed) do print(("  %-8s %s"):format("GONE", rel)) end
  print()
  print("If these are intended, re-bless and commit:")
  print(("  lua cli/scriptaudit.lua bless %s"):format(dir))
  os.exit(1)

else
  usage(2)
end
