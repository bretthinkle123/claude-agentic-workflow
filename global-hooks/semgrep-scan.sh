#!/usr/bin/env bash
# Semgrep via Docker. Semgrep has no native Windows build, so the security agent
# calls this drop-in wrapper instead of bare `semgrep`. Pass the SAME arguments you
# would pass to the `semgrep` CLI, e.g.:
#   $HOME/.claude/hooks/semgrep-scan.sh scan --config=auto --config=p/secrets --config=p/owasp-top-ten .
#
# The current working directory (repo root) is mounted at /src and used as the
# container workdir, so file/scope arguments are relative to the repo as usual.
# Requires Docker Desktop to be running.
set -euo pipefail

IMAGE="${SEMGREP_IMAGE:-semgrep/semgrep}"

if ! docker info >/dev/null 2>&1; then
  echo "[semgrep-scan] Docker is not running. Start Docker Desktop, then re-run." >&2
  # M4″-A9: stamp the disclosed skip (ast-grep pattern) — silent absence and disclosed
  # unavailability must be distinct, auditable states in scan-log.jsonl.
  "$(dirname "${BASH_SOURCE[0]}")/stamp-scan.sh" semgrep 2 "" "skipped: Docker not running" >/dev/null 2>&1 || true
  exit 2
fi

# `pwd -W` yields the Windows path (C:/...) that Docker Desktop accepts for -v.
# MSYS_NO_PATHCONV / MSYS2_ARG_CONV_EXCL stop Git Bash from rewriting the
# in-container paths (/src, config args) into Windows paths.
HOST_DIR="$(pwd -W 2>/dev/null || pwd)"

# EG side-track: opt into the default-deny egress network when the operator provisions it
# (export PIPELINE_EGRESS_NETWORK=<name>; see global-hooks/egress-proxy/). Unset ⇒ default bridge.
# F6 (events-force-rls run): a container on the --internal network has NO direct route out,
# and the host's HTTPS_PROXY points at loopback — unreachable from inside a container — so
# registry/rule fetches silently failed and SCA coverage degraded to prose. Pass the proxy
# env INTO the container using the docker-DNS name, which IS resolvable on that network.
set +e
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
  ${PIPELINE_EGRESS_NETWORK:+--network "$PIPELINE_EGRESS_NETWORK"} \
  ${PIPELINE_EGRESS_NETWORK:+-e HTTPS_PROXY=http://pipeline-egress-proxy:8888 -e HTTP_PROXY=http://pipeline-egress-proxy:8888 -e NO_PROXY=127.0.0.1,localhost} \
  -v "${HOST_DIR}:/src" \
  -w /src \
  "$IMAGE" \
  semgrep "$@"
_rc=$?
# U-09: stamp the execution (tool, args, exit) into .pipeline/scan-log.jsonl so a report
# can only claim "executed" for a tool with a THIS-pass stamp. Output goes to the agent's
# stdout redirect (.pipeline/semgrep.json); reconcile-scans.sh hashes + recounts it. The
# stamp writes a different file, so it never pollutes the tool's JSON on stdout.
"$(dirname "${BASH_SOURCE[0]}")/stamp-scan.sh" semgrep "$_rc" "" "$@" >/dev/null 2>&1 || true
exit "$_rc"
