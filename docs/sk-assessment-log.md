# SK — skill-enrichment assessment log

Records the SK first-pass assessments (planning → implementation → security preloads +
their shared on-demand skills), per the SK method: every preloaded skill gets either a
merged enrichment diff **or** a logged "already sufficient" assessment. Delta-only —
enrichment lands only when a public source has an additive technique our skill lacks
**and** it clears the token bar (preloaded skills pay on every invocation). Sources are
permissively licensed (MIT/Apache/BSD); provenance for anything imported is in
`global-skills/VENDORED.md`.

## First pass (2026-07-07)

| Skill | Agent · load | Sources checked | Outcome |
|---|---|---|---|
| `code-standards` | implementation · **preload** | ponytail (MIT), mattpocock code-review/tdd | **ENRICHED** — added a YAGNI / anti-over-engineering section (ponytail concept) as the missing counterweight to the SOLID table. tdd content already covered by TA/A-2 (test-first). Commit 499a970. |
| `stride-threat-model-template` | planning · **preload** | MS Threat Modeling, OWASP Threat Modeling cheat sheet, community STRIDE skills | **already sufficient** — ours already carries full ASVS 5.0 chapter mapping, a severity rubric, and the U-02 "enabling-conditions-not-just-names" rigor (RLS FORCE, IP-throttle derivation, scrubber scope) that no public STRIDE skill has. The abuse-case/attacker-persona angle is functionally covered by the per-category trigger prompts; adding it would not clear the preload bar. |
| `semgrep-ruleset-guide` | security · **preload** | — | **already sufficient** — a project-specific stack→config template + severity mapping; pipeline mechanics with no public analog to import. |
| `diff-scoping-conventions` | security · **preload** | — | **already sufficient** — the pipeline's change-set + hash mechanic; no public prior art. |
| `api-edge-conventions` | shared · on-demand | OWASP API Security Top 10 (2023) | **already sufficient** — covers the edge-relevant items (rate-limiting, security headers, CORS, error envelope, idempotency, outbound resilience); the authz items (BOLA/BFLA) live in STRIDE V8 + ASVS-DET by design, not the edge skill. |
| `auth-patterns` | shared · on-demand | OWASP ASVS V6/V7, Auth cheat sheets | **already sufficient** — facade + OAuth + two Duo MFA paths + custom-claim contract + guard ordering; session rotation/logout is handled at the ASVS-DET layer (T2-4), not duplicated here. |
| `logging-conventions` | shared · on-demand | OWASP Logging cheat sheet | **already sufficient** — facade, standard fields, levels, traceId, audit categories, 5W+H, immutability, PII rules — already exceeds the public cheat sheet. |
| `data-protection-conventions` | shared · on-demand | OWASP Cryptographic Storage cheat sheet | **already sufficient** — classification taxonomy → per-class control + crypto-facade + the layered plan/test/reconcile flow; pipeline-integrated beyond the generic guidance. |
| `secrets-management` | shared · on-demand | OWASP Secrets Management cheat sheet | **already sufficient** — fetch-at-runtime facade + forbid-list + cache/rotate + store-credential bootstrap. |
| `ddia-patterns` | shared · on-demand | Designing Data-Intensive Applications | **already sufficient** — already a condensed decision guide distilled from the source book. |

**First-pass conclusion:** the pipeline's skills are mature (iterated through M1–M3 + several
audits), so the genuinely-additive public deltas are few. One clear win landed
(`code-standards` YAGNI); the rest are logged sufficient. This is the honest delta-only
outcome — SK does not pad a preloaded skill to look busy.

## Later pass (deferred)
The remaining agents (`plan-audit`, `testing`, `documentation`, `deployment`, `debugging`)
and their skills — assess when the first pass's value is proven, per the SK addendum. Note
`test-conventions` already gained the TA/A-2 authorship-split section; any SK enrichment
there must build on that.
