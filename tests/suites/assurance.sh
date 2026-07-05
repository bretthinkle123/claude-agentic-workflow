#!/usr/bin/env bash
# assurance.sh — the reduced-assurance stamp (iOS plan Layer 3, honesty guarantee).
# run-summary.sh must stamp `assurance: "reduced (swift adapters absent)"` on a Swift/iOS target
# whose Swift language adapters aren't built yet (the deterministic gates run but analyze little
# Swift), and `standard` otherwise — so a Swift run can't be quietly described as "gate-verified".
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

RS="$REPO_ROOT/scripts/run-summary.sh"
echo "-- assurance (reduced-assurance stamp) --"

# Run run-summary.sh in a throwaway git repo seeded per KIND; echo the resulting .assurance.
assurance_of() {  # <kind: python|swift|claude-ios|swift-adapters>
  local kind="$1" w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    git init -q; git config user.email a@b.c; git config user.name t
    mkdir -p .pipeline
    printf '{"stage":"security","model":"opus","status":"clean"}\n' > .pipeline/run-log.jsonl
    case "$kind" in
      python)         printf 'def add(a, b):\n    return a + b\n' > app.py ;;
      swift)          printf 'import SwiftUI\nstruct ContentView: View {}\n' > ContentView.swift ;;
      claude-ios)     printf 'Frontend: native iOS (SwiftUI), not the JS default.\n' > CLAUDE.md ;;
      swift-adapters) printf 'import SwiftUI\n' > ContentView.swift; printf '{}' > .pipeline/swift-adapters.json ;;
    esac
    git add -A >/dev/null 2>&1 || true
    bash "$RS" ) >/dev/null 2>&1
  jq -r '.assurance' "$w/.pipeline/run-summary.json" 2>/dev/null
}

assert_eq "standard" "$(assurance_of python)" "python-only project → assurance=standard"
assert_eq "reduced (swift adapters absent)" "$(assurance_of swift)"      "swift source present → assurance=reduced"
assert_eq "reduced (swift adapters absent)" "$(assurance_of claude-ios)" "CLAUDE.md declares native iOS/SwiftUI → assurance=reduced"
assert_eq "standard" "$(assurance_of swift-adapters)" "swift + adapters sentinel present → assurance=standard"

finish assurance
