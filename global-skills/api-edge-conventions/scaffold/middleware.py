"""Edge middleware scaffold (FastAPI / Starlette) — the buildable default for
`api-edge-conventions`. Register the whole stack once at app construction; a new
route inherits the edge behavior by being mounted, never by re-declaring it.

This is a TEMPLATE: fill the `<...>` config, wire a shared Redis client, and adapt
per project. It is faithful to the skill's load-bearing correctness points — the
two throttle tiers keyed at two different lifecycle hooks, client-IP derivation
behind a proxy, and health-path exemption — which are exactly the classes M3 shipped
as defects. Express/Node equivalents are noted inline.

Ordering (outermost -> innermost), applied by `register_edge_middleware` below:
  1. request-id/trace (logging-conventions — imported, not re-implemented here)
  2. security headers   3. CORS   4. Tier-1 edge throttle (pre-auth, IP+route)
  5. auth guards (auth-patterns)  6. Tier-2 throttle (post-auth, principal-keyed)
  7. idempotency  8. handler wrapped by the error-envelope boundary
"""
from __future__ import annotations

import time
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

# The rate-limit / idempotency state MUST be a shared store (ElastiCache/Redis),
# never in-process counters — in-memory limits are per-instance and silently fail
# open behind a load balancer. Inject a configured async client at app construction.
#   redis = await aioredis.from_url(config.REDIS_URL)
# Config (CORS allowlist, limits, proxy trust) is read through the config facade,
# never hardcoded here.

# --- Health / readiness paths are EXEMPT from the pre-auth throttle -------------
# A throttleable probe lets an attacker drain LB targets (M3 shipped a throttleable
# /health/ready). Keep this list in sync with the LB health-check config.
HEALTH_PATHS = {"/health", "/health/ready", "/health/live"}


TRUST_PROXY = False  # set from config; true ONLY when a proxy/LB is declared and the
#                      plan states the trust mechanism. Defined before use below.


def client_ip(request: Request) -> str:
    """Derive the real client IP. ENABLING CONDITION (U-02): behind an ALB/nginx,
    `request.client.host` is the PROXY node's IP — every client then shares one
    bucket per node and one attacker can 429 everyone. Only trust `X-Forwarded-For`
    when a proxy is actually in front AND the app is configured to trust it
    (Starlette's ProxyHeadersMiddleware / uvicorn `--forwarded-allow-ips`, or the
    equivalent). Take the left-most XFF entry only when the hop is trusted; else fall
    back to the socket peer. Do NOT trust XFF unconditionally — it is client-settable."""
    if TRUST_PROXY:  # config flag — true only when a proxy/LB is declared in the plan
        xff = request.headers.get("x-forwarded-for", "")
        if xff:
            return xff.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


# --- 2. Security headers (set on EVERY response, including errors) ---------------
SECURITY_HEADERS = {
    "Strict-Transport-Security": "max-age=63072000; includeSubDomains",
    "Content-Security-Policy": "default-src 'self'",  # tighten per app
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "geolocation=(), microphone=(), camera=()",
}


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Applied outer enough that error responses carry the headers too. A JSON API
    that serves no HTML still sends nosniff + a restrictive CSP."""

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        for k, v in SECURITY_HEADERS.items():
            response.headers.setdefault(k, v)
        return response


# --- 4/6. Two-tier rate limiting -------------------------------------------------
# Algorithm: token bucket or sliding window. Backed by the shared Redis client.
# Response on limit: 429 + Retry-After (never a bare drop). Emit a `warn` log as a
# limit is approached and on every 429 (attack signal).

async def _rate_limit(redis, key: str, limit: int, window_s: int) -> tuple[bool, int]:
    """FIXED-window counter in Redis. Returns (allowed, retry_after_seconds). Simple and
    atomic, but it allows a burst across a window boundary (up to 2x the limit in a short
    span). For production prefer a true SLIDING window or a token-bucket Lua script — the
    skill names both; this is the minimal correct starting point, not the smoothest."""
    now = time.time()
    bucket = f"rl:{key}:{int(now // window_s)}"
    count = await redis.incr(bucket)
    if count == 1:
        await redis.expire(bucket, window_s)
    if count > limit:
        return False, window_s - int(now % window_s)
    return True, 0


class EdgeThrottleMiddleware(BaseHTTPMiddleware):
    """TIER 1 — pre-auth, keyed on IP + route. Cheap flood defense so an
    unauthenticated burst can't cost token verifications. This is the ONLY tier that
    legitimately keys on IP. Auth endpoints (login, reset, MFA, refresh) get a
    stricter limit keyed on IP + username (credential-stuffing mitigation).
    NOTE: this runs BEFORE auth, so no identity exists yet — do not key on identity
    here (it would silently fall back to IP; see Tier 2)."""

    def __init__(self, app, redis, limit=100, window_s=60, auth_paths=frozenset()):
        super().__init__(app)
        self.redis, self.limit, self.window_s = redis, limit, window_s
        self.auth_paths = auth_paths  # stricter, IP+username keyed

    async def dispatch(self, request: Request, call_next):
        if request.url.path in HEALTH_PATHS:
            return await call_next(request)  # probes are exempt
        ip = client_ip(request)
        if request.url.path in self.auth_paths:
            # Read the username from the parsed body in a real impl; keyed IP+username.
            key = f"auth:{ip}:{request.headers.get('x-username', '')}:{request.url.path}"
            limit, window = 5, 60
        else:
            key = f"edge:{ip}:{request.url.path}"
            limit, window = self.limit, self.window_s
        allowed, retry = await _rate_limit(self.redis, key, limit, window)
        if not allowed:
            return error_response("rate_limited", "Too many requests.", request,
                                  status=429, headers={"Retry-After": str(retry)})
        return await call_next(request)


async def resource_throttle(request: Request, redis, limit=1000, window_s=3600):
    """TIER 2 — per-identity resource throttle. Register on a hook that runs AFTER
    `require_auth` (FastAPI dependency/middleware-after-auth, Fastify `preHandler`),
    so `request.state.user` is set and the key is the authenticated principal.
    VERIFY with a two-principals-one-IP test: two identities on one client IP get
    independent buckets; one identity across two IPs shares a bucket. If the test
    can't distinguish them, the limiter is mis-keyed (the shipped defect class)."""
    user = getattr(request.state, "user", None)
    principal = (user or {}).get("uid") or request.headers.get("x-api-key")
    if not principal:
        return  # unauthenticated routes don't hit Tier 2
    allowed, retry = await _rate_limit(redis, f"res:{principal}", limit, window_s)
    if not allowed:
        raise RateLimited(retry)


# --- 7. Idempotency (non-idempotent unsafe methods) ------------------------------
async def idempotent(request: Request, redis, ttl_s=86_400):
    """For POST that creates/charges: accept an `Idempotency-Key`, store
    key -> (status, body) per caller, and replay the stored response on repeat so
    client retries and at-least-once webhook deliveries are safe. PUT/DELETE should
    be naturally idempotent by design — don't paper over a bad handler with a key."""
    key = request.headers.get("idempotency-key")
    if not key or request.method != "POST":
        return None
    principal = (getattr(request.state, "user", None) or {}).get("uid", "anon")
    cached = await redis.get(f"idem:{principal}:{key}")
    if cached:
        import json
        rec = json.loads(cached)
        return JSONResponse(rec["body"], status_code=rec["status"])
    return None  # first request: process, then store the response under this key


# --- 8. Error-envelope facade (innermost catch) ---------------------------------
class RateLimited(Exception):
    def __init__(self, retry_after: int): self.retry_after = retry_after


_STATUS_BY_CODE = {"validation_failed": 422, "unauthorized": 401, "forbidden": 403,
                   "not_found": 404, "rate_limited": 429, "internal": 500}


def error_response(code: str, message: str, request: Request, status: int | None = None,
                   headers: dict | None = None) -> JSONResponse:
    """One response shape for every error. `message` is safe-to-expose (no internals);
    NEVER leak a stack trace, exception type, SQL, or file path. Echo the requestId so
    a user report ties to a server log line.
    CONTRACT: the request-id middleware (logging-conventions' `request_logger`) MUST set
    `request.state.request_id` — its scaffold does (in addition to the structlog contextvar).
    If you swap in a different logger, expose the id on `request.state` or the echo is null."""
    body = {"error": {"code": code, "message": message,
                      "requestId": getattr(request.state, "request_id", None)}}
    return JSONResponse(body, status_code=status or _STATUS_BY_CODE.get(code, 500),
                        headers=headers)


class ErrorEnvelopeMiddleware(BaseHTTPMiddleware):
    """Central error boundary — the 'error handling' facade named in code-standards.
    Handlers `raise` domain errors; this maps class -> status and returns the envelope,
    logging the detail server-side. Any unmapped exception becomes a generic 500."""

    async def dispatch(self, request: Request, call_next):
        try:
            return await call_next(request)
        except RateLimited as e:
            return error_response("rate_limited", "Too many requests.", request,
                                  headers={"Retry-After": str(e.retry_after)})
        except Exception:  # noqa: BLE001 — the boundary catches everything
            # log.exception(...) server-side (logging-conventions); never to the client
            return error_response("internal", "An unexpected error occurred.", request)


def register_edge_middleware(app, redis, *, cors_origins: list[str], auth_paths=frozenset()):
    """Register the stack in the correct order. Starlette applies middleware in
    REVERSE of add order, so add innermost-first: error envelope, then throttle, CORS,
    security headers. Request-id/trace (logging-conventions) and the auth guards
    (auth-patterns) are added by their own skills; Tier-2 throttle + idempotency are
    per-route dependencies that must run AFTER `require_auth` (see above)."""
    app.add_middleware(ErrorEnvelopeMiddleware)          # 8 (innermost)
    app.add_middleware(EdgeThrottleMiddleware, redis=redis, auth_paths=auth_paths)  # 4
    app.add_middleware(                                   # 3 — CORS, explicit allowlist
        CORSMiddleware, allow_origins=cors_origins,       # never "*" on a credentialed API
        allow_credentials=True, allow_methods=["GET", "POST", "PUT", "DELETE"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
    )
    app.add_middleware(SecurityHeadersMiddleware)        # 2 (outermost of this set)
    return app
