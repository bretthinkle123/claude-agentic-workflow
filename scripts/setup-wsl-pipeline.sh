#!/usr/bin/env bash
# setup-wsl-pipeline.sh — one-command provisioning of the WSL2 pipeline host (autonomy plan
# Phases 5+6). Run this INSIDE the WSL2 (or Linux) environment, from the cloned framework repo.
# It captures the long manual sequence so provisioning is repeatable and reviewable.
#
# IDEMPOTENT and NON-DESTRUCTIVE where it can be: re-running skips what already exists. It
# NEVER writes a secret into the repo — the GitHub token is entered through `gh auth login`,
# which stores it in gh's own config, not here.
#
# FIRST-RUN VERIFY: this touches apt/pip/npm/docker on your machine and cannot be exercised in
# CI — read it before running, and confirm each phase's tool actually works afterward (Phase 6.3
# A9 note: a silently-absent scanner now fails loud, so prove each one runs before the canary).
#
# Usage (inside WSL, from the repo root):
#   bash scripts/setup-wsl-pipeline.sh [--skip-toolchain] [--skip-proxy]
set -uo pipefail

SKIP_TOOLCHAIN=false
SKIP_PROXY=false
ENFORCE=false
for a in "$@"; do
  case "$a" in
    --skip-toolchain) SKIP_TOOLCHAIN=true ;;
    --skip-proxy)     SKIP_PROXY=true ;;
    --enforce)        ENFORCE=true ;;
    *) echo "unknown arg: $a (use --skip-toolchain | --skip-proxy | --enforce)" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
say()  { printf '\n== %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- Precondition: must be Linux/WSL, not the Windows host -----------------------------------
if ! grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && [ "$(uname -s)" != "Linux" ]; then
  echo "Refusing: this must run inside WSL2/Linux (uname=$(uname -s)). The whole point is to" >&2
  echo "move pipeline execution off the Windows profile. Open your WSL distro and re-run." >&2
  exit 2
fi

# --- Precondition: repo lives on the native FS, not /mnt/c (perf + isolation) ----------------
case "$REPO_ROOT" in
  /mnt/*) echo "Warning: repo is under $REPO_ROOT (a Windows mount). Clone into the WSL native FS" >&2
          echo "         (e.g. ~/repos/) instead — /mnt/c defeats the isolation and is slow." >&2 ;;
esac

# --- Phase 6.3: toolchain --------------------------------------------------------------------
if [ "$SKIP_TOOLCHAIN" = false ]; then
  say "Toolchain (git, gh, jq, node, python, scanners)"
  if have apt-get; then
    sudo apt-get update -y
    sudo apt-get install -y git jq curl python3 python3-pip python3-venv gh
  else
    echo "  (no apt-get — install git/jq/curl/python3/gh with your package manager, then --skip-toolchain)"
  fi
  have node || { curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs; }
  # Scanners the hooks expect. A9 (PR #38): a silently-absent scanner fails loud, so install
  # all of them, then the verify step below proves each runs.
  have semgrep      || pip install --user semgrep
  have checkov      || pip install --user checkov
  have osv-scanner  || echo "  install osv-scanner: https://github.com/google/osv-scanner (Go binary or brew)"
  have gitleaks     || echo "  install gitleaks:    https://github.com/gitleaks/gitleaks/releases"
  have trivy        || echo "  install trivy:       https://aquasecurity.github.io/trivy (apt repo or binary)"
  have ast-grep     || npm install -g @ast-grep/cli
  have claude       || npm install -g @anthropic-ai/claude-code
  say "Scanner liveness (A9 — each must actually run)"
  for t in semgrep osv-scanner gitleaks trivy ast-grep checkov; do
    if have "$t"; then echo "  [ok]   $t present"; else echo "  [MISSING] $t — install before the canary (A9 will fail-loud otherwise)"; fi
  done
fi

# --- Publish the pipeline to WSL-side ~/.claude ----------------------------------------------
say "Publish pipeline to ~/.claude"
bash "$REPO_ROOT/scripts/install-global.sh"
if [ ! -f "$HOME/.claude/notify.env" ] && [ -f "$HOME/.claude/pipeline-templates/notify.env.example" ]; then
  cp "$HOME/.claude/pipeline-templates/notify.env.example" "$HOME/.claude/notify.env"
  echo "  [new] ~/.claude/notify.env — set NTFY_TOPIC (openssl rand -hex 16) and subscribe in the ntfy app"
fi

# --- Shell profile: scoped auto-mode launcher (idempotent; CN1-1/F-A2) -----------------------
# CLI >=2.1.207 ignores permissions.defaultMode:"auto" in settings (the --permission-mode
# flag works), so interactive launches need the flag. Scoped to bootstrapped pipeline repos
# (.pipeline/state.json present) so non-pipeline projects keep the default posture.
say "Shell profile launcher (~/.bashrc)"
if ! grep -q 'pipeline-claude-launcher' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'EOF'

# pipeline-claude-launcher — auto permission mode INSIDE bootstrapped pipeline repos only
# (CLI >=2.1.207 ignores settings defaultMode "auto"; remove when a fixed CLI honors it).
claude() {
  if [ -f .pipeline/state.json ]; then command claude --permission-mode auto "$@"
  else command claude "$@"; fi
}
EOF
  echo "  [new] appended the scoped claude launcher to ~/.bashrc (open a fresh terminal)"
else
  echo "  ~/.bashrc already has the pipeline-claude-launcher block"
fi

# --- Phase 3: GitHub auth via a fine-grained, repo-scoped token ------------------------------
say "GitHub auth (fine-grained PAT — repo-scoped)"
if have gh && gh auth status >/dev/null 2>&1; then
  echo "  gh already authenticated. Confirm the active token is FINE-GRAINED + scoped to the"
  echo "  target repo only (Contents RW, Pull requests RW, Actions Read). Re-run 'gh auth login' to change."
else
  echo "  Create a fine-grained PAT at https://github.com/settings/tokens?type=beta"
  echo "    Resource owner: you | Repository access: ONLY the target repo(s)"
  echo "    Permissions: Contents RW, Pull requests RW, Actions Read, Metadata Read | 30-90d expiry"
  echo "  Then authenticate (token goes into gh's config, NEVER this repo):"
  echo "    gh auth login --hostname github.com --git-protocol https"
fi

# --- Phase 5: egress proxy (log-only first; enforce after the canary reconciles) -------------
if [ "$SKIP_PROXY" = false ]; then
  say "Egress proxy (default-deny forward proxy)"
  if ! have docker; then
    echo "  docker not found — enable Docker Desktop WSL integration or install docker-ce, then --skip-proxy off."
  else
    bash "$REPO_ROOT/global-hooks/egress-proxy/build-filter.sh" > "$REPO_ROOT/global-hooks/egress-proxy/egress-filter.txt"
    docker network inspect pipeline-egress     >/dev/null 2>&1 || docker network create --internal pipeline-egress
    docker network inspect pipeline-egress-out >/dev/null 2>&1 || docker network create pipeline-egress-out
    # LOG-ONLY by default (plan 5.3: measure, don't guess): mount the no-filter conf so every
    # host passes but is logged. --enforce (Phase 7.3, after canary reconciliation) recreates
    # the container with the default-deny conf + filter. The two confs differ ONLY in filtering.
    CONF="tinyproxy-logonly.conf"; MODE="LOG-ONLY"
    if [ "$ENFORCE" = true ]; then CONF="tinyproxy.conf"; MODE="ENFORCING"; fi
    if [ "$ENFORCE" = true ] && docker inspect pipeline-egress-proxy >/dev/null 2>&1; then
      docker rm -f pipeline-egress-proxy >/dev/null   # recreate to flip modes
    fi
    if ! docker inspect pipeline-egress-proxy >/dev/null 2>&1; then
      # Start on the -out (publishable) network with the proxy port bound to loopback so
      # HOST commands can actually route through it — container names don't resolve from
      # the host shell, so http://pipeline-egress-proxy:8888 only ever worked for
      # containerized clients. Then connect the internal network for those clients.
      # (-p on an --internal network is not supported, hence the two-step order.)
      docker run -d --name pipeline-egress-proxy \
        --network pipeline-egress-out \
        -p 127.0.0.1:8888:8888 \
        -v "$REPO_ROOT/global-hooks/egress-proxy/$CONF:/etc/tinyproxy/tinyproxy.conf:ro" \
        -v "$REPO_ROOT/global-hooks/egress-proxy/egress-filter.txt:/etc/tinyproxy/egress-filter.txt:ro" \
        -v pipeline-egress-logs:/var/log/tinyproxy \
        vimagick/tinyproxy
      docker network connect pipeline-egress pipeline-egress-proxy
    fi
    echo "  Proxy up in $MODE mode. Add to your shell profile (guarded so a proxy-down host still works):"
    echo "    if docker inspect pipeline-egress-proxy >/dev/null 2>&1; then"
    echo "      export PIPELINE_EGRESS_NETWORK=pipeline-egress"
    echo "      # host commands reach the proxy on loopback; containerized clients use the network name"
    echo "      export HTTPS_PROXY=http://127.0.0.1:8888 HTTP_PROXY=http://127.0.0.1:8888"
    echo "      export NO_PROXY=127.0.0.1,localhost"
    echo "    fi"
    echo "  START LOG-ONLY: reconcile observed hosts against egress-allowlist.txt in the canary,"
    echo "  THEN re-run with --enforce (Phase 7.3). Do not enforce before reconciling."
  fi
fi

say "Next"
echo "  1. Set NTFY_TOPIC in ~/.claude/notify.env + subscribe in the ntfy app."
echo "  2. Restart your shell (or source the proxy exports above)."
echo "  3. Run:  bash scripts/verify-sandbox.sh   — every REQUIRED property must pass."
echo "  4. Clone your target app repo into the WSL native FS and bootstrap it, then run the canary."
