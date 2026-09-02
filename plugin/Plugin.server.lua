--!strict
-- Studio wiring only. Every line of analysis lives in src/Scanner.lua, which
-- runs under a plain `lua` binary so it can be tested outside Studio. That
-- separation is the reason there is a measured number at all.

local Selection = game:GetService("Selection")

-- WHY THIS LINE EXISTS (do not remove)
--   Scanner.lua chooses its Lexer import with:
--       _G.__ROBLOX and require(script.Parent.Lexer) or require("Lexer")
--   Under a plain `lua` binary the flag is nil, so it takes the package.path
--   branch, which is what the corpus tests use. Studio has no package.path,
--   so with the flag unset the plugin ERRORS ON LOAD. It has to be set before
--   Scanner is required. Doing it here keeps Scanner.lua byte-identical to
--   the file the 61-script corpus actually scored.
_G.__ROBLOX = true

local Scanner = require(script.Parent.Scanner)

--------------------------------------------------------------------------------
-- Baseline
--------------------------------------------------------------------------------

-- WHY A BASELINE IS THE POINT
--   A one-off scan of a place you did not write tells you almost nothing you
--   can act on: framework code loads modules dynamically, so a long list of
--   sites is the normal, healthy state. What is actually worth an alarm is a
--   site that WAS NOT THERE YESTERDAY.
--
--   So the plugin remembers the shape of the last scan you blessed, and every
--   scan after that leads with what changed. A backdoor added by a
--   collaborator, a free model dragged in, a plugin that edits your scripts -
--   all of them show up as NEW against a baseline and are invisible in a
--   single scan.
--
--   This is the same idea as watching a data feed for schema drift rather than
--   re-reading the whole feed every day.

local BASELINE_KEY = "ScriptAudit_baseline_v1"
-- Settings are stored per plugin and read back on every scan. A place with
-- tens of thousands of scripts would make that table a liability, so the
-- baseline is capped and says so rather than silently holding a partial one.
local BASELINE_MAX = 6000

-- FNV-1a, 32-bit. Not security - just a short stable stand-in for "the set of
-- findings in this script", so the baseline stays small.
--
-- The multiply is split into 16-bit halves on purpose. Lua numbers are
-- doubles, and a straight `h * 16777619` reaches 7.2e16 for large h, past the
-- 2^53 where a double stops being able to hold an exact integer. It would
-- still be deterministic, but it would no longer be FNV and it would depend on
-- float rounding. Each half here peaks near 1.1e12, which is exact.
local function fnv1a(str: string): number
	local h = 2166136261
	for i = 1, #str do
		h = bit32.bxor(h, string.byte(str, i))
		local lo = bit32.band(h, 0xFFFF) * 16777619
		local hi = bit32.band(bit32.rshift(h, 16) * 16777619, 0xFFFF)
		h = bit32.band(lo + bit32.lshift(hi, 16), 0xFFFFFFFF)
	end
	return h
end

-- WHY THE BASELINE IS A LIST OF STRINGS AND NOT A MAP KEYED BY PATH
--   The obvious shape is { ["ServerScriptService.Runtime"] = 12345 }. It does
--   not work. Studio's plugin settings mangle dots in KEYS: every path written
--   as a key came back as "ServerScriptService_Runtime", so on the next scan
--   every real path looked new and every stored path looked gone. The first
--   run against a modified place reported 6 new and 7 gone where the truth was
--   1 and 0.
--
--   So the path goes in the VALUE, never the key. Entries are "<sig>|<path>"
--   strings in a plain array, and the only keys are "saved" and "entries".
--
--   This is the bug that every test outside Studio would have missed, because
--   nothing outside Studio has plugin settings.

local function loadBaseline(): ({ [string]: number }?, string?)
	local ok, v = pcall(function()
		return plugin:GetSetting(BASELINE_KEY)
	end)
	if not ok or typeof(v) ~= "table" then return nil, nil end
	local entries = (v :: any).entries
	if typeof(entries) ~= "table" then return nil, nil end
	local map: { [string]: number } = {}
	for _, e in ipairs(entries) do
		if typeof(e) == "string" then
			local bar = string.find(e, "|", 1, true)
			if bar then
				local sig = tonumber(string.sub(e, 1, bar - 1))
				local path = string.sub(e, bar + 1)
				if sig and #path > 0 then map[path] = sig end
			end
		end
	end
	local stamp = (v :: any).saved
	return map, (typeof(stamp) == "string") and stamp or nil
end


--------------------------------------------------------------------------------
-- What counts as "this place"
--------------------------------------------------------------------------------

-- WHY A DENYLIST AND NOT A LIST OF SERVICES
--   A plugin runs at plugin identity and can walk CoreGui and CorePackages,
--   which hold hundreds of Roblox's own scripts whose .Source is denied. Those
--   would land in the COULD NOT BE READ list, so a clean baseplate would open
--   with four hundred lines of Roblox's own code reported as a hole in
--   coverage. They are not part of the place and are not ours to audit.
--
--   The first version of this fix was an allowlist of fourteen service names.
--   That is worse than the bug it fixed. "Coverage is the promise" and "here
--   are the fourteen places I look" cannot both be true, and the list can only
--   rot - TextChatService alone is where modern places keep chat modules, and
--   it was missing. Anything Roblox ships from now on would be silently
--   invisible, and the failure mode is a clean-looking report.
--
--   So: skip the two things that are demonstrably not ours, take everything
--   else, and SAY ON SCREEN what was skipped.
local SKIP: { [string]: boolean } = {
	CoreGui = true,
	CorePackages = true,
	CoreScriptDebuggerManager = true,
}

local function placeRoots(): ({ Instance }, { string })
	local out: { Instance } = {}
	local skipped: { string } = {}
	-- GetChildren, not a name list: a service that has never been instantiated
	-- is not a child of the DataModel, and a service that does not exist cannot
	-- be holding a script.
	for _, svc in ipairs(game:GetChildren()) do
		if SKIP[svc.Name] then
			skipped[#skipped + 1] = svc.Name
		else
			out[#out + 1] = svc
		end
	end
	return out, skipped
end

--------------------------------------------------------------------------------
-- Toolbar
--------------------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Script Audit")

-- An empty icon string gives a text-only button. `rbxassetid://0` does NOT -
-- it asks Studio for asset 0, which does not exist, and renders a blank box
-- that looks like the plugin failed to load.
local buttonShow = toolbar:CreateButton(
	"Script Audit", "Show or hide the report window", "")
local buttonPlace = toolbar:CreateButton(
	"Scan place", "List every place this game can load code at runtime", "")
local buttonSelection = toolbar:CreateButton(
	"Scan selection", "Same, but only what is selected in the Explorer", "")

for _, b in ipairs({ buttonShow, buttonPlace, buttonSelection }) do
	b.ClickableWhenViewportHidden = true
end

-- InitialEnabledShouldOverrideRestore is false, so Studio restores the open /
-- closed state itself. Do NOT add a second GetSetting/SetSetting mechanism on
-- top - two systems writing the same state is how the window ends up opening
-- blank.
local info = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, false, false, 560, 440, 380, 260)
local widget = plugin:CreateDockWidgetPluginGui("ScriptAuditWidget", info)
widget.Title = "Script Audit"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------

-- Studio has a Light theme and a lot of people use it. Hardcoding one palette
-- makes half the report invisible for them, so every colour here is either
-- taken from the theme or picked from a light/dark pair.
local DARK_SEV = {
	critical = Color3.fromRGB(214, 78, 78),
	high = Color3.fromRGB(219, 142, 52),
	medium = Color3.fromRGB(186, 176, 66),
	low = Color3.fromRGB(150, 150, 160),
}
local LIGHT_SEV = {
	critical = Color3.fromRGB(163, 26, 26),
	high = Color3.fromRGB(152, 84, 8),
	medium = Color3.fromRGB(115, 105, 10),
	low = Color3.fromRGB(105, 105, 115),
}
local KNOWN_SEV = { "critical", "high", "medium", "low" }
local IS_KNOWN_SEV: { [string]: boolean } = {}
for _, s in ipairs(KNOWN_SEV) do IS_KNOWN_SEV[s] = true end

-- Constants, so a lookup that fails on the SECOND theme change falls back to a
-- sane default instead of silently keeping the previous theme's colour.
local D_TEXT = Color3.fromRGB(220, 220, 220)
local D_BACK = Color3.fromRGB(46, 46, 46)
local D_DIM = Color3.fromRGB(150, 150, 160)
local D_HOVER = Color3.fromRGB(85, 85, 85)

local themeText, themeBack, themeDim, themeHover = D_TEXT, D_BACK, D_DIM, D_HOVER
local SEV = DARK_SEV

local function sevColour(name: any): Color3
	return SEV[name] or themeDim
end

local rerender: (() -> ())? = nil

local function refreshTheme()
	local ok, theme = pcall(function()
		return settings().Studio.Theme
	end)
	if ok and theme then
		-- Enum members are looked up BY NAME inside the pcall on purpose.
		-- Written as `Enum.StudioStyleGuideColor.DimmedText` the index happens
		-- while evaluating the argument, outside any pcall, so one member
		-- missing from this Studio build would kill the plugin at load.
		local function col(name: string, modifier: string?, fallback: Color3): Color3
			local okc, c = pcall(function()
				local item = (Enum.StudioStyleGuideColor :: any)[name]
				if modifier then
					return theme:GetColor(item, (Enum.StudioStyleGuideModifier :: any)[modifier])
				end
				return theme:GetColor(item)
			end)
			if okc and typeof(c) == "Color3" then return c end
			return fallback
		end
		themeText = col("MainText", nil, D_TEXT)
		themeBack = col("MainBackground", nil, D_BACK)
		themeDim = col("DimmedText", nil, D_DIM)
		-- Studio's own list-row hover colour. Tinting a mid-grey Button colour
		-- over a mid-grey background at 85% transparency was a difference of
		-- about four values out of 255 - present in the code, invisible on the
		-- screen. This is the colour Studio actually uses for the job.
		themeHover = col("Item", "Hover", D_HOVER)
	end
	-- Luminance, not a theme-name string: a custom theme is still light or dark.
	local lum = themeBack.R * 0.299 + themeBack.G * 0.587 + themeBack.B * 0.114
	SEV = (lum > 0.5) and LIGHT_SEV or DARK_SEV
	if rerender then rerender() end
end

--------------------------------------------------------------------------------
-- Scan
--------------------------------------------------------------------------------

type Row = { path: string, inst: Instance?, finding: any }
type Result = {
	rows: { Row },
	sites: number,
	scanned: number,
	unreadable: { string },
	skipped: { string },
	sigs: { [string]: number },
	scriptPaths: { string },
	seconds: number,
	cancelled: boolean,
	selectionOnly: boolean,
}

local scanning = false
local activeIsSelection: boolean? = nil
local cancelRequested = false

local function sourcesToScan(selectionOnly: boolean): ({ Instance }, { string })
	local out: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	local roots: { Instance }, skipped: { string }
	if selectionOnly then
		roots, skipped = Selection:Get(), {}
	else
		roots, skipped = placeRoots()
	end
	for _, root in ipairs(roots) do
		if root:IsA("LuaSourceContainer") and not seen[root] then
			seen[root] = true
			out[#out + 1] = root
		end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("LuaSourceContainer") and not seen[d] then
				seen[d] = true
				out[#out + 1] = d
			end
		end
	end
	return out, skipped
end

-- WHY THIS YIELDS
--   A place with a few thousand scripts is ordinary. Tokenising all of them in
--   one frame freezes Studio hard enough that Windows offers to kill it, and a
--   plugin that appears to hang the editor is a plugin nobody keeps installed.
--   Cancel possible. task.wait() rather than Heartbeat:Wait() - Heartbeat does
--   fire in edit mode, but task.wait() does not require me to be right.
--
-- WHY IT YIELDS ON A CLOCK AND NOT A COUNT
--   It used to yield every 25 scripts. task.wait() parks until the next frame,
--   so on a 20,000-script place that is 800 frames = about 13 seconds of
--   deliberate waiting, for roughly 1.3 seconds of actual work. Measured:
--   20,000 scripts took 13.44s, and ten times fewer scripts took 1.34s - the
--   time was almost entirely frames, not analysis.
--
--   Yielding on elapsed time instead gives the same responsiveness (the
--   window still repaints ~20 times a second, cancel still lands within a
--   frame) without padding the scan with idle frames. The count-based
--   fallback stays so a pathologically slow single script cannot stall the
--   UI for longer than YIELD_MAX_SCRIPTS.
local YIELD_SECONDS = 0.05
local YIELD_MAX_SCRIPTS = 400

local function scan(selectionOnly: boolean, onProgress: ((number, number) -> ())?): Result
	local started = os.clock()
	local list, skipped = sourcesToScan(selectionOnly)
	local rows: { Row } = {}
	local unreadable: { string } = {}
	local sites = 0
	local cancelled = false
	local lastYield = os.clock()
	local lastYieldAt = 0

	for i, inst in ipairs(list) do
		if cancelRequested then
			cancelled = true
			break
		end
		-- Reading .Source needs script-injection permission. Without it this
		-- errors rather than silently returning "", which is the only reason
		-- we can tell "clean" apart from "never looked at".
		local ok, src = pcall(function()
			return (inst :: any).Source
		end)
		if not ok or typeof(src) ~= "string" then
			unreadable[#unreadable + 1] = inst:GetFullName()
		else
			local okAnalyse, r = pcall(Scanner.analyse, src, inst:GetFullName())
			if not okAnalyse then
				-- One malformed script must not take the whole report with it.
				unreadable[#unreadable + 1] = inst:GetFullName()
					.. "   (analyser error: " .. tostring(r):sub(1, 80) .. ")"
			else
				sites += r.siteCount or 0
				for _, f in ipairs(r.findings) do
					rows[#rows + 1] = { path = inst:GetFullName(), inst = inst, finding = f }
				end
			end
		end
		if (os.clock() - lastYield) >= YIELD_SECONDS
			or (i - lastYieldAt) >= YIELD_MAX_SCRIPTS then
			if onProgress then onProgress(i, #list) end
			task.wait()
			lastYield = os.clock()
			lastYieldAt = i
		end
	end

	-- One number per script standing for "the set of findings in it". Built
	-- from severity+line+rule, sorted, so it does not move when the report
	-- ordering does.
	local perPath: { [string]: { string } } = {}
	for _, r in ipairs(rows) do
		local t = perPath[r.path]
		if not t then t = {}; perPath[r.path] = t end
		t[#t + 1] = ("%s|%s|%s"):format(
			tostring(r.finding.severity), tostring(r.finding.line), tostring(r.finding.rule))
	end
	local sigs: { [string]: number } = {}
	local scriptPaths: { string } = {}
	for _, inst in ipairs(list) do
		local p = inst:GetFullName()
		scriptPaths[#scriptPaths + 1] = p
		local t = perPath[p]
		if t then
			table.sort(t)
			sigs[p] = fnv1a(table.concat(t, "\n"))
		else
			-- A script with no findings still has to be in the baseline, or
			-- "findings appeared in a file that had none" reads as a new file.
			sigs[p] = 0
		end
	end

	local order = Scanner.SEV
	table.sort(rows, function(a, b)
		local sa = order[a.finding.severity] or 0
		local sb = order[b.finding.severity] or 0
		if sa ~= sb then return sa > sb end
		if a.path ~= b.path then return a.path < b.path end
		return (a.finding.line or 0) < (b.finding.line or 0)
	end)

	return {
		rows = rows, sites = sites, scanned = #list - #unreadable,
		unreadable = unreadable, skipped = skipped,
		sigs = sigs, scriptPaths = scriptPaths,
		seconds = os.clock() - started, cancelled = cancelled,
		selectionOnly = selectionOnly,
	}
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

-- One TextButton per finding, two per finding with the detail on its own row,
-- is a multi-second freeze at a few thousand findings - the same freeze the
-- scan loop yields to avoid. So: detail goes in the SAME button behind a
-- newline (half the instances), the loop yields, and the list is capped.
local MAX_ROWS = 150

-- The findings list was capped from the start. The diff list was not, and a
-- 2,000-script place against a baseline taken from a different place drew
-- 1,429 NEW rows before the findings - burying the actual report under a wall
-- of red you cannot scroll past. Same failure the cap exists to prevent; I
-- just never applied it to the block I added last.
local MAX_DIFF_ROWS = 40

-- The render loop yields, so a theme change can start a second render while
-- the first is parked. LayoutOrder happens to survive that, but only because
-- every reset is paired with a fresh list - an invariant nobody will remember.
-- A generation counter makes the stale render exit instead.
local renderGen = 0
local nextOrder = 0

local function clear()
	for _, c in ipairs(widget:GetChildren()) do
		c:Destroy()
	end
end

local function beginRender(): (ScrollingFrame, number)
	renderGen += 1
	local mine = renderGen
	clear()
	nextOrder = 0

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = themeBack
	bg.BorderSizePixel = 0
	bg.Parent = widget

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 8
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Parent = bg

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	return list, mine
end

local function line(list: ScrollingFrame, text: string, colour: Color3?, inst: Instance?,
		onClick: (() -> ())?): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -8, 0, 18)
	b.AutomaticSize = Enum.AutomaticSize.Y
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextYAlignment = Enum.TextYAlignment.Top
	b.TextWrapped = true
	b.RichText = false
	b.Font = Enum.Font.Code
	b.TextSize = 13
	b.TextColor3 = colour or themeText
	b.BackgroundColor3 = themeHover
	b.BackgroundTransparency = 1
	-- AutoButtonColor modulates BackgroundColor3, and there is nothing to
	-- modulate at full transparency - a clickable row would look exactly like
	-- a label. Do the hover by hand, and at full opacity: Studio's Item/Hover
	-- colour is chosen to be visible against Studio's own background, so
	-- fading it out is throwing away the only thing that makes it work.
	b.AutoButtonColor = false
	b.Text = text
	nextOrder += 1
	b.LayoutOrder = nextOrder
	b.Parent = list
	if inst or onClick then
		b.MouseEnter:Connect(function() b.BackgroundTransparency = 0 end)
		b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
		b.MouseButton1Click:Connect(function()
			if inst then Selection:Set({ inst }) end
			if onClick then
				local ok, err = pcall(onClick)
				if not ok then warn("[Script Audit] " .. tostring(err)) end
			end
		end)
	end
	return b
end

-- What is currently on screen. Without this, a theme change repaints the
-- "nothing selected" message as the previous scan's report, and repaints an
-- error screen as the intro - losing the error with no trace on screen.
type View = "intro" | "report" | "error" | "empty" | "busy"
local currentView: View = "intro"
local lastResult: Result? = nil
local lastError: string? = nil

local busyLabel: TextButton? = nil
local busyNote: TextButton? = nil

-- Rebuilding the whole widget on every progress tick is itself slow enough to
-- change what it is reporting on. Build it once; move one label after that.
local function renderBusy(done: number, total: number)
	if not busyLabel then
		currentView = "busy"
		local list = beginRender()
		busyLabel = line(list, "Scanning...")
		busyNote = line(list, "Click the same toolbar button again to cancel.", themeDim)
	end
	local b = busyLabel
	if b then
		b.Text = (total > 0)
			and ("Scanning... %d / %d scripts"):format(done, total)
			or "Scanning..."
	end
end

local function renderIntro()
	currentView = "intro"
	local list = beginRender()
	line(list, "Script Audit")
	line(list, "")
	line(list, "Scan place - list every point in this place where code can be "
		.. "loaded at runtime.", themeDim)
	line(list, "Scan selection - the same, for whatever is selected in the "
		.. "Explorer.", themeDim)
	line(list, "")
	line(list, "Coverage is the promise: every site gets a row.", themeDim)
	line(list, "The severity ranking is best effort. It is not a verdict.", themeDim)
end

local function renderEmpty()
	currentView = "empty"
	local list = beginRender()
	line(list, "Nothing is selected in the Explorer.", sevColour("high"))
	line(list, "Select a folder or a script, then click Scan selection.", themeDim)
end

local function renderError(what: string)
	currentView = "error"
	lastError = what
	local list = beginRender()
	line(list, "The scan failed. Nothing here is a result.", sevColour("critical"))
	line(list, what, themeDim)
end

-- Turn "Game.ServerScriptService.Runtime" back into the Instance, so a NEW or
-- CHANGED row is clickable like every other row. Nil if it has been deleted
-- since the scan, which is not an error.
-- GetFullName does NOT include the DataModel, so "ServerScriptService.Runtime"
-- walks straight down from `game`. A script whose own name contains a dot
-- cannot be found this way; that is a limit of GetFullName, not of this, and
-- it returns nil rather than guessing.
local function findByPath(full: string): Instance?
	local cur: Instance = game
	for part in string.gmatch(full, "[^%.]+") do
		local nxt = cur:FindFirstChild(part)
		if not nxt then return nil end
		cur = nxt
	end
	return (cur ~= game) and cur or nil
end

local function saveBaseline(res: Result)
	local total = 0
	for _ in pairs(res.sigs) do total += 1 end
	local entries: { string } = {}
	for p, v in pairs(res.sigs) do
		if #entries >= BASELINE_MAX then break end
		entries[#entries + 1] = ("%d|%s"):format(v, p)
	end
	local n = #entries
	local store = { saved = os.date("!%Y-%m-%d %H:%M UTC"), entries = entries }
	local ok, err = pcall(function()
		plugin:SetSetting(BASELINE_KEY, store)
	end)
	if not ok then
		warn("[Script Audit] could not save the baseline: " .. tostring(err))
		return
	end
	if total > BASELINE_MAX then
		warn(("[Script Audit] baseline capped at %d scripts of %d. The diff after "
			.. "this WILL be incomplete."):format(BASELINE_MAX, total))
	end
	print(("[Script Audit] baseline saved: %d script(s) at %s")
		:format(n, store.saved))
end

-- The report dies when the window closes, which is no use to anyone auditing a
-- place they just bought. This writes it into the place as a ModuleScript so it
-- can be read, saved with the file, and diffed in git through Rojo.
local function exportReport(res: Result)
	local lines = {
		"--[[  Script Audit report",
		"",
		("  generated : %s"):format(os.date("!%Y-%m-%d %H:%M UTC")),
		("  sites     : %d across %d script(s)"):format(res.sites, res.scanned),
		("  findings  : %d"):format(#res.rows),
	}
	if #res.skipped > 0 then
		lines[#lines + 1] = ("  not scanned: %s"):format(table.concat(res.skipped, ", "))
	end
	if #res.unreadable > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("  COULD NOT BE READ (%d) - coverage is incomplete:"):format(#res.unreadable)
		for _, u in ipairs(res.unreadable) do lines[#lines + 1] = "    " .. u end
	end
	lines[#lines + 1] = ""
	for _, r in ipairs(res.rows) do
		local f = r.finding
		lines[#lines + 1] = ("  [%s] %s:%s  %s"):format(
			tostring(f.severity):upper(), r.path, tostring(f.line), tostring(f.rule))
		lines[#lines + 1] = ("        %s"):format(tostring(f.detail))
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  Coverage is the promise: every site above is listed."
	lines[#lines + 1] = "  The ranking is best effort and is not a verdict."
	lines[#lines + 1] = "]]"
	lines[#lines + 1] = "return {}"

	local okS, storage = pcall(function() return game:GetService("ServerStorage") end)
	if not okS or not storage then
		warn("[Script Audit] no ServerStorage to write into.")
		return
	end
	-- Undoable. This is the only thing the plugin writes, and a read-only tool
	-- that suddenly edits your place had better leave a waypoint.
	pcall(function()
		game:GetService("ChangeHistoryService"):SetWaypoint("Script Audit report")
	end)
	local m = Instance.new("ModuleScript")
	m.Name = "ScriptAuditReport"
	m.Source = table.concat(lines, "\n")
	m.Parent = storage
	pcall(function()
		game:GetService("ChangeHistoryService"):SetWaypoint("Script Audit report written")
	end)
	Selection:Set({ m })
	print("[Script Audit] report written to ServerStorage.ScriptAuditReport (Ctrl+Z undoes it)")
end

local function render(res: Result)
	currentView = "report"
	local list, mine = beginRender()

	if res.cancelled then
		line(list, "CANCELLED - the numbers below are partial.", sevColour("high"))
	end

	line(list, ("%d code-loading site(s) across %d script(s)%s."):format(
		res.sites, res.scanned, res.selectionOnly and " in the selection" or ""))
	line(list, ("Scanned in %.2fs. Every site is listed; ranking is best effort.")
		:format(res.seconds), themeDim)
	if #res.skipped > 0 then
		-- Say what was not looked at. A coverage promise with a silent
		-- exception list is not a coverage promise.
		line(list, "Not scanned (Roblox's own, not part of your place): "
			.. table.concat(res.skipped, ", "), themeDim)
	end

	-- WHAT CHANGED comes before WHAT IS THERE. A list of sites is the normal
	-- state of any real place; a site that was not there last time is the
	-- thing worth looking at, so it goes at the top.
	local base, stamp = loadBaseline()
	line(list, "")
	if not base then
		line(list, "No baseline saved yet - this scan is a list, not a diff.", themeDim)
		line(list, "   [ save this scan as the baseline ]", themeText, nil, function()
			saveBaseline(res)
		end)
	else
		local added, changed, removed = {}, {}, {}
		local addedQuiet = 0
		local seen: { [string]: boolean } = {}
		for _, p in ipairs(res.scriptPaths) do
			seen[p] = true
			local now, was = res.sigs[p], base[p]
			if was == nil then
				if (now or 0) ~= 0 then
					added[#added + 1] = p
				else
					-- New, but loads no code. Counted so the total is honest,
					-- not listed, because a place under development would drown
					-- the real signal in ordinary new files.
					addedQuiet += 1
				end
			elseif was ~= now then
				changed[#changed + 1] = p
			end
		end
		for p in pairs(base) do
			if not seen[p] then removed[#removed + 1] = p end
		end
		table.sort(added); table.sort(changed); table.sort(removed)

		if #added == 0 and #changed == 0 and #removed == 0 and addedQuiet == 0 then
			line(list, "No change since the baseline" .. (stamp and (" saved " .. stamp) or "")
				.. ".", themeDim)
		else
			line(list, ("SINCE THE BASELINE%s: %d new, %d changed, %d gone."):format(
				stamp and (" saved " .. stamp) or "", #added, #changed, #removed),
				sevColour("high"))
			-- Draw at most MAX_DIFF_ROWS of each, say how many were left out,
			-- and send the remainder to Output in batches. A diff you cannot
			-- scroll past is not a diff.
			local function block(label: string, paths: { string }, colour: Color3, clickable: boolean)
				local shownD = math.min(#paths, MAX_DIFF_ROWS)
				for i = 1, shownD do
					local p = paths[i]
					line(list, ("   %-8s %s"):format(label, p), colour,
						clickable and findByPath(p) or nil)
					if i % 50 == 0 then
						task.wait()
						if renderGen ~= mine then return false end
					end
				end
				if shownD < #paths then
					line(list, ("   ... and %d more %s - in the Output window"):format(
						#paths - shownD, label), themeDim)
					local buf: { string } = {}
					for i = shownD + 1, #paths do
						buf[#buf + 1] = ("  %-8s %s"):format(label, paths[i])
						if #buf >= 25 then
							print("[Script Audit]\n" .. table.concat(buf, "\n"))
							buf = {}
						end
					end
					if #buf > 0 then print("[Script Audit]\n" .. table.concat(buf, "\n")) end
				end
				return true
			end

			if not block("NEW", added, sevColour("critical"), true) then return end
			if not block("CHANGED", changed, sevColour("high"), true) then return end
			if not block("GONE", removed, themeDim, false) then return end
			if addedQuiet > 0 then
				line(list, ("   and %d new script(s) that load no code."):format(addedQuiet),
					themeDim)
			end
		end
		line(list, "   [ make this scan the new baseline ]", themeText, nil, function()
			saveBaseline(res)
		end)
	end
	line(list, "   [ write this report into ServerStorage ]", themeText, nil, function()
		exportReport(res)
	end)

	if #res.unreadable > 0 then
		line(list, "")
		line(list, ("%d script(s) COULD NOT BE READ - coverage is incomplete:")
			:format(#res.unreadable), sevColour("high"))
		for _, n in ipairs(res.unreadable) do
			line(list, "   " .. n, sevColour("high"))
		end
	end

	line(list, "")

	if #res.rows == 0 then
		line(list, "Nothing was ranked. That is not the same as safe.", themeDim)
		return
	end

	-- A severity the Scanner emits that this file does not know about must not
	-- take the report down with it, and must not vanish from the count either.
	local counts: { [string]: number } = {}
	local unknownOrder: { string } = {}
	for _, r in ipairs(res.rows) do
		local s = tostring(r.finding.severity or "unknown")
		if counts[s] == nil then
			counts[s] = 0
			if not IS_KNOWN_SEV[s] then unknownOrder[#unknownOrder + 1] = s end
		end
		counts[s] += 1
	end
	local summary = {}
	for _, s in ipairs(KNOWN_SEV) do
		if counts[s] then summary[#summary + 1] = ("%d %s"):format(counts[s], s) end
	end
	for _, s in ipairs(unknownOrder) do
		summary[#summary + 1] = ("%d %s"):format(counts[s], s)
	end
	line(list, ("%d finding(s): %s"):format(#res.rows, table.concat(summary, ", ")))
	line(list, "Click any row to select that script in the Explorer.", themeDim)
	line(list, "")

	local shown = math.min(#res.rows, MAX_ROWS)
	for i = 1, shown do
		local row = res.rows[i]
		local f = row.finding
		line(list, ("[%s] %s:%s  %s\n      %s"):format(
			tostring(f.severity):upper(), row.path, tostring(f.line),
			tostring(f.rule), tostring(f.detail)),
			sevColour(f.severity), row.inst)
		if i % 50 == 0 then
			task.wait()
			-- A newer render started while this one was parked. Stop drawing
			-- into a list nobody can see.
			if renderGen ~= mine then return end
		end
	end

	if shown < #res.rows then
		line(list, "")
		line(list, ("Showing the top %d of %d findings. The other %d were "):format(
			shown, #res.rows, #res.rows - shown)
			.. "measured and are printed to the Output window - they are not "
			.. "missing, just not drawn.", sevColour("high"))
		-- One print per finding is what makes Output crawl; one print of two
		-- hundred lines is a single unfilterable, unclickable blob. Small
		-- batches keep both problems small.
		local buf: { string } = {}
		local function flush()
			if #buf > 0 then
				print("[Script Audit]\n" .. table.concat(buf, "\n"))
				buf = {}
			end
		end
		for i = shown + 1, #res.rows do
			local row = res.rows[i]
			local f = row.finding
			buf[#buf + 1] = ("  [%s] %s:%s  %s - %s"):format(
				tostring(f.severity):upper(), row.path, tostring(f.line),
				tostring(f.rule), tostring(f.detail))
			if #buf >= 25 then
				flush()
				task.wait()
				if renderGen ~= mine then return end
			end
		end
		flush()
	end
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

-- Assigned here rather than at the declaration so refreshTheme can repaint
-- whatever is actually on screen when Studio's theme changes under it.
rerender = function()
	if scanning then return end
	local ok, err = pcall(function()
		if currentView == "report" and lastResult then
			render(lastResult :: Result)
		elseif currentView == "error" then
			renderError(lastError or "unknown error")
		elseif currentView == "empty" then
			renderEmpty()
		else
			renderIntro()
		end
	end)
	if not ok then warn("[Script Audit] repaint failed: " .. tostring(err)) end
end

local function run(selectionOnly: boolean)
	if scanning then
		if activeIsSelection == selectionOnly then
			-- Same button twice means cancel.
			cancelRequested = true
		else
			-- The OTHER button. Cancelling the running scan here would look
			-- like the click did something random, so refuse it - and say so
			-- in the window, because the user is looking at the window and not
			-- at the Output panel.
			local n = busyNote
			if n then
				n.Text = "A scan is already running. Let it finish, or click "
					.. "the same button again to cancel it."
				n.TextColor3 = sevColour("high")
			end
			warn("[Script Audit] a scan is already running - let it finish, or "
				.. "click the same button again to cancel it.")
		end
		return
	end

	widget.Enabled = true

	if selectionOnly and #Selection:Get() == 0 then
		renderEmpty()
		return
	end

	busyLabel = nil
	busyNote = nil
	cancelRequested = false
	-- renderBusy touches the widget and is not inside the pcall below, so the
	-- flag goes up only once we are certain we will reach the reset.
	local okBusy, busyErr = pcall(renderBusy, 0, 0)
	if not okBusy then
		warn("[Script Audit] " .. tostring(busyErr))
		return
	end

	scanning = true
	activeIsSelection = selectionOnly
	local ok, res = pcall(scan, selectionOnly, renderBusy)
	busyLabel = nil
	busyNote = nil
	scanning = false
	activeIsSelection = nil
	cancelRequested = false

	if not ok then
		warn("[Script Audit] " .. tostring(res))
		lastResult = nil
		renderError(tostring(res))
		return
	end

	lastResult = res :: Result
	local okR, errR = pcall(render, res :: Result)
	if not okR then
		warn("[Script Audit] render failed: " .. tostring(errR))
		lastResult = nil
		renderError(tostring(errR))
	end
end

local function syncShowButton()
	buttonShow:SetActive(widget.Enabled)
end

buttonShow.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	syncShowButton()
end)
buttonPlace.Click:Connect(function()
	buttonPlace:SetActive(false)
	run(false)
end)
buttonSelection.Click:Connect(function()
	buttonSelection:SetActive(false)
	run(true)
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	syncShowButton()
	if widget.Enabled then
		-- Reopening during a scan means "I want to watch it again", not
		-- "cancel it" - so undo the cancel the close set.
		if scanning then cancelRequested = false end
	elseif scanning then
		-- Closing mid-scan stops the work rather than grinding through a few
		-- thousand scripts nobody is going to look at.
		cancelRequested = true
	end
end)

local themeConn: RBXScriptConnection? = nil
pcall(function()
	themeConn = settings().Studio.ThemeChanged:Connect(refreshTheme)
end)

-- Reloading the .rbxmx while iterating runs this file again without unloading
-- the old one, so without this every reload stacks another live refreshTheme
-- and leaves a ghost dock window behind.
plugin.Unloading:Connect(function()
	if themeConn then themeConn:Disconnect() end
	rerender = nil
	pcall(function() widget:Destroy() end)
end)

refreshTheme()
renderIntro()
syncShowButton()
