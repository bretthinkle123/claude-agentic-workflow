# Pipeline eval / regression harness (M8)

Fast, deterministic, zero-LLM regression tests for the pipeline's **deterministic layer** —
the shell hooks, the deploy gate, and the `loop-exit ≡ gate` no-drift invariant. Nothing here
calls a model. It exists because every session edits `global-agents/`, `global-hooks/`, and
`global-skills/`, and until now nothing but a full manual pipeline run could catch a regression.

## Run it

```bash
bash tests/run-eval.sh        # quiet: prints failures + per-suite summary
bash tests/run-eval.sh -v     # verbose: prints every passing assertion too
```

Exit code is `0` iff every suite passes — **CI-ready** (PR L wires this as a merge-gate job).
Run it after touching anything under `global-agents/`, `global-hooks/`, or `global-skills/`.

Requirements: `bash` + `jq` (both already required by the pipeline). No `bats`/`shellcheck`
needed; if `shellcheck` happens to be installed, `static.sh` uses it, otherwise it's skipped.

## What it covers

| Suite | Asserts |
|---|---|
| `static.sh` | every hook parses (`bash -n`); every `hooks/*.sh` an agent wires exists; the gate + loop-exit predicates compile |
| `gate.sh` | `deployment-gate.sh` passes the green fixture and blocks on each failure (tests fail, criteria incomplete, **perf F1**, security not clean, missing pr-description) |
| `loop-guard.sh` | `reset`/`tick`; cycle cap + wall-clock cap → `capped` exit 2; `done` → `completed`; `done` won't overwrite `capped`; no-op outside a project |
| `loop-exit-invariant.sh` | **`deployment-gate.sh` verdict ⟺ the canonical loop-exit predicate** across a matrix, plus a substring guard that the orchestration SKILL still carries the perf-pairing clause |
| `stamp-ran-at.sh` | placeholder `ran_at` → real UTC on both artifacts; no-op on missing/unknown/outside-project; malformed JSON left unchanged |
| `record-clean.sh` | resets `debug_retry_count` iff both gates clean; no-op otherwise |

These lock in this era's gate work: **G**'s perf-completeness block, **G6**'s terminal `completed`
loop-state, and the enforced non-placeholder `ran_at`.

## How it's built

- **Golden fixture** — `fixtures/linkly-green/pipeline/` is a snapshot of the real
  `linkly-pipeline-test` run (M2 fixture #1), with **one correction**: `perf.measured.throughput_rps`
  set to `100` so the fixture genuinely passes the perf-completeness gate. The real F6 placeholder
  `ran_at` is kept on purpose — `stamp-ran-at.sh` needs it. It is stored as `pipeline/` (no dot)
  because the repo gitignores `.pipeline/`; `mk_fixture` copies it into a real `.pipeline/` in the
  workdir. Every failing case is derived from this one snapshot by `mk_fixture` (copy) + a single
  `jq` mutation — no per-case fixture files.
- Suites run the **real** hooks by absolute path from a throwaway `mktemp -d` workdir (outside any
  git repo, so the gate's currency check self-skips). `helpers/assert.sh` holds the helpers and cleans
  up every workdir on exit.
- `helpers/loop-exit-predicate.jq` is the harness's own canonical copy of the GREEN condition; it must
  stay equivalent to `deployment-gate.sh` and the orchestrator's inline jq — `loop-exit-invariant.sh`
  is what enforces that.

## Add a case / fixture

- **New gate case:** add a `gate_case <want-exit> "<desc>" '<jq-mutation>'` line in `suites/gate.sh`.
- **New golden project (fixture #2+):** drop its artifacts under `fixtures/<name>/pipeline/`
  (no dot — `.pipeline/` is gitignored), and parametrize the suites' `FIXTURE` (or add a
  fixture-name loop) — today they read `linkly-green`.
- **New invariant row:** add a `row "<desc>" '<test-mut>' '<sec-mut>'` in `loop-exit-invariant.sh`.

## Deliberately out of scope

- **Live LLM golden-runs** (running the real agents end-to-end) — slow, costs tokens, flaky; a
  separate, heavier effort.
- **gate jq-missing fail-closed** and the **currency (git-state) check** — awkward to fixture
  cheaply (PATH manipulation / a real git tree); verified manually instead.
