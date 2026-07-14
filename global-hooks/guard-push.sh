#!/bin/bash
# guard-push.sh — structural block against a NON-deployment subagent publishing to the
# git remote. Only the deployment stage is allowed to push / open / merge a PR, and only
# after deployment-gate.sh passes; every other Bash-carrying agent (implementation,
# security, testing, debugging, documentation, plan-audit) has no legitimate reason to
# touch the remote. This hook is wired as an ADDITIONAL PreToolUse Bash hook on those six
# agents (NOT on deployment) and blocks (exit 2) any command that pushes code or writes a
# PR — so a prompt injection landing in one of them cannot ship code past the human
# diff-review checkpoint without a prompt. It fails CLOSED and never asks, so an
# autonomous run is unaffected: legitimate work continues, an injected push just dies.
#
# Why a hook, not the allow-list: `git push` stays allow-listed so the deployment agent
# pushes autonomously (an `ask` rule would stall an unattended run at the final step).
# A PreToolUse hook returning exit 2 overrides the allow-list for the agents it is wired
# onto — so deployment (no guard-push) pushes freely, the other six are hard-blocked.
# Agent IDENTITY is established by WHICH agents carry the hook (same design as
# guard-approval-markers.sh), so the hook never has to detect the caller at runtime.
#
# What is blocked (at a command position — start of string or after ; | & ( so the token
# can't be prose inside an argument):
#   - `git push` as the git SUBCOMMAND (any flags/args) — the subcommand anchor means a
#     commit message that merely CONTAINS the word push, e.g.
#     `git commit -m "add push notifications"`, is NOT mistaken for a push.
#   - `gh pr` WRITE subcommands: create, merge, comment, edit, ready, close, reopen,
#     review (reads — view/list/checks/status/diff — pass through).
#   - `gh api` with a mutating HTTP method (-X/--method POST|PUT|PATCH|DELETE), which could
#     open a PR / push a ref / merge via the REST API (default-GET `gh api` reads pass).
#
# Residual (documented in docs/pipeline-threat-model.md, same class as the marker guard):
# a push wrapped inside a script the agent first writes then runs (`bash scratch.sh`), or
# otherwise obfuscated (ref built from a variable / $() / base64), can slip past this
# string scan; and the option-laden `git -C <dir> push` form is not matched. This raises
# the bar from "just run git push" to "defeat the guard AND the deploy gate AND forge the
# human diff-approved marker" — a branch push is at worst a rogue branch that still cannot
# merge (branch protection + the diff-approved anchor).
set -uo pipefail

# Read the PreToolUse event and pull the Bash command. Fail TOWARD inspection: if the
# field can't be parsed (no jq / unexpected shape) scan the whole raw payload instead,
# so a malformed event can't smuggle a push through unread. Blocking a weird payload is
# safe — these agents never legitimately push.
PAYLOAD="$(cat)"
CMD=""
PARSED=false
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  [ -n "$CMD" ] && PARSED=true
fi
[ -z "$CMD" ] && CMD="$PAYLOAD"

# Command-position anchor. On the PARSED command it is strict: start of string, or after a
# real command separator/opener — ; & | ( { or a backtick — so a verb inside a quoted
# argument (e.g. `git commit -m "add push"`) is NOT mistaken for a command, while a subshell
# `(git push)`, brace group `{ git push; }`, or backtick substitution is still caught. In the
# FALLBACK (jq couldn't extract the command, so we scan the raw payload) it is EMPTY = match
# anywhere: fail toward inspection, since a malformed event has no legitimate command to
# false-positive against. (Newline-separated commands are handled by grep's per-line `^`.)
if [ "$PARSED" = true ]; then ANCHOR='(^|[;&|({`])[[:space:]]*'; else ANCHOR=""; fi

# 1. git push as the subcommand. `git` + zero-or-more DASH-option tokens (each starts with -)
#    + `push` as a whole word. `commit`/`log`/etc. are not dash-option tokens, so a
#    push-in-a-commit-message never matches. The trailing `[^[:alnum:]_]|$` (a non-word char
#    or end) accepts `push`, `push)`, `push;`, `push |…` etc. without matching `pushx`.
if printf '%s' "$CMD" | grep -qE "${ANCHOR}git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*push([^[:alnum:]_]|$)"; then
  echo "Blocked: a non-deployment agent may not push to the remote. Only the deployment stage pushes, after the human diff-review checkpoint (deployment-gate.sh). If code needs to ship, finish your stage and let the pipeline reach deployment — do not run 'git push' yourself. This is the guard-push structural block." >&2
  exit 2
fi

# 2. gh pr WRITE subcommands (create/merge/comment/edit/ready/close/reopen/review).
if printf '%s' "$CMD" | grep -qE "${ANCHOR}gh[[:space:]]+pr[[:space:]]+(create|merge|comment|edit|ready|close|reopen|review)\b"; then
  echo "Blocked: a non-deployment agent may not open, merge, or write to a pull request. The deployment stage opens the PR after the human diff-review checkpoint. This is the guard-push structural block." >&2
  exit 2
fi

# 3. gh api with a mutating HTTP method — could open a PR / push a ref / merge via REST.
if printf '%s' "$CMD" | grep -qE "${ANCHOR}gh[[:space:]]+api\b[^;|&]*(-X[[:space:]]*(POST|PUT|PATCH|DELETE)|--method[=[:space:]]*(POST|PUT|PATCH|DELETE))"; then
  echo "Blocked: a non-deployment agent may not issue a mutating GitHub API call (a write method can push a ref, open, or merge a PR). Read-only 'gh api' (default GET) is fine. This is the guard-push structural block." >&2
  exit 2
fi

exit 0
