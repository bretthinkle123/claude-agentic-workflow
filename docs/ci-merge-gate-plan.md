# Plan — CI as the merge gate (PR L): re-verify the objective gates on the merge commit

> **Status: SPEC — not built, awaiting approval.** The keystone of Track 2 (`pipeline-june-analysis.md`
> §7 Phase 1, §10 row L): everything downstream (M–P, CQ, DAST) depends on it. Companions:
> `docs/dast-plan.md` (runtime security jobs that slot into this CI), `docs/delivery-operations-plan.md`
> (PRs M–P, which chain deploy workflows onto this one), `docs/pipeline-deployment-targets.md`
> (existing post-merge recipes this supersedes-in-part). Scope is the **per-project CI wiring the
> pipeline scaffolds** plus the **engine's own CI**; it adds no new agents and changes no gate hook.

## Goal & honest scope

The pipeline's deterministic gates end at the PR, verified on the **author's machine**. A hostile or
merely edited PR shouldn't be trusted on its local green: after `diff-approved`, anything from a
rebase to a malicious commit can change what actually merges. PR L makes **CI on the merge commit
the source of truth** by re-verifying every *objective* property, and makes the engine's own
regression harness (`tests/run-eval.sh`) a merge gate for this repo.

**The honest bar — what CI can and cannot re-verify:**

| Property | Local mechanism | CI mechanism |
|---|---|---|
| Tests pass + coverage floor | testing agent → `test-results.json` | **re-run** the full suite + coverage natively |
| SAST / SCA / secrets / IaC | security agent → scanners | **re-run** Semgrep, OSV, Gitleaks, Trivy fs, Checkov natively |
| ASVS Tier-1 patterns | `asvs-sast.sh` (diff-scoped) | **re-run** `asvs-sast.sh` full-tree |
| Source markers | `guard-source-markers.sh` | **re-run** full-tree |
| Lockfile integrity | `lockfile-check.sh` | **re-run** against the PR diff |
| Criteria coverage (`criteria_covered`) | testing agent judgment vs `acceptance.md` | **NOT re-derivable** — judgment. CI preserves the record (Layer 0) and required human review guards it |
| Human checkpoints (plan/diff/design-approved) | TTY-only markers | **no CI analog** — branch protection + required review is the CI-side counterpart |
| ASVS 6g / DP / input-surface reconciliation | agent-reasoned → deterministic floors | **NOT re-runnable** (agent judgment); the *pattern-checkable* subset is covered by the re-run scanners |

**The core design decision (settles the open question): CI re-RUNS checks; it never re-reads
`.pipeline/` artifacts.** The merge commit carries no `.pipeline/*` (gitignored by design), so any
scheme that ships artifacts to CI would be re-checking the author's *claims*. Re-execution is the
only honest verification. Consequence: agent-judgment gates (criteria mapping, reconciliations)
remain **pre-merge guarantees**, protected in CI by (a) the objective re-runs catching what pattern
checks can catch, and (b) required human review on a diff that includes the Layer-0 design record.

## Layer 0 — design-record retention (prerequisite; standalone maintainability value)

`.pipeline/` is overwritten every feature, so a shipped app retains **no** plan, threat model, or
security report — bad for maintainability, and it leaves CI-era reviewers nothing to check the diff
against. Fix at the documentation stage (it already owns "writes that become part of the commit"):

- **documentation** copies, before `write-review-manifest.sh` runs (so the hash covers them):
  `.pipeline/plan.md`, `acceptance.md`, `security-report.md`, `plan-audit.md`, and (when present)
  `design-spec.md` + `run-summary.json` → **`docs/decisions/<feature-branch>/`** in the project.
- `doc-conventions` gains the layout + a redaction rule (the record must not carry secrets — the
  reports are already secret-free by the security agent's own rules; state it anyway).
- Explicitly **not** machine-gated: the record is evidence for humans and audits, not a CI input.
- Waivers that must survive into CI use **tool-native committed ignore files** (`.trivyignore`,
  `osv-scanner.toml`, `.semgrepignore`) — visible in the diff, therefore human-reviewed at the M5
  checkpoint. A local-only `.pipeline/waivers.json` entry that never lands in a committed ignore
  file will (correctly) fail CI — the committed file is the CI-side waiver record. **S–M.**

## Layer 1 — the engine's own CI (this repo; do first)

`.github/workflows/eval.yml`: on push + PR to `main`, run `bash tests/run-eval.sh` on
`ubuntu-latest` (bash + jq preinstalled; the harness needs nothing else). Branch protection on
`main` requires it. Converts "remember to run the harness" into a merge gate — the exact promise
PR H made ("CI-ready; PR L wires this as a job"). **S — an afternoon, zero risk, ship immediately.**

## Layer 2 — the per-project workflow template

`templates/ci/pipeline-ci.yml`, written to `.github/workflows/pipeline-ci.yml` by
`bootstrap-project.sh` (same fill-in channel as `smoke.env`: `--test`/`--build` populate
`<TEST_CMD>`/`<BUILD_CMD>`; coverage floor placeholder mirrors `test-conventions`). Jobs, all on
PR + push-to-main:

1. **build-and-test** — install deps from lockfile, `<BUILD_CMD>`, `<TEST_CMD>` with coverage,
   fail under the project's combined-lines floor (same figure the local gate rides; branch coverage
   surfaced in the job summary, not gated — mirrors the local posture).
2. **sast** — Semgrep (same rule packs the project's `semgrep-ruleset-guide` names) over the full
   tree; criticals fail, warnings annotate.
3. **deps** — osv-scanner (CVSS ≥ 7.0 fails, mirroring the B6 floor, honoring the committed
   `osv-scanner.toml`) + `lockfile-check.sh` logic against the PR diff.
4. **secrets** — Gitleaks over the full history of the PR branch (CI can afford history; the local
   hook is diff-scoped).
5. **containers-iac** — Trivy fs (+ image scan and Checkov when Dockerfile/`infra/` exist).
6. **asvs-markers** — `asvs-sast.sh` + `guard-source-markers.sh` re-run against the **PR diff vs.
   the merge base**, not the working tree. *(Implementation note, verified against the current
   scripts: both scope to `git diff HEAD` + untracked files, which is **empty on a merge commit** —
   so a naive re-run passes vacuously. The correct change is a `SCAN_BASE` env override so CI scans
   `git diff $SCAN_BASE...HEAD` (e.g. `origin/main`); this also preserves `guard-source-markers`'s
   added-lines-only semantics, which a full-tree grep would break. A small, honest edit to each
   script's file-population block — not a no-op env flag.)*
7. **dast-baseline** — placeholder slot; filled by `docs/dast-plan.md` Layer 1.
8. **deploy-verify** — skeleton for the reborn `post-deploy-check.sh`; inert (skipped) until
   PR N provides `DEPLOY_HEALTH_URL`. The hook finally gets implemented here as a job step, not a
   local hook — closing the `[UNIMPLEMENTED]` marker honestly.

Conventions baked into the template: **actions pinned by commit SHA** (supply-chain — same posture
as exact-pin deps), `permissions: read-all` default with per-job elevation, `concurrency` per ref,
job timeouts, no long-lived cloud keys (OIDC only, per `iac-conventions`). **M.**

**CI waiver channel (resolves the "re-run ignores local waivers" gap).** The local floors honor
`.pipeline/waivers.json`, which is gitignored and never reaches CI. So CI re-runs must read
**committed, tool-native ignore files** — `osv-scanner.toml`, `.trivyignore`, `.semgrepignore` —
which are visible in the diff and therefore human-reviewed at the M5 checkpoint (this is Layer 0's
waiver rule). The two grep jobs are deliberately *outside* this channel: `asvs-sast` (JWT-none /
fast-hash / weak-crypto) and `guard-source-markers` (revert/do-not-commit markers) are **fix-not-waive**
by design — there is no legitimate "ship it anyway," so CI offers them no ignore path.

## Layer 3 — `ci-conventions` skill + branch-protection checklist

A new global skill (on-demand; loaded by planning when a project has/needs CI, and the reference
documentation cites) carrying: the job inventory above and what each does/doesn't guarantee; the
**branch-protection checklist** the operator applies once per repo (`gh api` commands: require PR,
required status checks = jobs 1–6, dismiss stale approvals, block force-push); the honest-scope
table from this doc (so nobody later claims CI re-verifies criteria); and how M/N deploy workflows
chain (`workflow_run` on green main). Branch protection is configuration, not a hook — the skill
documents it, the operator runs it, and the checklist is the auditable record. **S.**

## Layer 4 — CQ slot-in

CodeQL (roadmap row CQ) is deliberately **not** part of this PR — but the template reserves the job
name and the skill documents where it lands, so CQ becomes a one-job diff once L is live.

## Sequencing

1. **Layer 1** (engine CI) — immediately; independent of everything.
2. **Layer 0** (design records) — next; it changes the documentation agent, so run the harness +
   one real pipeline run before relying on it.
3. **Layer 2 + 3** together (template is useless un-documented; skill is untestable un-templated).
   Prove them on a real app repo (ledgerly or the red-team app), not abstractly — M2 rule.
4. **Layer 4** (CQ) + `dast-plan.md` Layer 1 as fast-follows in the same repo.

## Non-goals

- **Not replacing the human checkpoints** — plan/diff/design approval stay pre-merge and TTY-bound;
  CI adds required review, it does not simulate the markers.
- **Not re-deriving agent judgments** (criteria mapping, ASVS 6g, DP/input reconciliation) — stated
  above; pretending CI covers these would be the vacuous-green failure mode with extra steps.
- **Not deployment** — jobs end at "merge commit verified"; deploy workflows are PR M/N
  (`docs/delivery-operations-plan.md`).
- Not GitLab/Jenkins portability (GitHub Actions only — matches the gh-CLI/OIDC posture).

## Tie-in

Wires `tests/run-eval.sh` as promised by PR H; implements `post-deploy-check.sh`'s replacement;
supersedes the ad-hoc CI sketches in `pipeline-deployment-targets.md` §CI (recipes for *delivery*
remain valid there). Layer 0 also delivers the design-record retention item from the 2026-07-05
audit. Add the L row's status change + a Layer-0 note to `pipeline-june-analysis.md` §10 when this
moves from spec to build.
