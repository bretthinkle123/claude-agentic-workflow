# Plan — universal input-control enforcement (validation + rate limiting) for pipeline-built apps

## Goal & honest scope

Make the pipeline **enforce**, not merely suggest, that every application it builds has
input validation and rate limiting on its input sources. No static gate can *prove* "all
input is sanitized" (undecidable; SAST only catches known sinks), so "universal" here means
**complete accountability with no silent gaps**:

> Every input source is enumerated; each has a **validation contract** and a **rate-limit
> policy** (or an explicit, reasoned **waiver**); each has a **test** proving malformed input
> is rejected; and the **implemented** input surface cannot drift from the **declared** one.

"Input source" = anything that accepts external/untrusted input: an HTTP route with a body /
query / path params, a form, a queue/message consumer, a file/CSV ingest, a webhook receiver.

## Design principles (inherited from this pipeline)

- **Deterministic gates only** — GREEN is decided by `jq` on status files, never LLM judgment.
- **`loop-exit ≡ gate`** — reuse existing loop-exit conjuncts (`criteria_covered`,
  `security-status.status=="clean"`) so we add **no new status file** to the loop predicate
  and avoid the invariant-harness churn a third file would cause.
- **Waiver-gated, never silent** — like the B6 CVE floor and WS3-1 quality gate: a control may
  be absent only with a recorded `{reason, approved_by}`.
- **Fix the guidance that causes the bug**, not just the gate — the `api-edge-conventions`
  pre-auth/post-auth contradiction is what produced Ledgerly's IP-keyed limiter.

## The enforcement chain (each layer is deterministic or hard-flagged)

### Layer 0 — `api-edge-conventions` ordering fix (prerequisite; without it we gate a bug in)
`global-skills/api-edge-conventions/SKILL.md` currently says both *"rate limiting sits before
auth"* and *"key by authenticated identity first"* — impossible together, and the exact cause
of the IP-keyed defect. Rewrite to cleanly separate two limiter tiers:
- **Anonymous/edge throttle** — runs pre-auth, keyed on **IP** (+ path). Cheap flood defense.
- **Per-identity resource throttle** — runs **after** auth, keyed on the authenticated
  principal (userId/API key). This is the one that protects per-owner data-entry/write flows;
  it MUST run on a post-auth lifecycle hook so the identity exists at key-generation time.
State the failure mode explicitly ("a limiter on the pre-auth hook cannot see the principal
and silently falls back to IP — cross-tenant DoS + per-owner bypass").

### Layer 1 — Planning enumerates the input surface as typed criteria
`global-agents/planning.md` + `stride-threat-model-template`: for every input source, planning
emits, in `acceptance.md`, **two typed acceptance criteria** (they ride the existing
`criteria_covered` machinery — no new artifact):
- `type: validation` — the input's contract (types/bounds/allowlist) + "malformed → 4xx".
- `type: rate_limit` — the throttle policy (tier, key dimension, limit/window) **or** a
  `waiver` with a reason (e.g. "internal-only, no untrusted callers").
Planning also lists the input surface in `plan.md` so the security agent can reconcile it.
Validation is **not** waivable for an untrusted source; rate-limit is waivable with a reason.

### Layer 2 — plan-audit HARD-flags gaps (material → forces one revision, BEFORE the human gate)
`global-agents/plan-audit.md` + `dependency-audit-policy`-style checklist: today plan-audit's
validation-contract check is advisory. Promote **"every input source in `plan.md` has both a
`validation` criterion and a `rate_limit` criterion-or-waiver in `acceptance.md`"** to a
**material** flag. A material flag sets `revision_recommended: true` and the plan cannot pass
the human checkpoint un-revised. This is the "make it material, not advisory" lever — it moves
enforcement to the cheapest point (before any code is written).

### Layer 3 — Implementation builds them centrally
`global-agents/implementation.md` + `code-standards` + the fixed `api-edge-conventions`:
validation as centralized schema at the boundary; the per-identity limiter on a **post-auth**
hook. (Guidance, but now bounded by Layers 2 and 4/5 on both sides.)

### Layer 4 — Testing covers each typed criterion (reuses the existing gate)
`global-project-skills/test-conventions/SKILL.md` (WS3-2 shapes already added): each
`validation` criterion needs a malformed-input→4xx test; each `rate_limit` criterion needs the
**two-principals-one-IP** discriminating test. Because these are acceptance criteria, the
existing `criteria_covered` completeness check in `deployment-gate.sh` **and** the loop-exit
predicate already block if any is uncovered — no new gate, no invariant-harness change.

### Layer 5 — Security reconciles implemented surface vs declared (folded into `security-status`)
`global-agents/security.md` step 6f already reconciles the implemented surface against the plan,
advisorily. Make it emit a machine-readable reconciliation into `security-status.json`:
```json
"input_surface": { "declared": N, "implemented": M, "uncontrolled": [ ... ], "reconciled": true }
```
and make `status:"clean"` REQUIRE `input_surface.reconciled == true` (no implemented input
source missing from the declared set / lacking its control). Since `security-status.status ==
"clean"` is already a loop-exit AND gate conjunct, this gets deterministic teeth **for free**
— an endpoint added in implementation without a declared contract flips security to not-clean
and blocks. Semgrep OWASP-top-ten SAST stays as the injection net underneath.

### Layer 6 — Deploy gate (mostly already covered)
`deployment-gate.sh` needs **no new predicate**: Layers 4 and 5 ride `criteria_covered` and
`security-status.clean`, both already gated and mirrored. Optionally add a defensive read that
`security-status.input_surface.uncontrolled` is empty, with a clear block message.

## Files touched

| Layer | File | Change |
|---|---|---|
| 0 | `global-skills/api-edge-conventions/SKILL.md` | split anonymous-edge vs per-identity limiter tiers; fix ordering |
| 1 | `global-agents/planning.md`, `stride-threat-model-template/SKILL.md` | emit typed `validation` + `rate_limit` criteria per input source; list surface in plan.md |
| 2 | `global-agents/plan-audit.md` | promote missing input-control criteria to a **material** flag |
| 3 | `global-agents/implementation.md`, `code-standards/SKILL.md` | reference the fixed limiter tiers; central validation |
| 4 | `global-project-skills/test-conventions/SKILL.md` | (mostly done in WS3-2) tie the shapes to the typed criteria |
| 5 | `global-agents/security.md` | emit `input_surface` reconciliation; `clean` requires `reconciled:true` |
| 6 | `global-hooks/deployment-gate.sh` (+ SKILL, loop-exit-predicate.jq if a new field is gated) | optional defensive `uncontrolled==[]` check, mirrored if it touches loop-exit |
| tests | `tests/suites/gate.sh`, new `tests/suites/input-surface.sh`; fixture `security-status.json` + `test-results.json` | prove each new gate bites |

## Proving tests (the eval suites that must pass before trusting it)

- **plan-audit**: a `plan.md` with an input source but no `rate_limit` criterion/waiver →
  `revision_recommended:true` with a material flag. With a waiver → advisory only.
- **security reconciliation**: `security-status.json` with `input_surface.reconciled:false`
  (an implemented route absent from declared) → deploy gate **blocks** even at
  `status:"clean"` written naively; and the loop-exit predicate agrees (no drift).
- **criteria coverage**: a `validation`/`rate_limit` criterion left uncovered → existing
  `criteria_covered` gate blocks (regression-guard the typed criteria ride it).
- **api-edge ordering**: a doc/lint check (or a targeted test in a sample app) that the
  per-identity limiter is registered on a post-auth hook — at minimum, `test-conventions`'
  two-principals-one-IP test is required and would fail an IP-keyed limiter.
- **waiver path**: rate-limit waiver present → pass; validation waiver on an `untrusted`
  source → still blocks (validation is non-waivable for untrusted input).

## Risks / decisions to confirm

1. **Expands the hard-gate scope** (settled M1 was "advisory quality + hard perf-pairing
   only"). This is a deliberate, authorized expansion — same pattern as B6/WS3-1. Confirm.
2. **Waiver discipline** — the escape hatch must record `{reason, approved_by}`; a subagent
   must never self-write a waiver (reuse the human-only marker discipline where relevant).
3. **False-positive risk on surface reconciliation** — needs a robust way to enumerate the
   implemented input surface per stack (routes, consumers). Start with the HTTP surface (the
   90% case, already tracked in `surface-delta.md`) and expand to queues/file-ingest later.
4. **Not a static sanitization proof** — we enforce *declared contract + test + no surface
   drift + SAST*, not "every byte is sanitized." State this in docs so it isn't oversold.

## Audit outcome & industry-standard alignment (pre-implementation review)

Reviewed against **OWASP ASVS** (V5 Validation/Sanitization/Encoding, V11 anti-automation),
**OWASP API Security Top 10 2023** (API4 Unrestricted Resource Consumption = rate limiting;
API9 Improper Inventory Management = the declared-vs-implemented surface reconciliation), and
secure-SDLC exception-register practice (waiver-with-reason). It aligns. Three refinements
were folded in during implementation:
1. **Output encoding ≠ input validation.** Injection is stopped by *contextual encoding at
   the sink*, not only boundary validation. `code-standards` already mandates encoding
   (parameterized queries, autoescape, encode-for-destination); planning/test-conventions now
   call for both, and a sink-payload test shape was added.
2. **"reconciled" is agent-asserted** (like `status:clean`) — not independently provable by a
   hook. The deterministic teeth are the `input_surface.uncontrolled == []` floor (a hook
   check), plus Semgrep SAST underneath; the reconciliation itself trusts the agent, same as
   every other security-status field. Stated honestly in `security.md`.
3. **Scope = backend HTTP input surface.** Mobile/client input surfaces (deep links, IPC,
   deserialization) and **object-level authorization (BOLA — OWASP API1, the #1 production
   API risk)** are OUT of this task and recommended as the next controls to add — not implied
   to be covered.

## Implementation status — LANDED + eval-green (10/10, 173 assertions)

- **Layer 0** — `api-edge-conventions` rewritten into two limiter tiers: anonymous edge
  (pre-auth, IP-keyed) vs per-identity resource (post-auth, principal-keyed), with the
  IP-fallback failure mode spelled out. Middleware ordering updated.
- **Layer 5/6** — deterministic `input_surface.uncontrolled == []` floor in
  `deployment-gate.sh`, **mirrored** in the SKILL security predicate + `loop-exit-invariant.sh`
  SEC_PREDICATE + battery + green fixture (loop-exit ≡ gate preserved). `security.md` now emits
  `input_surface {declared, implemented, uncontrolled, reconciled}` and ties `clean` to it.
  2 new gate cases + 2 invariant rows.
- **Layer 1** — `planning.md` emits a `validation` + `rate_limit` criterion (or
  `rate_limit_waiver`) per input source, listed in plan.md for reconciliation.
- **Layer 2** — `plan-audit.md` promotes missing input-control criteria to a **material**
  flag (forces a revision before the human gate); cross-checks the rate-limit tier against
  api-edge (flags "per-owner" described as IP-keyed/pre-auth).
- **Layer 4** — `test-conventions` sink-payload (reject-or-encode) shape added; WS3-2
  two-principals-one-IP + per-constraint 4xx shapes tie to the typed criteria.

Coverage of the typed criteria rides the **existing** `criteria_covered` gate + loop-exit
(no new loop-exit file). Validation non-waivable for untrusted sources; rate-limit waivable
with a recorded reason.

## Sequencing

1. Layer 0 (api-edge ordering fix) — prerequisite, low-risk, ships alone.
2. Layers 1–2 (planning emits typed criteria; plan-audit material flag) + their eval tests.
3. Layer 5 (security reconciliation into `security-status`) + eval tests — the deterministic
   teeth for "no silent endpoint."
4. Layer 4 wiring + Layer 6 defensive check; full eval green; `install-global.sh`; PR.
5. Dogfood on a small throwaway app (an HTTP write flow + one intentionally-missing rate limit)
   to confirm plan-audit blocks, then the fixed limiter passes the two-principals test.
