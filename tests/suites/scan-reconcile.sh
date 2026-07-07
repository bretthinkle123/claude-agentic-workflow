#!/usr/bin/env bash
# scan-reconcile.sh — U-09: reconcile-scans.sh recomputes per-tool counts from the
# hash-named artifacts and gates on the match. Fixtures are the REAL preserved M3
# scanner artifacts, so the formulas are validated against production data.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

HOOK="$HOOKS/reconcile-scans.sh"
FX="$REPO_ROOT/tests/fixtures/m3/run3-pipeline"
echo "-- scan-reconcile (U-09) --"

# A pipeline project with the four real M3 scanner artifacts + stamps for each tool.
mk_scan_proj() {
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  mkdir -p "$w/.pipeline"
  printf '{}' > "$w/.pipeline/state.json"
  cp "$FX/semgrep.json" "$FX/osv.json" "$FX/trivy-config.json" "$FX/checkov.json" "$w/.pipeline/"
  local t
  for t in semgrep osv trivy checkov; do
    jq -nc --arg t "$t" '{tool:$t,ran_at:"t",args:"scan",exit_code:0}' >> "$w/.pipeline/scan-log.jsonl"
  done
  echo "$w"
}
# Build a security-status.json with correct shas + the given counts (defaults = real).
write_status() {  # $1 workdir, $2..$5 semgrep osv trivy checkov counts
  local w="$1" sg="${2:-0}" osv="${3:-1}" tr="${4:-27}" ck="${5:-59}"
  local SG OSV TR CK
  SG=$(sha256sum "$w/.pipeline/semgrep.json"|cut -d' ' -f1)
  OSV=$(sha256sum "$w/.pipeline/osv.json"|cut -d' ' -f1)
  TR=$(sha256sum "$w/.pipeline/trivy-config.json"|cut -d' ' -f1)
  CK=$(sha256sum "$w/.pipeline/checkov.json"|cut -d' ' -f1)
  jq -nc --arg sg "$SG" --arg osv "$OSV" --arg tr "$TR" --arg ck "$CK" \
     --argjson csg "$sg" --argjson cosv "$osv" --argjson ctr "$tr" --argjson cck "$ck" \
    '{status:"clean",semgrep_findings:$csg,osv_findings:$cosv,trivy_findings:$ctr,checkov_findings:$cck,
      scan_artifacts:{semgrep:$sg,osv:$osv,trivy:$tr,checkov:$ck}}' > "$w/.pipeline/security-status.json"
}
run() { ( cd "$1" && bash "$HOOK" ) >/dev/null 2>&1; echo $?; }
reconciled() { jq -r '.scan_reconciled' "$1/.pipeline/security-status.json" 2>/dev/null; }

# All counts correct (the R4-validated formulas: semgrep 0 / osv 1 / trivy 27 / checkov 59).
w="$(mk_scan_proj)"; write_status "$w"
assert_eq 0 "$(run "$w")" "correct counts → exit 0"
assert_eq "true" "$(reconciled "$w")" "correct counts → scan_reconciled=true"

# The exact M3 lie: checkov recorded 58, artifact recomputes to 59.
w="$(mk_scan_proj)"; write_status "$w" 0 1 27 58
assert_eq 2 "$(run "$w")" "M3 checkov 58-vs-59 lie → exit 2 (BLOCK)"
assert_eq "false" "$(reconciled "$w")" "checkov count mismatch → scan_reconciled=false"
assert_eq 1 "$(jq '[.count_mismatches[]|select(.tool=="checkov")]|length' "$w/.pipeline/scan-reconciliation.json")" "the checkov mismatch is recorded"

# Stale/altered artifact: claimed sha doesn't match the file on disk.
w="$(mk_scan_proj)"; write_status "$w"
jq '.scan_artifacts.osv="deadbeefdeadbeef"' "$w/.pipeline/security-status.json" > "$w/t" && mv "$w/t" "$w/.pipeline/security-status.json"
run "$w" >/dev/null
assert_eq "false" "$(reconciled "$w")" "claimed osv sha != artifact → scan_reconciled=false"

# Claimed scan with NO execution stamp (the run-3 'executed but artifact is a prior run's' shape).
w="$(mk_scan_proj)"; write_status "$w"; grep -v '"osv"' "$w/.pipeline/scan-log.jsonl" > "$w/t" && mv "$w/t" "$w/.pipeline/scan-log.jsonl"
run "$w" >/dev/null
assert_eq "false" "$(reconciled "$w")" "claimed osv scan with no stamp → scan_reconciled=false"

# Legacy: no scan-log.jsonl at all → no-op, reconciled true, gate never blocks.
w="$(mk_scan_proj)"; rm "$w/.pipeline/scan-log.jsonl"; write_status "$w"
assert_eq 0 "$(run "$w")" "legacy (no scan-log) → exit 0"
assert_eq "true" "$(jq -r '.reconciled and .legacy' "$w/.pipeline/scan-reconciliation.json")" "legacy no-op recorded"

# Per-attempt report archiving.
w="$(mk_scan_proj)"; write_status "$w"; printf '# report pass 1\n' > "$w/.pipeline/security-report.md"
run "$w" >/dev/null
assert_eq "# report pass 1" "$(cat "$w/.pipeline/archive/security-report.1.md" 2>/dev/null)" "security-report archived per attempt"

# --- Scope reconciliation (previously untested — needs a real git repo + changed files) ---
# The run-3 semgrep fixture's .paths.scanned = src/api/routes/events.py, src/api/schemas/events_list.py,
# src/repositories/events_repo.py. Build a git repo whose UNTRACKED change set is a code file
# and assert the scope check flags a code file NOT in paths.scanned, passes one that IS, and —
# the false-block regression — never flags a non-code shape Semgrep doesn't scan (.toml).
mk_scan_git() {
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w" && git init -q && git config user.email e@x && git config user.name x \
      && printf '.pipeline/\n' > .gitignore && git add .gitignore && git commit -qm base ) >/dev/null 2>&1
  mkdir -p "$w/.pipeline"; printf '{}' > "$w/.pipeline/state.json"
  cp "$FX/semgrep.json" "$FX/osv.json" "$FX/trivy-config.json" "$FX/checkov.json" "$w/.pipeline/"
  local t; for t in semgrep osv trivy checkov; do jq -nc --arg t "$t" '{tool:$t,ran_at:"t",args:"scan",exit_code:0}' >> "$w/.pipeline/scan-log.jsonl"; done
  echo "$w"
}
# (a) changed code file NOT in paths.scanned → scope gap → block.
w="$(mk_scan_git)"; write_status "$w"; mkdir -p "$w/src"; printf 'x=1\n' > "$w/src/unscanned_new.py"
run "$w" >/dev/null
assert_eq "false" "$(reconciled "$w")" "scope: changed .py absent from paths.scanned → scan_reconciled=false"
assert_eq 1 "$(jq '.scope_gaps | length' "$w/.pipeline/scan-reconciliation.json")" "scope: the unscanned file is recorded"
# (b) changed file that IS in paths.scanned → no gap.
w="$(mk_scan_git)"; write_status "$w"; mkdir -p "$w/src/repositories"; printf '# edit\n' > "$w/src/repositories/events_repo.py"
run "$w" >/dev/null
assert_eq "true" "$(reconciled "$w")" "scope: changed file present in paths.scanned → reconciled true"
# (c) THE FALSE-BLOCK REGRESSION: a changed .toml (Semgrep doesn't scan it) must NOT be a scope gap.
w="$(mk_scan_git)"; write_status "$w"; printf '[tool]\nx=1\n' > "$w/pyproject.toml"
run "$w" >/dev/null
assert_eq "true" "$(reconciled "$w")" "scope: changed .toml (non-code shape) does NOT false-block (allowlist, not blocklist)"

finish scan-reconcile
