# Plan — data-classification + at-rest protection enforcement for built apps (DP side-track)

> **Status: spec, awaiting approval.** Forward-looking design; nothing built yet. Scope is the
> **security of the app the pipeline builds** (like input-controls / BOLA), NOT the engine.
> Builds on existing controls (Checkov at-rest, `logging-conventions` redaction,
> `secrets-management`, `auth-patterns`, ASVS 6g) — it makes them **accountable**, not
> duplicative.

## Goal & honest scope

Make the pipeline **enforce**, not merely advise, that every stored field carrying sensitive
user data has a named protection control (at-rest encryption, a password KDF, or a reasoned
waiver) — with complete accountability and no silent gaps. Mirrors the input-surface model:

> Every stored field is **classified**; each sensitive field has a **declared protection
> mechanism** (or an explicit, reasoned **waiver**); a **test** proves the persisted form is
> protected; and the **implemented** storage surface cannot drift from the **declared**
> classification.

No static gate can prove "all sensitive data is encrypted" (undecidable; the app can always
write plaintext somewhere a scanner can't see). "Enforce" here means **accountability with no
silent gap**, the same honest bar as `input-controls-enforcement-plan.md`.

## The gap it closes (why the current state isn't enough)

Today, at-rest/in-transit protection is **guided + partially forced**, with one real hole:
- **Forced (infra only):** `iac-conventions/baseline.md` makes S3/RDS/DynamoDB **SSE** and
  **TLS** `critical`, and the security agent's Checkov run over `infra/` blocks an unencrypted
  bucket/DB. Strong — but only when the app has an `infra/` dir, and only at the *storage-service*
  level (disk SSE), not per-field.
- **Guided (advisory):** ASVS **V11** (crypto — password KDF 11.4.2) / **V14** (data protection)
  / **V12** (TLS) are verified by the security agent's step 6g at the *declared* level.
- **The hole:** a **sensitive field that is not directly exploitable** — e.g. an unencrypted
  PII/health/financial column sitting behind auth — is a **non-exploitable ASVS gap**, which 6g
  dispositions as a **warning**, and **warnings do not block**. So it **ships**. SSE (disk) does
  not protect that column against an app-level read or a compromised query; only field-level
  (application-layer) encryption does, and nothing forces it. A Firebase / managed-DB app with
  **no `infra/`** gets no deterministic at-rest check at all.

This item closes that hole: a sensitive field without a protection mechanism becomes a
**deterministic block**, not a warning — regardless of exploitability.

## Design principles (inherited)

- **Deterministic gates only** — the block is `jq` on a status field, never LLM judgment.
- **`loop-exit ≡ gate`** — reuse `security-status.status=="clean"` + `criteria_covered`; add at
  most one new gated conjunct, mirrored into the loop-exit predicate + invariant harness (the
  input_surface precedent, already merged).
- **Waiver-gated, never silent** — a field may lack a control only with a recorded
  `{reason, approved_by}` (e.g. "pseudonymous analytics id, no PII").
- **Accountability, not proof** — teeth depend on honest classification (same caveat as
  input_surface); a misclassified field passes, so the material plan-audit flag + human review
  are the backstops. Semgrep/Checkov stay the nets underneath.
- **App scope, not engine** — this hardens built apps; distinct from the engine egress work.

## Layer 0 — the classification taxonomy (prerequisite: a `data-protection-conventions` skill)

A new **on-demand** skill (loaded by planning + implementation + security when a feature stores
user data) defines the taxonomy + the control per class. Maps to ASVS V14/V11 + `secrets-management`:

| Class | Examples | Required at-rest control | In transit | In logs |
|---|---|---|---|---|
| **Credential/secret** | password, API key, OAuth token, session secret | password → **slow KDF** (delegate to Firebase, else argon2/bcrypt — ASVS 11.4.2); other secrets → **not stored** (fetch at runtime, `secrets-management`) or field-encrypted | TLS | never logged (6e) |
| **Sensitive/regulated PII** | SSN, health, financial account, precise geolocation, biometrics | **field-level (application-layer) encryption** — envelope encryption via **AWS KMS** (per-record/table data key, wrapped by a CMK), **on top of** SSE | TLS 1.2/1.3 | never logged; hashed/opaque ref only |
| **Personal data** | email, name, phone, address | **SSE at rest** (infra, Checkov-forced) + a field-encryption *option* at L3 | TLS | hashed/opaque (`logging-conventions`) |
| **Non-sensitive** | public content, non-PII config | none required | TLS (default) | fine to log |

The skill also carries the **crypto-facade rule** (route all encryption/decryption/hashing
through one module, never inline crypto — `code-standards` facade) and the KMS key-access
pattern (`secrets-management`).

## The enforcement chain (each layer deterministic or hard-flagged)

### Layer 1 — Planning classifies the storage surface as typed criteria
`planning.md` + the new skill: for every stored field/table the plan introduces, planning
records its **class** in `plan.md`'s Data section and emits, in `acceptance.md`, a
`data_protection` criterion per **sensitive** field (credential / sensitive-PII / personal):
the class + the named at-rest mechanism (KDF | KMS field-encryption | SSE) + "persisted form is
not plaintext", **or** a `data_protection_waiver: <reason>`. These ride the existing
`criteria_covered` machinery — no new artifact.

### Layer 2 — plan-audit HARD-flags gaps (material → one revision, before the human gate)
`plan-audit.md`: promote **"every field classified sensitive has a named at-rest mechanism (or
reasoned waiver), and the plan states the data classification for each stored field"** to a
**material** flag. A sensitive field with no mechanism sets `revision_recommended: true` — the
cheapest enforcement point, before any code. (Same lever as the input-surface + BOLA material flags.)

### Layer 3 — Implementation builds them through a crypto facade
`implementation.md` + the new skill + `secrets-management`: password hashing via the auth
provider (Firebase default) or a hashing facade; sensitive-PII via a **KMS-backed
envelope-encryption facade**; personal data via SSE declared in `infra/`. All crypto behind one
facade, never inline. Emit the storage surface in `surface-delta.md` (extend it with a
data-sink category).

### Layer 4 — Testing covers each typed criterion (reuses the existing gate)
`test-conventions`: each `data_protection` criterion needs a **persisted-form test** — write
the value through the repository, read the raw stored column/blob, and assert it is **not the
plaintext** (ciphertext or hash), while the app's normal read still round-trips (decrypt/verify
works). For passwords: the stored column is a KDF hash, and verify succeeds but the plaintext is
absent. Because these are acceptance criteria, the **existing `criteria_covered` gate +
loop-exit already block** if any is uncovered — no new gate for this layer.

### Layer 5 — Security reconciles implemented storage surface vs declared (folded into `security-status`)
`security.md` (extend 6f/6g): enumerate the **implemented** storage surface (ORM models/columns,
file writes, cache entries, exported blobs). For each field, reconcile its implemented protection
against the declared class — verify the named mechanism is actually present in the diff (a KDF
call, a KMS `encrypt`, SSE in `infra/`). List any **sensitive** field that can't be reconciled to
a mechanism-or-waiver in a new `data_surface.unprotected` array, and tie `status:"clean"` to it
being empty:
```json
"data_surface": { "classified": N, "sensitive": M, "unprotected": [ ... ], "reconciled": true }
```

### Layer 6 — Deploy gate + loop-exit (the deterministic teeth)
Add a floor to `deployment-gate.sh`: block when `(.data_surface.unprotected // []) | length > 0`
— **mirrored** into the SKILL security predicate + `loop-exit-predicate.jq` + the
`loop-exit-invariant.sh` `SEC_PREDICATE` + battery + green fixture, exactly as `input_surface`
was (so loop-exit ≡ gate holds). This is what converts the current *warning* into a *block*: a
sensitive field shipped without its declared protection flips security to not-clean and blocks,
**regardless of exploitability** — closing the hole above. The Checkov at-rest/TLS criticals stay
as the infra-layer floor underneath.

## Status-file + harness impact (honest cost)

- Adds one gated conjunct (`data_surface.unprotected == []`) to `security-status.json`, the same
  shape and cost as the already-merged `input_surface` clause: gate + SKILL + `predicate` (note:
  it's a security field, so it lives in the SEC predicate, not `loop-exit-predicate.jq`) +
  `loop-exit-invariant.sh` battery + green fixture. ~2 new gate cases + ~2 invariant rows.
- **Accountability, not proof:** teeth depend on the security agent honestly enumerating +
  classifying the storage surface. A misclassified field (agent thinks it's non-sensitive) passes
  silently — the material plan-audit flag (Layer 2) and human diff-review are the backstops. Same
  honest posture as input_surface.

## Non-goals

- Not full DLP / not proving every byte is encrypted (undecidable).
- Not key-management/rotation policy beyond naming KMS + `secrets-management` (rotation is those
  skills' job; DR/backup encryption is Track-2 infra).
- Not an LLM-judged gate — the floor is `jq` on a field the agent populates; classification is the
  agent's analysis, the *block* is deterministic.
- Not the engine egress work (separate — `docs/egress-control-plan.md`).

## Sequencing (each slice independent; none on the critical path)

1. **Layer 0** — write the `data-protection-conventions` skill (taxonomy + facade + KMS pattern). **S.**
2. **Layers 1–2** — planning emits `data_protection` criteria; plan-audit material flag. Catches most
   gaps before code, no gate change yet. **S–M.**
3. **Layer 4** — persisted-form test shape in `test-conventions` (rides `criteria_covered`). **S.**
4. **Layers 5–6** — security `data_surface` reconciliation + the deterministic floor + harness
   update (the input_surface pattern). The teeth. **M.**

## ASVS / threat-model tie-in

Directly implements the verifiable side of ASVS **V14** (data protection: classification +
per-level controls) and **V11.4.2** (password KDF), and complements **V12** (TLS). Update the
`stride-threat-model-template` Information-Disclosure prompts to require, per stored sensitive
field, a named at-rest control — so the plan's threat model carries it as a concrete mechanism
(6d-verifiable), not the abstract "unencrypted storage" it prompts for today.
