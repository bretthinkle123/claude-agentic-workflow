# Pipeline refinement loops

Documents planned or candidate loop patterns for the agentic pipeline. Each
entry records the design, token cost, and trigger conditions so the decision to
implement is informed rather than speculative.

---

## Planning quality loop (Haiku evaluator → Opus revision)

**Status: UNIMPLEMENTED** — documented for future consideration after trial runs
establish whether planning quality is the actual bottleneck.

### What it does

After the planning agent (Opus) writes `.pipeline/plan.md`, a lightweight Haiku
evaluator agent scores the plan against a fixed rubric before the human
checkpoint. If the score is below a threshold, it feeds specific, targeted
feedback back to the planner for one revision pass. The human then reviews the
revised plan.

```
planning (Opus) → writes plan.md
     ↓
[NEW] haiku-plan-evaluator → scores plan.md against rubric
     ↓ pass                    ↓ fail (score < threshold)
human checkpoint          planning (Opus) re-runs with
                          targeted feedback → revised plan.md
                               ↓
                          human checkpoint
```

The loop fires at most once per feature (no recursive re-evaluation). If the
revised plan still scores below threshold, the evaluator surfaces the gap to
the human rather than looping again.

### Rubric (what the evaluator checks)

1. Every layer the feature touches has a plan section — no silently omitted layers.
2. Every non-trivial decision includes what/why/how inline — no bare assertions.
3. The STRIDE threat model is present and scoped to this feature.
4. **Files affected** list is concrete and matches the per-layer sections.
5. Every acceptance criterion from `PROJECT.md`'s "done" definition is traced to
   a plan section with a ✓.
6. **Open questions** lists every unresolved point with a proposed answer.

Each criterion is binary pass/fail. A score of 5/6 or 6/6 passes. Below 5/6,
the evaluator returns the failing criteria as structured feedback.

### Token cost estimate

| Step | Model | Est. tokens |
|---|---|---|
| Haiku evaluator (reads plan.md, scores rubric) | Haiku | ~800–1,500 |
| Opus revision pass (on fail only) | Opus | ~8,000–15,000 |
| **Total on pass (no revision needed)** | | ~800–1,500 |
| **Total on fail (one revision)** | | ~9,000–17,000 |

On a $20/month Pro plan: a revision loop costs roughly the same as a fresh
planning pass. Worth it only if the human checkpoint is consistently catching
the same category of gap (e.g. missing STRIDE, untraced acceptance criteria).
If the human is rarely sending planning back for revision, the Haiku evaluator
saves real Opus rework. If the human rarely catches gaps either (plans are
already good), this adds tokens with no benefit.

### When to consider implementing

Implement after 5–10 trial runs when one or more of the following is true:

- The human checkpoint regularly sends plans back for revision on the same
  rubric items (missing STRIDE, no acceptance criteria tracing, etc.)
- Debugging loops triggered by implementation misreading the plan occur in
  more than 30% of runs
- The planning self-audit (step 8) is consistently reporting corrections,
  meaning Opus is catching its own gaps late

### Implementation notes (what would need to change when ready)

1. **New agent file** `.claude/agents/plan-evaluator.md`:
   - `model: haiku`, `effort: low`, `maxTurns: 5`
   - `tools: Read, Write`
   - Preload a skill with the rubric (or inline it — it is short)
   - Reads `.pipeline/plan.md`, writes `.pipeline/plan-eval.json`:
     `{ "score": 5, "failing": ["STRIDE missing", ...], "pass": false }`

2. **Orchestrator instruction** (pipeline-orchestration skill): insert
   `plan-evaluator` between `planning` and the human checkpoint; if
   `plan-eval.json` shows `pass: false`, re-invoke `planning` with the
   failing criteria as context before presenting to the human.

3. **Planning agent** (planning.md): add a note that `.pipeline/plan-eval.json`
   may be present when re-invoked; read it and address each failing criterion
   before re-writing `plan.md`.

4. **settings.json**: no new permissions needed (Haiku only reads/writes
   `.pipeline/` files).

5. **Cleanup**: deployment agent should delete `.pipeline/plan-eval.json` along
   with other `.pipeline/` artifacts after the PR is opened.
