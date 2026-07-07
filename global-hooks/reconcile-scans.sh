#!/usr/bin/env bash
# reconcile-scans.sh — U-09: the deterministic teeth behind the security scan counts.
#
# The M3 series folded raw scanner JSON into per-tool counts (semgrep_findings,
# osv_findings, …) with NO independent recount anywhere, and claimed executions whose
# artifacts were a prior run's or gone. This hook — wired as a security Stop hook —
# recomputes each per-tool count from the hash-named artifact the agent says it counted,
# and blocks (exit 2, feeding the model) on any mismatch, so the agent must correct its
# numbers before it can stop. It is the P0-1 "stop trusting a summary integer" pattern
# applied to the security stage.
#
# The agent records, in security-status.json:
#   "scan_artifacts": { "semgrep": "<sha256>", "osv": "<sha256>",
#                       "trivy": "<sha256>", "checkov": "<sha256>" }
# naming the .pipeline/<tool>.json file each pre-fix count was computed from. For each
# named tool this hook: (1) verifies the artifact exists at .pipeline/<tool>.json and its
# sha256 matches the claim; (2) verifies a scan-log.jsonl stamp for that tool exists
# (the execution breadcrumb); (3) RECOMPUTES the count with the R4-validated formula and
# compares it to the recorded per-tool count. Results go to
# .pipeline/scan-reconciliation.json (detail) AND `security-status.json.scan_reconciled`
# (the boolean the deploy gate + loop-exit predicate read — folded into the SAME file
# the loop-exit security predicate already reads, so loop-exit ≡ gate stays intact,
# exactly parallel to .asvs.reconciled).
#
# NON-GATING by design: stamp FRESHNESS (a carried-forward artifact is legal), and the
# exploitable/hygiene triage of findings (LLM judgment — P0-3/U-23 evals are the control).
# Gitleaks is excluded from count reconciliation (its in-scope filtering is triage).
#
# Backward compatible: no scan-log.jsonl (a pre-U-09 project / no wrappers) ⇒ legacy
# no-op — writes {reconciled:true, legacy:true}, sets no scan_reconciled=false, exit 0.
set -uo pipefail

[ -f .pipeline/state.json ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

SS=".pipeline/security-status.json"
SCANLOG=".pipeline/scan-log.jsonl"
OUT=".pipeline/scan-reconciliation.json"

# --- per-attempt report archiving (U-09) — closes the overwritten-report defect -------
# security-report.md is overwritten every pass; M3's pass-1/2 reports are unrecoverable.
# Snapshot the current one to .pipeline/archive/ keyed by this security attempt number
# (its line count in run-log.jsonl + 1, the same counting log-run.sh uses).
if [ -f .pipeline/security-report.md ]; then
  mkdir -p .pipeline/archive
  _attempt=1
  if [ -f .pipeline/run-log.jsonl ]; then
    _prior="$(jq -rs 'map(select(.stage=="security")) | length' .pipeline/run-log.jsonl 2>/dev/null || echo 0)"
    [ -n "$_prior" ] && _attempt=$((_prior + 1))
  fi
  cp .pipeline/security-report.md ".pipeline/archive/security-report.${_attempt}.md" 2>/dev/null || true
fi

# --- legacy no-op: no stamps ⇒ nothing to reconcile -----------------------------------
if [ ! -f "$SCANLOG" ]; then
  jq -nc '{reconciled:true, legacy:true, ran_at:(now|todateiso8601)}' > "$OUT" 2>/dev/null || echo '{"reconciled":true,"legacy":true}' > "$OUT"
  exit 0
fi

[ -f "$SS" ] || { jq -nc '{reconciled:true, note:"no security-status.json"}' > "$OUT"; exit 0; }

# Conventional artifact path per tool.
artifact_path() {
  case "$1" in
    semgrep) echo ".pipeline/semgrep.json" ;;
    osv)     echo ".pipeline/osv.json" ;;
    trivy)   echo ".pipeline/trivy-config.json" ;;
    checkov) echo ".pipeline/checkov.json" ;;
    *)       echo "" ;;
  esac
}

# R4-validated recount formula per tool (calibrated against the real M3 artifacts).
recount() {  # $1 tool, $2 path → integer count, or "" if unreadable
  local tool="$1" p="$2"
  [ -f "$p" ] || { echo ""; return; }
  case "$tool" in
    semgrep) jq -r '(.results // []) | length' "$p" 2>/dev/null ;;
    osv)     jq -r '[.results[]?.packages[]?.vulnerabilities[]?.id] | unique | length' "$p" 2>/dev/null ;;
    trivy)   jq -r '[.Results[]? | (.Misconfigurations // [])[]] | length' "$p" 2>/dev/null ;;
    # checkov.json is a TOP-LEVEL ARRAY (one entry per framework); .summary.failed on the
    # root errors — must sum across entries. =59 on the M3 artifact (the agent recorded 58,
    # reproducible by no formula: THIS is the counting convention, first post-fix run recounts).
    checkov) jq -r '[.[].summary.failed] | add // 0' "$p" 2>/dev/null ;;
    *)       echo "" ;;
  esac
}

# Recorded per-tool count field in security-status.json.
recorded_count() { jq -r "(.${1}_findings // null)" "$SS" 2>/dev/null; }

MISMATCHES='[]'
for tool in semgrep osv trivy checkov; do
  claimed_sha="$(jq -r "(.scan_artifacts.${tool} // empty)" "$SS" 2>/dev/null)"
  [ -n "$claimed_sha" ] || continue                     # tool not claimed this pass → skip (carried forward / n/a)
  p="$(artifact_path "$tool")"
  reason=""
  if [ ! -f "$p" ]; then
    reason="artifact $p named in scan_artifacts.$tool is missing"
  else
    actual_sha="$(sha256sum "$p" 2>/dev/null | cut -d' ' -f1)"
    if [ "$actual_sha" != "$claimed_sha" ]; then
      reason="artifact $p sha $actual_sha != claimed $claimed_sha"
    elif ! jq -e "select(.tool==\"$tool\")" "$SCANLOG" >/dev/null 2>&1; then
      reason="no scan-log.jsonl execution stamp for $tool (claimed executed but not stamped)"
    else
      rc="$(recount "$tool" "$p")"
      rec="$(recorded_count "$tool")"
      if [ -z "$rc" ]; then
        reason="could not recompute $tool count from $p (unreadable/format change)"
      elif [ "$rec" != "null" ] && [ "$rec" != "$rc" ]; then
        reason="recorded ${tool}_findings=$rec but $p recomputes to $rc"
      fi
    fi
  fi
  [ -n "$reason" ] && MISMATCHES="$(printf '%s' "$MISMATCHES" | jq -c --arg t "$tool" --arg r "$reason" '. + [{tool:$t, reason:$r}]')"
done

# Scope reconciliation: every code-shaped changed file should appear in a this-run semgrep
# stamp's paths.scanned when available. If semgrep.json carries `.paths.scanned`, check it;
# absent that field, skip (older semgrep output / not a full-tree scan) rather than false-block.
SCOPE_GAPS='[]'
SEMGREP_P="$(artifact_path semgrep)"
if [ -f "$SEMGREP_P" ] && jq -e '.paths.scanned' "$SEMGREP_P" >/dev/null 2>&1; then
  # Only consider changed files with a CODE shape Semgrep is EXPECTED to scan — a positive
  # ALLOWLIST, not a blocklist. An exclusion blocklist would false-block on any unusual
  # extension Semgrep legitimately doesn't scan (a .toml/.cfg/.ini, a dependency-only
  # pyproject bump): it lands in "changed but not scanned" → a spurious scope gap →
  # scan_reconciled=false → a WRONGLY blocked clean deploy. Allowlisting the shapes Semgrep
  # covers (py/js/ts/go/java/rb/php/tf/yaml/json/dockerfile/bash — matching its own language
  # set) means an unknown extension is simply not checked here, never a false gap.
  CODE_INCLUDE='\.(py|js|jsx|ts|tsx|go|java|rb|php|tf|ya?ml|sh|bash)$|(^|/)Dockerfile$'
  DIFF_REF="HEAD"; git rev-parse --verify -q HEAD >/dev/null 2>&1 || DIFF_REF=""
  { [ -n "$DIFF_REF" ] && git diff "$DIFF_REF" --name-only 2>/dev/null; \
    git ls-files --others --exclude-standard 2>/dev/null; } \
    | grep -vE '(^|/)\.pipeline/' | grep -E "$CODE_INCLUDE" | sort -u > "/tmp/.u09_changed.$$" 2>/dev/null || true
  jq -r '.paths.scanned[]?' "$SEMGREP_P" 2>/dev/null | sed 's#^\./##' | sort -u > "/tmp/.u09_scanned.$$" 2>/dev/null || true
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -qxF "$f" "/tmp/.u09_scanned.$$" 2>/dev/null || \
      SCOPE_GAPS="$(printf '%s' "$SCOPE_GAPS" | jq -c --arg f "$f" '. + [$f]')"
  done < "/tmp/.u09_changed.$$"
  rm -f "/tmp/.u09_changed.$$" "/tmp/.u09_scanned.$$" 2>/dev/null || true
fi

RECONCILED=true
[ "$(printf '%s' "$MISMATCHES" | jq 'length')" -gt 0 ] && RECONCILED=false
[ "$(printf '%s' "$SCOPE_GAPS" | jq 'length')" -gt 0 ] && RECONCILED=false

jq -nc --argjson mm "$MISMATCHES" --argjson sg "$SCOPE_GAPS" --argjson rec "$RECONCILED" \
  --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{reconciled:$rec, count_mismatches:$mm, scope_gaps:$sg, ran_at:$t}' > "$OUT"

# Fold the boolean into security-status.json for the gate + loop-exit predicate (same file
# the loop-exit security predicate reads → loop-exit ≡ gate preserved, parallel to asvs).
tmp="$(mktemp)"; jq --argjson r "$RECONCILED" '.scan_reconciled = $r' "$SS" > "$tmp" 2>/dev/null && mv "$tmp" "$SS" || rm -f "$tmp"

if [ "$RECONCILED" = "false" ]; then
  echo "Blocked: security scan counts do not reconcile with the hash-named artifacts (U-09). A per-tool count must match a recomputation of the .pipeline/<tool>.json it was taken from, and every claimed scan must be stamped in scan-log.jsonl. See $OUT:" >&2
  printf '%s' "$MISMATCHES" | jq -r '.[]? | "  count: \(.tool): \(.reason)"' >&2
  printf '%s' "$SCOPE_GAPS" | jq -r '.[]? | "  scope: \(.) not in semgrep paths.scanned"' >&2
  exit 2
fi
exit 0
