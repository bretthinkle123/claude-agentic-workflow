#!/usr/bin/env bash
# assurance.sh — the reduced-assurance stamp (iOS plan Layer 3 + store-compliance Layer E).
# run-summary.sh must stamp `assurance: "reduced (<lang> adapters absent)"` on a native-MOBILE
# target (Swift/iOS or Kotlin/Android) whose language gate adapters aren't built yet (the
# deterministic gates run but analyze little of that language), and `standard` otherwise — so a
# mobile run can't be quietly described as "gate-verified". Layer E adds the Android arm: Android
# has NO gate adapters today, so an Android target is always reduced (previously it slipped through
# as `standard` — the exact vacuous-green the stamp exists to prevent).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

RS="$REPO_ROOT/scripts/run-summary.sh"
echo "-- assurance (reduced-assurance stamp) --"

# Run run-summary.sh in a throwaway git repo seeded per KIND; echo the resulting .assurance.
assurance_of() {  # <kind: python|swift|claude-ios|swift-adapters|android|claude-android|android-adapters>
  local kind="$1" w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    git init -q; git config user.email a@b.c; git config user.name t
    mkdir -p .pipeline
    printf '{"stage":"security","model":"opus","status":"clean"}\n' > .pipeline/run-log.jsonl
    case "$kind" in
      python)          printf 'def add(a, b):\n    return a + b\n' > app.py ;;
      swift)           printf 'import SwiftUI\nstruct ContentView: View {}\n' > ContentView.swift ;;
      claude-ios)      printf 'Frontend: native iOS (SwiftUI), not the JS default.\n' > CLAUDE.md ;;
      swift-adapters)  printf 'import SwiftUI\n' > ContentView.swift; printf '{}' > .pipeline/swift-adapters.json ;;
      android)         printf 'class MainActivity : ComponentActivity()\n' > MainActivity.kt ;;
      claude-android)  printf 'Frontend: native Android (Kotlin/Compose), not the JS default.\n' > CLAUDE.md ;;
      android-adapters) printf 'class MainActivity\n' > MainActivity.kt; printf '{}' > .pipeline/android-adapters.json ;;
    esac
    git add -A >/dev/null 2>&1 || true
    bash "$RS" ) >/dev/null 2>&1
  jq -r '.assurance' "$w/.pipeline/run-summary.json" 2>/dev/null
}

assert_eq "standard" "$(assurance_of python)" "python-only project → assurance=standard"
# Swift/iOS arm (unchanged by Layer E)
assert_eq "reduced (swift adapters absent)" "$(assurance_of swift)"      "swift source present → assurance=reduced"
assert_eq "reduced (swift adapters absent)" "$(assurance_of claude-ios)" "CLAUDE.md declares native iOS/SwiftUI → assurance=reduced"
assert_eq "standard" "$(assurance_of swift-adapters)" "swift + adapters sentinel present → assurance=standard"
# Android arm (Layer E) — the hole this closes: a Kotlin/Gradle project must NOT be stamped standard
assert_eq "reduced (android adapters absent)" "$(assurance_of android)"         "kotlin source present → assurance=reduced (was the standard-stamp hole)"
assert_eq "reduced (android adapters absent)" "$(assurance_of claude-android)"  "CLAUDE.md declares native Android/Kotlin → assurance=reduced"
assert_eq "standard" "$(assurance_of android-adapters)" "android + adapters sentinel present → assurance=standard"

finish assurance
