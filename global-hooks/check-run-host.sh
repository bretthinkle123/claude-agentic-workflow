#!/bin/bash
# check-run-host.sh — name the isolation tier of the current run location (CN2-3).
#
# The usage-daily canary executed in the OneDrive/Windows clone because nothing at
# kickoff said WHERE the run was standing — the operator's terminal choice silently
# decided the isolation tier, and OneDrive quarantined the venv mid-run to prove it.
# The orchestrator runs this at kickoff (step 0) and SURFACES the verdict to the
# operator; a non-zero result is advisory — the human decides whether a
# convenience-tier location is acceptable for this run. Never a hard gate: Windows
# runs are legitimate (engine dev, trusted attended work).
#
# Usage: check-run-host.sh [path]     (path defaults to $PWD; arg exists for tests)
# Exit:  0 = WSL/Linux native FS (sandbox-eligible)
#        2 = Windows host (convenience tier — sandbox does not apply)
#        3 = worst case: /mnt/* or OneDrive path (Windows profile blast radius +
#            sync corruption hazard — strongly advise relocating before running)
set -uo pipefail
P="${1:-$PWD}"

case "$P" in
  /mnt/*)
    echo "[run-host] WARNING: $P is the WINDOWS filesystem seen from WSL (/mnt/*)." >&2
    echo "[run-host] Sandbox properties DO NOT apply: writes land in the Windows profile," >&2
    echo "[run-host] OneDrive may sync/quarantine live run state, and 9P is slow." >&2
    echo "[run-host] Use the WSL-native clone (e.g. ~/repos/<app>) instead." >&2
    exit 3 ;;
  *OneDrive*)
    echo "[run-host] WARNING: $P is under OneDrive — live .pipeline/venv state will be synced" >&2
    echo "[run-host] and can be quarantined mid-run (this happened: usage-daily canary)." >&2
    exit 3 ;;
esac

if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null || [ "$(uname -s)" = "Linux" ]; then
  echo "[run-host] OK: WSL/Linux native filesystem ($P) — sandbox-eligible."
  exit 0
fi

echo "[run-host] NOTE: running on the Windows host — convenience tier only; the WSL sandbox does not apply to this run." >&2
exit 2
