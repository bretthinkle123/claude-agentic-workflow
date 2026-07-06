#!/bin/bash
# store-compliance.sh — Tier-1 deterministic app-store submission checks (store-compliance plan, Layer C).
#
# Makes the mechanically-checkable subset of Apple App Store / Google Play submission requirements a
# DETERMINISTIC gate, so an injected or sloppy agent cannot talk past a known auto-rejection cause.
# Wired EXACTLY like asvs-sast.sh: the hook writes its OWN .pipeline/store-compliance.json, runs as a
# security Stop hook (agent-independent), and deployment-gate.sh blocks on critical>0 (deploy-only,
# absent ⇒ 0 ⇒ no-op, NOT in the loop-exit predicate → zero loop-exit churn). Patterns are
# CONSERVATIVE — they favor a false negative over a false positive (a critical blocks the deploy).
#
# SCOPE = REPO STATE, not the diff (unlike asvs-sast): store-readiness is a whole-app property — an
# absent privacy manifest or a low targetSdk is a fact about the shipping app, not about one change.
#
# Activation = a DETERMINISTIC scoping key (a hook can't use planning's judgment). FAIL-OPEN: an
# undeclared target simply skips its checks (declaring only ADDS checks, so nothing is bypassed by
# omission). No store target ⇒ whole hook no-ops (default web/API runs cost nothing).
#
# Rules (critical → blocks via the gate floor; warning → advisory, surfaced by documentation):
#   SC-1  Apple    privacy manifest (PrivacyInfo.xcprivacy) absent from a real app target   (critical)
#   SC-2  Apple    a capability API used without its NS…UsageDescription string             (critical)
#   SC-3  Apple    App Transport Security disabled (NSAllowsArbitraryLoads = true)          (warning)
#   SC-8  Apple    export-compliance key (ITSAppUsesNonExemptEncryption) absent             (warning)
#   SC-9  Apple    Required-Reason API used without its declared reason category            (critical)
#   SC-4  Android  targetSdk below Google Play's floor (literal; indirection ⇒ advisory)    (critical)
#   SC-5  Android  debuggable / cleartext traffic in a release build                        (critical/warn)
#   SC-6  Android  permission declared-vs-used mismatch (conservative API↔permission map)   (warning)
#   SC-7  Both     debug-log flood / hardcoded localhost-emulator endpoint in release src   (warning)
# SC-6/7/9 are the Layer-C follow-up (used-API↔declaration compares). They keep the favour-FN
# posture: SC-9 is the only critical among them (it is what Apple's upload tooling hard-enforces)
# and runs only against an EXISTING privacy manifest (absence is already SC-1's critical); SC-6/7
# are advisory-only because their API maps are heuristic.
set -uo pipefail
[ -f .pipeline/state.json ] || exit 0          # ambient no-op outside a bootstrapped project
command -v jq >/dev/null 2>&1 || exit 0

# --- Deterministic scoping key (machine-checkable, fail-open) ---
# Keys ONLY on platform-SPECIFIC markers so a non-mobile project is never mis-activated: Apple = an
# .xcodeproj / PrivacyInfo.xcprivacy or an explicit declaration (NOT bare Info.plist/.entitlements —
# macOS/Electron desktop apps carry those); Android = an AndroidManifest.xml or an explicit
# declaration (NOT bare build.gradle — a Kotlin/Java backend uses Gradle too). Narrowing the trigger
# doesn't weaken the checks: a real iOS app has an .xcodeproj and a real Android app a manifest, and
# each rule still reads Info.plist/build.gradle content once its platform is triggered.
#
# lsfiles = every working-tree file that isn't gitignored — tracked AND untracked. This MUST include
# untracked: the deployment agent makes the pipeline's first/only commit LAST, so during the security
# stage (when this Stop hook fires) the app's own files (.xcodeproj, manifests, source) are typically
# UNCOMMITTED. Bare `git ls-files` (tracked only) would miss them and no-op on a real app.
lsfiles() { git ls-files --cached --others --exclude-standard 2>/dev/null; }
APPLE=false; ANDROID=false
lsfiles | grep -qiE '(\.xcodeproj|(^|/)PrivacyInfo\.xcprivacy$)' && APPLE=true
lsfiles | grep -qiE '(^|/)AndroidManifest\.xml$' && ANDROID=true
grep -riqE 'app store|native ios|swiftui' PROJECT.md CLAUDE.md 2>/dev/null && APPLE=true
grep -riqE 'google play|native android|jetpack compose' PROJECT.md CLAUDE.md 2>/dev/null && ANDROID=true

if [ "$APPLE" = false ] && [ "$ANDROID" = false ]; then
  echo "[store-compliance] no Apple/Google Play target declared — no-op."
  exit 0
fi

OUT=.pipeline/store-compliance.json
findings='[]'
add() {  # store rule sev "message"
  findings=$(jq -c --arg st "$1" --arg r "$2" --arg s "$3" --arg m "$4" \
    '. + [{store:$st, rule:$r, severity:$s, match:$m}]' <<<"$findings")
}

# Policy floors — POLICY-PINNED, verify annually (the stores change these on their schedule, not ours).
ANDROID_TARGET_SDK_FLOOR=35   # Google Play required targetSdk. # policy floor — verify annually
SC7_LOG_FLOOD=10              # SC-7: debug-log lines in release source above this count ⇒ advisory

# relsrc <path-ERE> — like readfiles, but EXCLUDES test/debug source sets (paths under a directory
# named *test*/*tests*/androidTest/debug): SC-7/SC-9 reason about what SHIPS in the release binary,
# and test code doesn't. Comment-stripped like the SC-2 scan (same favour-FN rationale) — but the
# strip is ://-AWARE (`//` preceded by `:` survives), or it would eat the very http://localhost /
# http://10.0.2.2 URLs SC-7's test-endpoint check exists to find.
relsrc() {
  lsfiles | grep -iE "$1" | grep -viE '(^|/)[^/]*tests?/|(^|/)(androidtest|debug)/' \
    | while IFS= read -r f; do [ -f "$f" ] && { cat "$f" 2>/dev/null; printf '\n'; }; done \
    | sed -E 's#(^|[^:])//.*#\1#'
}

# readfiles <grep-ERE> — concatenate the content of every working-tree file whose PATH matches the
# ERE, safe against spaces in filenames (`My App.xcodeproj`): reads the path list line-by-line with
# `read -r` instead of word-splitting `for f in $(…)`, which split a spaced path into non-existent
# fragments and silently dropped that file's content from the scan (a false negative).
readfiles() { lsfiles | grep -iE "$1" | while IFS= read -r f; do [ -f "$f" ] && { cat "$f" 2>/dev/null; printf '\n'; }; done; }

# ---------- Apple ----------
if [ "$APPLE" = true ]; then
  cfgtext=$(readfiles '(Info\.plist$|project\.pbxproj$|\.entitlements$|PrivacyInfo\.xcprivacy$)')
  cfgflat=$(printf '%s' "$cfgtext" | tr '\n' ' ')

  # SC-1 — privacy manifest absent. Gated on a real app target (.xcodeproj) so a pre-scaffold repo
  # isn't flagged; a SHIPPING iOS app without PrivacyInfo.xcprivacy is an automated rejection.
  if lsfiles | grep -qiE '\.xcodeproj'; then
    lsfiles | grep -qiE '(^|/)PrivacyInfo\.xcprivacy$' || \
      add apple SC-1 critical "PrivacyInfo.xcprivacy privacy manifest absent from the app target (App Store automated rejection)"
  fi

  # SC-2 — a capability API used without its usage-description string (Info.plist OR the modern
  # pbxproj INFOPLIST_KEY_NS… build-setting form). Conservative API→key map; favors false-negatives.
  # Strip `//` line comments before the capability-API scan so a class name mentioned only in a
  # comment doesn't trigger SC-2 — a false positive there would block a deploy; dropping the comment
  # errs to a false negative, the accepted posture. Block comments / string literals remain a residual.
  srctext=$(readfiles '\.(swift|m|mm)$' | sed 's#//.*##')
  cap() {  # api-ERE  key-token  human
    printf '%s' "$srctext" | grep -qiE "$1" || return 0
    printf '%s' "$cfgflat" | grep -qi "$2" || \
      add apple SC-2 critical "$3 API used but $2 usage string is absent from Info.plist/pbxproj (runtime crash + rejection)"
  }
  cap '\bAVCaptureDevice\b|\bAVCaptureSession\b' 'NSCameraUsageDescription'            'Camera'
  cap '\bCLLocationManager\b'                    'NSLocationWhenInUseUsageDescription' 'Location'
  cap '\bPHPhotoLibrary\b|\bPHPickerViewController\b' 'NSPhotoLibraryUsageDescription' 'Photo library'
  cap '\bLAContext\b'                            'NSFaceIDUsageDescription'            'Face ID'
  cap '\bATTrackingManager\b'                    'NSUserTrackingUsageDescription'      'App Tracking Transparency'

  # SC-3 (advisory) — App Transport Security disabled. Flatten first so the XML key/<true/> pair
  # (on separate lines) and the assignment form both match.
  if printf '%s' "$cfgflat" | grep -qiE 'NSAllowsArbitraryLoads</key>[[:space:]]*<true' \
     || printf '%s' "$cfgflat" | grep -qiE 'NSAllowsArbitraryLoads[[:space:]]*[=:][[:space:]]*(true|1)\b'; then
    add apple SC-3 warning "NSAllowsArbitraryLoads = true disables App Transport Security — scope the exception to specific domains instead"
  fi

  # SC-8 (advisory) — export-compliance key absent → a manual question on EVERY upload.
  printf '%s' "$cfgflat" | grep -qi 'ITSAppUsesNonExemptEncryption' || \
    add apple SC-8 warning "ITSAppUsesNonExemptEncryption absent — set it (usually false) to skip the export-compliance question on every upload"

  # SC-9 — a Required-Reason API used without its reason category declared in PrivacyInfo.xcprivacy.
  # THIS compare — not SC-1's mere manifest presence — is what Apple's upload tooling hard-enforces.
  # Runs only when a manifest EXISTS (an absent manifest is already SC-1's critical; no double-count)
  # and only over RELEASE source (relsrc — test code doesn't ship). The API surface is conservative:
  # only unambiguous, case-sensitive identifiers; bare .creationDate/.modificationDate are omitted
  # (common on photo/calendar objects — a critical false positive would block a deploy; favour-FN).
  privtext=$(readfiles '(^|/)PrivacyInfo\.xcprivacy$')
  if [ -n "$privtext" ]; then
    relsw=$(relsrc '\.(swift|m|mm)$')
    rra() {  # api-ERE  category  human
      printf '%s' "$relsw" | grep -qE "$1" || return 0
      printf '%s' "$privtext" | grep -qi "$2" || \
        add apple SC-9 critical "$3 Required-Reason API used but $2 is not declared in PrivacyInfo.xcprivacy (App Store automated rejection)"
    }
    rra '\bUserDefaults\b|\bNSUserDefaults\b'                                            'NSPrivacyAccessedAPICategoryUserDefaults'    'UserDefaults'
    rra 'fileModificationDate|creationDateKey|contentModificationDateKey|getattrlist|\bfstat(at)?\(|\blstat\(' 'NSPrivacyAccessedAPICategoryFileTimestamp' 'File-timestamp'
    rra 'volumeAvailableCapacity|systemFreeSize|\bstatv?fs\(|\bfstatfs\('                'NSPrivacyAccessedAPICategoryDiskSpace'       'Disk-space'
    rra '\bactiveInputModes\b'                                                           'NSPrivacyAccessedAPICategoryActiveKeyboards' 'Active-keyboard'
    rra '\bsystemUptime\b|\bmach_absolute_time\('                                        'NSPrivacyAccessedAPICategorySystemBootTime'  'System-boot-time'
  fi

  # SC-7 (advisory) — debug-log flood / test endpoints in release source. iOS has no release/debug
  # source-set split, so "release source" = everything outside test dirs. A handful of prints is
  # normal; only a FLOOD (> $SC7_LOG_FLOOD lines) or a hardcoded localhost endpoint is surfaced.
  relsw_sc7=${relsw:-$(relsrc '\.(swift|m|mm)$')}
  ioslogs=$(printf '%s' "$relsw_sc7" | grep -cE '\bprint\(|\bdebugPrint\(|\bNSLog\(' || true)
  [ "${ioslogs:-0}" -gt "$SC7_LOG_FLOOD" ] 2>/dev/null && \
    add apple SC-7 warning "$ioslogs debug-log lines (print/debugPrint/NSLog) in release source (> $SC7_LOG_FLOOD) — strip or wrap in #if DEBUG before store review"
  printf '%s' "$relsw_sc7" | grep -qE 'https?://(localhost|127\.0\.0\.1)' && \
    add apple SC-7 warning "hardcoded localhost endpoint in release source — a leftover test hook is store-review noise and dead in production"
fi

# ---------- Android ----------
if [ "$ANDROID" = true ]; then
  gtext=$(readfiles 'build\.gradle(\.kts)?$')
  mtext=$(readfiles 'AndroidManifest\.xml$')

  # SC-4 — targetSdk below Google's floor. Resolve the literal; an unresolvable variable/version-
  # catalog indirection is an ADVISORY "unresolved", never a silent pass (the one check Google
  # hard-blocks uploads on).
  tsdk=$(printf '%s' "$gtext" | grep -ioE 'targetSdk(Version)?[[:space:]]*[=( ][[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
  if [ -n "$tsdk" ]; then
    [ "$tsdk" -lt "$ANDROID_TARGET_SDK_FLOOR" ] 2>/dev/null && \
      add android SC-4 critical "targetSdk $tsdk is below Google Play's floor $ANDROID_TARGET_SDK_FLOOR (upload blocked)"
  elif printf '%s' "$gtext" | grep -qiE 'targetSdk'; then
    add android SC-4 warning "targetSdk set via an unresolved variable/version-catalog — verify it meets Google Play's floor $ANDROID_TARGET_SDK_FLOOR"
  fi

  # SC-5 — debuggable (critical) / cleartext (advisory) in a release build.
  # (a) Legacy manifest form: android:debuggable="true".
  printf '%s' "$mtext" | grep -qiE 'android:debuggable[[:space:]]*=[[:space:]]*"true"' && \
    add android SC-5 critical 'android:debuggable="true" in the manifest — must be false for a release build'
  # (b) Modern Gradle form (the COMMON case): debuggable enabled in the RELEASE buildType. This is
  # BLOCK-AWARE on purpose — a plain `debuggable true` grep would also fire on the legitimate
  # `debug { debuggable true }` buildType, a deploy-blocking FALSE POSITIVE. `release_debuggable`
  # extracts only the body of release buildType blocks (release {…} / getByName("release") {…} /
  # create("release") {…}) by brace-matching, then looks for a debuggable-enable inside. Comments and
  # http:// URLs are stripped and single→double quotes normalised first, and the walker is STRING-AWARE
  # (a `{`/`}` inside a "…" literal — e.g. a resValue template `"Hi {name}"` — does not move the brace
  # depth, so it can't misattribute a later debug block to release) — without that, an unbalanced brace
  # in a string was a deploy-blocking false positive. Any construct it can't resolve to a release block
  # is simply NOT flagged (favour-FN).
  release_debuggable() {  # stdin: gradle text → prints the concatenated body of every release block
    sed -E ':a;s@/\*[^*]*\*+([^/*][^*]*\*+)*/@ @;ta' \
      | sed -E "s@(^|[[:space:]])//.*@\1@; s@'@\"@g" \
      | awk '
        { doc = doc $0 "\n" }
        END {
          n = length(doc); depth = 0; tok = ""; last = ""; relopen = -1; instr = 0
          for (i = 1; i <= n; i++) {
            c = substr(doc, i, 1)
            if (c == "\"") { instr = 1 - instr; tok = tok c; if (relopen != -1) out = out c; continue }
            if (!instr && c == "{") {
              depth++
              lbl = (tok != "" ? tok : last)
              if (relopen == -1 && tolower(lbl) ~ /(^|[^a-z0-9])release([^a-z0-9]|$)/) relopen = depth
              tok = ""; last = ""; continue
            }
            if (!instr && c == "}") { if (relopen == depth) relopen = -1; if (depth > 0) depth--; tok = ""; last = ""; continue }
            if (c ~ /[A-Za-z0-9_.()]/) { tok = tok c } else { if (tok != "") { last = tok; tok = "" } }
            if (relopen != -1) out = out c
          }
          print out
        }'
  }
  printf '%s' "$gtext" | release_debuggable | grep -qiE '(is)?debuggable[[:space:]]*[=(]?[[:space:]]*true' && \
    add android SC-5 critical 'debuggable enabled in the release buildType (Gradle) — must be false/absent for a release build'
  printf '%s' "$mtext" | grep -qiE 'android:usesCleartextTraffic[[:space:]]*=[[:space:]]*"true"' && \
    add android SC-5 warning 'android:usesCleartextTraffic="true" — disable cleartext traffic for release'

  # SC-6 (advisory) — permission declared-vs-used mismatch, BOTH directions, over a CONSERVATIVE
  # API↔permission map (only unambiguous framework classes; a permission outside the map is never
  # judged). used-but-undeclared = a runtime failure waiting; declared-but-unused = a Play
  # Data-safety red flag (reviewers compare the form against the manifest). Advisory only — the
  # map is heuristic (reflection, libraries, and dynamic requests are invisible to a grep).
  droidsrc=$(relsrc '\.(kt|java)$')
  # mflat: the declaration grep must run on FLATTENED manifest text — Android Studio's default
  # formatting puts android:name= on its own line under <uses-permission, and a line-based grep
  # would read a properly-declared permission as undeclared (an advisory FP one way and a silent
  # FN the other). Same flatten rationale as the Apple cfgflat.
  mflat=$(printf '%s' "$mtext" | tr '\n' ' ')
  perm() {  # api-ERE  manifest-perm-ERE  human
    local used=false decl=false
    printf '%s' "$droidsrc" | grep -qE "$1" && used=true
    printf '%s' "$mflat" | grep -qiE "uses-permission[^>]*android\.permission\.($2)" && decl=true
    if [ "$used" = true ] && [ "$decl" = false ]; then
      add android SC-6 warning "$3 API used but no matching <uses-permission> in AndroidManifest.xml (runtime failure + Data-safety mismatch)"
    elif [ "$used" = false ] && [ "$decl" = true ]; then
      add android SC-6 warning "$3 permission declared in AndroidManifest.xml but no matching API use found — unused permissions are a Play Data-safety red flag"
    fi
  }
  perm '\bCameraManager\b|\bcamera2\b|\bCamera\.open\('            'CAMERA'                        'Camera'
  perm '\bAudioRecord\b|\bMediaRecorder\b'                         'RECORD_AUDIO'                  'Record-audio'
  perm '\bFusedLocationProviderClient\b|\bLocationManager\b'       'ACCESS_(FINE|COARSE)_LOCATION' 'Location'
  perm '\bContactsContract\b'                                      'READ_CONTACTS'                 'Contacts'
  perm '\bBluetoothAdapter\b|\bBluetoothManager\b'                 'BLUETOOTH(_CONNECT|_SCAN)?'    'Bluetooth'

  # SC-7 (advisory) — debug-log flood / emulator-endpoint in release source sets (test/androidTest/
  # debug source sets are excluded by relsrc; 10.0.2.2 is the Android-emulator host alias).
  droidlogs=$(printf '%s' "$droidsrc" | grep -cE '\bLog\.[dv]\(' || true)
  [ "${droidlogs:-0}" -gt "$SC7_LOG_FLOOD" ] 2>/dev/null && \
    add android SC-7 warning "$droidlogs Log.d/Log.v lines in release source (> $SC7_LOG_FLOOD) — strip or guard with BuildConfig.DEBUG before release"
  printf '%s' "$droidsrc" | grep -qE 'https?://(localhost|127\.0\.0\.1|10\.0\.2\.2)' && \
    add android SC-7 warning "hardcoded localhost/emulator (10.0.2.2) endpoint in release source — a leftover test hook is dead in production"
fi

CRIT=$(jq '[.[]|select(.severity=="critical")]|length' <<<"$findings" 2>/dev/null || echo 0)
WARN=$(jq '[.[]|select(.severity=="warning")]|length'  <<<"$findings" 2>/dev/null || echo 0)
TARGETS="$([ "$APPLE" = true ] && printf apple)"; [ "$ANDROID" = true ] && TARGETS="${TARGETS:+$TARGETS+}android"

jq -n --argjson f "$findings" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson c "${CRIT:-0}" --argjson w "${WARN:-0}" --arg scope "$TARGETS" \
  '{ran_at:$t, scope:$scope, critical:$c, warning:$w, findings:$f}' > "$OUT"

echo "[store-compliance] targets=$TARGETS — ${CRIT:-0} critical, ${WARN:-0} warning (Apple: manifest/SC-1, usage-strings/SC-2, ATS/SC-3, export/SC-8, required-reason/SC-9; Android: targetSdk/SC-4, debuggable-cleartext/SC-5, permissions/SC-6; both: debug-log/SC-7) — see $OUT"
exit 0
