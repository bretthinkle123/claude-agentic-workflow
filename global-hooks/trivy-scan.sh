#!/usr/bin/env bash
# Trivy via Docker. Like semgrep-scan.sh, Trivy runs through the official image so
# it needs no native install. The security agent calls this when the change set
# includes a Dockerfile / container image, to scan it for OS- and library-level
# CVEs and misconfigurations. Pass the SAME arguments you would pass to the `trivy`
# CLI, e.g.:
#   $HOME/.claude/hooks/trivy-scan.sh image --severity CRITICAL,HIGH --format json myimage:tag
#   $HOME/.claude/hooks/trivy-scan.sh config --severity CRITICAL,HIGH .        # Dockerfile/IaC misconfig
#   $HOME/.claude/hooks/trivy-scan.sh fs --scanners vuln,secret .             # filesystem scan
#
# The repo root is mounted at /src (container workdir) so path arguments are
# relative to the repo as usual, and Trivy's cache is persisted in a named volume
# to avoid re-downloading the vuln DB on every run. To scan a locally-built image,
# the Docker socket is mounted so Trivy can read it from the host daemon.
# Requires Docker Desktop to be running.
set -euo pipefail

IMAGE="${TRIVY_IMAGE:-aquasec/trivy}"

if ! docker info >/dev/null 2>&1; then
  echo "[trivy-scan] Docker is not running. Start Docker Desktop, then re-run." >&2
  # M4″-A9: stamp the disclosed skip — "never ran" vs "unavailable, disclosed" must be
  # distinct, auditable states in scan-log.jsonl.
  "$(dirname "${BASH_SOURCE[0]}")/stamp-scan.sh" trivy 2 "" "skipped: Docker not running" >/dev/null 2>&1 || true
  exit 2
fi

# `pwd -W` yields the Windows path (C:/...) that Docker Desktop accepts for -v.
# MSYS_NO_PATHCONV / MSYS2_ARG_CONV_EXCL stop Git Bash from rewriting the
# in-container paths (/src, severity args) into Windows paths.
HOST_DIR="$(pwd -W 2>/dev/null || pwd)"

# Pin the entrypoint to `trivy` so callers pass bare subcommands (`config`,
# `image`, ...) — the same "don't repeat the binary name" contract as
# semgrep-scan.sh — and the wrapper still works if TRIVY_IMAGE is overridden to an
# image that doesn't default its entrypoint to trivy.
# EG side-track: when the operator has provisioned the default-deny egress network
# (global-hooks/egress-proxy/), export PIPELINE_EGRESS_NETWORK=<name> and this container joins it
# (its only route out is the allow-listing proxy). Unset ⇒ default bridge, unchanged behavior.
set +e
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
  ${PIPELINE_EGRESS_NETWORK:+--network "$PIPELINE_EGRESS_NETWORK"} \
  --entrypoint trivy \
  -v "${HOST_DIR}:/src" \
  -v trivy-cache:/root/.cache/ \
  -v //var/run/docker.sock:/var/run/docker.sock \
  -w /src \
  "$IMAGE" \
  "$@"
_rc=$?
# U-09: stamp the execution into .pipeline/scan-log.jsonl (reconcile-scans.sh recounts
# the .pipeline/trivy-config.json artifact and gates on the match).
"$(dirname "${BASH_SOURCE[0]}")/stamp-scan.sh" trivy "$_rc" "" "$@" >/dev/null 2>&1 || true
exit "$_rc"
