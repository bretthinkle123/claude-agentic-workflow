# Plan — deterministic-driver spine gaps (L1 extensions: per-task impl + design-spec)

> **Status: PLANNED (not built), 2026-07-16.** Extends the L1 deterministic orchestration
> driver (`global-hooks/next-stage.sh` + `stage-prompt.sh`, wired advisory into
> `pipeline-orchestration/SKILL.md`) to the two conditional stages the L1 spine leaves at
> the LLM orchestrator's judgment: **per-task implementation segments** (`tasks.md` T1…Tn)
> and the **design-spec** pre-planning stage. Same pattern as L1 — a pure function of state,
> pinned `driver ≡ gate ≡ SKILL`, advisory first. Scope is the **engine's orchestration**,
> not the apps it builds. Do NOT start until the P0 blocker below is fixed.

## P0 — predicate-path portability (RESOLVED 2026-07-16, in the same change as this plan)

Recorded because it blocked live adoption of the *existing* L1 driver, not just these gaps.
**Was:** `next-stage.sh`'s default `TEST_PRED` pointed at `tests/helpers/loop-exit-predicate.jq`,
which `scripts/install-global.sh` does **not** publish — so in a live `~/.claude` run the file
was absent, `jq -e -f` failed on every `test-results.json`, and the driver wrongly emitted
`run:debugging:test` on a fully-GREEN state (loop wedged). The in-repo suite was green and
**structurally could not catch it** (it runs where the relative path resolves).
**Fixed by:** `git mv tests/helpers/loop-exit-predicate.jq → global-hooks/loop-exit-predicate.jq`
(now a single source, published with the hooks); repointed `next-stage.sh`
(`$HERE/loop-exit-predicate.jq`) and `tests/helpers/assert.sh` (`$HOOKS/...`), which carries
`loop-exit-invariant.sh` + `static.sh`; added a **published-layout regression** to
`tests/suites/next-stage.sh` (runs the hook from a hooks-only temp dir with no sibling `tests/`
and asserts a green state → `run:deployment`). Verified 34/34 suites green.

## Goal & honest scope

Make the driver deterministically sequence the two remaining spine branches, so "which stage
runs next / with what context" stays a pure function of state through them too — same honest
bar as L1: **deterministic DECISION, advisory execution** (enforcement is L2). Neither gap
improves generated-code quality (the gates own that); both improve **consistency and
cost-predictability** by removing orchestrator improvisation where it currently leaks.

## Design principles (inherited from L1)

- **Pure function of `.pipeline/*`** — a new action token per branch, computed, never judged.
- **`driver ≡ gate ≡ SKILL`** — every new token handled by `stage-prompt.sh` and documented in
  the SKILL; existing vocabulary drift guard in `tests/suites/next-stage.sh` extends to cover them.
- **Advisory first** — wired into the SKILL as guidance, not enforced; the orchestrator still calls the agents.
- **Emergent ordering over remembered cursors** — completion is a hash/marker the driver reads,
  never state the driver itself must remember across calls (the L1 change-hash trick).

---

## Gap 1 — per-task implementation segments (HIGHER value)

**Why:** the highest-token, most cap-prone stage. Per-task segmentation exists precisely so a
`maxTurns` cap means "anomaly," not "feature too big" (M4 needed ~130+ turns). Today the driver
emits `run:implementation` once and the T1…Tn loop is LLM-driven — the exact place improvisation
costs (skipped "stop cleanly after each task," cap storms, corrupted telemetry).

**The missing signal (the real work):** "which task is done" has no deterministic marker —
`implementation-progress.md` is prose. Add one, mirroring `tested_change_hash`:
- **`.pipeline/tasks-state.json`** — `{"completed":["T1","T2"],"current":"T3"}`, written by the
  implementation agent at each clean segment Stop (its segment already ends suite-green +
  app-bootable — the A-2 contract). This is the per-task completion signal the driver reads.
  (An alternative is a per-task Stop hook that appends the just-finished task id; decide during
  design — a hook is more forgery-resistant, an agent-written file is simpler.)

**Driver changes (`next-stage.sh`), inside the implementation branch:**
- If `tasks.md` present and `tasks-state.json` shows unfinished tasks (in dependency order),
  emit `run:implementation:<Tk>` for the next unstarted task whose deps are all in `completed`.
- If all `tasks.md` tasks are in `completed`, fall through to smoke/loop as today.
- No `tasks.md` ⇒ unchanged single-shot `run:implementation`.
- Dependency order comes from `tasks.md` (planning already emits it); the driver picks the next
  eligible task deterministically (topological, first-eligible).

**Context changes (`stage-prompt.sh`):** `run:implementation:<Tk>` → the implementation agent
with "Do `<Tk>` ONLY (see `.pipeline/tasks.md`), end suite-green + app-bootable, then stop
cleanly." Warm-resume slot: if `implementation-progress.md` shows an in-progress `<Tk>`, add
"You were resumed after a cap — read `.pipeline/implementation-progress.md` first; continue,
don't restart" (codifies the SKILL's warm-resume prompt).

**Still NOT deterministic (leave to observation/human):** cap-out *detection* mid-segment (no
Stop hook fires on a cap — the orchestrator still breadcrumbs it); the decision to escalate a
capped segment to planning.

**Tests:** matrix rows for `tasks-state.json` states (none done → T1; some done → next eligible;
dep not met → the dep first; all done → falls through to `run:security`); `stage-prompt`
per-task prompt + warm-resume slot; vocabulary guard covers `run:implementation:<Tk>`.

---

## Gap 2 — design-spec sequencing (LOWER value; bundle, don't do standalone)

**Why modest:** one conditional stage + one checkpoint, run once at the start; wrong = low
frequency, low blast radius (planning runs fine without it). Only relevant for design-source
projects (the deferred front-end workstream — the photography/diet apps). See the existing
`plan/design-spec-stage-plan.md` for the stage itself; this only makes its *sequencing*
deterministic.

**The wrinkle:** the trigger lives **outside `.pipeline/`** — a `design/` dir, or a
`Design source:` line (non-"none") in `PROJECT.md`/`CLAUDE.md`, or wired Figma MCP. The driver
must read those. Keep it a pure predicate: `design-source-present` = any of the three.

**Driver changes (`next-stage.sh`), before the planning branch:**
- `design-source-present` AND no `design-spec.md` ⇒ `run:design-spec`.
- `design-spec.md` present AND no `design-approved` ⇒ `checkpoint:design` (human reviews the
  spec + its injection report; the orchestrator records `design-approved` with the currency hash
  — unchanged from SKILL 0b, the driver just sequences to the wait).
- `design-approved` present but its `design_spec_hash` ≠ current `design-spec.md` ⇒
  `checkpoint:design` again (stale — the SKILL 0c currency check, made a driver predicate).
- No design source ⇒ skip straight to planning (today's behavior).

**Context changes (`stage-prompt.sh`):** `run:design-spec` → the design-spec agent prompt;
`checkpoint:design` → the human design-review directive (never auto-approve; the marker is
orchestrator-recorded because it needs the sha256, per U-15/D1).

**Still NOT deterministic:** the design bundle→Markdown pre-conversion (`markitdown`, main-thread,
only for PDF/DOCX/PPTX) stays an orchestrator step; the human approval itself.

**Tests:** matrix rows for design-source-present × {no spec, spec-no-approval, stale-approval,
fresh-approval} → expected token; `stage-prompt` handles the two new tokens; vocabulary guard.

---

## Sequencing & recommendation

1. **P0 predicate-path fix — DONE** (see above); live adoption of the existing L1 driver is
   no longer blocked by it.
2. **Measure before Gap 1** — run a few real features on the advisory L1 driver; only build
   per-task sequencing if segmentation improvisation actually shows up as cost. It's genuine
   work (the `tasks-state.json` signal), not a quick add.
3. **Gap 2 rides the front-end workstream** — implement when design-source apps come online
   (photography/diet), alongside un-deferring design-review wiring; not worth a standalone pass.

## Non-goals

- **Enforcement (L2)** — making the orchestrator *obey* the driver rather than be advised by it.
- **Deterministic skill selection** — on-demand skill triggering stays the subagent's judgment by design.
- **The ambiguous tails** — gate-block recovery and the post-deploy CI-watch/merge phase stay prose + human (remote/stderr state, not local files).
- **App-side anything** — this is engine orchestration only.
