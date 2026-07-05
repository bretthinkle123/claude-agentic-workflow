#!/bin/bash
# asvs-sast.sh — Tier-1 deterministic ASVS 5.0.0 checks (ASVS-DET roadmap, slice A).
#
# Promotes a small set of HIGH-value, HIGH-precision ASVS requirements from agent-reasoned (security
# 6g) to a deterministic grep scan over the diff-scoped change set. Patterns are deliberately
# CONSERVATIVE — they favor a false negative over a false positive, because a finding here is a
# critical that blocks the deploy. Cross-language (Python / JS / TS / a few others).
#
# Rules (critical → blocks via the gate floor; warning → advisory, folds into warning_count):
#   T1-1  9.1.2   JWT 'none' algorithm / signature verification disabled                (critical)
#   T1-2  11.4.2  password stored with a fast hash instead of a slow KDF                (critical)
#   T1-3  11.5.1  non-CSPRNG (random / Math.random) directly feeding a security value   (critical)
#   T1-4  11.3.1  insecure cipher / mode (ECB, DES, RC4, PKCS#1 v1.5)                    (critical)
#   T1-5  3.3.1   session/CSRF cookie explicitly stripped of HttpOnly/Secure (Slice C)  (critical)
#   T1-6  13.4.2  debug server on / stack trace returned to the client (Slice C)         (warning)
#   T1-7  3.4.x   CORS wildcard / unsafe-inline CSP / X-Frame-Options ALLOWALL (Slice D) (warning)
#   T1-8  14.2.1  a sensitive value carried in a URL query string (Slice D)              (warning)
#
# Writes .pipeline/asvs-sast.json {ran_at, scope, critical, warning, findings[]}. Two consumers:
#   - the security agent reads it and FIXES criticals (they fold into critical_count → the loop);
#   - deployment-gate.sh reads it as a DEPLOY-ONLY deterministic backstop (blocks on critical>0),
#     so an agent that ignores a finding still can't ship it. Absent file ⇒ 0 ⇒ no-op (like the
#     waiver/mutation checks), so this is NOT in the loop-exit predicate — no loop-exit churn.
# Wired as a Stop hook on the security agent (guaranteed to run, agent-independent).
set -uo pipefail
[ -f .pipeline/state.json ] || exit 0          # ambient no-op outside a bootstrapped project
command -v jq >/dev/null 2>&1 || exit 0         # no jq ⇒ can't emit JSON (the gate fails closed on jq anyway)

OUT=.pipeline/asvs-sast.json

# Diff-scoped change set (tracked changes since HEAD + untracked new files); full tree pre-first-commit.
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  mapfile -t FILES < <({ git diff HEAD --name-only; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
else
  mapfile -t FILES < <(git ls-files --others --exclude-standard 2>/dev/null | sort -u)
fi

CODE=()
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.py|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.java|*.go|*.rb|*.php|*.cs) CODE+=("$f") ;;
  esac
done

findings='[]'
scan() {  # rule asvs sev "ERE"
  local rule="$1" asvs="$2" sev="$3" re="$4" f line text
  [ "${#CODE[@]}" -eq 0 ] && return 0
  for f in "${CODE[@]}"; do
    while IFS=: read -r line text; do
      [ -n "$line" ] || continue
      text="$(printf '%s' "$text" | sed 's/^[[:space:]]*//' | cut -c1-160)"
      findings=$(jq -c --arg r "$rule" --arg a "$asvs" --arg s "$sev" --arg f "$f" --argjson l "$line" --arg m "$text" \
        '. + [{rule:$r, asvs:$a, severity:$s, file:$f, line:$l, match:$m}]' <<<"$findings")
    done < <(grep -nEi "$re" "$f" 2>/dev/null)
  done
}

# T1-1 — JWT 'none' algorithm / verification disabled.
scan T1-1 9.1.2 critical 'algorithms[[:space:]]*[:=][[:space:]]*\[?[[:space:]]*["'"'"']none["'"'"']'
scan T1-1 9.1.2 critical '(^|[^a-z])alg[[:space:]]*[:=][[:space:]]*["'"'"']none["'"'"']'
scan T1-1 9.1.2 critical 'verify_signature["'"'"']?[[:space:]]*[:=][[:space:]]*false'
scan T1-1 9.1.2 critical 'jwt\.decode\([^)]*verify[[:space:]]*=[[:space:]]*false'
# T1-2 — password fed to a fast hash (proximity, both directions).
scan T1-2 11.4.2 critical '(password|passwd|passphrase)[a-z0-9_]*[^=;\n]{0,40}\b(md5|sha1|sha224|sha256|sha384|sha512)\b[[:space:]]*\('
scan T1-2 11.4.2 critical '\b(md5|sha1|sha224|sha256|sha384|sha512)\b[[:space:]]*\([^)\n]{0,60}(password|passwd|passphrase)'
# T1-3 — non-CSPRNG directly assigned to a security value. The security term must be a WHOLE word
# (or a known compound like access_token) — NOT a prefix — so `token_index = random.randint(...)`
# (an index, not a token) does not false-positive.
scan T1-3 11.5.1 critical '\b(access[_-]?token|refresh[_-]?token|session[_-]?token|reset[_-]?token|csrf[_-]?token|api[_-]?key|secret[_-]?key|token|secret|nonce|otp|salt)\b[[:space:]]*[:=][^=\n]{0,40}(math\.random|random\.(random|randint|randrange))[[:space:]]*\('
# T1-4 — insecure cipher / mode / padding. Weak-algorithm words must be in a CALL/constructor
# context (`DES.new(`, `Cipher.getInstance("DES…`) — NOT bare — so the word "DES"/"RC4" in a string
# or comment does not false-positive.
scan T1-4 11.3.1 critical '(mode_ecb|aes/ecb|pkcs1v15|\b(des|3des|tripledes|desede|rc4|arc4|rc2)\b[[:space:]]*[.(]|getinstance\([[:space:]]*["'"'"'](des|rc4|desede|rc2|3des))'
# T1-5 (Slice C) — 3.3.1/3.3.4 — a session/CSRF cookie EXPLICITLY stripped of its protection.
# Only the explicit-disable forms (high confidence, low FP); absence-of-a-flag is deliberately NOT
# matched (it's framework-defaulted and un-greppable). `httponly=false` is essentially always a bug
# (JS-readable session cookie → XSS theft); the Django *_SECURE/_HTTPONLY=False settings are explicit.
scan T1-5 3.3.1 critical '\b(httponly|http_only)[[:space:]]*[:=][[:space:]]*(false|0)\b'
scan T1-5 3.3.1 critical '\b(session_cookie_secure|csrf_cookie_secure|session_cookie_httponly)[[:space:]]*=[[:space:]]*false\b'
# T1-6 (Slice C) — 13.4.2/16.5.1 — debug server / stack traces to the client. WARNING (Medium; a
# `debug=true` can legitimately appear in a dev-only config, so it is advisory, not a block). The
# Flask `app.run(debug=True)` form is the clearest prod-serving case.
scan T1-6 13.4.2 warning 'app\.run\([^)]*debug[[:space:]]*=[[:space:]]*true'
scan T1-6 13.4.2 warning '\bflask_debug[[:space:]]*[:=][[:space:]]*(1|true)\b'
scan T1-6 16.5.1 warning 'return[^\n]{0,40}traceback\.format_exc\('
# T1-7 (Slice D) — 3.4.x — weak/overbroad response-security config. WARNING (framework-ambiguous):
# an explicit CORS wildcard, a CSP that permits unsafe-inline/eval, or X-Frame-Options ALLOWALL.
scan T1-7 3.4.1 warning 'access-control-allow-origin["'"'"']?[[:space:]]*[,:=][[:space:]]*["'"'"']?\*'
scan T1-7 3.4.5 warning 'content-security-policy[^\n]{0,120}unsafe-(inline|eval)'
scan T1-7 3.4.3 warning 'x-frame-options[[:space:]]*[:=][[:space:]]*["'"'"']?allowall'
# T1-8 (Slice D) — 14.2.1 — a sensitive value carried in a URL query string (logged/cached/refererd).
# WARNING (heuristic): a query param named for a secret/PII field.
scan T1-8 14.2.1 warning '[?&](password|passwd|token|access[_-]?token|api[_-]?key|apikey|secret|ssn|card|cvv)=[^&"'"'"'[:space:]]'

CRIT=$(jq '[.[]|select(.severity=="critical")]|length' <<<"$findings" 2>/dev/null || echo 0)
WARN=$(jq '[.[]|select(.severity=="warning")]|length'  <<<"$findings" 2>/dev/null || echo 0)

jq -n --argjson f "$findings" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson c "${CRIT:-0}" --argjson w "${WARN:-0}" \
  '{ran_at:$t, scope:"diff", critical:$c, warning:$w, findings:$f}' > "$OUT"

echo "[asvs-sast] ${CRIT:-0} critical, ${WARN:-0} warning (ASVS Tier-1: JWT-none/9.1.2, pw-KDF/11.4.2, CSPRNG/11.5.1, cipher/11.3.1, cookie/3.3.1; advisory: debug/13.4.2, headers/3.4.x, url-secrets/14.2.1) — see $OUT"
exit 0
