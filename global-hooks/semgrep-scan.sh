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
  exit 2
fi

# `pwd -W` yields the Windows path (C:/...) that Docker Desktop accepts for -v.
# MSYS_NO_PATHCONV / MSYS2_ARG_CONV_EXCL stop Git Bash from rewriting the
# in-container paths (/src, config args) into Windows paths.
HOST_DIR="$(pwd -W 2>/dev/null || pwd)"

# EG side-track: opt into the default-deny egress network when the operator provisions it
# (export PIPELINE_EGRESS_NETWORK=<name>; see global-hooks/egress-proxy/). Unset ⇒ default bridge.
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
  ${PIPELINE_EGRESS_NETWORK:+--network "$PIPELINE_EGRESS_NETWORK"} \
  -v "${HOST_DIR}:/src" \
  -w /src \
  "$IMAGE" \
  semgrep "$@"
