# Documentation consolidation plan (DOC side-track)

> **Status: plan, awaiting approval.** Execution counterpart to the `DOC` row in the master
> roadmap. Deliberately scheduled last, once Track-1 churn settled (it has: PRs F–K are merged).
> This file is itself temporary — delete it once the migration is done.

**Goal.** Collapse the proliferated `.md` set into a coherent structure: one PR-indexed record of
*what shipped and why*, one forward-looking roadmap, a clear living-vs-historical split, and
cross-links instead of duplicated prose. Nothing is deleted — history moves to `docs/archive/`.

**Decisions (approved 2026-07-02):** archive historical docs under `docs/archive/`; archive the
2,959-line design log as-is (no distillation); `system_architecture.md` remains the current-state
source of truth.

---

## Target tree (after migration)

```
README.md                          entry point + NEW "Documentation map" section
docs/
  system_architecture.md           UNCHANGED — the current-state reference (file map, flow, gates)
  pipeline-changelog.md            NEW — PR-indexed "what shipped + why", A→K + side-tracks
  roadmap.md                       NEW — forward-looking only: Track 2 (L–P) + open side-tracks
  pipeline-threat-model.md         UNCHANGED — engine STRIDE model (shipped PR K)
  pipeline-alternatives.md         UNCHANGED — reference companion (banner re-pointed)
  pipeline-deployment-targets.md   UNCHANGED — reference companion (banner re-pointed)
  pipeline-mcp-config.md           UNCHANGED — reference companion (banner re-pointed)
  pipeline-code-quality-audit.md   KEPT as future-design doc; links re-pointed to roadmap.md
  pipeline-refinement-loops.md     SLIMMED to candidate designs only
  eval/
    m2-run-1-linkly.md             MOVED from root m2-test-plan.md (executed run #1)
    m2-run-2-ledgerly.md           MOVED from root m2-run-2-test-plan.md (active run #2)
  archive/
    README.md                      NEW — "point-in-time; superseded by changelog/roadmap"
    agentic-pipeline-plan.md       MOVED from docs/ (2,959-line design log)
    max-pipeline-improvements.md   MOVED from root (Max 20x advisory — rationale for A–E)
    pipeline-revision-plan.md      MOVED from root (A–E execution plan)
    pipeline-june-analysis.md      MOVED from root (original assessment; findings preserved)
tests/README.md                    UNCHANGED
```

> **On the two run plans:** `m2-run-1-linkly.md` is executed (historical) but I recommend keeping
> it under `docs/eval/` alongside run #2 rather than in `archive/`, so both evaluation plans live
> together as a runnable series. If you'd rather it go to `archive/`, that's a one-line change.

Root-level loose planning docs go from **5 → 0** (only `README.md` remains at root).

---

## The two new documents

### `docs/pipeline-changelog.md` — the centerpiece

The single answer to "what's implemented, by PR, and how it improved the pipeline." One concise
section per shipped unit, newest-last, each with: **what changed · why it improved the pipeline ·
link to the archived deep rationale.** Content is *migrated and compressed* from the "Done" rows of
`pipeline-june-analysis.md §10`, `pipeline-revision-plan.md`, and `max-pipeline-improvements.md` —
no new claims, just consolidation.

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

---

## Cross-references to fix (verified by grep)

Links in files that **stay** but point at files that **move**:

| File (stays) | Line | Current target | Re-point to |
|---|---|---|---|
| `README.md` | 119 | `docs/agentic-pipeline-plan.md` | `docs/archive/agentic-pipeline-plan.md` (+ note it's historical); add changelog/roadmap to new doc map |
| `docs/system_architecture.md` | 4 | `docs/agentic-pipeline-plan.md` | `docs/archive/agentic-pipeline-plan.md` |
| `docs/system_architecture.md` | 177 | tree entry `agentic-pipeline-plan.md` | update tree to new layout |
| `docs/pipeline-alternatives.md` | 1 | "companion to `agentic-pipeline-plan.md`" | "companion to `system_architecture.md`" (live ref) |
| `docs/pipeline-deployment-targets.md` | 1 | same | same re-point |
| `docs/pipeline-mcp-config.md` | 1 | same | same re-point |
| `docs/pipeline-code-quality-audit.md` | 4 | companion to `agentic-pipeline-plan.md` | `system_architecture.md` |
| `docs/pipeline-code-quality-audit.md` | 156–157 | `pipeline-june-analysis.md §10`; `pipeline-revision-plan.md` | `docs/roadmap.md`; `docs/archive/pipeline-revision-plan.md` |

Links **inside archived files** that point at other archived files (e.g. revision-plan ↔
max-improvements) still resolve after the move because both land in `docs/archive/` — but relative
paths like `../pipeline-june-analysis.md` need checking. I'll do a grep sweep post-move and fix any
dangling relative links (both intra-archive and archive→docs, e.g. june-analysis's `[[redteam-app-goal]]`
style refs are memory links, not file links, and are unaffected).

### Memory files to update (in `~/.claude/.../memory/`)

These reference repo docs that move; update the pointers (content, not just paths):

| Memory file | Reference | Action |
|---|---|---|
| `MEMORY.md` | redteam hook cites `pipeline-june-analysis.md` | → `docs/archive/pipeline-june-analysis.md` (assessment) + `docs/roadmap.md` (live) |
| `project-context.md` | line 13 lists `agentic-pipeline-plan.md` as "the main spec" | reword: `system_architecture.md` is the live reference; design log archived; add changelog + roadmap |
| `redteam-app-goal.md` | line 26 cites june-analysis §5/§7 | → roadmap.md (§7 material) + archive (assessment) |
| `pr-g-criterion-completeness-decisions.md` | line 19 cites june-analysis §10 | → `docs/pipeline-changelog.md` (PR G row) |
| `feedback-check-existing-work-first.md` | line 20 cites `max-pipeline-improvements.md` | → `docs/archive/max-pipeline-improvements.md` |

---

## Execution checklist (on approval)

1. `mkdir docs/archive docs/eval`.
2. **Write** `docs/pipeline-changelog.md` (migrate + compress the "Done" content).
3. **Write** `docs/roadmap.md` (migrate the forward-looking content).
4. **Write** `docs/archive/README.md` (banner: these are point-in-time; see changelog/roadmap).
5. `git mv` the historical docs into `docs/archive/`; `git mv` the run plans into `docs/eval/`
   (rename to `m2-run-1-linkly.md` / `m2-run-2-ledgerly.md`). *(Use `git mv` to preserve blame.)*
6. Add a strong "historical — see `system_architecture.md`" banner to the archived design log.
7. **Slim** `pipeline-refinement-loops.md` to candidate designs; note the implemented planning loop
   now lives in the changelog.
8. Fix all cross-references in the table above; run a grep sweep for any dangling links and fix.
9. Add a **"Documentation map"** section to `README.md` (7-line index: changelog, roadmap,
   architecture, threat-model, the three reference companions, eval, archive).
10. Update the 5 memory files.
11. Run `bash tests/run-eval.sh` as a sanity check (docs-only change → must stay green) and verify
    no skill/agent references a moved path (grep `global-*` for the moved filenames — none expected,
    but confirm).
12. Delete this plan file.

**Risk:** minimal — docs only; touches no agent, hook, gate, or skill logic. Fully reversible via
git. The only care items are (a) not losing the §8 findings data (preserved in the changelog) and
(b) fixing every cross-link (enumerated above + a final grep sweep).

**Estimated diff:** 2 new docs (~250–350 ln combined), 1 archive README, ~8 link edits, 5 files
moved, 1 file slimmed, 5 memory edits.
