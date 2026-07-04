# Pipeline MCP Configuration (companion to agentic-pipeline-plan.md)

**Status:** documentation-only. Nothing here loads at runtime unless you wire a
server into `.mcp.json` and grant a subagent access to it. Treat MCP as opt-in
per agent, never global.

---

## Current wiring decision (2026-06-25) — read this first

After an agent-by-agent audit, only **three** servers earn their tokens, and they
are wired to be **project-scoped, exactly like project skills** — defined per
project in a root `.mcp.json` (copy `templates/mcp.json`, keep only what that
project needs, pin versions/digests), never baked into the portable agents. A
project with no `.mcp.json` loads **zero** MCP. The agents only carry the `tools:`
allow-list entries; those resolve to nothing unless the project opts in.

| Server | Wired to (agent `tools:`) | When it pays off |
|---|---|---|
| **Context7** | implementation only | Current library APIs — avoids wrong-API write/fail/rewrite. Not on planning (no benefit for architecture reasoning). |
| **AWS Knowledge** | planning, implementation | Only on AWS-infra projects (replaces huge `WebFetch` doc dumps). |
| **Terraform** | planning, implementation | Only on `infra/` projects (exact provider args → fewer plan failures). |
| **Figma (Dev Mode MCP)** | **design-spec only** | Only on a project whose design source is a live Figma file — streams component/layout/token metadata for the design-spec normalization instead of eyeballing a static export. Off (zero schema) on any project that ships a `design/` folder or screenshots instead. **Its results are untrusted** (a layer/node name can be an injected instruction) — they flow into `design-spec.md`'s injection report, never into a gate. |

**Security gets no MCP.** Its work is deterministic — it runs Semgrep/OSV/Checkov
(shell) and reports the counts; it doesn't research provider docs, so loading
aws-knowledge/terraform schemas there bought nothing. (Briefly wired then dropped
2026-06-26.)

**Deliberately NOT wired (vanity / replaced / out-of-scope for this pipeline):**
GitHub MCP (the `gh` CLI already does the deploy agent's PR + costs no schema),
Sentry (the pipeline fixes *local* failures pre-merge — no prod issues in the loop),
Firebase MCP (30+ tool schemas; the `auth-patterns` skill already covers the code
side), Playwright MCP (a11y snapshots are 2k–10k tokens/step — a budget hazard;
specs are authored from reading code). SAST stays a deterministic shell hook, never MCP.

Sections §2–§4 below retain the full roster and rationale as background; where they
disagree with this box, **this box is authoritative.**

---

## 0. The token-economics rule (read first)

An MCP server's tool **schemas load into the context of every agent that can see
it** — before it saves a single token. So a server is only a net win when it
replaces a *verbose, multi-step* pattern (read-whole-doc, dump-full-CLI-output,
exploratory grep) with **one targeted query**.

Three enforcement levers, used everywhere below:

1. **Scope per agent, never globally.** A subagent only loads schemas for the
   tools in its frontmatter `tools:` allowlist. Unlisted server = zero schema
   cost for that agent. This is the primary token-discipline mechanism.
2. **Enable only the toolsets you use.** Most first-party servers let you turn
   off tool groups (e.g. GitHub `--toolsets pull_requests,actions`).
3. **Read-only by default.** Separate server entries for read vs write so the
   write token only exists where mutation is intended (deployment).

> Verify exact tool names with `/mcp` (or the server README) before pasting them
> into `tools:` allowlists — the `mcp__server__tool` names below are
> representative, not guaranteed verbatim.

---

## 1. Server roster (all first-party / widely-vetted)

| Server | Maintainer | What it replaces | Trust notes |
|---|---|---|---|
| **Context7** | Upstash | Reading whole doc files / guessing library APIs | Widely used; hosted remote option; pin version |
| **GitHub MCP** | GitHub (`github/github-mcp-server`) | Parsing verbose `gh` CLI text | Official; Docker; read-only mode + per-toolset scoping |
| **AWS Knowledge MCP** | AWS (`knowledge-mcp.global.api.aws`) | `WebFetch` dumping whole AWS doc pages | First-party, **GA, fully-managed remote**; superset of docs (regional availability, Well-Architected, CDK). No AWS account needed. **Preferred over the local Documentation MCP.** |
| **AWS Knowledge MCP** *(alt)* | AWS Labs (`awslabs/mcp`) | same as above, local | Lighter local-only fallback if you can't reach the remote endpoint; take ONLY the Documentation server from the suite |
| **Terraform MCP** | HashiCorp (`hashicorp/terraform-mcp-server`) | Reading provider/module docs, guessing resource args | First-party; registry (providers/modules/policies) lookup is read-only |
| **Sentry MCP** | Sentry (`mcp.sentry.dev`) | Streaming logs into context to find one error | Official; remote; OAuth |
| *(optional)* **Firebase MCP** | Google (`firebase-tools experimental:mcp`) | Guessing Firebase Auth/Firestore APIs & config | Official, GA. **30+ tools** — only worth it scoped to the auth toolset; opt-in, not default-on |
| *(optional)* **Playwright MCP** | Microsoft (`microsoft/playwright-mcp`) | Hand-rolled browser drivers | Official but **token-heavy** (a11y snapshots are large) — opt-in |

---

## 2. Per-agent mapping

Token rationale is the concrete waste each server removes for *that* agent.

### 1. Planning
- **Context7**, **Terraform MCP** (read), **AWS Knowledge MCP**
- *Why:* the heaviest doc-retrieval agent. Pulls version-pinned API snippets and
  exact Terraform provider/module schemas on demand instead of loading full docs.
- *Token win:* kills the "read big doc → still guess → re-read" spiral up front,
  where it's cheapest to fix.

### 2. Implementation
- **Context7**, **Terraform MCP** (read), **AWS Knowledge MCP**
- *Why:* writing code/HCL against real, current APIs.
- *Token win:* eliminates wrong-API retries (write → fail gate → re-read → rewrite).

### 3. Debugging
- **Sentry MCP**, **Context7**
- *Why:* fetch one specific issue's stack/context; confirm library behavior.
- *Token win:* one issue object vs. piping log files into context.

### 4. Security
- **AWS Knowledge MCP**, **Terraform MCP** (read), **GitHub MCP (read-only)**
- *Why:* IAM/policy patterns, provider security args, and pulling **specific**
  code-scanning / secret-scanning / Dependabot alerts.
- *Token win:* targeted alert objects vs. scanning the tree; feeds your
  deterministic `security-status.json` instead of bloating LLM context.
- *Note on SAST (Semgrep/Snyk):* run these as a **shell-hook** that writes to
  `security-status.json`, NOT as an MCP server. Deterministic CLI → JSON is both
  more token-efficient and consistent with your non-LLM gate design. Semgrep is
  official (now shipped via the `semgrep` binary's built-in MCP), but the hook
  path wins for your architecture.

### 5. Testing
- **None by default.** Your `smoke-check.sh` shell gate already covers this for
  free and deterministically.
- *Optional:* **Playwright MCP**, only if a project has real browser E2E. Keep it
  off otherwise — its snapshots are some of the most token-expensive output in
  the whole MCP ecosystem.

### 6. Documentation
- **Context7**, **GitHub MCP (read-only)**
- *Why:* verify API references stay correct; read PR/diff context for changelogs.
- *Token win:* confirm one symbol vs. re-reading source; structured PR data vs.
  `gh` text.

### 7. Deployment
- **GitHub MCP (write — `pull_requests` + `actions` toolsets only)**
- *Why:* your only mutating agent — commit/push/open-PR + read CI status.
- *Token win:* structured PR/CI objects vs. parsing verbose CLI output.

---

## 3. `.mcp.json` skeleton (split read vs write GitHub)

Two GitHub entries so the **write token only exists for deployment**. Pin
images/versions; never auto-pull `latest`.

The live skeleton is the three project-scoped servers (this is what
`templates/mcp.json` contains — copy it into a project's root as `.mcp.json` and
keep only the servers that project needs; pin the version/digest). The GitHub
split below it is retained only as reference for a project that later decides it
genuinely needs GitHub MCP over the `gh` CLI.

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@<pin-a-version>"]
    },
    "aws-knowledge": {
      "type": "http",
      "url": "https://knowledge-mcp.global.api.aws"
    },
    "terraform": {
      "command": "docker",
      "args": ["run","-i","--rm","hashicorp/terraform-mcp-server@sha256:<pin-a-digest>"]
    }
  }
}
```

<details><summary>Reference only — GitHub MCP read/write split (not wired by default)</summary>

```json
{
  "mcpServers": {
    "github-ro": {
      "command": "docker",
      "args": ["run","-i","--rm",
        "-e","GITHUB_PERSONAL_ACCESS_TOKEN",
        "ghcr.io/github/github-mcp-server@sha256:<digest>",
        "--read-only",
        "--toolsets","pull_requests,code_security,secret_protection"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN_RO}" }
    },
    "github-deploy": {
      "command": "docker",
      "args": ["run","-i","--rm",
        "-e","GITHUB_PERSONAL_ACCESS_TOKEN",
        "ghcr.io/github/github-mcp-server@sha256:<digest>",
        "--toolsets","pull_requests,actions"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN_DEPLOY}" }
    }
  }
}
```
</details>

## 4. Per-subagent `tools:` allowlists (the actual token discipline)

In each subagent's frontmatter, list **only** that agent's servers. Everything
unlisted costs zero schema tokens for that agent. Keep your native tools too.

The live allow-lists (matching the *Current wiring decision* box — the three
project-scoped servers only):

```yaml
# design-spec.md   — figma (only when the design source is a live Figma file); read-only discovery otherwise
tools: Read, Glob, Grep, Write, Skill, mcp__figma

# planning.md      — aws-knowledge + terraform (infra design); NO context7
tools: Read, Grep, Glob, WebSearch, Write, Skill, mcp__aws-knowledge, mcp__terraform

# implementation.md — context7 (library APIs) + aws-knowledge + terraform
tools: Read, Write, Edit, Bash, Skill, mcp__context7, mcp__aws-knowledge, mcp__terraform

# security.md      — NO MCP (deterministic scanners only; SAST stays a shell hook)
tools: Read, Bash, Grep, Write, Skill

# debugging.md     — none (no Sentry: this pipeline fixes LOCAL failures pre-merge)
tools: Read, Edit, Bash, Grep

# testing.md       — none (shell gate; specs authored from code, never Playwright live-driving)
tools: Bash, Read, Write, Edit

# documentation.md — none (gh CLI / direct reads suffice)
tools: Read, Write, Edit, Glob, Bash

# deployment.md    — none (uses gh CLI; GitHub MCP not worth the schema cost)
tools: Bash
```

> The server *definitions* live in the project's `.mcp.json` (from
> `templates/mcp.json`). An entry above resolves to a usable tool only when the
> project defines that server; otherwise it loads nothing. That is the
> project-scoping mechanism — same idea as project vs. global skills.

---

## 5. Considered and intentionally skipped

| Server | Why skipped |
|---|---|
| Filesystem / Memory / Git reference servers | You already have native file tools + `.pipeline/*` handoff + free `git diff HEAD`. Pure schema bloat, no new capability. |
| Sequential-Thinking MCP | *Increases* reasoning tokens by design — opposite of the goal. |
| Fetch MCP | Claude Code's built-in `WebFetch` already returns markdown. Redundant. |
| Broader AWS Labs suite (CDK, cost, ECS, etc.) | Adds capability + heavy schemas, not token savings. The single Knowledge MCP covers the read/docs need. |
| Semgrep / Snyk MCP | Official, but for *your* pipeline a deterministic shell-hook → `security-status.json` is more token-efficient and matches your gate design. Use the CLI in a hook, not the MCP. |
| Datadog / observability MCP | Not in your stack; Sentry MCP already covers error retrieval. |
| Postgres / SQL MCP | Schema-introspection *would* save tokens, but no first-party server currently meets your security bar (the old reference Postgres server is archived). Revisit if a trusted one emerges; for now read migrations on demand. |

---

## 7. Audit verdict — token vs. performance (2026-06-25)

Every default-on server below was checked on two axes: does it *reduce* tokens,
and does it risk *hurting* capability/performance. None of the keepers hurt
capability; the two heavy ones are gated to opt-in.

| Server | Token effect | Performance/capability effect | Verdict |
|---|---|---|---|
| Context7 | ↓↓ targeted snippets replace whole-doc reads | ↑ fewer wrong-API retries; +1 retrieval round-trip | **Keep** |
| GitHub MCP (RO + write split) | ↓ structured objects vs `gh` text | neutral→↑; **must** scope toolsets or schemas bloat | **Keep (scoped)** |
| AWS Knowledge MCP (remote) | ↓↓ authoritative targeted content vs WebFetch dumps | ↑ current + regional-aware; remote = no local footprint | **Keep (upgraded)** |
| Terraform MCP | ↓ registry schema lookup vs reading docs | ↑ correct provider args → fewer plan/apply failures | **Keep** |
| Sentry MCP | ↓↓ one issue object vs log dump | ↑ faster root-cause for debugging agent | **Keep** |
| Firebase MCP | ↑ 30+ tool schemas (cost) unless scoped | ↑ only when actually managing Firebase | **Opt-in, auth toolset only** |
| Playwright MCP | ↑↑ a11y snapshots are large | ↑ only for real browser E2E | **Opt-in, testing only** |

**Bottom line:** the five default-on servers are all net token-reducers with no
capability cost, *provided* the two discipline rules hold — per-agent `tools:`
scoping (§4) and toolset narrowing on GitHub. The two heavy servers stay off
until a project genuinely needs them. No further first-party servers clear both
your token and security bars today; SAST stays a shell-hook.

## 6. Security checklist (recap)

1. First-party servers only (all of §1 qualify).
2. Pin versions / Docker image **digests** — no `latest`.
3. Read-only + minimal toolsets everywhere except deployment.
4. **Treat all tool *results* as untrusted** (a fetched issue/doc can carry
   prompt-injection). Your non-LLM shell gates are the mitigation — keep gates
   deterministic; never let an MCP result decide a gate.
5. Per-agent token scoping: deployment holds the only write token; security/docs
   get read-only; everyone else gets no GitHub access at all.
```
