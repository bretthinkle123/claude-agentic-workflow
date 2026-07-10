#!/usr/bin/env bash
# gitleaks-scan.sh — dedicated secrets scanning (SB side-track, slice 1).
#
# A second, independent secrets opinion alongside the regex-grep (security step 6a) and Semgrep
# `p/secrets`: Gitleaks is purpose-built for credential detection (entropy + a large rule set,
# git-history aware), language-agnostic, deterministic, and — natively — a single binary needing
# no Docker. The security agent runs this and folds any finding into `critical_count` (a committed
# secret is a hard block).
#
# Prefers the native `gitleaks` binary (the plan's low-friction path); falls back to the official
# Docker image on a machine without it (this Windows host), the same portability pattern as
# semgrep-scan.sh / trivy-scan.sh. Pass the args you would pass to `gitleaks`, e.g.:
#   $HOME/.claude/hooks/gitleaks-scan.sh dir --report-format json --report-path .pipeline/gitleaks.json .
#   $HOME/.claude/hooks/gitleaks-scan.sh git --report-format json .            # scan history
# Surfaces (never silently skips) when no engine is available — same rule as "Docker not running".
#
# VERSION NOTE: the `dir`/`git` subcommands need gitleaks >= v8.19; older binaries use
# `detect --source .`. The Docker image below is unpinned `:latest`, so the DOCKER path (what this
# Windows host uses) is always modern and supports `dir`/`git`. A NATIVE binary older than v8.19
# will error on `dir` — that error surfaces (not silent); upgrade gitleaks, or `unset` it from PATH
# so the Docker path is used, or pass `detect --source .` on the old CLI. We do NOT auto-fall-back
# from a failed native run because gitleaks exits 1 for BOTH "leaks found" and "unknown command",
# so a fallback could mask a real finding.
set -uo pipefail

IMAGE="${GITLEAKS_IMAGE:-ghcr.io/gitleaks/gitleaks:latest}"
STAMP="$(dirname "${BASH_SOURCE[0]}")/stamp-scan.sh"

# M4″-A9: gitleaks was the one scanner wrapper that never stamped scan-log.jsonl (it
# exec'd the tool, so nothing ran afterwards) — the M4″ run had a fresh 87KB
# gitleaks.json and NO execution breadcrumb. Run + stamp + exit like every other
# wrapper; stamp-scan.sh derives the artifact path from --report-path.
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks "$@"
  _rc=$?
  "$STAMP" gitleaks "$_rc" "" "$@" >/dev/null 2>&1 || true
  exit "$_rc"
fi

if docker info >/dev/null 2>&1; then
  HOST_DIR="$(pwd -W 2>/dev/null || pwd)"
  # EG side-track: join the restricted egress network when the operator provisions it.
  env MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
    ${PIPELINE_EGRESS_NETWORK:+--network "$PIPELINE_EGRESS_NETWORK"} \
    -v "${HOST_DIR}:/src" -w /src \
    "$IMAGE" "$@"
  _rc=$?
  "$STAMP" gitleaks "$_rc" "" "$@" >/dev/null 2>&1 || true
  exit "$_rc"
fi

echo "[gitleaks-scan] neither the native 'gitleaks' binary nor Docker is available — cannot run the dedicated secrets scan. Install gitleaks (single binary) or start Docker Desktop, then re-run. Do NOT report secrets-clean without it." >&2
# A9: stamp the disclosed skip too (ast-grep-scan.sh pattern) — "never ran" vs
# "unavailable, disclosed" must be distinct, auditable states.
"$STAMP" gitleaks 2 "" "skipped: no native binary and Docker not running" >/dev/null 2>&1 || true
exit 2
