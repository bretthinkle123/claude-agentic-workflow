#!/usr/bin/env bash
# verify-sandbox.sh — assert the intrusion-tier hardening properties actually hold before
# you trust an unattended pipeline run (autonomy plan — the verifiable half of Phases 3/5/6).
#
# ON-DEMAND, NOT A GATE (yet). Nothing forces this to run — you invoke it when you want
# assurance. A fail-closed preflight that REFUSES to run the pipeline unless this passes is
# the intended follow-up, deliberately deferred until this check has run green in the real
# WSL2+proxy environment (prove-then-codify — a gate that false-blocks is worse than none).
#
# Exit 0 iff every REQUIRED property holds; nonzero + a labeled report otherwise. It is
# designed to FAIL SAFE: an un-hardened environment (this Windows dev host, no proxy) must
# report INCOMPLETE, never a false OK.
set -uo pipefail

FAIL=0
ok()   { printf '  [ok]   %s\n' "$1"; }
no()   { printf '  [FAIL] %s\n' "$1"; FAIL=1; }
warn() { printf '  [warn] %s\n' "$1"; }

echo "== pipeline sandbox verification =="

# 1. REQUIRED: running inside WSL2 / Linux, not the Windows (or macOS) host — so a hostile
#    dependency's install/test script executes in a disposable userland, not your profile.
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
  ok "running inside WSL ($(uname -r))"
elif [ "$(uname -s)" = "Linux" ]; then
  ok "running on Linux ($(uname -r)) — non-WSL; acceptable if this is an isolated host/VM"
else
  no "NOT inside WSL/Linux (uname=$(uname -s)) — the pipeline runs on the host OS; blast radius = your user profile"
fi

# 2. REQUIRED: no credential material readable from the pipeline environment.
creds_clean=1
for p in "$HOME/.aws" "$HOME/.ssh"; do
  if [ -d "$p" ] && [ -n "$(ls -A "$p" 2>/dev/null)" ]; then
    no "credential dir present and non-empty: $p (a compromised run could read it)"
    creds_clean=0
  fi
done
[ "$creds_clean" = 1 ] && ok "no ~/.aws or ~/.ssh credential material readable"

# 3. REQUIRED: GitHub auth exists as a token. Fine-grained scoping cannot be read back from
#    gh, so we confirm auth + surface the scope reminder (the token value is never printed).
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    ok "gh authenticated"
    warn "confirm the gh token is FINE-GRAINED and scoped to the target repo only (not auto-verifiable)"
  else
    no "gh not authenticated"
  fi
else
  warn "gh not installed (install in the pipeline environment before a real run)"
fi

# 4. REQUIRED: the egress proxy is wired AND actually enforces default-deny — proven by a
#    non-allowlisted host being REFUSED *while an allowlisted host succeeds*. The allowlisted
#    probe is a required conjunct, not a warning: if pypi.org can't get through, a "refusal"
#    of the deny-probe is indistinguishable from the proxy being down or unreachable from
#    this shell — exactly the false OK this script exists to never emit (found live
#    2026-07-10: an unresolvable proxy hostname made every curl fail and check 4 passed).
if [ -n "${HTTPS_PROXY:-}" ]; then
  ok "HTTPS_PROXY set ($HTTPS_PROXY)"
  if curl -fsS --max-time 8 -o /dev/null https://pypi.org 2>/dev/null; then
    ok "allowlisted host reachable through proxy (pypi.org)"
    # example.com is stable and deliberately NOT in egress-allowlist.txt: if it resolves, the
    # proxy is not enforcing default-deny.
    if curl -fsS --max-time 8 -o /dev/null https://example.com 2>/dev/null; then
      no "non-allowlisted host example.com was REACHABLE — proxy is NOT enforcing default-deny (log-only mode?)"
    else
      ok "non-allowlisted host refused (proxy enforcing default-deny)"
    fi
  else
    no "allowlisted host pypi.org NOT reachable through proxy — cannot prove enforcement (proxy down, unreachable from this shell, or ACL broken)"
  fi
else
  no "HTTPS_PROXY not set — shell egress is unrestricted (provision the egress proxy, Phase 5)"
fi

echo
if [ "$FAIL" = 0 ]; then
  echo "SANDBOX OK — required intrusion-tier properties hold."
else
  echo "SANDBOX INCOMPLETE — one or more REQUIRED properties failed (see [FAIL] above)."
  echo "Do NOT trust an unattended run against untrusted inputs until these pass."
fi
exit "$FAIL"
