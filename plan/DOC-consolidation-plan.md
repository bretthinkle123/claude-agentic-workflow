# Documentation consolidation plan (DOC side-track)

> **Status: EXECUTED 2026-07-10 (branch `docs/doc-consolidation`)** — this archived copy is the
> plan of record; the checklist below was carried out as written. **Post-execution operator
> adjustments (same branch, 2026-07-11):** `system_architecture.md` moved from `docs/` to the repo
> root, and a follow-up sort audit moved four more delivered/design docs into `plan/`
> (`dast-plan.md`, `asvs-determinism-roadmap.md`, `pipeline-code-quality-audit.md`,
> `pipeline-refinement-loops.md`) — so the final tree is root README + `system_architecture.md`,
> nine living docs in `docs/`, and everything else under `plan/`. **Revised 2026-07-09** to fold
> in the new `plans/`-vs-`docs/` split (see Decisions). **Revised 2026-07-10** — migration destination changed to the new
> **tracked `plan/` directory** (operator decision; `plans/` stays as the gitignored scratch
> area), cross-reference table re-verified against the current tree (deltas folded in:
> `m4-double-prime-run-plan.md` added to the move list; new refs in `dast-plan.md`,
> `asvs-determinism-roadmap.md`, `system_architecture.md:1134`, `memory/audit-prompt.md`; line
> drift). Execution counterpart to the `DOC` row in the master roadmap. Deliberately scheduled
> last, once Track-1 churn settled (it has: PRs F–K are merged). This file is itself a plan — it
> moves to `plan/` as the final step instead of being deleted.

**Goal.** Collapse the proliferated `.md` set into a coherent structure: one PR-indexed record of
*what shipped and why*, one forward-looking roadmap, and a hard three-directory split — `docs/`
holds only curated, living documentation (placed there by the operator); **`plan/` (tracked)**
holds the committed plan archive — every historical plan file, moved with blame preserved;
**`plans/` (gitignored)** holds new private drafts and scratch. Nothing is deleted — history moves
to `plan/`.

**Decisions (approved 2026-07-02):** archive historical docs (destination revised below); archive
the 2,959-line design log as-is (no distillation); `system_architecture.md` remains the
current-state source of truth.

**Decisions (2026-07-09):**
- **`plans/` replaces `docs/archive/`** as the destination for all one-shot plans, run plans,
  audits, and temporary docs — from `docs/`, root, everywhere. Scope of this PR grows accordingly
  (full sweep, not just the original 5 root files).
- **Gitignore:** `plans/` is added to `.gitignore` — every file dropped into `plans/` is private
  by default. Opt a draft into publication explicitly with `git add -f plans/<file>`.
- **Standing convention:** from now on, agents and operator alike write new plans / temporary /
  scratch `.md` files to `plans/`, never to `docs/` or root. `docs/` changes only when the
  operator curates it.

**Decisions (2026-07-10):**
- **Migration destination is `plan/` (tracked), not `plans/`.** The operator created `plan/` as a
  normal tracked directory; all MOVED files land there via `git mv`. This kills the confusing
  tracked-files-inside-a-gitignored-directory hybrid: `plan/` is the public, committed archive;
  `plans/` is purely gitignored scratch (nothing tracked in it, ever). Plan files committed as
  part of a PR — including this one, and any future published plan — belong in `plan/`.
- `plan/README.md` (tracked) states the three-directory convention once; `plans/` needs no README
  (it is invisible in the repo).

---

## Target tree (after migration)

```
README.md                          entry point + NEW "Documentation map" section — ONLY file at root
.gitignore                         + plans/ entry
docs/                              curated living docs only
  system_architecture.md           UNCHANGED — the current-state reference (file map, flow, gates)
  pipeline-changelog.md            NEW — PR-indexed "what shipped + why", A→K + side-tracks
  roadmap.md                       NEW — forward-looking only: Track 2 (L–P) + open side-tracks
  pipeline-threat-model.md         UNCHANGED — engine STRIDE model (shipped PR K)
  pipeline-alternatives.md         UNCHANGED — reference companion (banner re-pointed)
  pipeline-deployment-targets.md   UNCHANGED — reference companion (banner re-pointed)
  pipeline-mcp-config.md           UNCHANGED — reference companion (banner re-pointed)
  pipeline-code-quality-audit.md   KEPT as future-design doc; links re-pointed to roadmap.md
  pipeline-refinement-loops.md     SLIMMED to candidate designs only
  dast-plan.md                     UNCHANGED — living convention doc (dast-conventions skill refs it)
  finding-ledger.md                UNCHANGED — living ledger
  pr-history.md                    UNCHANGED — living record
  sk-assessment-log.md             UNCHANGED — ongoing log
  asvs-determinism-roadmap.md      UNCHANGED — living roadmap companion
plan/                              tracked — the committed plan archive
  README.md                        NEW — states the plan/ vs plans/ vs docs/ convention
  eval/
    m2-run-1-linkly.md             MOVED from root m2-test-plan.md (executed run #1)
    m2-run-2-ledgerly.md           MOVED from root m2-run-2-test-plan.md (executed run #2)
  agentic-pipeline-plan.md         MOVED from docs/ (2,959-line design log)
  pipeline-june-analysis.md        MOVED from root (original assessment; findings preserved)
  pipeline-revision-plan.md        MOVED from root (A–E execution plan)
  max-pipeline-improvements.md     MOVED from root (Max 20x advisory — rationale for A–E)
  audit-remediation-plan.md        MOVED from root
  input-controls-enforcement-plan.md  MOVED from root
  PIPELINE-AUDIT-REPORT.md         MOVED from root
  ci-merge-gate-plan.md            MOVED from docs/ (PR L rationale)
  delivery-operations-plan.md      MOVED from docs/ (PR M/P rationale)
  environments-delivery-plan.md    MOVED from docs/ (PR N rationale)
  data-protection-enforcement-plan.md  MOVED from docs/
  design-spec-stage-plan.md        MOVED from docs/
  egress-control-plan.md           MOVED from docs/
  store-compliance-plan.md         MOVED from docs/
  ios-swiftui-target-plan.md       MOVED from docs/
  triage-agent-plan.md             MOVED from docs/
  m3-validation-run-plan.md        MOVED from docs/
  m4-proof-run-plan.md             MOVED from docs/
  m4-prime-fix-plan.md             MOVED from docs/
  m4-prime-run-plan.md             MOVED from docs/
  m4-double-prime-run-plan.md      MOVED from docs/ (added 2026-07-10 — created after the 07-09 sweep)
  DOC-consolidation-plan.md        MOVED from docs/ (this file, final step)
plans/                             gitignored — new private drafts/scratch only (not part of this migration)
tests/README.md                    UNCHANGED
```

All moves use `git mv` (every file above is currently tracked; preserves blame). Root-level loose
docs go from **8 → 0** (only `README.md` remains); `docs/` goes from 28 files to 14 curated ones
(16 move out, changelog + roadmap move in).

---

## The two new documents

### `docs/pipeline-changelog.md` — the centerpiece

The single answer to "what's implemented, by PR, and how it improved the pipeline." One concise
section per shipped unit, newest-last, each with: **what changed · why it improved the pipeline ·
link to the archived deep rationale (now under `plan/`).** Content is *migrated and compressed*
from the "Done" rows of `pipeline-june-analysis.md §10`, `pipeline-revision-plan.md`, and
`max-pipeline-improvements.md` — no new claims, just consolidation.

Planned sections (in ship order):
- **PRs A–C** (design PRs 1–6): instrument + retune → smarter agents + contracts → autonomous loop
  + circuit-breaker. Source: revision-plan; rationale: max-improvements.
- **PR E** — robustness conventions (migration/property/concurrency/perf modes, Trivy, secrets skill,
  IaC scale defaults).
- **PR F** — M2 fast-fixes (`.gitignore`, `maxTurns`); **F2-node** follow-up.
- **PR G** — quality + criterion-completeness gate (perf-pairing; advisory `test-quality.json`).
- **PR G6** — results-file integrity (real `ran_at`, terminal `loop-state`).
- **PR H** — eval/regression harness (`tests/`).
- **PR I** — human diff-review + supply-chain + data safety (M5/M6/F3).
- **PR J** — token/altitude polish.
- **PR K** — pipeline-as-target threat model + approval-marker guards.
- **Side-tracks:** SEC (security→opus + step 6f), DEP (deployment→sonnet + pre-commit inspection),
  DB (debugging→opus), AE (`api-edge-conventions` skill).
- **Findings that drove the work** — a compact subsection preserving the §8 observed-failures
  (F1–F6) as the evaluation evidence behind PRs F–J.

### `docs/roadmap.md` — forward-looking only

Everything still open, lifted from `pipeline-june-analysis.md §7/§10`:
- **Track 2 (L–P)** — CI merge gate → build/provenance → environments+load → observability →
  scale/DR. The "last 40%."
- **Open side-tracks** — FE (front-end), PI (parallel implementation), SK (skill enrichment), and
  this DOC task itself.
- **Two "10/10" definitions** and the critical path, kept as the orientation header.
- Links to the design docs that back specific items (`pipeline-code-quality-audit.md` for a
  code-audit stage; the deferred-workstream memory entries).

### `plan/README.md` — the convention, stated once

Short: (a) `plan/` (tracked) is the committed plan archive — historical one-shot PR plans, run
plans, audits, plus any plan file published as part of a PR; (b) `plans/` (gitignored) is where
agents and operator write **new** plans/drafts/scratch — private by default, promoted into
`plan/` via `git mv`-style copy when a PR publishes them; (c) `docs/` is operator-curated living
documentation only — never write new plans there or to root.

---

## Cross-references to fix (verified by grep, 2026-07-09; re-verified 2026-07-10)

Links in files that **stay** but point at files that **move**:

| File (stays) | Line | Current target | Re-point to |
|---|---|---|---|
| `README.md` | 118 | `docs/agentic-pipeline-plan.md` | `plan/agentic-pipeline-plan.md` (+ note it's historical); add changelog/roadmap/plan-convention to new doc map |
| `docs/system_architecture.md` | 4 | `docs/agentic-pipeline-plan.md` | `plan/agentic-pipeline-plan.md` |
| `docs/system_architecture.md` | 177 | tree entry `agentic-pipeline-plan.md` | update tree to new layout (incl. `plan/` + `plans/`) |
| `docs/system_architecture.md` | 1134 | `docs/ci-merge-gate-plan.md` | `plan/ci-merge-gate-plan.md` *(added 07-10)* |
| `docs/pipeline-alternatives.md` | 1 | "companion to `agentic-pipeline-plan.md`" | "companion to `system_architecture.md`" (live ref) |
| `docs/pipeline-deployment-targets.md` | 1 | same | same re-point |
| `docs/pipeline-mcp-config.md` | 1 | same | same re-point |
| `docs/pipeline-code-quality-audit.md` | 4 | companion to `agentic-pipeline-plan.md` | `system_architecture.md` |
| `docs/pipeline-code-quality-audit.md` | 156–157 | `pipeline-june-analysis.md §10`; `pipeline-revision-plan.md` | `docs/roadmap.md`; `plan/pipeline-revision-plan.md` |
| `docs/dast-plan.md` | 6–8, 149–150 | `docs/ci-merge-gate-plan.md`, `docs/delivery-operations-plan.md`, `docs/egress-control-plan.md`, `pipeline-june-analysis.md §10` | `plan/…` equivalents *(added 07-10)* |
| `docs/asvs-determinism-roadmap.md` | 28, 41 | `docs/store-compliance-plan.md`; `docs/data-protection-enforcement-plan.md` | `plan/…` equivalents *(added 07-10)* |
| `templates/ci/pipeline-ci.yml` | 12, 136 | `docs/ci-merge-gate-plan.md` | `plan/ci-merge-gate-plan.md` |
| `templates/ci/deploy.yml` | 1 | `docs/environments-delivery-plan.md` | `plan/environments-delivery-plan.md` |
| `templates/ci/build-provenance.yml` | 1 | `docs/delivery-operations-plan.md` | `plan/delivery-operations-plan.md` |
| `templates/ci/dr-drill.yml` | 1 | `docs/delivery-operations-plan.md §P` | `plan/delivery-operations-plan.md §P` |
| `scripts/bootstrap-project.sh` | 149 | `docs/ci-merge-gate-plan.md` | `plan/ci-merge-gate-plan.md` |
| `global-skills/ci-conventions/SKILL.md` | 12 | `docs/ci-merge-gate-plan.md` | `plan/ci-merge-gate-plan.md` |
| `global-skills/iac-conventions/SKILL.md` | 62 | `docs/environments-delivery-plan.md` | `plan/environments-delivery-plan.md` |
| `global-skills/VENDORED.md` | 55 | `pipeline-june-analysis.md` | `plan/pipeline-june-analysis.md` |
| `global-project-skills/claude-design-to-swiftui/SKILL.md` | 11 | `docs/design-spec-stage-plan.md` | `plan/design-spec-stage-plan.md` |
| `global-project-skills/google-play-submission-requirements/SKILL.md` | 16 | `docs/ios-swiftui-target-plan.md` | `plan/ios-swiftui-target-plan.md` |
| `global-project-skills/semgrep-ruleset-guide/SKILL.md` | 47 | `docs/ios-swiftui-target-plan.md` | `plan/ios-swiftui-target-plan.md` |

**Deliberately NOT updated:** `examples/meterly/run-journal.md` and `examples/meterly/run-evidence/`
reference m4 plan paths — these are point-in-time evidence records and must not be rewritten.

Refs *between* moved files need the sweep too *(clarified 07-10)*: bare same-dir refs
(revision-plan ↔ max-improvements) still resolve inside `plan/`, but `docs/`-prefixed refs between
two moved files (e.g. `environments-delivery-plan.md:4` → `docs/delivery-operations-plan.md`,
`m4-double-prime-run-plan.md:3` → `docs/m4-prime-run-plan.md`) become stale-prefixed, and the two
`plan/eval/` files reference `pipeline-june-analysis.md`, which lands one level up
(`../pipeline-june-analysis.md`). The step-8 repo-wide grep for old paths covers all of these —
run it over `plan/` as well as the staying tree. june-analysis's `[[redteam-app-goal]]`-style refs
are memory links, not file links, and are unaffected.

### Memory files to update (in `~/.claude/.../memory/`)

These reference repo docs that move; update the pointers (content, not just paths):

| Memory file | Reference | Action |
|---|---|---|
| `MEMORY.md` | redteam hook cites `pipeline-june-analysis.md` | → `plan/pipeline-june-analysis.md` (assessment) + `docs/roadmap.md` (live) |
| `project-context.md` | lists `agentic-pipeline-plan.md` as "the main spec" | reword: `system_architecture.md` is the live reference; design log in `plan/`; add changelog + roadmap |
| `audit-prompt.md` | cites `docs/agentic-pipeline-plan.md` (lines 23, 54) | → `plan/agentic-pipeline-plan.md` *(added 07-10)* |
| `redteam-app-goal.md` | cites june-analysis §5/§7 | → `docs/roadmap.md` (§7 material) + `plan/` (assessment) |
| `pr-g-criterion-completeness-decisions.md` | cites june-analysis §10 | → `docs/pipeline-changelog.md` (PR G row) |
| `feedback-check-existing-work-first.md` | cites `max-pipeline-improvements.md` | → `plan/max-pipeline-improvements.md` |
| `m3-audit-fix-plan.md` | cites m4′ plan docs if by path | → `plan/m4-prime-*.md` |
| `plans-vs-docs-convention.md` | states the two-directory convention | already updated 2026-07-10 with the `plan/` (tracked) addition |

---

## Execution checklist (on approval)

1. `mkdir plan/eval` (`plan/` already exists — operator-created 2026-07-10); commit the `plans/`
   `.gitignore` entry (already sitting in the working tree with its comment).
2. **Write** `docs/pipeline-changelog.md` (migrate + compress the "Done" content).
3. **Write** `docs/roadmap.md` (migrate the forward-looking content).
4. **Write** `plan/README.md` (the three-directory convention).
5. `git mv` every file in the target-tree MOVED list into `plan/` (run plans into `plan/eval/`
   with the `m2-run-1-linkly.md` / `m2-run-2-ledgerly.md` renames). Verify with `git status` that
   each move is staged as a rename — a silent drop here would mean history lost, not just a
   dangling link.
6. Add a strong "historical — see `system_architecture.md`" banner to the archived design log.
7. **Slim** `pipeline-refinement-loops.md` to candidate designs; note the implemented planning loop
   now lives in the changelog.
8. Fix all cross-references in the table above (incl. the CI templates, bootstrap script, and
   skills); run a repo-wide grep sweep for the old paths — **including inside `plan/` itself**
   (`docs/`-prefixed refs between moved files, the `plan/eval/` → `../` hop) — and fix any
   stragglers.
9. Add a **"Documentation map"** section to `README.md` (~8-line index: changelog, roadmap,
   architecture, threat-model, the three reference companions, `plan/`+`plans/` convention,
   tests). While in `README.md`, fix the stale skill count at line 18 ("21 global skills" —
   actual is 28; prefer dropping the number, as `global-skills/README.md` now does) and the
   `scripts/install-global.sh:9` comment ("19 global skills") the same way.
10. Update the memory files per the table.
11. Run `bash tests/run-eval.sh` as a sanity check (docs-only + comment-path edits → must stay
    green); confirm `scripts/bootstrap-project.sh` still runs (only a comment changed).
12. `git mv docs/DOC-consolidation-plan.md plan/` (this file — last move).
13. Commit; verify `git status` is clean and that a scratch file dropped into `plans/` shows as
    ignored, not untracked.

**Risk:** minimal — docs, comments, and one gitignore line; touches no agent, hook, gate, or skill
*logic* (the skill edits are prose path references). Fully reversible via git. Care items: (a) not
losing the §8 findings data (preserved in the changelog); (b) fixing every cross-link (enumerated
above + final grep sweep); (c) every move lands in tracked `plan/` — nothing from the MOVED list
goes into gitignored `plans/`.

**Estimated diff:** 2 new docs (~250–350 ln combined), 1 plan/ README, 1 gitignore line, ~28 link
edits (11 docs + 6 CI/script + 6 skill + README + counts), 23 files moved, 1 file slimmed,
~8 memory edits.
