# STRIDE — worked example

A sample threat model for an **"add MFA-protected funds transfer endpoint"**
feature. Use it as a shape reference, not a checklist to copy verbatim.

## Assets and trust boundaries

- **Assets:** the user's session/ID token, the `mfa_verified` claim, the transfer
  amount + destination, the funds themselves.
- **Boundaries:** browser ↔ API (untrusted client), API ↔ auth provider
  (Firebase), API ↔ datastore.

## Threat table

| Category | Asset / Boundary | Attack vector | Severity | Mitigation | ASVS req(s) |
|---|---|---|---|---|---|
| Spoofing | Browser ↔ API | Forged/replayed ID token | High | Verify token server-side via `require_auth`; reject expired tokens | 9.1.1, 7.2.1 |
| Tampering | Transfer request | Amount/destination altered in flight | High | TLS in transit; server-side validation; never trust client-supplied balances | 12.2.1, 2.2.2 |
| Repudiation | Transfer action | User denies initiating a transfer | Medium | Audit log: hashed `userId`, `operation=transfer.create`, amount, timestamp | 16.2.1 |
| Information Disclosure | Error responses | Stack trace / internal IDs leak to client | Medium | Generic client errors; stack traces server-side only (see logging-conventions) | 16.5.1 |
| Denial of Service | Transfer endpoint | Rapid-fire transfers exhaust the service | Medium | Rate-limit per user; bound request size | 2.4.1 |
| Elevation of Privilege | `mfa_verified` claim | Reach the endpoint without completing MFA | High | Gate with `require_mfa` after `require_auth`; never check MFA client-side only | 8.3.1, 6.3.3 |

## Accepted risks / out of scope

- Account recovery / device-loss flows — out of scope for this feature; handled
  by the existing auth onboarding path.
- Fraud scoring of transfer patterns — accepted risk for v1; flagged for a later
  feature.

## ASVS Compliance

L1 + L2 are the universal baseline (security verifies all triggered chapters).

- **Triggered chapters:** V2 (validation), V6 (auth), V7 (session), V8 (authz),
  V9 (ID token), V11 (crypto), V12 (TLS), V14 (data protection), V16 (logging).
  `n/a`: V5 (no file handling), V10 (no OAuth), V17 (no WebRTC).
- **In-scope L3** (money → high value): `6.3.5` suspicious-auth notification,
  `7.5.3` step-up auth before the transfer, `8.4.2` layered admin-interface
  protection. Other L3 items out of scope for v1.
- **Waivers:** none.
