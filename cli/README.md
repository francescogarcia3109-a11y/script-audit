# scriptaudit — the Script Audit engine, outside Roblox Studio

Lists every place a Roblox codebase can load code at runtime, and fails a build
when a change adds one that was not there before.

No Roblox account. No Studio. No network. It reads `.lua` / `.luau` files off
disk with the same `Scanner.lua` the Studio plugin uses.

## Why the diff, and not the list

A one-off list of code-loading sites in a real place is close to useless.
Framework code loads modules dynamically — Knit, ProfileService, a folder loop —
so a long list is the normal, healthy state of any codebase. Reading it teaches
you nothing.

**What deserves an alarm is a site that was not there yesterday.** That is a
question a machine can answer definitively, and it is exactly the question you
want asked on a pull request from someone you do not know.

## Use

```sh
lua5.4 cli/scriptaudit.lua scan   src        # list every site
lua5.4 cli/scriptaudit.lua bless  src        # record the current state
lua5.4 cli/scriptaudit.lua check  src        # fail if anything is new
```

`bless` writes `.scriptaudit-baseline`. **Commit it.** From then on the diff on
that one file, in the pull request, *is* the security review — one line per
file, human readable, and it only moves when the way that file loads code moves.

## Exit codes

| | |
|---|---|
| `0` | nothing new |
| `1` | new or changed code-loading sites since the baseline |
| `2` | the tool could not run — bad path, unreadable file, no baseline |

`2` is deliberately not `1`. *"The check failed"* and *"the check could not
run"* are different facts, and a CI job that treats them the same will one day
go green because the scanner crashed.

Deleting a file **does not** fail the build. Losing a code-loading site is not a
security regression, and a check that cries wolf gets switched off.

## In CI

```yaml
- uses: actions/checkout@v4
- run: sudo apt-get install -y lua5.4
- run: lua5.4 cli/scriptaudit.lua check src
```

Or use the composite action in `action.yml`.

## What it promises, and what it does not

**Coverage is the promise.** Every point where code can be loaded gets a row.
On the 61-script corpus — written by the author plus two independent
adversaries — coverage is **61/61** and false alarms are **0/61**.

**The severity ranking is not a promise.** It gets it right unaided **46 times
out of 61**. The other 15 are still listed, just not ranked loudly.

That distinction is the whole design, and it was learned the hard way: two
earlier versions of this scanner claimed a verdict, scored 1.000/1.000 against
corpora their own author wrote, and were then measured at **0.31** and **0.053**
recall by independent adversaries on code they had not seen. `require(id)` in a
framework loader and `require(id)` in a backdoor **are the same source text**.
The difference is the value of the id, and the value is not in the file.

So this is an inventory with a ranking, and a diff on top of it. Not a verdict.

## Tests

```sh
lua5.4 tests/run_corpus.lua        # coverage 61/61, false alarms 0/61
bash   cli/tests/run_cli_tests.sh  # 17 cases, exit codes included
```

The corpus tests the answers. The CLI tests test the exit codes — because the
corpus cannot tell you whether `check` returns `1` instead of `0` when a
backdoor lands, and that exit code is the entire product.
