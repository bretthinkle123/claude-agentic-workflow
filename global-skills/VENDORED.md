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
| impeccable | github pbakaus/impeccable | `7190295f3de3` | Apache-2.0 | `global-skills/impeccable/` | **ENGINE + operational SKILL.md + generation commands ALL stripped** — vendored as a pure reference dir: `README.md` (dormant note) + `reference/audit.md` + `reference/critique.md` + LICENSE only. No active SKILL.md (the operational one drove the excluded engine). The 46 executable skill scripts NOT copied. | 2026-07-07 | upstream detector-rule changes | **VENDORED (DORMANT, reference-only)** — scan: engine phones home to impeccable.style (update check + live server), opens sockets, spawns git subprocesses, ships an edit-interception hook (`hook-before-edit.mjs`); NOT malicious but active — excluded. Not wired; activation is a future PR that re-scans any engine code. |
| frontend-design | github anthropics/claude-plugins-official `/plugins/frontend-design` | `6ec4b4020230` | Apache-2.0 | `global-skills/frontend-design/` | none (SKILL.md + LICENSE only; the plugin ships no scripts) | 2026-07-07 | plugin license/content change | **VENDORED** — scan: pure markdown, no scripts, no red flags. Re-sourced from claude-plugins-official (Apache) NOT claude-code (All-Rights-Reserved). Not yet wired to implementation (precedence rule is a follow-up). |
| skill-creator | github anthropics/skills `/skills/skill-creator` | `9d2f1ae18723` | **Apache-2.0** (per-skill LICENSE.txt) | `global-skills/skill-creator/` | eval/benchmark subsystem excluded (`scripts/*.py`, `agents/`, `eval-viewer/`) — SKILL.md + LICENSE only | 2026-07-07 | Anthropic changes the skill's license | **VENDORED** — earlier "no license" was a missed per-skill LICENSE.txt. Scan: 9 Python scripts clean (only "network" hits are dict `.get()` + a Google-Fonts link in an HTML report; subprocess calls invoke `claude -p` for its eval tooling — benign, explicit-use only). Guide vendored; harness left upstream (unused, reduces footprint). |
| design-extract | ~~github Manavarya09/design-extract~~ **404 (removed)** | — | — | — | — | — | a local-bundle token extractor appears | **BACKLOG** — primary gone; only fallback (`arvindrk/extract-design-system`, MIT) is a live-**website** scraper (fetches URLs), which conflicts with the design-spec local-bundle-only injection-safety rule. Wrong shape; revisit A-4. |

## Content imports (C-series + SK)

| name | upstream | pin | license | imported into | notes | scan date | status |
|---|---|---|---|---|---|---|---|
| grill-me (concept) | github mattpocock/skills | `8515a08` | MIT | `global-skills/requirements-elicitation/` | concept only ("relentless interview to sharpen a plan"), written house-style — NOT vendored-verbatim. Upstream grill-me SKILL.md is a 1-line trigger to a `/grilling` skill; nothing copied, no scripts touched. | 2026-07-07 | IMPORTED |
| handoff (pattern) | github mattpocock/skills | `8515a08` | MIT | `global-skills/pipeline-orchestration/` prose (U-06 warm-resume) | idea cherry-pick only, no artifact copied: "reference `.pipeline/*` artifacts by path, don't re-summarize; name the unit + skills the resumed agent needs". Upstream SKILL.md read (10 lines, no scripts). | 2026-07-07 | IMPORTED |

| ponytail (concept) | github DietrichGebert/ponytail | `main` (concept) | MIT | `global-skills/code-standards/` (YAGNI section) | anti-over-engineering heuristics (no speculative abstraction / don't reinvent stdlib / earn dependencies / no dead flexibility / delete before add) — concept adapted house-style, no text copied; balances the existing SOLID table | 2026-07-07 | IMPORTED (SK-2) |

*(SK first-pass imports append rows here as they land — see the SK build-ready addendum in
`pipeline-june-analysis.md`.)*
