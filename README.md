# Script Audit

**Lists every place a Roblox codebase can load code at runtime — and tells you
when a change adds one that was not there before.**

Two front ends, one engine:

| | |
|---|---|
| **Studio plugin** | `dist/ScriptAudit.rbxmx` — drop it in your Plugins folder |
| **CLI / GitHub Action** | `cli/scriptaudit.lua` — fails a pull request that adds a new site |

The CLI needs no Roblox account, no Studio and no network. It is plain Lua.

---

## The idea

A one-off list of code-loading sites in a real place is close to useless.
Framework code loads modules dynamically — Knit, ProfileService, a folder loop —
so a long list is the **normal, healthy state** of any codebase.

What deserves an alarm is a site that **was not there yesterday**. So the tool
records a baseline you bless, and every run after that leads with what changed.
In CI that is a question a machine can answer definitively on a pull request
from someone you do not know.

---

## Quick start

**In Studio**

```powershell
Copy-Item dist\ScriptAudit.rbxmx "$env:LOCALAPPDATA\Roblox\Plugins\" -Force
```

Restart Studio. Three buttons appear under **Plugins**. See `dist/INSTALL.md`.

**In CI**

```sh
lua5.4 cli/scriptaudit.lua bless src   # once; commit .scriptaudit-baseline
lua5.4 cli/scriptaudit.lua check src   # on every PR
```

See `cli/README.md`, or copy `.github/workflows/script-audit.yml`.

---

## What it promises, and what it does not

**Coverage is the promise.** Every point where code can be loaded gets a row.
On the 61-script corpus — the author's, plus two independent adversaries' —
coverage is **61/61** and false alarms are **0/61**.

**Then it was tested again, blind.** A red-team adversary that had never seen
`Scanner.lua`, `Lexer.lua` or any corpus file wrote 23 new backdoors and 16 new
decoys against only the promise above. It aimed at cross-function dataflow,
loaders pulled out of `select`/`coroutine`/`pcall`/`next`/`table.unpack`, keys
built by XOR-decode and by carving `"require"` out of `"requirements.txt"`, and
`__index` / `BindableFunction` indirection.

**Coverage 23/23. False alarms 0/16.** For scale: the same test measured v1 at
**0.31** recall and v2 at **0.053**. Those 39 scripts are now
`corpus/holdout3-*` and gated in CI.

**The ranking is not a promise.** It gets it right unaided **46 times out of
61** on the original corpus, and **11 of 23** on the harder blind set. The rest
are still listed, just not ranked loudly.

That distinction is the entire design, and it was learned expensively. Two
earlier versions claimed a verdict and scored 1.000/1.000 against corpora their
own author wrote. Independent adversaries then measured them at **0.31** and
**0.053** recall on code they had not seen.

`require(id)` in a framework loader and `require(id)` in a backdoor **are the
same source text**. The difference is the value of the id, and the value is not
in the file. So this is an inventory with a ranking and a diff on top — not a
verdict, and it says so on screen.

---

## Tests

```sh
lua5.4 tests/run_corpus.lua            # coverage 61/61, false alarms 0/61
lua5.4 tests/run_holdout3.lua          # blind adversary: 23/23, 0/16
bash   cli/tests/run_cli_tests.sh      # 17 cases, exit codes included
python tools/build_test_place.py       # a Studio place with a known answer
python tools/build_stress_place.py 20000
```

The Studio plugin has been run against places of **8, 2,000 and 20,000
scripts**. In every case the answer was predicted before the scan and matched
exactly. Three real bugs came out of those runs that no amount of code review
had caught — see `dist/INSTALL.md`.

---

## Repository layout

```
src/Lexer.lua       a real Luau tokenizer, not a regex
src/Scanner.lua     the analysis. Runs under plain lua5.4
plugin/             Studio wiring only
cli/                the command line tool and its tests
tools/              build the .rbxmx and the test places
corpus/             61 scripts: author + two adversaries, plus a blind third
tests/              the two numbers this scanner is allowed to claim
```

## A note on the corpus

`corpus/holdout-malicious/` contains short backdoor patterns used as the test
set. They are the well-known shapes already documented publicly on the Roblox
DevForum, they use a placeholder asset id, and they exist so the detector can be
measured against something its author did not write. A detector with no
adversarial test set is how the first two versions of this scored 1.000 and were
wrong by a factor of ten.

## Licence

MIT — see `LICENSE`.
