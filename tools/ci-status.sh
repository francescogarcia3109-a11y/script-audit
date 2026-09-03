#!/bin/sh
# Print the CI result for this repo without a browser, a token, or JavaScript.
#
# The Publish CI status workflow writes the answer to an orphan branch named
# ci-status, so plain git - which needs no auth to read a public repo - can
# fetch it. This is the reader.
#
#   sh tools/ci-status.sh            # this repo's origin
#   sh tools/ci-status.sh <git-url>  # any repo using the same workflow
#
# Exit codes:  0 green   1 red   2 anything else (see the message, which says
#                                which "anything else" it was - a check that
#                                cannot tell you why it failed is not a check)
set -eu

REMOTE="${1:-origin}"

# Distinguish the failure modes. Reporting "no ci-status branch" when the real
# problem is "you are not in a git repo" sends you looking in the wrong place.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "not inside a git repository - cd to the repo first, or pass a git URL"
  echo "  usage: sh tools/ci-status.sh [remote-or-url]"
  exit 2
fi

if ! out=$(git fetch -q "$REMOTE" ci-status 2>&1); then
  case "$out" in
    *"couldn't find remote ref"*|*"couldn't find remote ref ci-status"*)
      echo "no ci-status branch on '$REMOTE' yet."
      echo "It appears after the first push that runs the Publish CI status workflow." ;;
    *"does not appear to be a git repository"*|*"not found"*|*"Repository not found"*)
      echo "cannot reach '$REMOTE' - is the name or URL right?" ;;
    *)
      echo "git fetch failed against '$REMOTE'." ;;
  esac
  [ -n "$out" ] && echo "  git said: $out"
  exit 2
fi

status=$(git show FETCH_HEAD:status.txt 2>/dev/null) || {
  echo "the ci-status branch exists but has no status.txt on it"; exit 2; }

echo "$status"
echo

verdict=$(printf '%s\n' "$status" | sed -n 's/^OVERALL: *//p' | head -1)
case "$verdict" in
  SUCCESS) exit 0 ;;
  FAILURE) exit 1 ;;
  "")      echo "status.txt has no OVERALL: line"; exit 2 ;;
  *)       exit 2 ;;
esac
