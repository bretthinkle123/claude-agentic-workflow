# Running the pipeline autonomously in WSL2 — operator guide

**Audience:** anyone who wants to kick off a pipeline run, walk away, and come back only
for the human checkpoints. This documents the sandboxed pipeline host — how to set it up
on your own machine, run against it, and maintain it. It assumes you already know the
basic pipeline flow (install → bootstrap a project → `PROJECT.md` → run); if not, start
with the root [README](../README.md). The threat reasoning behind every control here is
in [docs/pipeline-threat-model.md](pipeline-threat-model.md).

**What the setup gives you, in one sentence:** a pipeline run executes with **zero
permission prompts** between checkpoints, **pages you with a Windows toast** when it needs
you, and — if it's ever compromised by a hostile dependency or prompt injection — is
bounded to **one disposable Linux userland, one egress-filtered network, and one
repo-scoped GitHub token**.

The three security layers, and why each exists:

| Layer | What it caps | Without it |
|---|---|---|
| WSL2 userland (`~/repos`, WSL-side `~/.claude`) | Filesystem blast radius — dependency install scripts and test code run in a throwaway Linux home | Same code runs as Windows-you: real profile, OneDrive, browser data |
| Egress proxy (tinyproxy, default-deny allowlist) | Where stolen data can go / where payloads come from | Any process can reach any host |
| Fine-grained PAT (repo-scoped, 90-day) | What a stolen GitHub credential is worth | A leaked broad token = write access to every repo you own; `github.com` is always on the egress allowlist, so ONLY token scoping caps this channel |

None of this replaces the two human checkpoints — the plan review and the diff review are
still the strongest defense and are deliberately not automatable.

---

## 1. One-time setup (per machine)

Prerequisites: Windows 10/11 with WSL2 and an Ubuntu distro (`wsl --install -d Ubuntu`),
Docker Desktop with WSL integration enabled for that distro. (On a native Linux host the
same scripts run without the WSL parts — the isolation story is then your VM/host
hygiene.) For desktop toast notifications, install BurntToast once on the Windows side
(PowerShell): `Install-Module BurntToast -Scope CurrentUser`.

1. **Clone this repo into the WSL native filesystem** (never `/mnt/c/...` — 9P is
   slow, and a pipeline writing to your Windows profile defeats the isolation):

   ```bash
   git clone <this-repo-or-your-fork> ~/repos/claude-agentic-workflow
   cd ~/repos/claude-agentic-workflow
   ```

2. **Provision:** `bash scripts/setup-wsl-pipeline.sh` — toolchain, scanners, publish to
   WSL-side `~/.claude`, and the egress proxy in **log-only** mode. Notes from the first
   provisioning run:
   - The apt/npm steps need root. Do **not** give the pipeline user passwordless sudo (an
     injected agent with free root can disable the proxy). Either type your password when
     prompted, or run the root-level steps from Windows via `wsl -u root`.
   - Ubuntu's Python is PEP-668 externally-managed: `semgrep` and `checkov` install via
     `pipx`, not `pip --user`.
   - `ast-grep` must be the native release binary — the npm package's `sg` alias collides
     with Linux's `/usr/bin/sg`, and a Windows shim leaking through `/mnt/c` PATH interop
     will LOOK present but isn't a real install. `command -v` answers starting with
     `/mnt/c/` don't count.
   - Verify every scanner actually runs before trusting a run: each `*-scan.sh` hook must
     execute and stamp `.pipeline/scan-log.jsonl` (A9 makes a missing scanner fail-loud
     mid-run, which is the wrong time to find out). Note the stamp only writes when
     `.pipeline/state.json` exists.

3. **Persist the proxy environment** in `~/.bashrc` (the setup script prints the block;
   paste it). It's guarded by a `docker inspect` check so a proxy-down host still works.
   Interactive terminals get it; `claude` inherits it from the terminal that launches it.

4. **GitHub token** — see §3. The WSL `gh` must hold ONLY the scoped PAT, never your
   personal browser-login OAuth token (`gh auth status` showing scopes like `repo, gist,
   workflow` means the broad token — replace it).

5. **Claude login:** `claude` once in the WSL terminal and complete the login flow.

6. **Notifications:** `~/.claude/notify.env` is seeded by the setup script. Pick one:
   - **Desktop toast (default — leave `NTFY_TOPIC=` blank):** checkpoint/cap/attention
     events pop a Windows toast (works from WSL via interop; needs BurntToast, see
     prerequisites) and persist in the Windows notification center. You get paged at the
     machine, not on a phone; a run that pauses while you're out simply waits for you.
   - **Phone pings (ntfy):** set `NTFY_TOPIC` to a long random string
     (`openssl rand -hex 16`) and subscribe to that topic in the ntfy app. The topic IS
     the secret — treat it like a password. Payload is always event + feature slug +
     repo name, never content. Note this pages you; it does not let you approve from the
     phone — approvals are desk-only by design (§7).

7. **Target repo(s):** clone into `~/repos/<app>` and run
   `bash ~/.claude/pipeline-templates/bootstrap-project.sh` in each. **Bootstrap will not
   overwrite an existing `.claude/settings.json`** — a repo bootstrapped before the
   autonomy hardening carries old settings that WILL prompt mid-run; refresh them from
   `templates/project-settings.json` (keep any project-specific allow rules, but never
   re-add bare `curl`, bare `WebFetch`, or anything the template's admission rules exclude).

8. **Verify:** `bash scripts/verify-sandbox.sh`. Until the proxy is flipped to enforcing
   it will honestly FAIL the enforcement conjunct — everything else must be green. After
   the flip it must print `SANDBOX OK`.

## 2. Running a pipeline autonomously

Precondition: the target repo is bootstrapped and its `PROJECT.md` describes the feature
scope (the normal flow from the root README — nothing about it changes in WSL).

1. Open a **fresh WSL terminal** (fresh = the proxy env from `.bashrc` is loaded).
2. `cd ~/repos/<app>` and start `claude`. It's the same conversational interface as the
   VSCode extension — describe the feature in plain English and ask for a pipeline run.
3. **Walk away.** The run proceeds with zero prompts. You get a toast at exactly these
   moments:
   - `plan` — the plan is ready for review
   - `diff` — the built change + findings are ready for review
   - `capped` — a retry/loop cap was hit and the run stopped for a human
   - `attention` — the session hit an unexpected prompt or is waiting on input
4. **At each checkpoint, YOU type the approval in the terminal** — never the agent, never
   from a phone (settled decisions: desk-only, human-typed):
   - plan: `bash ~/.claude/hooks/approve-plan.sh` (or `touch .pipeline/plan-approved`)
   - diff: `bash ~/.claude/hooks/approve-diff.sh`
5. An `attention` toast between checkpoints is a bug in the allowlist, not a fact of
   life: triage every one to a resolution — a new scoped allow rule in
   `templates/project-settings.json`, a wrapper hook (the `registry-check.sh` pattern),
   a WebFetch domain entry, or an explicit rejection with a reason. The goal is that the
   next run doesn't ping.

VSCode users: the same thing works with identical UX via the **WSL extension** (Connect
to WSL → open `/home/<user>/repos/<app>` → Claude Code panel). A session opened on the
plain Windows side runs OUTSIDE the sandbox — convenient, but don't use it for unattended
runs on untrusted inputs.

## 3. The GitHub token (create / renew / extend)

The pipeline host authenticates with a **fine-grained PAT** scoped to only the repos the
pipeline builds. You create it **once**, not per run.

**Create** — github.com → Settings → Developer settings → Fine-grained tokens:
- Repository access: *Only select repositories* → the pipeline target repo(s)
- Permissions: **Contents: Read and write**, **Pull requests: Read and write**,
  **Actions: Read-only**, **Commit statuses: Read-only** (there is no separate "Checks"
  permission; statuses covers the CI reads)
- Expiration: 90 days

Then, in a WSL terminal:

```bash
gh auth logout --hostname github.com          # only if replacing an old token
gh auth login --hostname github.com --git-protocol https --with-token
# paste the token, press Enter, then Ctrl+D
gh auth setup-git                             # REQUIRED — wires git push to use the token
```

**Three gotchas that cost real time on first setup:**
1. GitHub silently adds **Contents: Read-only** when you grant Pull requests RW. If the
   deployment push gets 403 on the repo the token IS granted for, this is why — edit the
   token, bump Contents to Read and write, save. No regeneration needed.
2. The REST API's `permissions` field on **public** repos describes your user, not the
   token — it will claim `push: true` for repos the token can't touch. Verify with a real
   probe, not the API: push a throwaway ref (`git push origin HEAD:refs/heads/pat-probe`,
   then delete it) and confirm a push to a NON-granted repo is denied.
3. `--with-token` does **not** configure git's credential helper. Skip `gh auth setup-git`
   and every pipeline push will stall asking for credentials.

**Add a repo (new project):** token settings page → Repository access → check the new
repo → Update token. Takes effect immediately; nothing to re-paste. Do this once per new
pipeline target (e.g. when creating the next app repo).

**Renew (every ~90 days):** GitHub emails you before expiry. Token settings page →
Regenerate → re-run the `gh auth login --with-token` paste above. ~2 minutes. The expiry
is the cap on how long a stolen token stays useful — don't extend it to "no expiration".

**Never** put the token in a repo file, an env file inside a repo, or `notify.env`. It
lives only in gh's own config (`~/.config/gh/hosts.yml` in WSL).

## 4. The egress proxy (modes, allowlist, logs)

- **Log-only** (provisioning default): every host passes, every decision is logged.
  Used until a canary run measures what the pipeline actually needs.
- **Enforcing:** `bash scripts/setup-wsl-pipeline.sh --skip-toolchain --enforce`
  recreates the container with the default-deny filter. Verify:
  `curl https://pypi.org` succeeds, `curl https://example.com` is refused, and
  `scripts/verify-sandbox.sh` prints `SANDBOX OK`.
- **Allowlist changes:** edit `global-hooks/egress-allowlist.txt` (one host per line,
  with a comment naming the consumer), then re-run the `--enforce` command above (it
  re-derives the filter via `build-filter.sh` — never hand-edit `egress-filter.txt`).
  An unexplained host in the proxy log is a finding to investigate, not an allowlist
  entry to add.
- **Reading the log:**
  `docker exec pipeline-egress-proxy sh -c 'cat /var/log/tinyproxy/tinyproxy.log'`,
  or bridge it into a run's `.pipeline/egress-log.jsonl` with
  `global-hooks/egress-proxy/bridge-log.sh` so `egress-check.sh` surfaces denials in the
  security report.
- WebFetch (the agent tool, distinct from shell egress) has its own domain allowlist:
  `global-hooks/webfetch-domains.txt`, enforced by `guard-webfetch-domains.sh`. Unlisted
  domains are DENIED (not prompted — an unattended `ask` is a silent stall); denials log
  to `.pipeline/webfetch-denied.jsonl`. Triage that file between runs like the proxy log.

## 5. Keeping the engine current

After any framework change (or `git pull`) — **inside WSL**:

```bash
cd ~/repos/claude-agentic-workflow && git pull --ff-only
bash scripts/install-global.sh     # publish to WSL-side ~/.claude
```

then restart any standing `claude` sessions (they read `~/.claude` at startup; running
against a stale publish has caused real drift). The Windows-side `~/.claude` is published
separately from the Windows clone — the two hosts don't share a `~/.claude`.

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `attention` toast mid-run | command not in the allowlist | triage per §2.5 |
| Deployment push 403 on the granted repo | token's Contents perm is Read-only, or token expired | §3 gotcha 1 / renew |
| Push asks for username/password | credential helper not wired | `gh auth setup-git` |
| A9 liveness block for a scanner | binary missing or a `/mnt/c` Windows shim | reinstall natively (§1.2), re-verify stamps |
| Every egress fails after proxy work | proxy container down while env vars point at it | `docker start pipeline-egress-proxy`, or open a fresh terminal (the `.bashrc` guard skips the exports when the proxy is absent) |
| Toast never appears | BurntToast not installed on Windows, or hook predates the `-ExecutionPolicy Bypass` fix | `Install-Module BurntToast -Scope CurrentUser` in PowerShell; re-publish |
| verify-sandbox FAILs enforcement | proxy still in log-only | expected before the flip; `--enforce` when reconciled |

## 7. Invariants — do not "fix" these

- The pipeline user has **no passwordless sudo** in WSL, and the WSL home has **no
  `~/.ssh`, no `~/.aws`**, no cloud credentials. `verify-sandbox.sh` checks this.
- Checkpoint approvals are **typed by a human in a TTY, at the desk**. Never automate
  them, never approve from a phone, never let an agent create the marker files.
- Bare `curl`/`wget`, bare `WebFetch`, and paste/storage domains never go on an
  allowlist. Egress rides enumerated hosts or it doesn't ride.
- Notification payloads carry event + slug + repo name only — never findings, diffs, or
  file paths.
- The broad personal GitHub token never enters the WSL environment.
