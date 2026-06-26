# STRIDE — worked example

A sample threat model for an **"add MFA-protected funds transfer endpoint"**
feature. Use it as a shape reference, not a checklist to copy verbatim.

## Assets and trust boundaries

- **Assets:** the user's session/ID token, the `mfa_verified` claim, the transfer
  amount + destination, the funds themselves.
- **Boundaries:** browser ↔ API (untrusted client), API ↔ auth provider
  (Firebase), API ↔ datastore.

## Threat table

| Category | Asset / Boundary | Attack vector | Severity | Mitigation |
|---|---|---|---|---|
| Spoofing | Browser ↔ API | Forged/replayed ID token | High | Verify token server-side via `require_auth`; reject expired tokens |
| Tampering | Transfer request | Amount/destination altered in flight | High | TLS in transit; server-side validation; never trust client-supplied balances |
| Repudiation | Transfer action | User denies initiating a transfer | Medium | Audit log: hashed `userId`, `operation=transfer.create`, amount, timestamp |
| Information Disclosure | Error responses | Stack trace / internal IDs leak to client | Medium | Generic client errors; stack traces server-side only (see logging-conventions) |
| Denial of Service | Transfer endpoint | Rapid-fire transfers exhaust the service | Medium | Rate-limit per user; bound request size |
| Elevation of Privilege | `mfa_verified` claim | Reach the endpoint without completing MFA | High | Gate with `require_mfa` after `require_auth`; never check MFA client-side only |

## Accepted risks / out of scope

- Account recovery / device-loss flows — out of scope for this feature; handled
  by the existing auth onboarding path.
- Fraud scoring of transfer patterns — accepted risk for v1; flagged for a later
  feature.
