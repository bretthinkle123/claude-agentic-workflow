# Agent-eval corpus (U-23) — planted-defect golden trees

The deterministic gates verify what agents *report*; nothing evals the agents themselves.
A prompt regression in `security.md` (or a model change) that silently degrades detection
would today surface only on the next real run's /code-review — the exact M3 blind spot,
recurring invisibly on every engine edit. This corpus closes that: each case is a small,
frozen tree with a **planted, documented defect**, and `run-agent-evals.sh` invokes the
REAL agent against it and asserts (deterministic grep over the agent's output artifacts)
that the finding is named.

## Why this isn't in `tests/run-eval.sh`

The deterministic harness is zero-LLM. Running an agent needs model access, so the eval
RUNNER is a separate step (CI job with an API key, or manual: `bash
tests/agent-evals/run-agent-evals.sh`). What the deterministic harness DOES check
(`static.sh`): every case dir is well-formed — has a planted defect and an
`expected-findings.json` manifest. The manifest is the contract; the runner is the
execution.

## Corpus

| Case | Agent under test | Planted defect (origin) | Must be flagged |
|---|---|---|---|
| `security-topology/` | security | Tier-1 throttle keyed on `request.client.host` behind an ALB, no proxy-header trust (R1-2) | topology efficacy |
| `security-rls/` | security | RLS `ENABLE` (not FORCE) while the app role owns the table (R1-1) | DB-privilege efficacy |
| `security-append-only/` | security | events "append-only" claim with UPDATE/DELETE granted (R1-9) | DB-privilege efficacy |
| `security-async/` | security | Argon2id verify sync on the event loop in an async handler (R1-4) | async-runtime efficacy |
| `security-scrub/` | security | Sentry before_send scrubs headers/body but not query_string (R1-7) | contract-drift efficacy |
| `security-crash-control/` | security | a hardcoded secret (the crash-class control the scanners MUST catch) | secret / SAST |
| `plan-audit-proof-claim/` | plan-audit | a plan asserting a filter is "provably implied" by an invariant enforced nowhere (R2-1) | proof-claim material flag |
| `plan-audit-crossfeature/` | plan-audit | a dashboard plan reading per-key rollups with a reader key that owns no rows (R3-1) | cross-feature data-flow material flag |
| `doc-invented-name/` | documentation | a README naming a nonexistent function + a wrong signature on a real one (R2-5/R3-5) | doc-identifier resolution |
| `testing-dead-knob/` | testing | an env knob whose only test pins it to the constant default; nothing ever sets it (R2-9/R2-10, M4 #4) | dead-flexibility gap in test-quality.json |
| `testing-vacuous-failclosed/` | testing | a fail-closed test whose monkeypatch raises BEFORE the state mutation — "row survives" is vacuously true, rollback never exercised (M4″ #2, ledger F4-02) | vacuity named in test-quality.json (adversarial gap or falsifiability.unfalsifiable) |
| `impl-k6-fork/` | implementation | an env-parameterized k6 harness + a plan asking for a new scenario — will the agent extend or fork? (R2-7/R3-7, M4 #3) | inverted: `check-no-fork.sh` exit 0 (U-21) |

## Contract: `expected-findings.json`

```json
{
  "agent": "security | plan-audit | documentation",
  "prompt": "the invocation prompt for the runner",
  "must_flag": [
    { "id": "topology", "grep": "request.client.host|ProxyHeaders|forwarded", "where": "security-report.md" }
  ],
  "planted_marker": "a string that MUST exist in the tree (proves the defect is present, so a green eval means caught-not-absent)"
}
```

The runner: (1) asserts every `planted_marker` exists in the case tree (the defect is
really there); (2) invokes `agent` with `prompt` in a copy of the tree; (3) asserts each
`must_flag[].grep` matches in the named output artifact. A case passes iff the agent
NAMED every planted defect. Retry-once on a flaky LLM miss before failing.

## Hard rule

These trees contain real vulnerability shapes. They live ONLY here, are excluded from
`install-global.sh` publishing and every template/bootstrap path, and the runner operates
on read-only copies — a planted defect must never enter a bootstrapped pipeline project.
