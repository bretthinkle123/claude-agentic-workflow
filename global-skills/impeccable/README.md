# impeccable — vendored DORMANT (audit reference only)

Not an active skill. Vendored (TA/B-9) from `pbakaus/impeccable@7190295` (Apache-2.0)
as **reference material only** for a future design-review PR — it is **not wired to any
agent** and nothing here executes.

## What is here
- `reference/audit.md`, `reference/critique.md` — the design audit/critique methodology
  and the anti-pattern rule catalog (each rule tagged `<!-- rule:skill-... -->`).
- `LICENSE` — upstream Apache-2.0.

## What was deliberately EXCLUDED at vendor time (2026-07-07)
The upstream repo is a full product (marketing site, browser extension, Cloudflare
functions, CLI). Its skill ships **46 executable scripts** — a detector/live-browser/hook
engine that **phones home** to `impeccable.style` (update check + a live-editing server
that polls with tokens), opens raw sockets, spawns git subprocesses, and installs an
**edit-interception hook** (`hook-before-edit.mjs`). Not malicious, but an active,
network-touching footprint. None of it is vendored, and the operational `SKILL.md`
(which drives that engine) is intentionally omitted.

## Activation (future PR — out of scope here)
When the detector rules are wired into `global-hooks/design-review-check.sh` as a second
advisory signal, that PR must re-fetch, re-scan, and sandbox any engine code it needs —
it does not inherit trust from this dormant reference drop. See `global-skills/VENDORED.md`
for the full provenance + scan record.
