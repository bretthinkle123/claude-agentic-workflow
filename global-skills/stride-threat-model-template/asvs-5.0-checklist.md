# ASVS 5.0.0 verification checklist (deep, per-chapter)

Reference companion to the `stride-threat-model-template` skill. **Single source of the deep
ASVS content** — planning cites chapters/requirements from it, the security agent walks it in
step 6g, and `code-standards` points at its build-time items. Loaded on demand (it is a sibling
file, not preloaded), so its length costs nothing on a normal run.

- **Standard:** OWASP Application Security Verification Standard **5.0.0** (released May 2025).
- **Source of truth (verbatim requirement text):** `github.com/OWASP/ASVS` at tag `v5.0.0`,
  path `5.0/en/`. Each chapter below names its file; consult it for the exhaustive/verbatim list.
- **Relationship to the OWASP Top 10:** the Top 10 is a *risk-awareness* list (what tends to go
  wrong); ASVS is the *verifiable-requirements* standard (what must be true). Semgrep
  `p/owasp-top-ten` remains the SAST net for the injection-class chapters (V1/V2/parts of V5);
  ASVS 6g covers the chapters SAST cannot reach (auth, session, authz, tokens, crypto, comms,
  config, data protection, logging). They are complementary, not redundant.

## Verification levels — pick the target level per feature

ASVS defines three cumulative levels (L2 includes L1; L3 includes L2). Planning declares the
target level in the plan's `## Threat Model`; the security agent verifies against it.

- **L1 (default, every feature)** — the baseline every pipeline-built app must meet.
- **L2 (escalate to this when the feature handles) —** authentication/identity, PII/personal
  data, money or financial records, multi-tenant/owner-scoped data, or anything an attacker would
  target for gain. This is the realistic default for most real apps.
- **L3 (high-value / high-assurance)** — regulated data, high monetary value, or a system where a
  breach is critical. Declare explicitly; L3 items are otherwise advisory.

Chapters carry an **applicability trigger** — a chapter with no matching surface in the feature is
`n/a` (record it as such; do not invent findings). A REST API with bearer auth over TLS typically
triggers V1, V2, V4, V6, V7/V9, V8, V11, V12, V13, V14, V15, V16.

---

## The 17 chapters

Format per chapter: **applicability** · **pipeline coverage** (which skill builds it / whether SAST
sees it) · the L1 and key L2 items (real IDs, tight text) · L3 themes · official file.

### V1 — Encoding and Sanitization · applies: always (any untrusted input reaches an interpreter)
Coverage: `code-standards` (build), security 6c + Semgrep `p/owasp-top-ten` (verify — SAST sees much of this).
- **L1** 1.2.1 context-correct output encoding (HTML elem/attr/CSS/header); 1.2.2 safe URL building + protocol allowlist (no `javascript:`/`data:`); 1.2.3 encode when building JS/JSON; **1.2.4 parameterized queries / ORM (SQLi)**; 1.2.5 OS-command-injection protection; 1.3.1 sanitize WYSIWYG HTML with a vetted library; 1.3.2 avoid `eval()`/dynamic-code exec; 1.5.1 XML parser hardened (no external entities — XXE).
- **L2** 1.1.1 decode-once to canonical form before processing; 1.1.2 encode as the final step before the interpreter; 1.2.6–1.2.9 LDAP/XPath/LaTeX/regex-metachar injection; 1.3.3–1.3.11 sanitize before dangerous contexts (SVG, templates, **1.3.6 SSRF: allowlist protocol/domain/path/port**, JNDI, memcache, format strings, mail headers); 1.4.x memory-safety/integer-overflow (unmanaged code); 1.5.2 safe deserialization (type allowlist).
- **L3** 1.2.10 CSV/formula injection (RFC 4180); 1.3.12 ReDoS-safe regex; 1.5.3 consistent parsers.
- Official: `5.0/en/0x10-V1-Encoding-and-Sanitization.md`

### V2 — Validation and Business Logic · applies: always
Coverage: `code-standards` + planning validation contracts (build), security 6c + `input-controls` reconciliation (verify).
- **L1** 2.2.1 validate input to business expectations (positive/allowlist or expected-structure + logical limits); **2.2.2 enforce validation at a trusted service layer** (client-side validation is UX, never a security control); 2.3.1 process business-logic steps only in the expected sequential order.
- **L2** 2.1.x document validation rules + contextual consistency + business limits; 2.2.3 related-data combinations are reasonable; 2.3.2 business-logic limits enforced; **2.3.3 transactional all-or-nothing** (rollback on partial failure); 2.3.4 locking so limited resources can't be double-booked; **2.4.1 anti-automation** (protect against excessive calls → exfiltration/quota/DoS).
- **L3** 2.3.5 multi-user approval for high-value flows; 2.4.2 human-realistic timing.
- Official: `5.0/en/0x11-V2-Validation-and-Business-Logic.md`

### V3 — Web Frontend Security · applies: the feature serves HTML/browser content or sets cookies
Coverage: `api-edge-conventions` (security headers/CORS) + `auth-patterns` (cookies); security 6c/6g (verify). Backend-only/API-only ⇒ largely `n/a` except CORS.
- **L1** 3.2.1 prevent wrong-context rendering (`Sec-Fetch-*`/CSP-sandbox/Content-Disposition); 3.2.2 text via safe sinks (`textContent`, not HTML); 3.3.1 cookies `Secure` + `__Host-`/`__Secure-` prefix; **3.4.1 HSTS** (≥1yr); **3.4.2 CORS `Access-Control-Allow-Origin` fixed or allowlist-validated**; 3.5.1–3.5.3 anti-CSRF / safe methods for sensitive functions.
- **L2** 3.3.2 `SameSite`; 3.3.4 `HttpOnly` for non-JS cookies; **3.4.3 CSP** (`object-src 'none'`, `base-uri 'none'`); 3.4.4 `X-Content-Type-Options: nosniff`; 3.4.5 referrer policy; 3.4.6 `frame-ancestors` (clickjacking); 3.5.5 validate `postMessage` origin; 3.7.2 open-redirect allowlist.
- **L3** 3.4.7 CSP report-uri; 3.4.8 COOP; 3.6.1 SRI for external assets; XSSI/JSONP hardening.
- Official: `5.0/en/0x12-V3-Web-Frontend-Security.md`
> Deeper front-end verification (visual-regression/a11y) is the deferred FE workstream — see roadmap.

### V4 — API and Web Service · applies: the feature exposes an HTTP API / web service
Coverage: `api-edge-conventions` (build), security 6f/6g (verify).
- **L1** 4.1.1 every body response has a correct `Content-Type` (incl. charset); 4.4.1 WebSockets over WSS.
- **L2** 4.1.2 only user-facing endpoints auto-redirect HTTP→HTTPS; 4.1.3 intermediary-set headers can't be overridden by the user; 4.2.1 determine HTTP message boundaries per version (request-smuggling); 4.3.1 GraphQL depth/cost/amount limiting; 4.3.2 introspection off in prod; 4.4.2 WebSocket `Origin` allowlist.
- **L3** 4.1.4 block unused HTTP methods; 4.1.5 per-message signatures for highly sensitive txns; 4.2.2–4.2.5 HTTP/2·3 framing/CRLF hardening.
- Official: `5.0/en/0x13-V4-API-and-Web-Service.md`

### V5 — File Handling · applies: the feature accepts/serves file uploads or downloads
Coverage: security 6c/6g + Semgrep (verify). No file surface ⇒ `n/a`.
- **L1** 5.2.1 bound accepted file size (DoS); 5.2.2 extension matches content/type; **5.3.1 uploaded files in public folders are not executed as server code**; 5.3.2 use trusted/internal file paths, not user filenames (path traversal).
- **L2** 5.2.3 zip-bomb guard (uncompressed size + file count before unpacking); 5.4.1 validate/ignore user filenames + set `Content-Disposition`; 5.4.2 encode served filenames (RFC 6266); 5.4.3 AV-scan untrusted files.
- **L3** 5.2.4 per-user quota; 5.2.5 reject symlinked archive entries; 5.2.6 pixel-flood guard; 5.3.3 zip-slip (ignore user path on decompress).
- Official: `5.0/en/0x14-V5-File-Handling.md`

### V6 — Authentication · applies: the feature authenticates users / manages credentials
Coverage: `auth-patterns` (build), security 6g (verify). SAST: no. Bearer-API-key features cover a subset.
- **L1** 6.2.1 password ≥8 (15+ recommended); 6.2.2/6.2.3 change requires current+new; **6.2.4 block top-3000 breached passwords**; 6.2.5 no composition rules; 6.2.7 allow paste/password-managers; 6.2.8 verify password exactly as received (no truncation/case-fold); **6.3.2 no default accounts** (root/admin/sa); 6.4.1 initial secrets random + short-lived + single-use; 6.4.2 no secret-questions/hints.
- **L2** 6.2.9 permit ≥64-char passwords; **6.2.10 no forced periodic rotation**; 6.2.12 check breached set; **6.3.3 MFA (or a combination of single factors)**; 6.4.3 forgotten-password reset doesn't bypass MFA; 6.5.x lookup/OOB/TOTP secrets are single-use, CSPRNG-generated, bounded lifetime (OOB ≤10 min, TOTP ≤30 s); 6.6.x OOB codes bound to the request + rate-limited; 6.8.x IdP assertion signature/audience/replay validation.
- **L3** phishing-resistant hardware factor; no email as a factor; user-enumeration resistance on login/register/reset; suspicious-login + credential-change notifications.
- Official: `5.0/en/0x15-V6-Authentication.md`

### V7 — Session Management · applies: the feature maintains user sessions
Coverage: `auth-patterns` (build), security 6g (verify).
- **L1** 7.2.1 verify session tokens on a trusted backend; 7.2.2 dynamically generated tokens (not static API keys as sessions); 7.2.3 reference tokens ≥128-bit CSPRNG entropy; **7.2.4 new session token on (re)authentication, terminating the old**; 7.4.1 terminated sessions are truly unusable (backend invalidation / self-contained-token revocation strategy); 7.4.2 terminate all sessions on account disable/delete.
- **L2** 7.1.x document inactivity + absolute-lifetime timeouts; **7.3.1/7.3.2 inactivity + absolute session timeouts** enforced; 7.4.3 offer "log out other sessions" after a credential change; 7.5.1 re-authenticate before changing sensitive auth attributes; 7.5.2 user can view/terminate active sessions.
- **L3** 7.5.3 step-up auth before highly sensitive operations; federated re-auth coordination.
- Official: `5.0/en/0x16-V7-Session-Management.md`

### V8 — Authorization · applies: any feature with owner/role/tenant-scoped resources
Coverage: security 6b (RLS) + 6g (verify). **This is the IDOR/BOLA chapter — high priority.**
- **L1** **8.2.1 function-level access restricted to explicit permissions**; **8.2.2 data-level access restricted (mitigate IDOR / BOLA)**; **8.3.1 enforce authz at a trusted service layer** (never client-side).
- **L2** 8.1.2 document field-level access rules; **8.2.3 field-level access (mitigate BOPLA / mass-assignment on read/write)**; **8.4.1 multi-tenant cross-tenant isolation** (an operation never affects another tenant).
- **L3** 8.2.4 adaptive/contextual controls; 8.3.2 authz-change takes effect immediately (self-contained-token caveat); 8.3.3 decisions on the originating subject's permissions; 8.4.2 layered admin-interface protection.
- Official: `5.0/en/0x17-V8-Authorization.md`

### V9 — Self-contained Tokens · applies: the feature issues/consumes JWTs or similar
Coverage: `auth-patterns` (build), security 6g (verify).
- **L1** **9.1.1 validate signature/MAC before trusting token contents**; **9.1.2 algorithm allowlist — never `none`**, ideally only symmetric xor asymmetric; 9.1.3 key material only from trusted pre-configured sources; 9.2.1 honor the validity window (exp/nbf).
- **L2** 9.2.2 validate token type/purpose; **9.2.3 validate audience** (token meant for this service); 9.2.4 audience restriction when one key serves multiple audiences.
- Official: `5.0/en/0x18-V9-Self-contained-Tokens.md`

### V10 — OAuth and OIDC · applies: the feature acts as an OAuth/OIDC client, RS, AS, or OP
Coverage: `auth-patterns` (build), security 6g (verify). No OAuth ⇒ `n/a`.
- **L1** 10.4.2 authorization codes single-use (reuse ⇒ revoke).
- **L2** 10.1.1 tokens only to components that need them; 10.2.1 CSRF protection via PKCE/state on code flow; **10.3.1 resource-server audience validation**; **10.4.6 PKCE mandatory for code grant** (no `plain`); 10.5.1 OIDC `nonce` replay mitigation; 10.7.2 consent prompt shows scope/client/lifetime.
- **L3** 10.4.14 sender-constrained (PoP) access tokens; pushed authorization requests. Legacy implicit/password grants are deprecated — do not use.
- Sections: V10.1 Generic · V10.2 Client · V10.3 Resource Server · V10.4 Auth Server · V10.5 OIDC Client · V10.6 OpenID Provider · V10.7 Consent.
- Official: `5.0/en/0x19-V10-OAuth-and-OIDC.md` (consult for the full per-role requirement set).

### V11 — Cryptography · applies: the feature encrypts, hashes, signs, or generates secrets/tokens
Coverage: `code-standards`/`secrets-management` (build), security 6g + Semgrep weak-crypto rules (verify).
- **L1** 11.3.1 no insecure block modes (ECB) / weak padding (PKCS#1 v1.5); **11.3.2 only approved ciphers/modes (AES-GCM)**; 11.4.1 only approved hash functions for crypto uses.
- **L2** 11.2.1 use vetted library implementations (don't roll your own); 11.2.2 crypto-agility (swap algorithms/keys); 11.2.3 ≥128-bit security; 11.3.3 authenticated encryption (or encrypt-then-MAC); **11.4.2 store passwords with an approved slow KDF** (argon2/scrypt/bcrypt/PBKDF2, current params); 11.4.4 key-stretch when deriving keys from passwords; **11.5.1 non-guessable values via CSPRNG, ≥128-bit entropy**; 11.6.1 approved algorithms for keygen/signatures; 11.1.x documented key lifecycle + inventory.
- **L3** 11.2.4 constant-time operations; 11.2.5 fail securely (padding-oracle); 11.3.4/11.3.5 nonce/IV uniqueness + encrypt-then-MAC; 11.7.x in-use data protection; PQC migration plan.
- Official: `5.0/en/0x20-V11-Cryptography.md`

### V12 — Secure Communication · applies: any network communication (essentially always)
Coverage: `iac-conventions`/`api-edge-conventions` (build), security 6g (verify).
- **L1** **12.1.1 only current TLS versions (1.2/1.3)**; 12.2.1 TLS for all client↔external-service traffic, no cleartext fallback; 12.2.2 publicly trusted certs on external services.
- **L2** 12.1.2 strong cipher suites, strongest preferred; 12.1.3 validate mTLS client certs before trusting identity; **12.3.1 TLS on all inbound/outbound connections** (incl. monitoring/mgmt/SSH); 12.3.2 clients validate server certs; 12.3.3/12.3.4 internal service-to-service TLS with trusted certs.
- **L3** 12.1.4 OCSP stapling / revocation; 12.1.5 Encrypted Client Hello; 12.3.5 PKI-based service authentication.
- Official: `5.0/en/0x21-V12-Secure-Communication.md`

### V13 — Configuration · applies: always (deployment/config surface)
Coverage: `secrets-management` + `iac-conventions` (build), security 6a + Checkov/Trivy + 6g (verify).
- **L1** **13.4.1 no source-control metadata (`.git`/`.svn`) served or reachable**.
- **L2** **13.3.1 secrets in a vault/secret-manager — never in source or build artifacts**; 13.3.2 least-privilege access to secrets; 13.2.1 backend-to-backend auth via service accounts/short-lived tokens/mTLS (not shared static creds); 13.2.2 least-privilege service accounts; 13.2.3 no default credentials; **13.2.4/13.2.5 egress allowlist for outbound/SSRF-capable calls**; **13.4.2 debug modes off in prod**; 13.4.3 no directory listing; 13.4.4 no HTTP TRACE; 13.4.5 internal docs/monitoring endpoints not exposed.
- **L3** 13.1.x document communication/resource/rotation policies; 13.3.3 HSM-isolated crypto; 13.3.4 secret expiry+rotation; 13.4.6/13.4.7 no version leakage / extension allowlist.
- Official: `5.0/en/0x22-V13-Configuration.md`

### V14 — Data Protection · applies: the feature handles sensitive/personal data
Coverage: `logging-conventions`/`secrets-management` (build), security 6a/6e + 6g (verify).
- **L1** **14.2.1 sensitive data only in body/headers — never in URL/query string**; 14.3.1 clear authenticated data from client storage on session end.
- **L2** 14.1.x classify sensitive data into protection levels + document controls; 14.2.2 don't cache sensitive data server-side (or purge); 14.2.3 don't send sensitive data to untrusted third parties (trackers); 14.2.4 apply the documented per-level controls; **14.3.2 `Cache-Control: no-store` for sensitive responses**; 14.3.3 no sensitive data in browser storage (except session tokens).
- **L3** 14.2.5 web-cache-deception guard; 14.2.6 return/mask minimum data; 14.2.7 retention/auto-deletion; 14.2.8 strip file metadata.
- Official: `5.0/en/0x23-V14-Data-Protection.md`

### V15 — Secure Coding and Architecture · applies: always (this is the build-time chapter)
Coverage: **`code-standards` (build — primary home)**, security 6g + OSV/`lockfile-check`/SBOM (verify).
- **L1** 15.1.1 documented remediation time-frames for vulnerable/outdated dependencies; **15.2.1 no components past their remediation window**; **15.3.1 return only the required subset of fields** (no over-broad responses).
- **L2** **15.1.2 maintain an SBOM from trusted repositories**; 15.2.2 defenses against resource-exhaustion functionality; 15.2.3 prod ships only required functionality (no extraneous/debug surface); 15.3.2 don't follow outbound redirects unless intended (SSRF); **15.3.3 mass-assignment protection** (allowlist fields per action); 15.3.4 trusted client-IP propagation; 15.3.5 strict type/equality checks; **15.3.6 prevent JS prototype pollution**; 15.3.7 HTTP parameter-pollution defense.
- **L3** 15.2.4 dependency-confusion protection; 15.2.5 sandbox risky/dangerous functionality; **15.4.x safe concurrency** (thread-safe shared state, TOCTOU-atomic check-then-act, deadlock/starvation avoidance).
- Official: `5.0/en/0x24-V15-Secure-Coding-and-Architecture.md`

### V16 — Security Logging and Error Handling · applies: always
Coverage: `logging-conventions` (build), security 6e + 6g (verify).
- **L2 (this chapter is L2-and-up)** 16.2.1 log entries carry when/where/who/what; 16.2.2 synchronized clocks, UTC/offset timestamps; **16.2.5 protection-level-aware logging** (never log credentials/payment data; session tokens only hashed/masked); 16.3.1 log auth successes+failures; 16.3.2 log failed authorization; 16.3.3 log security-control-bypass attempts (validation/business-logic/anti-automation); 16.3.4 log unexpected errors + security-control failures; **16.4.1 encode log data to prevent log injection**; 16.4.2 logs tamper-protected; 16.4.3 ship logs to a separate system; **16.5.1 generic error message to the consumer** (no stack traces/queries/secrets); **16.5.3 fail gracefully/securely — no fail-open** (don't process a transaction despite a validation error).
- **L3** 16.3.2 log all authz decisions + sensitive-data access; 16.5.4 last-resort catch-all handler.
- Official: `5.0/en/0x25-V16-Security-Logging-and-Error-Handling.md`

### V17 — WebRTC · applies: the feature uses WebRTC media/data channels
Coverage: security 6g (verify). No WebRTC ⇒ `n/a` (the common case for this pipeline).
- Covers SRTP/DTLS media encryption, TURN server hardening, signaling-channel security, and
  media-abuse/DoS controls. Consult the official file when a feature actually uses WebRTC.
- Official: `5.0/en/0x26-V17-WebRTC.md`

---

## How each stage uses this file

- **Planning** (`stride-threat-model-template`): after the STRIDE table, select the target level
  (rubric above), mark each chapter `applies`/`n/a` for the feature, and cite the specific ASVS
  requirement ID(s) in each threat's mitigation so the control is *verifiable*, not vague.
- **Implementation** (`code-standards`): build to the L1/L2 items of the triggered chapters —
  especially V1/V2 (encoding/validation) and V15 (secure coding).
- **Security agent** (step 6g): for each triggered chapter at the target level, verify the items
  are met in the diff-scoped change set; fold any gap into `critical_count`/`warning_count` (an
  unmet L1/L2 item on triggered surface is a finding — severity per the STRIDE rubric) and record
  `asvs_level` / `asvs_reqs_verified` / `asvs_reqs_missing` in `security-status.json`. Advisory —
  it adds no new gate; a critical still blocks via the existing gate.
