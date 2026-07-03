# Plan — default-deny egress control for the pipeline engine (EG side-track)

> **Status: spec, awaiting approval.** Forward-looking design; nothing here is built yet.
> Companion to `docs/pipeline-threat-model.md` (this *upgrades* one of its stated accepted
> residuals). Scope is the **pipeline engine as target** — NOT the built app's SSRF/outbound
> controls, which `api-edge-conventions` + `code-standards` already own. Keep the two scopes
> distinct (same discipline as PR K).

## Goal & honest scope

Replace the pipeline's current **`Bash(curl:*)` = unrestricted egress** with **default-deny,
allow-listed network egress** for the agent workload, so a prompt-injected agent cannot
exfiltrate data or fetch a hostile payload to a host the pipeline has no legitimate reason to
reach. "Egress control" here means **complete accountability with no silent path out**:

> Every outbound destination the pipeline needs is enumerated in an allow-list; everything
> else is denied by default; a denied attempt is logged as a security signal, not silently
> dropped or silently permitted.

No control can prove "the model will never be injected" (that is the open problem). This makes
injection **non-actionable for the most common payload — data exfiltration** — by removing the
route out, the same "contain the blast radius" posture the rest of the engine already takes
(deterministic gates, no secrets in the tree, per-agent tool scoping).

## The threat it closes (and the residual it upgrades)

`docs/pipeline-threat-model.md` §4 currently **accepts** "`curl` egress is unrestricted …
because the working tree holds no secrets to exfiltrate; the machine credential is outside the
repo." That acceptance is only valid while **nothing sensitive ever transits the tree** — which
breaks the moment:
- a project **consumes a runtime secret** during a test (DB password, API key fetched per
  `secrets-management`), so a value is briefly in memory/files an injected agent can read; or
- the pipeline is pointed at the **[[redteam-app-goal]]** build, where it deliberately ingests
  adversarial, injection-laden content and handles security-sensitive material.

For both, "nothing to steal" stops holding, so the residual needs to become a **control**. This
item is the natural follow-on to **PR K** (which threat-modeled the engine) and a hard
precursor to the red-team app work.

## Design principles (inherited from this pipeline)

- **Default-deny, allow-list from evidence** — never guess the allow-list; derive it from a
  real run with egress *logged* first (same measure-first rigor as the perf-scenario and
  hash-determinism work).
- **Deterministic, not model-judged** — enforcement is a proxy/firewall + shell, never an LLM
  deciding "is this host ok." An injection can't argue with a default-deny ACL.
- **Don't break legitimate egress** — the pipeline genuinely needs the registries + scanner
  vuln-DBs; a control that blocks those just trains people to disable it.
- **Engine ≠ app scope** — this hardens the *factory*. The app's own outbound/SSRF allow-list
  is a per-feature control the app's plan + `api-edge-conventions`/`code-standards` produce.

## The allow-list (starter set — CONFIRM empirically in Phase 0)

The destinations the pipeline provably needs today (derive the authoritative list from the
Phase-0 logging run; this is the expected shape, not the final ACL):

| Consumer | Destination(s) | Why |
|---|---|---|
| plan-audit dependency reality-check | `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org` | anti-slopsquatting registry lookups (`dependency-audit-policy`) |
| security — OSV | the OSV database source (`osv.dev` / its GCS bucket) | dependency CVE scan |
| security — Semgrep (Docker) | Docker Hub (`registry-1.docker.io`, `auth.docker.io`), `semgrep.dev` | pull `semgrep/semgrep` + fetch `--config` rulesets |
| security — Trivy (Docker) | Docker Hub, `ghcr.io` (`ghcr.io/aquasecurity/trivy-db`) | pull `aquasec/trivy` + vuln DB |
| deployment (`gh`/git) | `github.com`, `api.github.com`, `codeload.github.com` | push + open PR |
| implementation package installs / context7 MCP (if enabled) | npm/PyPI as above; the context7 endpoint if the project wires it | dependency install; current-library-API lookups |
| the Claude Code runtime itself | `api.anthropic.com` | the harness (out of the sandbox scope — see below) |

Anything not on the confirmed list is denied.

## Enforcement — four layers, each deterministic

### Layer 0 — Enumerate (prerequisite; log, don't block)
Run one full pipeline (a representative project) with **egress logging on and blocking off** —
capture every outbound host from the agent workload (a logging forward-proxy, or Docker
network logging on the scanner containers). Output: `egress-allowlist.txt` (the confirmed set
above, plus anything real the run surfaces). Without this, Layer 2 either over-blocks (breaks a
scanner) or under-blocks (misses a real path). This mirrors the "measure the real artifacts"
discipline used for the gate designs.

### Layer 1 — Command-level tighten (cheap, immediate, PARTIAL)
In the per-project `templates/project-settings.json` allow-list, replace the blanket
`Bash(curl:*)` with **host-scoped** entries and drop other fetchers from the allow-list
(`wget`, etc.). Honest about its weakness: Claude Code permission matching is prefix-based on
the command string, so it is **bypassable** (flag reordering, a Docker `run` that curls from
inside, python `requests`, node `fetch`). Ship it as documented defense-in-depth + intent, and
say so — it is **not** the boundary; Layer 2 is.

### Layer 2 — Network-level default-deny egress proxy (the REAL boundary)
Route the network-touching workload through a **default-deny forward proxy** whose ACL is
`egress-allowlist.txt`; agents' environment carries `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`, and
direct routes out are removed so the proxy is the only path. Concretely on this stack:
- **Scanner containers** (`semgrep-scan.sh`, `trivy-scan.sh`, `generate-sbom.sh`) already run
  via `docker run` — attach them to a **restricted Docker network** whose only egress is the
  allow-listing proxy container (e.g. an ACL-configured `squid`/`tinyproxy`), instead of the
  default bridge. This is the highest-value, lowest-friction slice because the scanners are the
  fattest, most-automatable egress.
- **Agent host commands** (`curl` in plan-audit, `gh`/git in deployment, package installs in
  implementation) get `HTTPS_PROXY` pointed at the same proxy.
- Default action: **deny + log**. A `429`/blocked destination returns a clear error the agent
  surfaces (never a silent skip — same rule as "Docker not running" surfacing).

### Layer 3 — Detection (surface denied attempts)
The proxy logs every allow/deny to a pipeline artifact (`.pipeline/egress-log.jsonl`); a
**denied attempt to a non-allow-listed host is a security signal** the security agent folds
into its report (a warning at minimum; a repeated/exfil-shaped attempt is escalated). This
turns "was there an injection attempt?" from invisible into an auditable line, consistent with
the run-log/telemetry posture.

## Windows / Docker Desktop reality (the main friction)

Network-layer egress control is materially easier on Linux than on Windows+Docker Desktop.
Honest options, cheapest first:
- **Scanner-container network restriction (Layer 2, container slice)** works today on Docker
  Desktop — a custom Docker network + proxy container is portable. Do this first; it covers the
  automatable bulk of egress.
- **Host-command proxying** via `HTTPS_PROXY` works for `curl`/`gh`/`pip`/`npm` but relies on
  each tool honoring the proxy env (most do) — belt-and-suspenders, not airtight.
- **Cleanest substrate:** run the pipeline's shell workload under **WSL2**, where Linux egress
  firewalling (nftables/`iptables` default-deny with an allow-list, or a transparent proxy) is
  straightforward. Flag WSL2 as the recommended enforcement host if strong guarantees are
  wanted; keep the Docker-network slice as the portable default otherwise.
- The `api.anthropic.com` traffic is the **Claude Code runtime**, not the sandboxed workload —
  keep it out of scope (blocking it breaks the pipeline); the control targets the *tools the
  agents invoke*, not the model transport.

## Non-goals

- Not an app-side SSRF/outbound control (that stays in `api-edge-conventions`/`code-standards`).
- Not a full per-agent filesystem sandbox (a separate, larger threat-model residual — note it,
  don't bundle it).
- Not an LLM-judged allow-list. The ACL is static config; only shell/proxy enforces it.
- Not a guarantee the model won't be injected — a blast-radius reducer, stated as such.

## Sequencing (each slice ships independently; none on the critical path)

1. **Layer 0 (enumerate)** — one logged run → `egress-allowlist.txt`. **S.**
2. **Layer 1 (command-level tighten)** — host-scoped `Bash(curl …)` in `project-settings.json`;
   document it as partial. **S.**
3. **Layer 2, container slice** — scanner containers on a restricted Docker network behind an
   allow-listing proxy. The real boundary for the fattest egress. **M.**
4. **Layer 3 (detection)** — `.pipeline/egress-log.jsonl` + a security-agent warning on a denied
   host; optional `tests/` assertion that the proxy denies a non-allow-listed host. **S.**
5. **Layer 2, host slice + WSL2 note** — `HTTPS_PROXY` for host commands; document WSL2 as the
   strong-guarantee substrate. **M.**

## Threat-model update on completion

When Layers 2–3 land, edit `docs/pipeline-threat-model.md` §4: the "`curl` egress is
unrestricted (accepted)" residual becomes "egress is **default-deny allow-listed** (Layer 2)
with **denied-attempt logging** (Layer 3)"; the remaining residual narrows to "a legitimately
allow-listed host is itself the exfil channel" (e.g. abusing a permitted registry) — a much
smaller, statable surface. Add an `egress` row to the STRIDE table under Information Disclosure.
