#!/usr/bin/env bash
# store-compliance.sh — Tier-1 deterministic app-store compliance checks (store-compliance plan, Layer C).
#  (1) SCOPING — no Apple/Google Play target ⇒ whole hook no-ops (no file written).
#  (2) DETECTION — each critical/advisory fires on its bad fixture; a clean app yields nothing
#      (favouring false negatives over false positives, like asvs-sast).
#  (3) GATE FLOOR — deployment-gate.sh blocks on .pipeline/store-compliance.json critical>0
#      (deploy-only); absent file ⇒ 0 ⇒ no-op (backward compatible).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

STORE="$HOOKS/store-compliance.sh"
GATE="$HOOKS/deployment-gate.sh"
echo "-- store-compliance (Tier-1 app-store) --"

# Build a throwaway git repo from <file> <content> pairs, run the hook, echo a jq query on its JSON.
#   store_scan '<jq>' <file1> <content1> [<file2> <content2> ...]
store_scan() {
  local q="$1"; shift
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"; git init -q; git config user.email a@b.c; git config user.name t
    printf '.pipeline/\n' > .gitignore; mkdir -p .pipeline; echo '{}' > .pipeline/state.json
    while [ $# -ge 2 ]; do
      case "$1" in */*) mkdir -p "$(dirname "$1")" ;; esac
      printf '%s\n' "$2" > "$1"; shift 2
    done
    git add -A >/dev/null 2>&1
    bash "$STORE" ) >/dev/null 2>&1
  jq -rc "$q" "$w/.pipeline/store-compliance.json" 2>/dev/null
}

# (1) scoping — a plain Python project declares no store target → no-op, no JSON file written.
assert_eq "" "$(store_scan '.critical' app.py 'def add(a,b): return a+b')" "no store target → no-op (no output file)"

# (2) Apple detection
#   SC-1 (privacy manifest absent, gated on a real .xcodeproj) + SC-2 (camera API w/o usage string)
APPLE_BAD_JSON="$(store_scan '{c:.critical,rules:[.findings[].rule]}' \
  App.xcodeproj/project.pbxproj '// proj' \
  Camera.swift 'import AVFoundation
let d = AVCaptureDevice.default(for: .video)' \
  Info.plist '<plist><dict><key>CFBundleName</key><string>App</string></dict></plist>')"
assert_eq 2 "$(printf '%s' "$APPLE_BAD_JSON" | jq -r '.c')" "Apple: no manifest + camera-w/o-usage → 2 critical"
assert_eq "true" "$(printf '%s' "$APPLE_BAD_JSON" | jq -r '.rules|index("SC-1")!=null')" "SC-1 (privacy manifest absent) fires"
assert_eq "true" "$(printf '%s' "$APPLE_BAD_JSON" | jq -r '.rules|index("SC-2")!=null')" "SC-2 (capability API w/o usage string) fires"
#   SC-1 NOT fired without a real .xcodeproj (pre-scaffold repo shouldn't be flagged)
assert_eq 0 "$(store_scan '.critical' Info.plist '<plist><dict><key>ITSAppUsesNonExemptEncryption</key><false/></dict></plist>')" "Apple w/o .xcodeproj → SC-1 not fired (no premature flag)"
#   SC-8 advisory (export-compliance key absent) — warning, not critical
assert_eq 1 "$(store_scan '.warning' App.xcodeproj/project.pbxproj '//' PrivacyInfo.xcprivacy 'x' Info.plist '<plist><dict/></plist>')" "SC-8 export key absent → 1 warning"
#   Clean Apple app (manifest + export key present, no capability API) → nothing
assert_eq 0 "$(store_scan '.critical' App.xcodeproj/project.pbxproj '//' Main.swift 'import Foundation' PrivacyInfo.xcprivacy 'x' Info.plist '<plist><dict><key>ITSAppUsesNonExemptEncryption</key><false/></dict></plist>')" "clean Apple app → 0 critical"

# (2) Android detection
#   SC-4 (targetSdk below floor) + SC-5 (debuggable release)
ANDROID_BAD_JSON="$(store_scan '{c:.critical,rules:[.findings[].rule]}' \
  build.gradle.kts 'android { targetSdk = 30 }' \
  AndroidManifest.xml '<manifest><application android:debuggable="true"/></manifest>')"
assert_eq 2 "$(printf '%s' "$ANDROID_BAD_JSON" | jq -r '.c')" "Android: low targetSdk + debuggable → 2 critical"
assert_eq "true" "$(printf '%s' "$ANDROID_BAD_JSON" | jq -r '.rules|index("SC-4")!=null')" "SC-4 (targetSdk below floor) fires"
#   SC-4 unresolved indirection → advisory, not a silent pass
assert_eq 1 "$(store_scan '.warning' build.gradle.kts 'android { targetSdk = libs.versions.target.get() }')" "SC-4 unresolved targetSdk indirection → 1 warning (never silent)"
#   Clean Android (targetSdk at floor, not debuggable) → nothing
assert_eq 0 "$(store_scan '.critical' build.gradle.kts 'android { targetSdk = 35 }' AndroidManifest.xml '<manifest><application/></manifest>')" "clean Android (targetSdk=floor) → 0 critical"

# (3) gate floor on the critical count
gate_store() {  # <want-exit> <desc> <json|''>
  local want="$1" desc="$2" j="$3" w; w="$(mk_fixture)"
  [ -n "$j" ] && printf '%s' "$j" > "$w/.pipeline/store-compliance.json"
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq "$want" "$?" "$desc"
}
gate_store 2 "store-compliance critical=1 → gate blocks" '{"critical":1,"warning":0,"findings":[]}'
gate_store 0 "store-compliance critical=0 → gate passes" '{"critical":0,"warning":2,"findings":[]}'
gate_store 0 "no store-compliance.json → gate passes (backward compat)" ''

finish store-compliance
