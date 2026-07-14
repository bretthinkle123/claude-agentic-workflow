#!/usr/bin/env bash
# push-guard.sh — proves guard-push.sh blocks a NON-deployment subagent from publishing
# to the git remote (git push / gh pr write / gh api write), while passing every
# legitimate non-deployment git command (add, commit, status, diff, log, branch, and a
# commit MESSAGE that merely contains the word "push"). Also asserts the hook is wired on
# exactly the six non-deployment Bash agents and NOT on deployment (which must still push).
#
# Feeds a PreToolUse-shaped event on stdin and asserts the hook's exit code:
#   exit 2 = blocked (a push / PR write), exit 0 = allowed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

HOOK="$HOOKS/guard-push.sh"
echo "-- push-guard --"

# feed <command-string> — pipe a realistic PreToolUse Bash event into the hook.
feed() {
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | bash "$HOOK"
}
# feed_raw <payload> — exercise the fail-toward-inspection fallback (no .tool_input.command).
feed_raw() { printf '%s' "$1" | bash "$HOOK"; }

assert_exit 0 "hook parses (bash -n)" bash -n "$HOOK"

# --- BLOCK: pushes / PR writes, across shapes -------------------------------------
assert_exit 2 "block: bare git push"                 feed "git push"
assert_exit 2 "block: git push -u origin HEAD"       feed "git push -u origin HEAD"
assert_exit 2 "block: git push origin main"          feed "git push origin main"
assert_exit 2 "block: git push --force"              feed "git push --force"
assert_exit 2 "block: git --no-pager push"           feed "git --no-pager push"
assert_exit 2 "block: commit then push (;)"          feed "git commit -m x; git push"
assert_exit 2 "block: commit then push (&&)"         feed "git add -A && git commit -m x && git push -u origin HEAD"
assert_exit 2 "block: subshell (git push)"           feed "(git push)"
assert_exit 2 "block: brace group { git push; }"     feed "{ git push; }"
assert_exit 2 "block: backtick subst"                feed 'echo `git push`'
assert_exit 2 "block: push then pipe"                feed "git push origin main | tee log"
assert_exit 2 "block: push then && chain"            feed "git push && echo done"
assert_exit 2 "block: multi-space / tab"             feed "git    push"
assert_exit 2 "block: gh pr create"                  feed "gh pr create --title t --body-file .pipeline/pr-description.md"
assert_exit 2 "block: gh pr merge"                   feed "gh pr merge 12 --squash"
assert_exit 2 "block: gh pr comment"                 feed "gh pr comment 12 --body hi"
assert_exit 2 "block: gh api -X POST"                feed "gh api -X POST repos/o/r/git/refs -f ref=x"
assert_exit 2 "block: gh api --method PATCH"         feed "gh api --method PATCH repos/o/r/pulls/1"

# --- ALLOW: legitimate non-deployment git usage -----------------------------------
assert_exit 0 "allow: git add + commit"              feed "git add -A && git commit -m 'x'"
assert_exit 0 "allow: git status"                    feed "git status --porcelain"
assert_exit 0 "allow: git diff HEAD"                 feed "git diff HEAD --name-only"
assert_exit 0 "allow: git log"                       feed "git log --oneline -5"
assert_exit 0 "allow: git rev-parse"                 feed "git rev-parse --abbrev-ref HEAD"
assert_exit 0 "allow: git branch"                    feed "git branch --show-current"
assert_exit 0 "allow: git checkout -b"               feed "git checkout -b pipeline/foo"
# The subcommand anchor: "push" as PROSE in a commit message must NOT be mistaken for a push.
assert_exit 0 "allow: commit msg contains 'push'"    feed "git commit -m 'add push notifications'"
assert_exit 0 "allow: commit msg 'fix git push retry'" feed "git commit -m 'fix git push retry logic'"
assert_exit 0 "allow: grep for 'git push' (read)"    feed "grep -rn 'git push' global-hooks/"
assert_exit 0 "allow: gh pr view (read)"             feed "gh pr view 12"
assert_exit 0 "allow: gh pr checks (read)"           feed "gh pr checks 12"
assert_exit 0 "allow: gh api default GET (read)"     feed "gh api repos/o/r/commits"
assert_exit 0 "allow: gh run list (read)"            feed "gh run list"

# --- Fallback: field absent ⇒ scan raw payload, still catch a push ----------------
assert_exit 2 "fallback: push in raw payload"        feed_raw '{"weird":"git push -u origin HEAD"}'
assert_exit 0 "fallback: benign raw payload"         feed_raw '{"weird":"git commit -m x"}'

# --- Wiring: on exactly the six NON-deployment Bash agents, and NOT on deployment.
# (static.sh checks the hook FILE resolves; this checks it is WIRED on the right set —
# catches a dropped wiring that would leave an agent's push vector unguarded, and catches
# it accidentally landing on deployment, which must still push.)
# Anchor to the `command:` wiring line so a PROSE mention (e.g. deployment.md explaining
# the guard) is not miscounted as a wiring.
WIRED="$(grep -lE 'command:.*guard-push\.sh' "$REPO_ROOT"/global-agents/*.md | wc -l | tr -d ' ')"
assert_eq 6 "$WIRED" "guard-push.sh wired on the 6 non-deployment Bash agents"
assert_exit 1 "guard-push.sh NOT wired on deployment (it must still push)" \
  grep -qE 'command:.*guard-push\.sh' "$REPO_ROOT/global-agents/deployment.md"

finish push-guard
