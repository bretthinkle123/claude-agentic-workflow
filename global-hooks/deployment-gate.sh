#!/bin/bash
# Blocks deployment unless interlock files show a clean, CURRENT, documented state.
#
# Installed globally at ~/.claude/hooks/ and wired as the deployment agent's Bash
# PreToolUse gate. Deliberately has NO ".pipeline/state.json" no-op guard (unlike
# the ambient Stop hooks): if it ever fires outside a bootstrapped pipeline project
# the interlock files below are absent, so every check fails CLOSED (blocks) —
# exactly the safe behavior. Resolve sibling hooks relative to THIS script (not the
# CWD) so the global install location still finds compute-change-hash.sh.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_RESULTS=".pipeline/test-results.json"
SECURITY_STATUS=".pipeline/security-status.json"
PR_DESCRIPTION=".pipeline/pr-description.md"
DIFF_APPROVED=".pipeline/diff-approved"

# Fail closed if jq is unavailable — every status check below depends on it.
# (Without this a missing jq still blocks, but with a misleading "tests not
# passing" reason; this makes the block reason accurate.)
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq not found on PATH — cannot verify gate status. Install jq and restart the session." >&2
  exit 2
fi

if [ ! -f "$TEST_RESULTS" ] || [ "$(jq -r '.status' "$TEST_RESULTS")" != "pass" ]; then
  echo "Blocked: tests are not passing. See $TEST_RESULTS." >&2
  exit 2
fi

# M4″-A4 backstop: status "pass" with failed > 0 is legal ONLY when every failing test
# is enumerated in failures[] AND matched by name in pre_existing_failures[] (each entry
# carrying out-of-diff + reproduces-at-base evidence, per the testing agent contract).
# The M4″ run shipped "pass" with 1 failure disclosed in prose — the gate consumed the
# bare status and could not tell disclosed from undisclosed. Now it can.
PEF_REASON=$(jq -r '
  (.failed // 0) as $f
  | if $f == 0 then "ok"
    else
      ((.failures // []) | map(.name)) as $names
      | ((.pre_existing_failures // []) | map(.name)) as $pef
      | if ($names | length) != $f then
          "failed=\($f) but failures[] enumerates \($names | length) — every failure must be named"
        else
          ($names | map(select(. as $n | ($pef | index($n)) | not))) as $undisclosed
          | if ($undisclosed | length) == 0 then "ok"
            else "failing test(s) with no matching pre_existing_failures[] entry: \($undisclosed | join(", "))"
            end
        end
    end' "$TEST_RESULTS" 2>/dev/null)
if [ "$PEF_REASON" != "ok" ]; then
  echo "Blocked: test status is \"pass\" with unaccounted failures (M4″-A4). $PEF_REASON — a failure is only ignorable when pre_existing_failures[] records its out-of-diff + reproduces-at-base evidence; otherwise status must be \"fail\". See $TEST_RESULTS." >&2
  exit 2
fi

# Acceptance-criteria coverage must be COMPLETE and its arithmetic HONEST (PR C + U-01).
# In the M3 run the recorded summary said covered:24/24 while the same file's by_id
# marked AC20 covered:false — the gate compared two trusted integers and passed. Now,
# when `by_id` is present, the summary is RECOMPUTED from it: every entry must be
# covered or delegated to "security" (the ONLY valid delegate — its clean/asvs checks
# are already conjuncts of this gate; any other delegate value blocks until that stage
# has its own gate-conjunct-backed status file), the recorded `covered` must equal the
# covered==true count (delegation never inflates the numerator), and `total` must equal
# the by_id length. A legacy result file without by_id keeps the original integer
# compare. This is the SAME condition the orchestrator's run-to-condition loop exits on
# (pipeline-orchestration SKILL.md, asserted by tests/suites/loop-exit-invariant.sh),
# so loop-exit ≡ deploy gate and the two cannot drift. An absent/empty criteria_covered
# (a feature with no acceptance criteria, or a pre-PR-C result file) means total 0 ==
# covered 0 → complete — never blocks a legitimately criteria-less change.
CRIT_REASON=$(jq -r '
  (.criteria_covered // {}) as $c
  | if ($c.by_id // null) == null
    then if (($c.covered // 0) >= ($c.total // 0)) then "ok"
         else "not fully covered (\($c.covered // 0)/\($c.total // 0))" end
    else ($c.by_id | map(select(.covered == true)) | length) as $ct
       | if (($c.by_id | map(select((.delegated // null) != null and .delegated != "security")) | length) > 0)
         then "invalid delegate value (only \"security\" is gate-backed): \([$c.by_id[] | select((.delegated // null) != null and .delegated != "security") | .id] | join(", "))"
         elif (($c.by_id | map(select(.covered == true or .delegated == "security")) | length) != ($c.by_id | length))
         then "unaccounted criteria (neither covered nor delegated): \([$c.by_id[] | select(.covered != true and .delegated != "security") | .id] | join(", "))"
         elif (($c.covered // -1) != $ct)
         then "recorded covered=\($c.covered) but by_id counts \($ct) covered==true entries — the summary integer must equal the recomputation"
         elif (($c.total // -1) != ($c.by_id | length))
         then "recorded total=\($c.total) but by_id has \($c.by_id | length) entries"
         else "ok" end
    end' "$TEST_RESULTS" 2>/dev/null)
if [ "$CRIT_REASON" != "ok" ]; then
  echo "Blocked: acceptance-criteria arithmetic — ${CRIT_REASON:-unreadable criteria_covered}. See $TEST_RESULTS .criteria_covered." >&2
  exit 2
fi

# Acceptance-frontmatter anchors (U-01, DEPLOY-ONLY — like waiver authenticity, NOT in
# the loop-exit predicate). The denominator and the right to delegate are PLANNING-owned
# and human-reviewed at the plan checkpoint: testing must neither shrink the total nor
# invent a delegation. acceptance.md absent, or present without a `criteria_total:` line
# (a legacy format) ⇒ the total anchor self-skips; a delegated entry with no matching id
# in `delegated_criteria:` ALWAYS blocks (fail closed — self-delegation is the vector).
ACCEPTANCE=".pipeline/acceptance.md"
if [ -f "$ACCEPTANCE" ]; then
  ACC_TOTAL=$(grep -m1 -E '^criteria_total:' "$ACCEPTANCE" | sed -E 's/^criteria_total:[[:space:]]*//' | tr -cd '0-9')
  TR_TOTAL=$(jq -r '(.criteria_covered.total // 0)' "$TEST_RESULTS")
  if [ -n "$ACC_TOTAL" ] && [ "$TR_TOTAL" -ne "$ACC_TOTAL" ] 2>/dev/null; then
    echo "Blocked: test-results records criteria_covered.total=$TR_TOTAL but acceptance.md frontmatter declares criteria_total: $ACC_TOTAL — the denominator is planning-owned and must match." >&2
    exit 2
  fi
  DELEG_IDS=$(jq -r '[.criteria_covered.by_id[]? | select(.delegated == "security") | .id] | join(" ")' "$TEST_RESULTS" 2>/dev/null)
  if [ -n "$DELEG_IDS" ]; then
    ACC_DELEG=$(grep -m1 -E '^delegated_criteria:' "$ACCEPTANCE" | sed -E 's/^delegated_criteria:[[:space:]]*//')
    for _id in $DELEG_IDS; do
      if ! printf '%s' "$ACC_DELEG" | grep -qw "$_id"; then
        echo "Blocked: $TEST_RESULTS delegates criterion $_id to security, but acceptance.md frontmatter declares no matching id in delegated_criteria (${ACC_DELEG:-<absent>}). Delegation is declared by PLANNING and human-reviewed — a testing agent cannot self-delegate." >&2
        exit 2
      fi
    done
  fi
fi

# Criterion-completeness (PR G / F1). Counting criteria_covered trusts the testing
# agent's per-criterion covered:true; this adds a deterministic backstop for the one
# structured "measurable dimension" the schema carries — a declared perf budget must
# actually be MEASURED. If perf mode ran (status != n/a) and a non-null budget field
# (p95_ms / throughput_rps) has a null measured counterpart, the load/latency half of
# the criterion was never exercised — block, so a partial verification can't score the
# AC complete. Budget fields derive from the acceptance criterion's wording, so the
# honest fix is to measure it or mark the criterion uncovered (which then fails the
# criteria_covered check above). This same predicate is mirrored in the orchestrator's
# loop-exit (pipeline-orchestration skill), so loop-exit ≡ gate and the two never drift.
# A declared perf budget must be MEASURED (p95/throughput non-null) AND the measured
# run must DISCLOSE its scenario (audit WS3-3). In the trial the headline perf number
# was a best case (webhook disabled, uncontended, amount:1) reported without that
# context — a true number measured under an unrepresentative scenario overstates. A
# non-null `.perf.scenario` (the harness records what it actually exercised) is now
# required when perf ran, so the metric can't silently be a best case. Mirrored in the
# orchestrator loop-exit (SKILL) + loop-exit-predicate.jq — loop-exit ≡ gate.
PERF_GAP=$(jq -r '
  if (.perf.status // "n/a") == "n/a" then "ok"
  elif (.perf.budget.p95_ms != null and .perf.measured.p95_ms == null) then "p95_ms"
  elif (.perf.budget.throughput_rps != null and .perf.measured.throughput_rps == null) then "throughput_rps"
  elif (.perf.scenario == null) then "scenario"
  else "ok" end' "$TEST_RESULTS")
if [ "$PERF_GAP" = "scenario" ]; then
  echo "Blocked: perf ran but $TEST_RESULTS .perf.scenario is null — the measured scenario is undisclosed (a best-case number reported as the headline overstates). Record .perf.scenario (what the harness actually exercised: concurrency, workload, webhook on/off, contention)." >&2
  exit 2
elif [ "$PERF_GAP" != "ok" ]; then
  echo "Blocked: perf criterion under-covered — budget declares $PERF_GAP but measured is null. Measure it or mark the criterion uncovered. See $TEST_RESULTS .perf." >&2
  exit 2
fi

if [ ! -f "$SECURITY_STATUS" ] || [ "$(jq -r '.status' "$SECURITY_STATUS")" != "clean" ]; then
  echo "Blocked: security status is not clean. See .pipeline/security-report.md." >&2
  exit 2
fi

# Waiver authenticity (Option B — waivers are human-owned). A waiver excuses an otherwise-blocking
# finding (a High/Critical CVE, or an unmet ASVS L1/L2 code/config requirement). Waivers are recorded
# ONLY by a human via record-waiver.sh (TTY-only) into .pipeline/waivers.json; the security agent may
# READ and honor them but cannot create them (guard-approval-markers.sh + a settings deny block agent
# writes). This refuses to trust any waiver the agent CLAIMED in security-status.json unless a human
# recorded it here — closing the "agent self-writes a waiver to go green" vector. It runs BEFORE the
# CVE floor so a fabricated osv_waiver cannot lift it. Deploy-only (like the WS3-1 mutation-scope
# honesty check); NOT in the loop-exit predicate. Absent waivers.json ⇒ empty ⇒ any claim blocks.
WAIVERS_FILE=".pipeline/waivers.json"
HUMAN_OSV=$(jq -c '[.osv[]?.id]'  "$WAIVERS_FILE" 2>/dev/null); [ -n "$HUMAN_OSV" ]  || HUMAN_OSV='[]'
HUMAN_ASVS=$(jq -c '[.asvs[]?.id]' "$WAIVERS_FILE" 2>/dev/null); [ -n "$HUMAN_ASVS" ] || HUMAN_ASVS='[]'

OSV_CLAIM=$(jq -r '(.osv_waiver.id // empty)' "$SECURITY_STATUS" 2>/dev/null)
if [ -n "$OSV_CLAIM" ] && ! printf '%s' "$HUMAN_OSV" | jq -e --arg id "$OSV_CLAIM" 'index($id) != null' >/dev/null 2>&1; then
  echo "Blocked: security-status.json claims osv_waiver id='$OSV_CLAIM' but no matching human waiver is recorded in $WAIVERS_FILE. Waivers are recorded only by a human (record-waiver.sh); a subagent cannot self-waive. Record it after accepting the risk, or patch the dependency." >&2
  exit 2
fi

CLAIMED_ASVS=$(jq -c '([.asvs.waivers[]?] | map(if type=="object" then .id else . end))' "$SECURITY_STATUS" 2>/dev/null); [ -n "$CLAIMED_ASVS" ] || CLAIMED_ASVS='[]'
FAB_ASVS=$(jq -cn --argjson c "$CLAIMED_ASVS" --argjson h "$HUMAN_ASVS" '$c - $h' 2>/dev/null); [ -n "$FAB_ASVS" ] || FAB_ASVS='[]'
if [ "$(printf '%s' "$FAB_ASVS" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ]; then
  echo "Blocked: security-status.json claims ASVS waiver(s) $FAB_ASVS with no matching human record in $WAIVERS_FILE. Waivers are recorded only by a human (record-waiver.sh); a subagent cannot self-waive. Record them after accepting the risk, or meet the requirement." >&2
  exit 2
fi

# CVE-severity floor (audit B6). `status:"clean"` is the security agent's judgment; this
# is a DETERMINISTIC backstop so a High/Critical OSV finding (CVSS >= 7.0) cannot ship as
# clean without an explicit, recorded `.osv_waiver`. A CVSS 7.5 High shipped green in the
# audited run precisely because nothing independently checked severity. `.osv_max_cvss`
# is the max CVSS across remaining (unfixed) OSV findings, written by the security agent;
# absent ⇒ 0 ⇒ no block. This same predicate is mirrored in the orchestrator's loop-exit
# security check (pipeline-orchestration SKILL.md) so loop-exit ≡ gate and the two never
# drift (asserted by tests/suites/loop-exit-invariant.sh).
CVE_BLOCK=$(jq -r 'if ((.osv_max_cvss // 0) >= 7) and ((.osv_waiver // null) == null) then "block" else "ok" end' "$SECURITY_STATUS")
if [ "$CVE_BLOCK" = "block" ]; then
  echo "Blocked: an OSV finding at CVSS >= 7.0 (High/Critical) remains and no .osv_waiver is recorded in $SECURITY_STATUS. Patch the dependency, or record an explicit waiver {id, reason, approved_by} after a human accepts the risk. See .pipeline/security-report.md." >&2
  exit 2
fi

# Input-surface reconciliation floor (input-controls plan). The security agent reconciles the
# IMPLEMENTED input surface (routes/consumers that accept untrusted input) against the declared
# controls, and lists any source it could NOT reconcile to a validation contract + rate-limit
# policy/waiver in `.input_surface.uncontrolled`. A non-empty list means an input source shipped
# without an accounted-for input control — block. Absent field ⇒ [] ⇒ no block (backward
# compatible / features with no input surface). Mirrored in the loop-exit security predicate
# (SKILL + loop-exit-invariant.sh) so loop-exit == gate.
SURFACE_UNCONTROLLED=$(jq -r '((.input_surface.uncontrolled // []) | length)' "$SECURITY_STATUS" 2>/dev/null || echo 0)
if [ "${SURFACE_UNCONTROLLED:-0}" -gt 0 ]; then
  UNLIST=$(jq -rc '(.input_surface.uncontrolled // [])' "$SECURITY_STATUS" 2>/dev/null)
  echo "Blocked: $SURFACE_UNCONTROLLED input source(s) shipped without an accounted-for validation contract + rate-limit policy/waiver (uncontrolled: $UNLIST). Add the missing control (or a recorded waiver) and re-scan. See $SECURITY_STATUS .input_surface and .pipeline/surface-delta.md." >&2
  exit 2
fi

# Data-surface reconciliation floor (data-protection plan, DP). The security agent reconciles the
# IMPLEMENTED storage surface (stored fields carrying user data) against the declared classification,
# and lists any SENSITIVE field it could NOT reconcile to a named at-rest mechanism (KDF / KMS
# field-encryption / SSE) or a recorded waiver in `.data_surface.unprotected`. A non-empty list means
# a sensitive field shipped without its declared protection — block, regardless of exploitability
# (this is what converts the old non-exploitable warning into a block). Absent field ⇒ [] ⇒ no block
# (backward compatible / features that store no user data). Mirrored in the loop-exit security
# predicate (SKILL + loop-exit-invariant.sh) so loop-exit == gate.
DATA_UNPROTECTED=$(jq -r '((.data_surface.unprotected // []) | length)' "$SECURITY_STATUS" 2>/dev/null || echo 0)
if [ "${DATA_UNPROTECTED:-0}" -gt 0 ]; then
  DLIST=$(jq -rc '(.data_surface.unprotected // [])' "$SECURITY_STATUS" 2>/dev/null)
  echo "Blocked: $DATA_UNPROTECTED sensitive stored field(s) shipped without a declared at-rest mechanism or recorded waiver (unprotected: $DLIST). Add the field-level control through the crypto facade (KDF / KMS field-encryption / SSE) or record a data_protection_waiver, then re-scan. See $SECURITY_STATUS .data_surface and .pipeline/surface-delta.md." >&2
  exit 2
fi

# ASVS 5.0.0 reconciliation floor (ASVS enforcement). The security agent (step 6g) verifies
# ASVS 5.0.0 L1/L2 (universal) + in-scope L3 and sets `.asvs.reconciled=false` when an unmet,
# unwaived code/config requirement remains. Such an item is ALSO a critical (→ status not clean,
# blocked above), so this is the deterministic backstop: a security-status that claims
# `status:"clean"` while `.asvs.reconciled` is false cannot slip through. Uses `== "false"` (not
# `// true`) because jq's `//` treats false like null; absent field ⇒ not "false" ⇒ no block
# (backward compatible / features with no ASVS surface). Mirrored in the loop-exit security
# predicate (SKILL + loop-exit-invariant.sh) so loop-exit == gate.
ASVS_RECONCILED=$(jq -r '(.asvs.reconciled)' "$SECURITY_STATUS" 2>/dev/null || echo null)
if [ "$ASVS_RECONCILED" = "false" ]; then
  echo "Blocked: $SECURITY_STATUS .asvs.reconciled is false — an unmet ASVS 5.0.0 L1/L2 (or in-scope L3) code/config requirement remains (see .asvs.l1_l2_missing / .asvs.l3_in_scope_missing and .pipeline/security-report.md). Meet it, or record a human-approved waiver." >&2
  exit 2
fi

# Scan-count reconciliation floor (U-09). reconcile-scans.sh (a security Stop hook) recomputes
# each per-tool finding count from the hash-named .pipeline/<tool>.json artifact and sets
# `.scan_reconciled=false` when a recorded count doesn't match its artifact, an artifact is
# missing/altered, a claimed scan has no execution stamp, or a code-shaped changed file wasn't
# in semgrep's scanned paths. The M3 series recorded per-tool counts with no independent recount
# (a checkov 58 that reproduces to 59; execution claims whose artifacts were a prior run's) — this
# is the deterministic backstop, same shape as the ASVS floor. Same `== "false"` semantics: absent
# field ⇒ not "false" ⇒ no block (pre-U-09 project / no scanner wrappers). Mirrored in the loop-exit
# security predicate (SKILL + loop-exit-invariant.sh) so loop-exit == gate. Stamp FRESHNESS and
# finding TRIAGE stay non-gating by design.
SCAN_RECONCILED=$(jq -r '(.scan_reconciled)' "$SECURITY_STATUS" 2>/dev/null || echo null)
if [ "$SCAN_RECONCILED" = "false" ]; then
  echo "Blocked: $SECURITY_STATUS .scan_reconciled is false — a per-tool scan count does not match a recomputation of the hash-named artifact it was taken from (or a claimed scan is unstamped / a changed file went unscanned). See .pipeline/scan-reconciliation.json and re-scan." >&2
  exit 2
fi

# ASVS Tier-1 SAST floor (ASVS-DET). asvs-sast.sh (a Stop hook on the security agent, agent-independent)
# writes .pipeline/asvs-sast.json with a deterministic count of high-precision ASVS violations (JWT
# alg:none 9.1.2, password fast-hash 11.4.2, non-CSPRNG 11.5.1, insecure cipher 11.3.1). This is the
# gate-side backstop: even if the agent doesn't fold a Tier-1 finding into critical_count, an unfixed
# one blocks here. Deploy-only (NOT in the loop-exit predicate); absent file ⇒ 0 ⇒ no-op (a project
# whose stack the scan doesn't cover, or a pre-scan run).
ASVS_SAST=".pipeline/asvs-sast.json"
SAST_CRIT=$(jq -r '(.critical // 0)' "$ASVS_SAST" 2>/dev/null || echo 0)
if [ "${SAST_CRIT:-0}" -gt 0 ] 2>/dev/null; then
  echo "Blocked: $ASVS_SAST reports $SAST_CRIT unfixed ASVS Tier-1 finding(s) (JWT alg:none / fast-hash password / non-CSPRNG / insecure cipher). Fix them (see .findings[]) — these are deterministic critical violations, not waivable." >&2
  exit 2
fi

# App-store compliance floor (store-compliance plan, Layer C). store-compliance.sh (a Stop hook on
# the security agent, agent-independent) writes .pipeline/store-compliance.json with a deterministic
# count of known auto-rejection causes for a declared Apple/Google Play target (absent privacy
# manifest, a capability API without its usage string, targetSdk below Google's floor, a debuggable
# release, …). Same posture as the ASVS-DET floor: deploy-only, NOT in the loop-exit predicate;
# absent file ⇒ 0 ⇒ no-op (a non-mobile project, or a run before the scan). Designs out the
# rejection cause pre-upload; it is NOT a guarantee of store acceptance (human review remains).
STORE_COMPLIANCE=".pipeline/store-compliance.json"
STORE_CRIT=$(jq -r '(.critical // 0)' "$STORE_COMPLIANCE" 2>/dev/null || echo 0)
if [ "${STORE_CRIT:-0}" -gt 0 ] 2>/dev/null; then
  echo "Blocked: $STORE_COMPLIANCE reports $STORE_CRIT app-store compliance critical(s) (see .findings[]) — a known automated rejection cause for the declared store target (privacy manifest / usage strings / targetSdk floor / debuggable release). Fix it before submission." >&2
  exit 2
fi

# Reverted / do-not-commit source markers (audit E3). A reverted money-path fix once
# passed build-green and nearly shipped; this makes the signal deterministic. The guard
# no-ops on a clean change set and self-skips outside a pipeline project.
# Invoked via `bash` explicitly (not the +x bit): the repo is authored on Windows
# (core.fileMode=false), where a lost executable bit is invisible locally but breaks a
# fresh Linux checkout with "Permission denied" — which this gate would report as a
# BLOCK on a perfectly green state (found by eval.yml's first CI run).
if ! bash "$HOOK_DIR/guard-source-markers.sh"; then
  exit 2   # guard already printed the offending lines to stderr
fi

if [ ! -f "$PR_DESCRIPTION" ]; then
  echo "Blocked: documentation has not produced $PR_DESCRIPTION." >&2
  exit 2
fi

# Mutation scope-pairing (audit WS3-1) — a DEPLOY-ONLY honesty check, deliberately NOT in
# the loop-exit predicate. Mutation quality is settled-ADVISORY (a low kill score never
# blocks) and folding it into the per-cycle loop would re-introduce the exact per-loop
# mutation cost that drives the cap-out problem. But a FALSE completeness claim must not
# ship: in the trial `quality_ok:true` was written while the mutation scope had silently
# shrunk from the configured set (stryker.conf `mutate`) to one file — so the security-
# critical guard shipped mutation-UNMEASURED under a green quality flag. This blocks only
# that lie: quality_ok=true asserted while `mutation.scope` fails to cover
# `mutation.configured_scope`, with no recorded `quality_waiver`. An honest quality_ok=false
# still ships (advisory); running the full scope or recording a waiver clears the block.
# test-quality.json is optional (projects with no mutation tool omit it) → absent ⇒ no-op.
TEST_QUALITY=".pipeline/test-quality.json"
if [ -f "$TEST_QUALITY" ]; then
  QUAL_BLOCK=$(jq -r '
    if (.quality_ok == true)
       and (((.mutation.configured_scope // []) - (.mutation.scope // [])) | length > 0)
       and ((.quality_waiver // null) == null)
    then "block" else "ok" end' "$TEST_QUALITY" 2>/dev/null || echo "ok")
  if [ "$QUAL_BLOCK" = "block" ]; then
    MISSING=$(jq -rc '((.mutation.configured_scope // []) - (.mutation.scope // []))' "$TEST_QUALITY" 2>/dev/null)
    echo "Blocked: $TEST_QUALITY claims quality_ok=true but mutation.scope does not cover the configured mutation scope (uncovered: $MISSING). Either run mutation over the full configured scope, set quality_ok=false (honest advisory), or record a quality_waiver {id, reason, approved_by} after a human accepts the gap." >&2
    exit 2
  fi
fi

# Human diff-review checkpoint (M5) + currency, anchored to the HUMAN's approval (F3).
# While ANY change is uncommitted, a human must have approved the diff
# (`.pipeline/diff-approved`, written only by approve-diff.sh, which refuses without a
# TTY), AND every changed path must match its approved state — per-path when the marker
# carries approved_paths (F1), aggregate-hash otherwise (legacy). Once everything
# approved is committed at its approved bytes, remaining approved-but-uncommitted paths
# (out-of-scope dirt the human saw at approval) no longer block push/pr commands.
#
# The anchor is the human-owned diff-approved hash, NOT documentation's review-manifest:
# that removes the F3 vector — the deployment agent can regenerate review-manifest (it's
# in its Bash allow-list), but the gate no longer reads it, and any tree change the agent
# makes shifts the change-set hash away from approved_change_hash → blocked → re-review.
# approve-diff.sh is human-only (TTY) and the deployment agent is instructed never to
# write diff-approved itself; the gate can't verify who wrote the file. That fabrication
# vector is now structurally guarded (PR K): guard-approval-markers.sh (a PreToolUse Bash
# hook on every Bash agent) blocks commands that write the marker, and a settings
# Write/Edit deny covers the tool vector. The residual — obfuscated Bash past the string
# scan — is documented in docs/pipeline-threat-model.md; this gate still doesn't verify
# authorship, it relies on those two guards + the currency hash below.
if [ -n "$(git status --porcelain)" ]; then
  if [ ! -f "$DIFF_APPROVED" ]; then
    echo "Blocked: no human diff approval. Review the diff + the security/test/quality reports, then run approve-diff.sh (the M5 diff-review checkpoint)." >&2
    exit 2
  fi
  if jq -e '.approved_paths | type == "object"' "$DIFF_APPROVED" >/dev/null 2>&1; then
    # PER-PATH currency (F1, events-force-rls run). The aggregate-hash compare treated
    # ANY tree divergence as post-approval drift: staging alone changed the hash
    # (untracked content moves into `git diff HEAD`), and a diff-scoped commit that
    # correctly left two out-of-scope files dirty blocked every follow-up command.
    # Instead: every path in the CURRENT change set must be an approved path at its
    # approved bytes, and every STAGED blob likewise (the index holding different bytes
    # than a matching worktree is the staged-tamper vector — commit ships the index).
    # Teeth preserved: a NEW path, or ANY byte drift from the approved state, blocks
    # exactly as before. What no longer blocks: approved paths already committed at
    # their approved bytes (they leave the change set), approved paths still dirty at
    # their approved bytes, and staging/committing any subset of the approved set.
    VIOLATION=""
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      REC=$(jq -r --arg p "$p" '.approved_paths[$p] // empty' "$DIFF_APPROVED")
      if [ -z "$REC" ]; then VIOLATION="path not in the human-approved set: $p"; break; fi
      if [ -f "$p" ]; then CUR=$(sha256sum "$p" | cut -d' ' -f1); else CUR="__deleted__"; fi
      if [ "$CUR" != "$REC" ]; then VIOLATION="bytes differ from the approved state: $p"; break; fi
    done <<CHANGESET
$( { git diff HEAD --name-only 2>/dev/null; git ls-files --others --exclude-standard; } | LC_ALL=C sort -u )
CHANGESET
    if [ -z "$VIOLATION" ]; then
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        REC=$(jq -r --arg p "$p" '.approved_paths[$p] // empty' "$DIFF_APPROVED")
        if [ -z "$REC" ]; then VIOLATION="staged path not in the human-approved set: $p"; break; fi
        if git cat-file -e ":$p" 2>/dev/null; then CUR=$(git show ":$p" | sha256sum | cut -d' ' -f1); else CUR="__deleted__"; fi
        if [ "$CUR" != "$REC" ]; then VIOLATION="staged bytes differ from the approved state: $p"; break; fi
      done <<STAGED
$(git diff --cached --name-only 2>/dev/null)
STAGED
    fi
    if [ -n "$VIOLATION" ]; then
      echo "Blocked: working tree does not match the human-approved diff — $VIOLATION. Something changed after approval — re-review and re-run approve-diff.sh." >&2
      exit 2
    fi
  else
    # Legacy aggregate compare (pre-F1 marker without approved_paths). Shared change-set
    # hash helper: approve-diff.sh recorded approved_change_hash via this same script,
    # so the two match byte-for-byte (see the diff-scoping-conventions skill). On an
    # empty repo (no HEAD) both sides hash the untracked tree identically.
    APPROVED=$(jq -r '.approved_change_hash' "$DIFF_APPROVED" 2>/dev/null)
    CURRENT=$(bash "$HOOK_DIR/compute-change-hash.sh")
    if [ -z "$APPROVED" ] || [ "$APPROVED" = "null" ] || [ "$APPROVED" != "$CURRENT" ]; then
      echo "Blocked: working tree does not match the human-approved diff ($DIFF_APPROVED approved_change_hash). Something changed after approval — re-review and re-run approve-diff.sh." >&2
      exit 2
    fi
  fi
fi

exit 0
