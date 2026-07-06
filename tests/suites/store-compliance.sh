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
# NOTE: the files are left UNCOMMITTED and UNSTAGED on purpose — that is the real pipeline state when
# this security Stop hook fires (deployment makes the first commit LAST). It regression-guards the
# bug where the hook used bare `git ls-files` (tracked only) and silently no-oped on a real app.
store_scan() {
  local q="$1"; shift
  local w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"; git init -q; git config user.email a@b.c; git config user.name t
    printf '.pipeline/\n' > .gitignore; mkdir -p .pipeline; echo '{}' > .pipeline/state.json
    while [ $# -ge 2 ]; do
      case "$1" in */*) mkdir -p "$(dirname "$1")" ;; esac
      printf '%s\n' "$2" > "$1"; shift 2
    done
    bash "$STORE" ) >/dev/null 2>&1   # deliberately NO `git add` — files stay untracked (real state)
  jq -rc "$q" "$w/.pipeline/store-compliance.json" 2>/dev/null
}

# (1) scoping — no store target → no-op, no JSON file written.
assert_eq "" "$(store_scan '.critical' app.py 'def add(a,b): return a+b')" "no store target → no-op (no output file)"
# A Kotlin/Java Gradle BACKEND (Gradle but no AndroidManifest / no declaration) must NOT be scoped as
# Android — the over-broad-detection fix (bare build.gradle no longer triggers).
assert_eq "" "$(store_scan '.critical' build.gradle 'plugins { id "java" }')" "JVM/Gradle backend (no manifest/declaration) → no-op (not mis-scoped as Android)"

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
#   SC-1 NOT fired without a real .xcodeproj (Apple declared via PROJECT.md; pre-scaffold shouldn't flag)
assert_eq 0 "$(store_scan '.critical' PROJECT.md 'Target: native iOS (SwiftUI)' Info.plist '<plist><dict><key>ITSAppUsesNonExemptEncryption</key><false/></dict></plist>')" "Apple declared but no .xcodeproj → SC-1 not fired (no premature flag)"
#   SC-8 advisory (export-compliance key absent) — warning, not critical
assert_eq 1 "$(store_scan '.warning' App.xcodeproj/project.pbxproj '//' PrivacyInfo.xcprivacy 'x' Info.plist '<plist><dict/></plist>')" "SC-8 export key absent → 1 warning"
#   Clean Apple app (manifest + export key present, no capability API) → nothing
assert_eq 0 "$(store_scan '.critical' App.xcodeproj/project.pbxproj '//' Main.swift 'import Foundation' PrivacyInfo.xcprivacy 'x' Info.plist '<plist><dict><key>ITSAppUsesNonExemptEncryption</key><false/></dict></plist>')" "clean Apple app → 0 critical"
#   Spaced-path regression: the usage string lives in a pbxproj under a directory with a SPACE. The
#   old `for f in $(…)` word-split that path and dropped the file, wrongly firing SC-2. read -r fixes it.
assert_eq 0 "$(store_scan '.critical' \
  'My App.xcodeproj/project.pbxproj' 'INFOPLIST_KEY_NSCameraUsageDescription = "we use the camera";' \
  Cam.swift 'import AVFoundation
let d = AVCaptureDevice.default(for: .video)' \
  PrivacyInfo.xcprivacy 'x')" "spaced-path pbxproj is read (usage string found) → SC-2 not fired"
#   SC-2 comment FP: the capability class appears ONLY inside a // comment → must NOT fire (line
#   comments are stripped before the scan; erring to a false negative is the accepted posture).
assert_eq 0 "$(store_scan '.critical' \
  App.xcodeproj/project.pbxproj '//' \
  Cam.swift '// AVCaptureDevice is documented elsewhere, not used here
import Foundation' \
  PrivacyInfo.xcprivacy 'x')" "capability API only in a // comment → SC-2 not fired (no false positive)"

# (2) Android detection
#   SC-4 (targetSdk below floor) + SC-5 (debuggable release)
ANDROID_BAD_JSON="$(store_scan '{c:.critical,rules:[.findings[].rule]}' \
  build.gradle.kts 'android { targetSdk = 30 }' \
  AndroidManifest.xml '<manifest><application android:debuggable="true"/></manifest>')"
assert_eq 2 "$(printf '%s' "$ANDROID_BAD_JSON" | jq -r '.c')" "Android: low targetSdk + debuggable → 2 critical"
assert_eq "true" "$(printf '%s' "$ANDROID_BAD_JSON" | jq -r '.rules|index("SC-4")!=null')" "SC-4 (targetSdk below floor) fires"
#   SC-4 unresolved indirection → advisory, not a silent pass (manifest triggers Android scope)
assert_eq 1 "$(store_scan '.warning' AndroidManifest.xml '<manifest/>' build.gradle.kts 'android { targetSdk = libs.versions.target.get() }')" "SC-4 unresolved targetSdk indirection → 1 warning (never silent)"
#   Clean Android (targetSdk at floor, not debuggable) → nothing
assert_eq 0 "$(store_scan '.critical' build.gradle.kts 'android { targetSdk = 35 }' AndroidManifest.xml '<manifest><application/></manifest>')" "clean Android (targetSdk=floor) → 0 critical"
#   SC-5 Gradle form (Groovy): debuggable enabled in the RELEASE buildType → critical.
GRADLE_REL_JSON="$(store_scan '{c:.critical,rules:[.findings[].rule]}' \
  build.gradle 'android { targetSdk 35
  buildTypes { release { debuggable true } debug { debuggable true } } }' \
  AndroidManifest.xml '<manifest><application/></manifest>')"
assert_eq 1 "$(printf '%s' "$GRADLE_REL_JSON" | jq -r '.c')" "SC-5 Gradle: release{debuggable true} → 1 critical"
assert_eq "true" "$(printf '%s' "$GRADLE_REL_JSON" | jq -r '.rules|index("SC-5")!=null')" "SC-5 (Gradle release debuggable) fires"
#   THE SAFETY TEST: debuggable in the DEBUG buildType (release is false) must NOT fire — that would
#   be a deploy-blocking false positive. This is why the check is block-aware, not a plain grep.
assert_eq 0 "$(store_scan '.critical' \
  build.gradle 'android { targetSdk 35
  buildTypes { release { debuggable false } debug { debuggable true } } }' \
  AndroidManifest.xml '<manifest><application/></manifest>')" "debug{debuggable true}, release false → 0 critical (no false positive)"
#   SC-5 Gradle form (Kotlin DSL): getByName("release") { isDebuggable = true } → critical.
assert_eq "true" "$(store_scan '.findings|map(.rule)|index("SC-5")!=null' \
  build.gradle.kts 'android { buildTypes { getByName("release") { isDebuggable = true } } }' \
  AndroidManifest.xml '<manifest/>')" "SC-5 Kotlin DSL: getByName(\"release\"){isDebuggable=true} fires"
#   String-aware safety: an unbalanced brace inside a STRING literal in the release block must not
#   desync brace tracking and misattribute the debug block's debuggable to release (a deploy-blocking
#   false positive). release is debuggable=false here; only debug is true → must NOT fire.
assert_eq 0 "$(store_scan '.critical' \
  build.gradle 'android { buildTypes {
  release { resValue "string", "x", "brace{here"
           debuggable false }
  debug   { debuggable true }
} }' AndroidManifest.xml '<manifest><application/></manifest>')" "unbalanced { in a release string + debug debuggable → 0 critical (no false positive)"

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
