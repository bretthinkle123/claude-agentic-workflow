#!/usr/bin/env bash
# Generate a CycloneDX SBOM for the repo (M6) into .pipeline/sbom.cdx.json, using
# Trivy via Docker (already the pipeline's container-scan toolchain — no native
# install). The security agent runs this; documentation surfaces the component count
# in the PR description's Supply-chain section. Non-gating — the SBOM is a provenance
# artifact, not a gate. (Signed/attached SBOM in the build is PR M territory.)
#
# Graceful no-op: if Docker isn't running it prints a note and exits 0 (best-effort,
# like the rest of the container toolchain) — a missing SBOM never blocks the pipeline.
set -uo pipefail

[ -f .pipeline/state.json ] || exit 0   # pipeline-project guard

OUT=".pipeline/sbom.cdx.json"
IMAGE="${TRIVY_IMAGE:-aquasec/trivy}"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "[generate-sbom] Docker not available — skipping SBOM (best-effort; not a gate)." >&2
  exit 0
fi

# `pwd -W` gives the Windows path Docker Desktop accepts; MSYS_NO_PATHCONV stops Git
# Bash rewriting the in-container paths (mirrors trivy-scan.sh).
HOST_DIR="$(pwd -W 2>/dev/null || pwd)"
mkdir -p .pipeline

if MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
    --entrypoint trivy \
    -v "${HOST_DIR}:/src" \
    -v trivy-cache:/root/.cache/ \
    -w /src \
    "$IMAGE" fs --format cyclonedx --output "/src/$OUT" . >/dev/null 2>&1; then
  if command -v jq >/dev/null 2>&1 && [ -f "$OUT" ]; then
    N="$(jq -r '(.components // []) | length' "$OUT" 2>/dev/null || echo '?')"
    echo "[generate-sbom] wrote $OUT (CycloneDX, $N components)."
  else
    echo "[generate-sbom] wrote $OUT (CycloneDX)."
  fi
  exit 0
fi
echo "[generate-sbom] Trivy SBOM generation failed — skipping (best-effort; not a gate)." >&2
exit 0
