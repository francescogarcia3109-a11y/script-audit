#!/usr/bin/env bash
# Tests for the CLI, not for the Scanner. The Scanner has the 61-script corpus;
# this file exists because the corpus cannot tell you whether `check` returns 1
# instead of 0 when a backdoor lands, and that exit code IS the product.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LUA="${LUA:-lua5.4}"
CLI="$ROOT/cli/scriptaudit.lua"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

t() { # t <name> <expected-exit> <command...>
  local name="$1" want="$2"; shift 2
  "$@" >"$TMP/out" 2>&1; local got=$?
  if [ "$got" = "$want" ]; then
    printf "ok    %-46s exit %s\n" "$name" "$got"; pass=$((pass+1))
  else
    printf "FAIL  %-46s exit %s, wanted %s\n" "$name" "$got" "$want"; sed 's/^/        /' "$TMP/out"; fail=$((fail+1))
  fi
}
grep_out() { # grep_out <name> <pattern>
  if grep -q "$2" "$TMP/out"; then printf "ok    %-46s\n" "$1"; pass=$((pass+1));
  else printf "FAIL  %-46s (no match: %s)\n" "$1" "$2"; sed 's/^/        /' "$TMP/out"; fail=$((fail+1)); fi
}

P="$TMP/proj"; mkdir -p "$P/src/server" "$P/src/shared"
cp "$ROOT/corpus/holdout-clean/01_knit_packages.lua"  "$P/src/server/Runtime.server.lua"
cp "$ROOT/corpus/holdout-clean/06_profileservice.lua" "$P/src/server/Profiles.lua"
cp "$ROOT/corpus/clean/09_datastore.lua"              "$P/src/shared/DataStore.lua"
cp "$ROOT/corpus/clean/10_ui.lua"                     "$P/src/shared/Ui.lua"

t  "scan an ordinary project"            0 $LUA "$CLI" scan  "$P"
t  "check before any baseline exists"    2 $LUA "$CLI" check "$P"
t  "bless writes a baseline"             0 $LUA "$CLI" bless "$P"
[ -f "$P/.scriptaudit-baseline" ] && { printf "ok    %-46s\n" "baseline file exists"; pass=$((pass+1)); } \
                                   || { printf "FAIL  %-46s\n" "baseline file exists"; fail=$((fail+1)); }
t  "check with nothing changed"          0 $LUA "$CLI" check "$P"
grep_out "says 'No change'" "No change since the baseline"

cp "$ROOT/corpus/holdout-malicious/25_realistic_backdoor.lua" "$P/src/server/Spawner.lua"
t  "a NEW backdoored file fails the check" 1 $LUA "$CLI" check "$P"
grep_out "names it as NEW"  "NEW .*Spawner.lua"
grep_out "shows the severity" "CRITICAL"

rm "$P/src/server/Spawner.lua"
cat "$ROOT/corpus/holdout-malicious/10_getfenv_stringindex.lua" >> "$P/src/shared/Ui.lua"
t  "an EXISTING file gaining one fails"  1 $LUA "$CLI" check "$P"
grep_out "names it as CHANGED" "CHANGED .*Ui.lua"

$LUA "$CLI" bless "$P" >/dev/null
t  "re-blessing clears the failure"      0 $LUA "$CLI" check "$P"

# Deleting a file must NOT fail the build - losing a code-loading site is not
# a security regression, and a check that cries wolf gets switched off.
rm "$P/src/shared/DataStore.lua"
t  "deleting a file does not fail"       0 $LUA "$CLI" check "$P"
grep_out "reports it as gone" "gone since the baseline"

t  "a nonexistent directory is exit 2"   2 $LUA "$CLI" scan "$TMP/no-such-dir"

# The scanner used to try `find` and then fall back to a Windows `dir ... 2>nul`.
# On Linux "nul" is a filename, not a null device, so any scan that found no
# files silently created a stray file called `nul` in the working directory -
# litter that lands in a commit. Platform is now detected, not guessed.
EMPTY="$TMP/emptyproj"; mkdir -p "$EMPTY"
GUARD="$TMP/nulguard"; mkdir -p "$GUARD"
( cd "$GUARD" && $LUA "$CLI" scan "$EMPTY" >/dev/null 2>&1 )
if [ -e "$GUARD/nul" ]; then
  printf "FAIL  %-46s (stray 'nul' file created)\n" "scanning an empty dir leaves no litter"; fail=$((fail+1))
else
  printf "ok    %-46s\n" "scanning an empty dir leaves no litter"; pass=$((pass+1))
fi
t  "no arguments is exit 2"              2 $LUA "$CLI"

# Determinism: the same tree must bless to the same bytes, or the baseline
# churns in git and everyone stops reading the diff.
$LUA "$CLI" bless "$P" -o "$TMP/b1" >/dev/null
$LUA "$CLI" bless "$P" -o "$TMP/b2" >/dev/null
if cmp -s "$TMP/b1" "$TMP/b2"; then printf "ok    %-46s\n" "bless is deterministic"; pass=$((pass+1));
else printf "FAIL  %-46s\n" "bless is deterministic"; fail=$((fail+1)); fi

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
