# Pipeline alternatives (companion to `agentic-pipeline-plan.md`)

Documentation-only. **Nothing here is loaded at pipeline runtime** — these are the non-default scaffolds, kept so you can switch later without re-deriving them. The main plan's defaults are **AWS** (cloud/infra), **Firebase Auth** (auth), **Python** (backend), **JavaScript** (frontend). When the planning agent recommends one of these alternatives for a specific project and you approve it at the checkpoint, copy the relevant scaffold into that project (or have the pipeline regenerate it).

Contents:
- [Amazon Cognito auth scaffold (AWS-native)](#amazon-cognito)
- [Firebase Auth — JavaScript/Node backend variant](#firebase-js-backend)
- [Pino (JavaScript) logging scaffold](#pino-logging)
- [AWS CloudWatch / X-Ray — JavaScript/OTel-Node observability](#aws-otel-node)
- [GCP observability backend (Cloud Logging / Monitoring / Trace)](#gcp-observability)
- [Other-language loggers (Go, Java/Kotlin)](#other-loggers)

---

<a id="amazon-cognito"></a>
## Amazon Cognito auth scaffold (AWS-native)

The AWS-native variant of the auth facade. It uses the **same `src/auth/` layout and the same public surface** as the Firebase scaffold in the main plan — the guards are unchanged; only the provider internals differ. Stack: `amazon-cognito-identity-js` (client), `@aws-sdk/client-cognito-identity-provider` (server admin ops), and `aws-jwt-verify` (token verification). Shown in TypeScript.

**`src/auth/` directory structure (Cognito):**

```
src/auth/
├── index.ts                 ← public surface (guards identical; sign-in/MFA helpers swapped)
├── cognito.ts               ← User Pool client singleton
├── cognito-admin.ts         ← AWS SDK admin client (server-side only, never in client bundle)
├── oauth.ts                 ← Hosted UI federated sign-in (Google/Apple native; GitHub/Microsoft via OIDC)
├── mfa.ts                   ← Cognito TOTP enroll/verify (Path A) or Duo Auth API (Path B)
├── token.ts                 ← token verification + claim helpers; NORMALIZES claims to the neutral shape
├── middleware.ts            ← unchanged — same guards as the Firebase variant
└── pre-token-generation.ts  ← Lambda trigger: promotes custom:* attributes to token claims
```

**`cognito.ts` — client User Pool singleton:**
```typescript
import { CognitoUserPool } from 'amazon-cognito-identity-js';

/** Singleton Cognito User Pool — client-side identity operations. */
export const userPool = new CognitoUserPool({
  UserPoolId: process.env.COGNITO_USER_POOL_ID!,
  ClientId: process.env.COGNITO_CLIENT_ID!,
});
```

**`cognito-admin.ts` — server-side admin client:**
```typescript
import { CognitoIdentityProviderClient } from '@aws-sdk/client-cognito-identity-provider';

/** Singleton Cognito admin client — server-side only; uses the task/instance IAM role, no static keys. */
export const cognitoAdmin = new CognitoIdentityProviderClient({
  region: process.env.AWS_REGION,
});
```

**`oauth.ts` — Hosted UI federated sign-in:**
```typescript
// Social sign-in goes through the Cognito Hosted UI (OAuth 2.0 / OIDC). Google
// and Apple are native Cognito identity providers; GitHub and Microsoft are
// configured as generic OIDC providers in the user pool.
const HOSTED_UI = process.env.COGNITO_HOSTED_UI_DOMAIN!;   // e.g. app.auth.us-east-1.amazoncognito.com
const CLIENT_ID = process.env.COGNITO_CLIENT_ID!;
const REDIRECT_URI = process.env.COGNITO_REDIRECT_URI!;

type Provider = 'Google' | 'SignInWithApple' | 'GitHub' | 'Microsoft';

/** Build the Hosted UI authorize URL for a federated provider; redirect the user to it. */
export function getSignInUrl(provider: Provider): string {
  const params = new URLSearchParams({
    identity_provider: provider,
    client_id: CLIENT_ID,
    response_type: 'code',
    scope: 'openid email profile',
    redirect_uri: REDIRECT_URI,
  });
  return `https://${HOSTED_UI}/oauth2/authorize?${params.toString()}`;
}
```

**`mfa.ts` — Path A (Cognito TOTP, recommended):**
```typescript
import {
  AssociateSoftwareTokenCommand,
  VerifySoftwareTokenCommand,
  SetUserMFAPreferenceCommand,
} from '@aws-sdk/client-cognito-identity-provider';
import { cognitoAdmin } from './cognito-admin';

/** Begin TOTP enrollment; returns the secret to render as a Duo Mobile QR code. */
export async function enrollTotp(accessToken: string) {
  const res = await cognitoAdmin.send(
    new AssociateSoftwareTokenCommand({ AccessToken: accessToken }),
  );
  return res.SecretCode; // render as an otpauth://… QR for Duo Mobile
}

/** Confirm TOTP enrollment with the code from Duo Mobile, then make TOTP the preferred factor. */
export async function confirmTotpEnrollment(accessToken: string, code: string) {
  await cognitoAdmin.send(
    new VerifySoftwareTokenCommand({ AccessToken: accessToken, UserCode: code }),
  );
  await cognitoAdmin.send(
    new SetUserMFAPreferenceCommand({
      AccessToken: accessToken,
      SoftwareTokenMfaSettings: { Enabled: true, PreferredMfa: true },
    }),
  );
}
```

*Sign-in challenge (the Cognito analog of the Firebase variant's `resolveTotpChallenge`):* when a returning user authenticates, Cognito issues a `SOFTWARE_TOKEN_MFA` challenge that is answered client-side — `cognitoUser.sendMFACode(code, callbacks, 'SOFTWARE_TOKEN_MFA')` via `amazon-cognito-identity-js` — rather than through an admin call, so it lives in the client auth flow, not this server module.

**`token.ts` — verification + claim helpers (the portability seam):**
```typescript
import { CognitoJwtVerifier } from 'aws-jwt-verify';
import { AdminUpdateUserAttributesCommand } from '@aws-sdk/client-cognito-identity-provider';
import { cognitoAdmin } from './cognito-admin';

const verifier = CognitoJwtVerifier.create({
  userPoolId: process.env.COGNITO_USER_POOL_ID!,
  tokenUse: 'id',
  clientId: process.env.COGNITO_CLIENT_ID!,
});

/**
 * Verify a Cognito ID token and return a PROVIDER-NEUTRAL claims object, so that
 * middleware is identical to the Firebase variant. Cognito stores custom
 * claims as strings — booleanize / arrayify them here. This is the only place
 * provider differences are absorbed.
 */
export async function verifyIdToken(idToken: string) {
  const c: any = await verifier.verify(idToken);
  return {
    ...c,
    uid: c.sub,
    mfa_verified: c.mfa_verified === 'true' || c.mfa_verified === true,
    mfa_method: c.mfa_method ?? '',
    roles: typeof c.roles === 'string' ? c.roles.split(',').filter(Boolean) : (c.roles ?? []),
  };
}

/**
 * Record the MFA result. Writes the custom:* attributes the Pre-Token-Generation
 * Lambda reads; the client then re-fetches its token to pick up the elevated
 * claim. method is 'totp' (Path A) or 'duo-push' (Path B) — the same contract as
 * the Firebase setMfaVerified.
 */
export async function setMfaVerified(username: string, method: 'totp' | 'duo-push') {
  await cognitoAdmin.send(
    new AdminUpdateUserAttributesCommand({
      UserPoolId: process.env.COGNITO_USER_POOL_ID!,
      Username: username,
      UserAttributes: [
        { Name: 'custom:mfa_verified', Value: 'true' },
        { Name: 'custom:mfa_method', Value: method },
      ],
    }),
  );
}
```

**`pre-token-generation.ts` — Lambda trigger (promotes attributes to claims):**
```typescript
/**
 * Cognito Pre-Token-Generation Lambda. Promotes the user's custom:* attributes
 * into first-class ID-token claims (mfa_verified, mfa_method, roles) so tokens
 * carry the same shape as the Firebase path. Wire it as the user pool's
 * "Pre token generation" trigger. Claim values must be strings; token.ts
 * normalizes them back on the way in.
 */
export async function handler(event: any) {
  const a = event.request.userAttributes;
  event.response = {
    claimsOverrideDetails: {
      claimsToAddOrOverride: {
        mfa_verified: a['custom:mfa_verified'] ?? 'false',
        mfa_method: a['custom:mfa_method'] ?? '',
        roles: a['custom:roles'] ?? 'user',
      },
    },
  };
  return event;
}
```

**Migrating to a Python backend:** the verification seam (`token.ts`) maps directly to Python using `python-jose`/`PyJWT` against the Cognito JWKS (`https://cognito-idp.<region>.amazonaws.com/<pool>/.well-known/jwks.json`), normalizing the string-typed `custom:*` claims exactly as above; the guards mirror the Firebase Python `middleware.py` in the main plan.

> **Why this stays portable:** route code calls only `require_auth` / `require_mfa` / `require_role`, which read the normalized claims. Swapping Firebase ↔ Cognito touches only the files behind the facade — never a route or handler.

---

<a id="firebase-js-backend"></a>
## Firebase Auth — JavaScript/Node backend variant

If a project's backend is JavaScript/Node instead of the default Python, these are the server-side equivalents of `token.py` / `middleware.py` from the main plan (using `firebase-admin`).

**`firebase-admin.ts` — server-side singleton:**
```typescript
import { initializeApp, getApps, cert } from 'firebase-admin/app';

/** Singleton Firebase Admin app — never import this in client-side code. */
export const adminApp = getApps().length
  ? getApps()[0]
  : initializeApp({ credential: cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT!)) });
```

**`token.ts` — ID token verification and custom-claim helpers (server-side):**
```typescript
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { adminApp } from './firebase-admin';

/** Verify a Firebase ID token and return its decoded claims. */
export async function verifyIdToken(idToken: string) {
  return getAdminAuth(adminApp).verifyIdToken(idToken);
}

/** Set the MFA custom claim after a second factor completes. method is 'totp' or 'duo-push'. */
export async function setMfaVerified(uid: string, method: 'totp' | 'duo-push') {
  await getAdminAuth(adminApp).setCustomUserClaims(uid, { mfa_verified: true, mfa_method: method });
}
```

**`middleware.ts` — the auth facade (Express):**
```typescript
import { verifyIdToken } from './token';

/** Verify Firebase ID token and attach decoded claims to req.user. */
export async function requireAuth(req, res, next) {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'Missing auth token' });
  try {
    req.user = await verifyIdToken(token);
    next();
  } catch {
    res.status(401).json({ error: 'Invalid auth token' });
  }
}

/** Verify MFA completion via custom claim — apply after requireAuth. */
export async function requireMfa(req, res, next) {
  if (!req.user?.mfa_verified) return res.status(403).json({ error: 'MFA required' });
  next();
}

/** Check for a required role — apply after requireAuth. */
export function requireRole(role: string) {
  return (req, res, next) => {
    if (!req.user?.roles?.includes(role)) return res.status(403).json({ error: 'Forbidden' });
    next();
  };
}
```

---

<a id="pino-logging"></a>
## Pino (JavaScript) logging scaffold

The JavaScript/Node equivalent of the default Python structlog logger in the main plan.

**`logger.ts` — logging singleton:**
```typescript
import pino from 'pino';

/** Singleton structured logger. All modules import from src/logging/index.ts —
 *  never configure a second pino instance elsewhere in the app. */
export const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  formatters: { level: (label) => ({ level: label }) },
  base: { service: process.env.SERVICE_NAME ?? 'app' },
  timestamp: pino.stdTimeFunctions.isoTime,
  redact: {
    paths: ['req.headers.authorization', 'req.body.password', 'req.body.token', 'req.body.secret'],
    censor: '[REDACTED]',
  },
});
```

**`middleware.ts` — request logging facade:**
```typescript
import { randomUUID, createHash } from 'crypto';
import { logger } from './logger';

/** Attaches a child logger with requestId and traceId to req.log, then logs
 *  request start and completion (duration, status, hashed userId). */
export function requestLogger(req, res, next) {
  const requestId = randomUUID();
  // OTel span trace id when active; else the cloud trace header; else a UUID.
  const traceId = req.headers['x-amzn-trace-id']?.split(';').find((p) => p.startsWith('Root='))?.slice(5)
    ?? req.headers['x-cloud-trace-context']?.split('/')[0]
    ?? randomUUID();

  req._startTime = Date.now();
  req.log = logger.child({ requestId, traceId });
  req.log.info({ operation: `${req.method} ${req.path}` }, 'request started');

  res.on('finish', () => {
    req.log.info({
      operation: `${req.method} ${req.path}`,
      userId: req.user?.uid ? hashUserId(req.user.uid) : 'anonymous',
      statusCode: res.statusCode,
      duration: Date.now() - req._startTime,
    }, 'request completed');
  });
  next();
}

function hashUserId(uid: string): string {
  return createHash('sha256').update(uid).digest('hex').slice(0, 16);
}
```

---

<a id="aws-otel-node"></a>
## AWS CloudWatch / X-Ray — JavaScript/OTel-Node observability

The Node/OTel-JS observability bootstrap (the default Python plan summarizes the equivalent Python OTel/ADOT setup). `logger.ts` (Pino) is unchanged; JSON on stdout is ingested into **CloudWatch Logs** automatically on ECS/Lambda. What changes is traces/metrics (exported to X-Ray / CloudWatch via an ADOT collector) and the trace-correlation header.

**`otel.ts` — OpenTelemetry bootstrap for AWS:**
```typescript
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { AWSXRayPropagator } from '@opentelemetry/propagator-aws-xray';
import { AWSXRayIdGenerator } from '@opentelemetry/id-generator-aws-xray';

/** Exports OTLP to a local ADOT collector sidecar → X-Ray (traces) + CloudWatch
 *  (metrics). Import this FIRST, before any other module, at process start. */
export const otelSdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? 'http://localhost:4317',
  }),
  textMapPropagator: new AWSXRayPropagator(),  // X-Amzn-Trace-Id <-> span context
  idGenerator: new AWSXRayIdGenerator(),        // X-Ray-compatible trace IDs
  instrumentations: [getNodeAutoInstrumentations()],
});

otelSdk.start();
```

The request middleware resolves `traceId` from `trace.getActiveSpan()?.spanContext().traceId` first, then the `X-Amzn-Trace-Id` Root, then a UUID (same shape as the Pino middleware above).

> **Provisioning note:** the ADOT collector runs as a sidecar (ECS) or layer/extension (Lambda); the CloudWatch log group, retention, and X-Ray write permissions are declared in `infra/` (Terraform). No application code beyond OTel wiring changes between the GCP and AWS backends — the OTel portability payoff.

---

<a id="gcp-observability"></a>
## GCP observability backend (Cloud Logging / Monitoring / Trace)

For a project the planner moves to GCP. The application logger (structlog/Pino) and OTel instrumentation are unchanged — only the backend destinations differ:

| Pillar | GCP backend |
|---|---|
| Logs | Google Cloud Logging |
| Metrics | Google Cloud Monitoring (+ alerting policies) |
| Traces | Google Cloud Trace |
| Export path | OTLP → Cloud exporters |
| Trace-correlation header | `x-cloud-trace-context` (first segment is the trace id) |
| Errors / perf | Sentry — unchanged on either cloud |

In the request middleware, resolve `traceId` from the active OTel span, else `x-cloud-trace-context`'s first `/`-segment, else a UUID. SLOs/alerts live in Cloud Monitoring rather than CloudWatch Alarms.

---

<a id="other-loggers"></a>
## Other-language loggers (Go, Java/Kotlin)

| Language | Recommended library | Notes |
|---|---|---|
| Go | **zerolog** or **zap** | Both are zero-allocation structured loggers |
| Java / Kotlin | **SLF4J + Logback** | Standard interface + JSON encoder (logstash-logback-encoder) |

Same standard field set, PII rules, and log levels as the main plan; only the configuration idiom changes.
