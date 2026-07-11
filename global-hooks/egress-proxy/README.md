# Egress proxy — Layer 2 default-deny boundary (EG side-track)

> **Operator-provisioned, Docker/OS-bound.** This is the **real** egress boundary (the rest of EG
> is the enumerated allow-list, the command-level intent, and the Layer-3 detection hook). It is
> **not run-verified on the Windows dev host** — it needs Docker Desktop (portable slice) or,
> for a strong guarantee, WSL2/Linux. Provision it when the pipeline handles anything sensitive
> (a runtime secret in a test, or the [[redteam-app-goal]] build). Until then, egress is the
> enumerated intent + Layer-1 command scope; the proxy is what makes it enforced.

## What it does

A default-deny forward proxy (tinyproxy) whose ACL is generated from the single source of truth
`global-hooks/egress-allowlist.txt`. The scanner containers (and, optionally, host commands) are
routed through it and have **no other route out**, so a prompt-injected agent cannot reach a
non-allow-listed host to exfiltrate data or fetch a hostile payload. Every decision is logged, and
`egress-check.sh` surfaces denied attempts in the security report.

## Provision (Docker Desktop — portable slice, covers the scanner egress)

```sh
# 1. Generate the proxy ACL from the allow-list (deterministic — always re-derive, never hand-edit).
bash global-hooks/egress-proxy/build-filter.sh > global-hooks/egress-proxy/egress-filter.txt

# 2. Create a restricted network whose only gateway to the internet is the proxy.
docker network create --internal pipeline-egress          # --internal = no direct outbound
docker network create pipeline-egress-out                 # the proxy's own outbound leg

# 3. Run the proxy attached to BOTH (internal for clients, -out for its own egress).
docker run -d --name pipeline-egress-proxy \
  --network pipeline-egress \
  -v "$PWD/global-hooks/egress-proxy/tinyproxy.conf:/etc/tinyproxy/tinyproxy.conf:ro" \
  -v "$PWD/global-hooks/egress-proxy/egress-filter.txt:/etc/tinyproxy/egress-filter.txt:ro" \
  -v pipeline-egress-logs:/var/log/tinyproxy \
  vimagick/tinyproxy
docker network connect pipeline-egress-out pipeline-egress-proxy

# 4. Point the scanner wrappers at the restricted network (they already opt in on this env var).
export PIPELINE_EGRESS_NETWORK=pipeline-egress
# Host commands (curl/gh/pip/npm) reach the proxy on loopback — container names do NOT
# resolve from the host shell, so the proxy must be published there (setup-wsl-pipeline.sh
# runs the container with `-p 127.0.0.1:8888:8888` on the -out network for exactly this).
# Containerized clients keep using http://pipeline-egress-proxy:8888 via docker DNS.
export HTTPS_PROXY=http://127.0.0.1:8888
export HTTP_PROXY=http://127.0.0.1:8888
export NO_PROXY=127.0.0.1,localhost
```

Now `semgrep-scan.sh` / `trivy-scan.sh` / `generate-sbom.sh` run inside `pipeline-egress`; their
only path out is the allow-listing proxy. A pull from `registry-1.docker.io` succeeds; a `curl`
to `evil.example` is denied.

## Feed the detection hook (Layer 3)

`egress-check.sh` reads `.pipeline/egress-log.jsonl` — one JSON object per outbound decision,
`{"ts","host","action":"allow|deny"}`. Bridge tinyproxy's log to that shape after each run (a
denied `CONNECT`/GET shows in tinyproxy's log as a filtered request):

```sh
# minimal bridge — adapt to your tinyproxy log format; the key fields are host + allow/deny
docker exec pipeline-egress-proxy sh -c 'cat /var/log/tinyproxy/tinyproxy.log' \
  | awk '/Filtered/{print $0" deny"} /Established/{print $0" allow"}' \
  | sed -E 's/.* ([A-Za-z0-9._-]+)(:[0-9]+)? (allow|deny)$/{"host":"\1","action":"\3"}/' \
  >> .pipeline/egress-log.jsonl
```

The security agent then folds any denied host into `warning_count` (step 4f).

## Strong-guarantee substrate (WSL2 / Linux)

For a hard boundary rather than a proxy tools must honor, run the pipeline's shell workload under
**WSL2** and use nftables/iptables default-deny egress with the same allow-list, or a transparent
proxy. `HTTPS_PROXY` on host commands is belt-and-suspenders (most tools honor it, some don't); the
container-network slice above is the airtight part on Docker Desktop.

## Scope

- `api.anthropic.com` (the Claude Code model transport) is **out of scope** — it is the harness,
  not the sandboxed tool workload; blocking it breaks the pipeline. The proxy targets the tools
  the agents invoke.
- Not the app's own SSRF/outbound control — that stays in `api-edge-conventions` / `code-standards`.
