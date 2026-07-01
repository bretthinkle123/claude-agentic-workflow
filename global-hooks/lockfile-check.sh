#!/usr/bin/env bash
# Deterministic supply-chain integrity check (M6). Inspects the working-tree change
# set (tracked diff + untracked files vs HEAD — the same set the rest of the pipeline
# scopes to) for two problems:
#   1. a dependency MANIFEST changed but its LOCKFILE did not (deps left unlocked /
#      unresolved — the classic "it works on my machine" + supply-chain drift risk)
#   2. UNPINNED version specifiers entering a changed manifest (floating deps)
#   3. a LOCKFILE changed with no manifest change (a re-lock — usually fine, but worth
#      a glance in case a dependency was injected)
#
# Run by the security agent as part of its scan; its findings fold into
# security-report.md / security-status.json, so a hard violation rides the EXISTING
# security gate — no new gate hook. Zero-LLM, deterministic.
#
# Exit: 0 = clean · 1 = warnings only (unpinned dep / bare re-lock) · 2 = BLOCK
#       (a manifest changed without its lockfile).
set -uo pipefail

# Pipeline-project guard: no-op outside a bootstrapped pipeline project.
[ -f .pipeline/state.json ] || exit 0

# Change set = tracked diff + untracked files vs HEAD (see diff-scoping-conventions).
CHANGED="$( { git diff HEAD --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u )"
[ -n "$CHANGED" ] || { echo "[lockfile-check] clean — empty change set."; exit 0; }

changed_has() { printf '%s\n' "$CHANGED" | grep -qiE "(^|/)$1$"; }

block=0; warn=0
say() { echo "[lockfile-check] $1"; }

# A manifest is "new" if it isn't tracked at HEAD (a brand-new dependency file).
manifest_is_new() { ! git ls-files --error-unmatch "$1" >/dev/null 2>&1; }
# npm dependency maps only (sorted) — so a scripts/name/version-only edit doesn't
# look like a dependency change.
npm_dep_maps() { jq -cS '{d:(.dependencies//{}),e:(.devDependencies//{}),p:(.peerDependencies//{}),o:(.optionalDependencies//{})}' 2>/dev/null; }

npm_lock_in_set() { changed_has 'package-lock\.json' || changed_has 'npm-shrinkwrap\.json' || changed_has 'yarn\.lock' || changed_has 'pnpm-lock\.yaml'; }

# --- Rule 1: DEPENDENCIES changed without a lockfile update (BLOCK) ---
# Precise for npm (compare dep maps): block only when deps actually changed and no
# lockfile is in the change set — a scripts/metadata-only manifest edit is NOT blocked
# (a gate that fires on non-dependency edits just trains people to bypass it).
while IFS= read -r pj; do
  [ -n "$pj" ] && [ -f "$pj" ] || continue
  npm_lock_in_set && continue
  if manifest_is_new "$pj"; then
    say "BLOCK: new $pj declares dependencies with no lockfile (package-lock.json / yarn.lock / pnpm-lock.yaml) in the change set — commit the lockfile."; block=1
  elif command -v jq >/dev/null 2>&1 \
       && [ "$(git show "HEAD:$pj" 2>/dev/null | npm_dep_maps)" != "$(npm_dep_maps < "$pj")" ]; then
    say "BLOCK: $pj dependencies changed but no lockfile update in the change set — dependencies are unlocked. Commit the updated lockfile."; block=1
  fi
done <<< "$(printf '%s\n' "$CHANGED" | grep -iE '(^|/)package\.json$')"

# python (pyproject): TOML dependency parsing isn't available in bash, so we can't
# tell a dependency change from a metadata edit. Block only a NEW manifest; otherwise
# WARN (never hard-block a possibly-metadata-only pyproject edit).
while IFS= read -r pp; do
  [ -n "$pp" ] && [ -f "$pp" ] || continue
  { changed_has 'poetry\.lock' || changed_has 'Pipfile\.lock'; } && continue
  if manifest_is_new "$pp"; then
    say "BLOCK: new $pp declares dependencies with no poetry.lock / Pipfile.lock in the change set — commit the lockfile."; block=1
  else
    say "WARN: $pp changed with no poetry.lock / Pipfile.lock update — if you changed dependencies, commit the updated lockfile."; warn=1
  fi
done <<< "$(printf '%s\n' "$CHANGED" | grep -iE '(^|/)pyproject\.toml$')"

# --- Rule 3: a lockfile changed with no manifest change (WARN) ---
if { changed_has 'package-lock\.json' || changed_has 'yarn\.lock' || changed_has 'pnpm-lock\.yaml'; } && ! changed_has 'package\.json'; then
  say "WARN: an npm lockfile changed with no package.json change — confirm this is an intentional re-lock, not an injected dependency."; warn=1
fi
if { changed_has 'poetry\.lock' || changed_has 'Pipfile\.lock'; } && ! changed_has 'pyproject\.toml'; then
  say "WARN: a Python lockfile changed with no pyproject.toml change — confirm this is an intentional re-lock."; warn=1
fi

# --- Rule 2: unpinned specifiers in a changed manifest (WARN) ---
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  unpinned="$(grep -vE '^\s*(#|-r|--|$)' "$f" | grep -E '[A-Za-z0-9]' | grep -vE '==' || true)"
  [ -n "$unpinned" ] && { say "WARN: $f has unpinned requirements (no '=='): $(printf '%s' "$unpinned" | tr '\n' ' ')"; warn=1; }
done <<< "$(printf '%s\n' "$CHANGED" | grep -iE '(^|/)requirements[^/]*\.txt$')"

if command -v jq >/dev/null 2>&1; then
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    floating="$(jq -r '[(.dependencies // {}),(.devDependencies // {})] | add // {} | to_entries[] | select(.value|type=="string" and test("[\\^~*]|latest")) | "\(.key)@\(.value)"' "$f" 2>/dev/null || true)"
    [ -n "$floating" ] && { say "WARN: $f has floating version specifiers (pin these for reproducible installs): $(printf '%s' "$floating" | tr '\n' ' ')"; warn=1; }
  done <<< "$(printf '%s\n' "$CHANGED" | grep -iE '(^|/)package\.json$')"
fi

if [ "$block" -eq 1 ]; then exit 2; fi
if [ "$warn" -eq 1 ]; then exit 1; fi
say "clean — no supply-chain integrity issues in the change set."
exit 0
