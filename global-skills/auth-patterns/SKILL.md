---
name: auth-patterns
description: Firebase-default auth facade, OAuth 2.0 provider setup, the two Duo MFA paths, the mfa_verified custom-claim contract, and the require_auth/require_mfa/require_role guard pattern. Invoke when a feature touches identity or protected resources.
---

# Auth patterns

Invoke this when a feature involves user identity or protected resources. Default
provider is **Firebase Auth** (cloud-agnostic — Google-hosted, no GCP infra, runs
on AWS). **Amazon Cognito** is the AWS-single-vendor alternative; its scaffold
lives in `docs/pipeline-alternatives.md`, not here. Buildable default code is in
`scaffold/` (Python backend + JS frontend).

## The facade rule

Every route check goes through the backend guards — `require_auth` /
`require_mfa` / `require_role`. **No route calls `token` or the admin init
directly.** New code plugs into the facade; if a guard you need doesn't exist,
add it behind the facade rather than inlining a token check.

## The portability seam (`token`)

Each provider's `verify_id_token` returns a **normalized claims object** (`uid`,
`mfa_verified: bool`, `roles: list[str]`, …) so middleware is byte-identical
across providers. This is the one place provider differences are absorbed —
Cognito's string-typed `custom:mfa_verified` becomes a real boolean there,
matching Firebase.

## OAuth providers

Google + GitHub at minimum (enable in Firebase Console → Authentication →
Sign-in method). Add Microsoft/Apple the same way via `OAuthProvider` once
enabled. See `scaffold/oauth.ts`.

## Two Duo Mobile MFA paths — both converge on one claim

- **Path A — Firebase TOTP + Duo Mobile (recommended start).** Native Firebase
  TOTP (RFC 6238); Duo Mobile is the authenticator app. No Duo API account.
  Native TOTP completion does **not** set a custom claim by itself — a backend
  finalize-MFA endpoint calls `set_mfa_verified(uid, "totp")`.
- **Path B — Duo Universal Prompt.** Push notifications, device trust, Duo
  policy. Backend calls the Duo Auth API; the Duo callback calls
  `set_mfa_verified(uid, "duo-push")`. Requires a Duo account (ikey/skey/host).

Pick A unless push UX or enterprise device trust is required. Both set the same
`mfa_verified` (+ `mfa_method`) custom claim server-side, so one `require_mfa`
gates both.

## Custom-claim contract

```json
{ "uid": "...", "mfa_verified": true, "mfa_method": "totp", "roles": ["user"] }
```

Set server-side via `set_custom_user_claims` (Admin SDK). `mfa_verified` gates
protected resources; `mfa_method` is `"totp"` (Path A) or `"duo-push"` (Path B);
`roles` enables RBAC without a per-request lookup. The client must re-fetch its
ID token after the claim is set to pick up the elevated claim.

## Guard ordering

`require_auth` → `require_mfa` → `require_role`. MFA and role guards depend on
`require_auth` running first. See `scaffold/middleware.py`.
