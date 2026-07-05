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
#   SC-4  Android  targetSdk below Google Play's floor (literal; indirection ⇒ advisory)    (critical)
#   SC-5  Android  debuggable / cleartext traffic in a release build                        (critical/warn)
# Deferred to a Layer-C follow-up (higher false-positive risk — used-API↔declaration compares):
#   SC-6 permission declared-vs-used, SC-7 debug logging in release, SC-9 Required-Reason API compare.
set -uo pipefail
[ -f .pipeline/state.json ] || exit 0          # ambient no-op outside a bootstrapped project
command -v jq >/dev/null 2>&1 || exit 0

# --- Deterministic scoping key (machine-checkable, fail-open) ---
APPLE=false; ANDROID=false
git ls-files 2>/dev/null | grep -qiE '(\.xcodeproj|(^|/)Info\.plist$|\.entitlements$|(^|/)PrivacyInfo\.xcprivacy$)' && APPLE=true
git ls-files 2>/dev/null | grep -qiE '((^|/)build\.gradle(\.kts)?$|(^|/)AndroidManifest\.xml$)' && ANDROID=true
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

# ---------- Apple ----------
if [ "$APPLE" = true ]; then
  APPLE_CFG=$(git ls-files 2>/dev/null | grep -iE '(Info\.plist$|project\.pbxproj$|\.entitlements$|PrivacyInfo\.xcprivacy$)')
  cfgtext=""; for f in $APPLE_CFG; do [ -f "$f" ] && cfgtext="$cfgtext"$'\n'"$(cat "$f" 2>/dev/null)"; done
  cfgflat=$(printf '%s' "$cfgtext" | tr '\n' ' ')

  # SC-1 — privacy manifest absent. Gated on a real app target (.xcodeproj) so a pre-scaffold repo
  # isn't flagged; a SHIPPING iOS app without PrivacyInfo.xcprivacy is an automated rejection.
  if git ls-files 2>/dev/null | grep -qiE '\.xcodeproj'; then
    git ls-files 2>/dev/null | grep -qiE '(^|/)PrivacyInfo\.xcprivacy$' || \
      add apple SC-1 critical "PrivacyInfo.xcprivacy privacy manifest absent from the app target (App Store automated rejection)"
  fi

  # SC-2 — a capability API used without its usage-description string (Info.plist OR the modern
  # pbxproj INFOPLIST_KEY_NS… build-setting form). Conservative API→key map; favors false-negatives.
  swiftsrc=$(git ls-files 2>/dev/null | grep -iE '\.(swift|m|mm)$')
  srctext=""; for f in $swiftsrc; do [ -f "$f" ] && srctext="$srctext"$'\n'"$(cat "$f" 2>/dev/null)"; done
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
fi

# ---------- Android ----------
if [ "$ANDROID" = true ]; then
  gtext=""; for f in $(git ls-files 2>/dev/null | grep -iE 'build\.gradle(\.kts)?$'); do [ -f "$f" ] && gtext="$gtext"$'\n'"$(cat "$f" 2>/dev/null)"; done
  mtext=""; for f in $(git ls-files 2>/dev/null | grep -iE 'AndroidManifest\.xml$');   do [ -f "$f" ] && mtext="$mtext"$'\n'"$(cat "$f" 2>/dev/null)"; done

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
  printf '%s' "$mtext" | grep -qiE 'android:debuggable[[:space:]]*=[[:space:]]*"true"' && \
    add android SC-5 critical 'android:debuggable="true" in the manifest — must be false for a release build'
  printf '%s' "$mtext" | grep -qiE 'android:usesCleartextTraffic[[:space:]]*=[[:space:]]*"true"' && \
    add android SC-5 warning 'android:usesCleartextTraffic="true" — disable cleartext traffic for release'
fi

CRIT=$(jq '[.[]|select(.severity=="critical")]|length' <<<"$findings" 2>/dev/null || echo 0)
WARN=$(jq '[.[]|select(.severity=="warning")]|length'  <<<"$findings" 2>/dev/null || echo 0)
TARGETS="$([ "$APPLE" = true ] && printf apple)"; [ "$ANDROID" = true ] && TARGETS="${TARGETS:+$TARGETS+}android"

jq -n --argjson f "$findings" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson c "${CRIT:-0}" --argjson w "${WARN:-0}" --arg scope "$TARGETS" \
  '{ran_at:$t, scope:$scope, critical:$c, warning:$w, findings:$f}' > "$OUT"

echo "[store-compliance] targets=$TARGETS — ${CRIT:-0} critical, ${WARN:-0} warning (Apple: manifest/SC-1, usage-strings/SC-2, ATS/SC-3, export/SC-8; Android: targetSdk/SC-4, debuggable-cleartext/SC-5) — see $OUT"
exit 0
