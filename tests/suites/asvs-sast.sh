#!/usr/bin/env bash
# asvs-sast.sh — Tier-1 deterministic ASVS scan (ASVS-DET slice A).
#  (1) DETECTION — the hook flags each high-precision pattern on a bad file and stays quiet on a
#      clean one (favouring false negatives over false positives).
#  (2) GATE FLOOR — deployment-gate.sh blocks on .pipeline/asvs-sast.json critical>0 (deploy-only);
#      absent file ⇒ 0 ⇒ no-op (backward compatible).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

SAST="$HOOKS/asvs-sast.sh"
GATE="$HOOKS/deployment-gate.sh"
echo "-- asvs-sast (ASVS-DET Tier 1) --"

# A throwaway git repo with .pipeline/state.json; the bad file is untracked (in the change set).
scan_repo() {  # <filename> <file-contents>  → echoes the .pipeline/asvs-sast.json critical count
  local fn="$1" body="$2" w
  w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"
    git init -q; git config user.email a@b.c; git config user.name t
    printf '.pipeline/\n' > .gitignore
    mkdir -p .pipeline; echo '{}' > .pipeline/state.json
    printf '%s\n' "$body" > "$fn"
    bash "$SAST" ) >/dev/null 2>&1
  jq -r '.critical' "$w/.pipeline/asvs-sast.json" 2>/dev/null
}

# (1) each rule fires on its bad pattern
assert_eq 1 "$(scan_repo app.py 'tok = jwt.decode(t, algorithms=["none"])')" "T1-1 JWT algorithms=[none] → 1 critical"
assert_eq 1 "$(scan_repo a.py   'jwt.decode(t, key, verify=False)')"         "T1-1 verify=False → 1 critical"
assert_eq 1 "$(scan_repo h.py   'digest = hashlib.md5(password.encode())')"  "T1-2 md5(password) → 1 critical"
assert_eq 1 "$(scan_repo r.py   'reset_token = random.randint(0, 999999)')"  "T1-3 random.randint→token → 1 critical"
assert_eq 1 "$(scan_repo j.js   'const secret = Math.random().toString(36)')" "T1-3 Math.random→secret → 1 critical"
assert_eq 1 "$(scan_repo c.py   'cipher = AES.new(key, AES.MODE_ECB)')"      "T1-4 AES MODE_ECB → 1 critical"

# clean code: no findings
assert_eq 0 "$(scan_repo ok.py 'def add(a, b):
    return a + b')" "clean file → 0 critical"
# good crypto is NOT flagged (bcrypt / secrets / GCM)
assert_eq 0 "$(scan_repo good.py 'ph = bcrypt.hashpw(password, bcrypt.gensalt())
tok = secrets.token_urlsafe(32)
c = AES.new(key, AES.MODE_GCM)')" "good crypto (bcrypt/secrets/GCM) → 0 critical"
# FALSE-POSITIVE regression guards (found in audit):
assert_eq 0 "$(scan_repo fp3.py 'token_index = random.randint(0, len(items))')" "FP: token_index=randint (an index) → 0 critical"
assert_eq 0 "$(scan_repo fp3b.py 'session_count = random.randint(1, 9)')"        "FP: session_count=randint → 0 critical"
assert_eq 0 "$(scan_repo fp4.py 'note = \"Uses DES historically\"  # RC4 mentioned too')" "FP: DES/RC4 in prose → 0 critical"
# ...but the real forms still fire after the tightening:
assert_eq 1 "$(scan_repo tp3.py 'access_token = random.random()')"  "access_token=random.random → 1 critical (still caught)"
assert_eq 1 "$(scan_repo tp4.py 'c = DES.new(key)')"                "DES.new( → 1 critical (still caught)"

# Slice C/D — warning-severity variant of scan_repo (echoes the .warning count).
scan_repo_w() {
  local fn="$1" body="$2" w; w="$(mktemp -d)"; _WORKDIRS+=("$w")
  ( cd "$w"; git init -q; git config user.email a@b.c; git config user.name t
    printf '.pipeline/\n' > .gitignore; mkdir -p .pipeline; echo '{}' > .pipeline/state.json
    printf '%s\n' "$body" > "$fn"; bash "$SAST" ) >/dev/null 2>&1
  jq -r '.warning' "$w/.pipeline/asvs-sast.json" 2>/dev/null
}

# T1-5 (Slice C, CRITICAL) — explicit cookie protection disabled
assert_eq 1 "$(scan_repo t5.py 'resp.set_cookie("sid", v, httponly=False)')" "T1-5 httponly=False → 1 critical"
assert_eq 1 "$(scan_repo t5b.py 'SESSION_COOKIE_SECURE = False')"            "T1-5 Django SESSION_COOKIE_SECURE=False → 1 critical"
assert_eq 0 "$(scan_repo t5ok.py 'resp.set_cookie("sid", v, httponly=True, secure=True)')" "FP: httponly=True (good) → 0 critical"
assert_eq 0 "$(scan_repo t5ok2.py 'SESSION_COOKIE_SECURE = True')"           "FP: SESSION_COOKIE_SECURE=True → 0 critical"
# T1-6/T1-7/T1-8 are WARNINGS (advisory) — 0 critical, >=1 warning
assert_eq 0 "$(scan_repo t6.py 'app.run(debug=True)')"                       "T1-6 app.run(debug=True) → 0 critical (advisory)"
assert_eq 1 "$(scan_repo_w t6.py 'app.run(debug=True)')"                     "T1-6 app.run(debug=True) → 1 warning"
assert_eq 1 "$(scan_repo_w t7.py 'CORS_HEADER = "Access-Control-Allow-Origin: *"')" "T1-7 CORS wildcard → 1 warning"
assert_eq 1 "$(scan_repo_w t8.py 'link = f\"https://x/reset?token={tok}\"')" "T1-8 token in URL query → 1 warning"
assert_eq 0 "$(scan_repo_w t8ok.py 'url = \"https://x/list?page=2&sort=asc\"')" "FP: benign query params → 0 warning"

# (2) gate floor on the count
gate_sast() {  # <want> <desc> <json|''>
  local want="$1" desc="$2" j="$3" w; w="$(mk_fixture)"
  [ -n "$j" ] && printf '%s' "$j" > "$w/.pipeline/asvs-sast.json"
  ( cd "$w" && bash "$GATE" ) >/dev/null 2>&1
  assert_eq "$want" "$?" "$desc"
}
gate_sast 2 "asvs-sast critical=2 → gate blocks" '{"critical":2,"warning":0,"findings":[]}'
gate_sast 0 "asvs-sast critical=0 → gate passes" '{"critical":0,"warning":1,"findings":[]}'
gate_sast 0 "no asvs-sast.json → gate passes (backward compat)" ''

finish asvs-sast
