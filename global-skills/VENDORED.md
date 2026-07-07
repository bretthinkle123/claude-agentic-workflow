# Vendored third-party provenance ledger

Single source of truth for everything third-party the pipeline runs or imports text from.
Created by the TA overhaul track (B-0). **Nothing third-party enters `global-skills/`
without a row here.** `tests/suites/vendored.sh` enforces the invariants below.

## Vendoring protocol (B-0)

For every item before it lands:
1. **Read every `SKILL.md` and every bundled script** at the pinned commit — "skills" can
   ship executable lifecycle hooks (ponytail) and large JS payloads (taste-skill).
2. **Copy at the pin** into `global-skills/<name>/` — never `npx <tool> install`, never a
   plugin-marketplace add, nothing self-updating.
3. **Injection-scan** the vendored text (same treatment `design-spec` gives untrusted
   bundles); record the scan date in the row.
4. **Strip** anything out of contract (note what, in the row).
5. The manifest row lands **in the same commit** as the vendored files.

**License rule:** permissive only (MIT/Apache-2.0/BSD), confirmed **per item at pin
time**. `anthropics/skills` has no discoverable license and `anthropics/claude-code` is
All-Rights-Reserved — an item's grant must be confirmed before it is vendored.

Row schema: `name | upstream (repo/path) | pin (SHA or version) | license | vendored dir |
stripped/modified | injection-scan date | re-review trigger`.

Status legend: **PINNED** = diligence done, ready to vendor · **VENDORED** = copied in and
scanned · **HOLD** = blocked (reason in row) · **RE-SOURCE** = upstream changed, needs a
new source.

---

## Vendored tools (B-series)

| name | upstream | pin | license | vendored dir | stripped | scan date | re-review trigger | status |
|---|---|---|---|---|---|---|---|---|
| repomix | npm `repomix` | 1.16.0 | MIT | — (CLI, not copied) | n/a | n/a | major version bump | PINNED |
| ast-grep | npm `@ast-grep/cli` | 0.44.1 | MIT | — (CLI, not copied) | n/a | n/a | major version bump | PINNED |
| markitdown | github microsoft/markitdown | v0.1.6 | MIT | — (CLI, not copied) | n/a | n/a | any markitdown security advisory | PINNED |
| codeburn | npm `codeburn` | 0.9.15 | MIT | — (operator machine, not agent-invoked) | n/a | n/a | new outbound host beyond LiteLLM/Frankfurter | PINNED |
| impeccable | github pbakaus/impeccable | `7190295f3de3` | Apache-2.0 | `global-skills/impeccable/` (planned, TA-2) | generation/opinion commands (keep detector rules + audit only) | pending | upstream detector-rule changes | PINNED |
| frontend-design | github anthropics/claude-plugins-official `/plugins/frontend-design` | `6ec4b4020230` | Apache-2.0 | `global-skills/frontend-design/` (planned, TA-2) | none planned | pending | plugin license/content change | PINNED |
| skill-creator | github anthropics/skills `/skills/skill-creator` | `9d2f1ae18723` | **UNCONFIRMED** | — | — | — | Anthropic publishes a clear license | **HOLD** — no discoverable LICENSE at anthropics/skills (root or per-skill), 2026-07-07; do not vendor until the grant is confirmed permissive |
| design-extract | ~~github Manavarya09/design-extract~~ **404 (removed)** | — | — | — | — | — | evaluate MIT fallback `arvindrk/extract-design-system` | **RE-SOURCE** — primary gone since audit; fallback is a simpler token extractor, eval before adopting (TA-2 / A-4) |

## Content imports (C-series + SK)

| name | upstream | pin | license | imported into | notes | scan date | status |
|---|---|---|---|---|---|---|---|
| grill-me (seed) | github mattpocock/skills | *(pin at import)* | MIT | `global-skills/requirements-elicitation/` (planned, TA-3 / A-1) | ported house-style, NOT vendored-verbatim; repo contains shell scripts — full read-through required | pending | PLANNED |
| handoff (pattern) | github mattpocock/skills | *(pin at import)* | MIT | `global-skills/pipeline-orchestration/` prose (planned, TA-3 / C-2) | idea cherry-pick only; no artifact copied | pending | PLANNED |

*(SK first-pass imports append rows here as they land — see the SK build-ready addendum in
`pipeline-june-analysis.md`.)*
