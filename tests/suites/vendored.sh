#!/usr/bin/env bash
# vendored.sh — B-0 (TA track): the vendoring-provenance guard.
# Enforces that global-skills/VENDORED.md is the single source of truth for anything
# third-party, and that no third-party code sneaks into global-skills/ without a row +
# pin. Structural checks only — no network, no clone.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

echo "-- vendored (B-0 provenance ledger) --"

# Resolve the repo-of-record root (this suite lives at <root>/tests/suites/).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/global-skills/VENDORED.md"
GS="$ROOT/global-skills"

# 1. The manifest exists and declares both sections.
assert_exit 0 "VENDORED.md exists"                    test -f "$MANIFEST"
if [ -f "$MANIFEST" ]; then
  body="$(cat "$MANIFEST")"
  assert_match "$body" 'Vendored tools \(B-series\)'  "manifest has a Vendored-tools section"
  assert_match "$body" 'Content imports'              "manifest has a Content-imports section"
  assert_match "$body" 'License rule'                 "manifest states the license rule"
else
  body=""
fi

# 2. Hand-authored (first-party) skill dirs that must NOT be treated as vendored.
#    Anything else appearing under global-skills/ is presumed third-party and MUST have a
#    manifest row naming its dir. This is the "no vendoring without a row" invariant.
is_firstparty() {
  case "$1" in
    api-edge-conventions|auth-patterns|ci-conventions|code-standards|\
containerization-conventions|dast-conventions|data-protection-conventions|ddia-patterns|\
debugging-escalation-protocol|delivery-conventions|dependency-audit-policy|\
deployment-checklist-and-rollback|diff-scoping-conventions|doc-conventions|\
iac-conventions|logging-conventions|observability-conventions|pipeline-orchestration|\
secrets-management|stride-threat-model-template|triage-conventions) return 0 ;;
    *) return 1 ;;
  esac
}

# Walk global-skills/ top-level dirs; any non-first-party dir needs a row naming it.
if [ -d "$GS" ]; then
  unrowed=0
  for d in "$GS"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    is_firstparty "$name" && continue
    # Third-party present on disk → the manifest must reference its dir path.
    if ! printf '%s' "$body" | grep -qF "global-skills/$name/"; then
      unrowed=1
      echo "    UNROWED third-party dir: global-skills/$name/ (add a VENDORED.md row)" >&2
    fi
    # A vendored dir must not carry a self-updating npm lifecycle or a nested repo.
    assert_exit 1 "global-skills/$name has no nested .git"        test -d "${d}.git"
    if [ -f "${d}package.json" ]; then
      assert_exit 1 "global-skills/$name package.json has no lifecycle hooks" \
        grep -qE '"(postinstall|preinstall|prepare)"' "${d}package.json"
    fi
  done
  assert_eq 0 "$unrowed" "every third-party global-skills dir has a manifest row"
fi

# 3. A HOLD/RE-SOURCE item must NOT already be vendored on disk (its block is real).
#    design-extract (BACKLOG) must have no dir yet. (skill-creator cleared + vendored 2026-07-07.)
for held in design-extract; do
  assert_exit 1 "held item '$held' is not vendored on disk yet" test -d "$GS/$held"
done

# 4. Every PINNED tool row that names a concrete vendored dir path also carries a
#    non-empty pin token (SHA-ish or version). Guards against a row with a dir but a
#    placeholder pin. (Checks the two frontend acquisitions' rows specifically.)
if [ -n "$body" ]; then
  for tool in impeccable frontend-design; do
    row="$(printf '%s\n' "$body" | grep -E "^\| $tool ")"
    assert_match "$row" '[0-9a-f]{12}' "$tool row carries a 12-hex pin"
  done
fi

finish "vendored"
