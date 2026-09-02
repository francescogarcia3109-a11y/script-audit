# Script Audit — install into Roblox Studio

One file. One folder. Thirty seconds.

## What you are installing

`ScriptAudit.rbxmx` is an uncompressed Roblox model file containing three things:

    Folder "ScriptAudit"
      Script       "Plugin"    the toolbar button and the results window
      ModuleScript "Scanner"   the analysis (38,894 characters)
      ModuleScript "Lexer"     the Luau tokenizer (6,371 characters)

Studio loads every model file sitting in your local Plugins folder when it
starts, and runs any Script inside with plugin permissions. That is the whole
install mechanism — there is no installer and nothing to sign in to.

**It is already installed.** The file is sitting in
`%LOCALAPPDATA%\Roblox\Plugins\ScriptAudit.rbxmx` next to Airlock and Rojo.
Restart Studio and it will be there. The install steps below are for a
different machine, or for reinstalling after a rebuild.

## Install

Open PowerShell and paste this one line:

    Copy-Item "C:\DAVID\Factory\roblox\script-scanner\dist\ScriptAudit.rbxmx" "$env:LOCALAPPDATA\Roblox\Plugins\" -Force

If it says the folder does not exist, make it first:

    New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\Roblox\Plugins" | Out-Null

Then **restart Studio**. Plugins are only read at startup — reopening a place
is not enough.

You can also do it by hand: in Studio, **Plugins → Plugins Folder**, then drag
`ScriptAudit.rbxmx` into the window that opens, and restart.

## Use

A toolbar tab called **Script Audit** appears with three buttons:

* **Script Audit** — show or hide the report window. Does not scan.
* **Scan place** — every script in the open place.
* **Scan selection** — only what is selected in the Explorer.

Clicking a finding selects that script in the Explorer. Clicking the same scan
button while a scan is running cancels it; the progress counter tells you where
it got to. Closing the window mid-scan stops the work.

## The baseline — this is the part that is actually worth something

One scan of a place tells you very little. Framework code loads modules at
runtime, so a long list of sites is the normal, healthy state of any real
place. What deserves an alarm is **a site that was not there last time.**

So: scan a place you trust, then click

    [ save this scan as the baseline ]

From then on every scan leads with the diff:

    SINCE THE BASELINE saved 2026-09-02 13:43 UTC: 1 new, 0 changed, 0 gone.
       NEW      ReplicatedStorage.SoundManager

`NEW` is a script that loads code and was not in the baseline. `CHANGED` means
the same script loads code in a different place or a different way than it did.
`GONE` is a script from the baseline that is no longer here. New scripts that
load no code are counted, not listed, so ordinary development does not drown
the signal.

The baseline lives in your Studio plugin settings, not in the place, so it
follows you rather than the file. `[ make this scan the new baseline ]` blesses
the current state.

## Saving a report

    [ write this report into ServerStorage ]

writes the whole report into `ServerStorage.ScriptAuditReport` as a
ModuleScript — so it survives closing the window, saves with the place, and
diffs in git through Rojo. It is the **only** thing this plugin ever writes,
and it leaves a ChangeHistory waypoint, so Ctrl+Z undoes it.

## Read the output honestly

The window tells you three things and they are not the same thing:

1. **`N code-loading site(s) across the place.`**
   This is the number that is actually promised. Every site gets a row. On the
   61-script test corpus coverage was 61/61 — nothing was missed.

2. **The severity ranking (`[CRITICAL]`, `[HIGH]`, …)**
   Best effort, and explicitly *not* promised. On the corpus it put 46 of 61
   backdoors at high or critical unaided — 75%. The other 25% are still listed,
   just not ranked loudly. This is a ranked inventory, not a verdict.
   Two earlier versions of this scanner claimed a verdict and both were wrong
   by a factor of ten on code they had not seen before.

3. **`N script(s) COULD NOT BE READ`**
   In orange. This is a hole in the coverage promise, not a clean result.
   Reading `.Source` needs script-injection permission; if Studio refuses,
   those scripts were never looked at. Never read that line as "safe".

And `Nothing found` means nothing was found. It does not mean the place is
clean.

## Rebuilding it

If you change `src/Scanner.lua`, `src/Lexer.lua` or `plugin/Plugin.server.lua`:

    cd C:\DAVID\Factory\roblox\script-scanner
    python tools\build_rbxmx.py

The builder refuses to write a file if any source contains the sequence `]]>`
(it would silently truncate the script inside the XML), and it re-parses what
it just wrote and compares every script back against the source before saying
BUILD OK.

## What has and has not been tested

Verified on 2026-09-01:

* All three scripts compile under the real Luau compiler (`luau-compile`).
* All three round-trip byte-identical out of the `.rbxmx`.
* The corpus still passes: coverage 61/61, false alarms 0/61, flag rate 46/61.
* The Studio import path was simulated and fixed — see below.
* Two rounds of independent adversarial review of the Studio wiring, against
  the official Roblox API docs. **Fifteen bugs found and fixed** — see below.

**Verified in Roblox Studio, 2026-09-02 00:12.** Predicted 5 code-loading
sites, 0 false alarms and 3 of 3 backdoors flagged; Studio reported exactly
that. The prediction was written before the scan ran — see
`tools/predict-style` note below.

## The regression test

`dist/ScriptAuditTestPlace.rbxlx` is a place built from seven corpus scripts —
four ordinary, three backdoors. Open it with **File > Open from File** (it
needs no network and no Roblox account) and click **Scan place**. A correct
run says:

```
5 code-loading site(s) across 7 script(s).
Not scanned (Roblox's own, not part of your place): CoreGui
15 finding(s): 2 critical, 2 high, 1 medium, 10 low
```

Both criticals and both highs must be on `VehicleSpawner`, `HudBoot` and
`Analytics`. If any of `Runtime`, `ProfileWrapper`, `Settings` or `DoorHandler`
reaches high or critical, that is a false alarm and a failure.

Rebuild the place with `python tools\build_test_place.py` — it prints the
expected answer every time it runs.

### The stress test — 2,000 scripts

`python tools\build_stress_place.py 2000` writes
`dist\ScriptAuditStressPlace.rbxlx`: 2,000 real corpus scripts in 50 folders
across 5 services, roughly one in twelve a backdoor.

This one is **not about the findings.** It is the only thing that exercises the
code written to stop Studio freezing: the yield inside the scan loop, the
progress counter, cancel, the 150-row cap, the 40-row diff cap, and the batched
Output print. None of that had ever executed before 2026-09-02.

Predicted, then measured in Studio. Every number matched:

| | predicted | Studio |
|---|---|---|
| code-loading sites | 1405 | **1405 across 2000 scripts** |
| findings | 3165 | **3165** |
| critical / high / medium / low | 164 / 66 / 259 / 2676 | **164 / 66 / 259 / 2676** |
| scan time | — | **1.34s, no freeze** |

Then the same test at **20,000 scripts**, which is where the last two untested
features finally ran:

| | predicted | Studio |
|---|---|---|
| code-loading sites | 14008 | **14008** |
| progress counter | — | **`Scanning... 8300 / 20000 scripts`** |
| cancel | — | **`CANCELLED - the numbers below are partial.`** |
| scan time, before | — | 13.44s |
| scan time, after the fix below | — | **1.93s** |

### The 7x speed-up the 20,000-script run exposed

The scan yielded every 25 scripts. `task.wait()` parks until the next frame, so
20,000 scripts meant **800 frames — about 13 seconds of deliberate waiting for
roughly 1.9 seconds of actual work.** The plugin was spending 90% of its runtime
doing nothing, and the smaller tests could never show it: 2,000 scripts is 80
frames, which just looks like 1.34 seconds.

It now yields on a **clock** (every 0.05s) rather than a count, with a
400-script hard cap so one pathologically slow file cannot stall the window.
Same responsiveness, same cancel latency, and **13.44s became 1.93s** with
byte-identical output.

**Rule: a yield-every-N loop is timed by the frame rate, not by N. Measure the
scan against a size where the frames dominate, or the cost is invisible.**

### Testing the baseline

`python tools\build_test_place.py --tampered` writes
`dist\ScriptAuditTestPlaceTampered.rbxlx`: the same place with **one** extra
backdoor dropped into ReplicatedStorage. Scan the clean place, save the
baseline, open the tampered one, scan again. A correct run says exactly:

```
SINCE THE BASELINE saved <when>: 1 new, 0 changed, 0 gone.
   NEW      ReplicatedStorage.SoundManager
```

and `ReplicatedStorage.SoundManager` appears as CRITICAL in the findings.

Anything else is a regression. The first run of this test reported **6 new and
7 gone** — see below.

### The bug the stress test caught

The findings list was capped at 150 rows from the start. **The diff list was
not.** Scanning the 2,000-script place against a baseline taken from the small
one drew **1,429 NEW rows** before the findings — I scrolled 200 ticks and was
still in them. The report was unreachable.

It is the same failure the 150-row cap exists to prevent; I simply never
applied it to the block I added afterwards. NEW/CHANGED/GONE now cap at 40 each,
say `... and 1389 more NEW - in the Output window`, and yield while drawing.

**Rule: a cap is not a property of one list. It is a property of every list you
draw.**

### One thing to know about the toolbar

**Studio reorders plugin toolbar buttons between sessions.** Across three
restarts the order was `Script Audit | Scan place | Scan selection`, then
`Script Audit | Scan selection | Scan place`, then back. Read the button, do
not count positions.

### The bug the first baseline run caught

The baseline was originally a table keyed by script path:

```lua
plugin:SetSetting(KEY, { ["ServerScriptService.Runtime"] = 12345 })
```

**Studio replaces dots in plugin-setting keys.** Every path came back as
`ServerScriptService_Runtime`, so every real script looked new and every
remembered one looked deleted. Not slightly wrong — inverted, permanently, for
everyone.

Paths now go in the value and never the key: entries are `"<sig>|<path>"`
strings in a plain array, and the only keys are `saved` and `entries`.

Nothing outside Studio could have caught it. There is no `plugin` object under
a plain `lua` binary and no settings store to round-trip through, and the code
compiles and reads correctly either way. **Any value that survives a round trip
through someone else's storage has to be round-tripped in that storage before
it is trusted.**

### The bug this packaging step found

`Scanner.lua` line 36 picks its Lexer import with:

    local Lexer = _G.__ROBLOX and require(script.Parent.Lexer) or require("Lexer")

Nothing anywhere set `_G.__ROBLOX`. Under a plain `lua` binary that is correct —
the flag is nil, so it takes the `package.path` branch the tests use. Inside
Studio there is no `package.path`, so it would have taken the same branch and
**errored on load**. The plugin would have installed and done nothing.

The fix is one line at the top of `Plugin.server.lua`, before Scanner is
required, which keeps `Scanner.lua` byte-identical to the file the corpus
actually scored:

    _G.__ROBLOX = true

Proven both ways in a fake Studio environment: without it, load fails; with it,
`Scanner.analyse` loads and correctly flags `local f = require; f(1234)`.

### What two rounds of adversarial review found

Compiling is not working. An independent reviewer read the Studio wiring twice
against create.roblox.com/docs. Round one, seven bugs:

1. `counts[severity] = ...` crashed on a nil severity — and it was the one code
   path not wrapped in `pcall`. Half the report would vanish with a stack trace.
2. Six of eight text colours were hardcoded dark-theme values. On Studio's
   Light theme the detail line under every finding was washed-out grey and the
   medium-severity rows were invisible yellow-on-white.
3. `AutoButtonColor` modulates the background colour, and the background was
   fully transparent — so clickable rows had no hover at all and the
   click-to-select feature read as "clicking does nothing".
4. There was no way to open the window without launching a full place scan.
   And on a fresh install the intro screen never rendered, so the very first
   thing a new user did was scan the entire DataModel.
5. Drawing the report froze Studio — up to 800 auto-sizing TextButtons in one
   frame — which is exactly the freeze the scan loop yields to avoid.
6. Clicking the *other* scan button while one was running cancelled the running
   scan and started nothing.
7. One unprotected call could leave `scanning = true` forever, making both
   buttons silently inert until Studio restarted.

Round two graded the fixes. Two of them did not actually fix anything:

* The new hover used Studio's `Button` colour at 85% transparency over Studio's
  `MainBackground`. Both are mid-greys. The visible difference was about
  **four values out of 255** — present in the code, invisible on the screen.
  Now uses Studio's real `Item` + `Hover` colour at full opacity.
* The CoreGui fix had become a fourteen-name allowlist of services. That trades
  a cosmetic bug for a correctness one: *"coverage is the promise"* and *"here
  are the fourteen places I look"* cannot both be true. `TextChatService` —
  where modern places keep chat modules — was already missing, and every
  service Roblox ships from now on would have been silently invisible. It is
  now a three-name denylist, and the report prints what it skipped.

Plus six more: a theme change repainting an error screen as the intro,
reopening the window mid-scan leaving it cancelled with no way back, batching
2,850 Output lines into unfilterable 200-line blobs, a refusal message sent to
a panel the user is not looking at, theme fallbacks chaining off the previous
theme's values instead of constants, and a toggle button that never looked
toggled.

**The lesson, again: it compiled cleanly before every one of those fifteen.**
