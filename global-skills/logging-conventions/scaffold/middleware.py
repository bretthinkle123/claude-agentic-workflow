import time, uuid, hashlib
import structlog
from .logger import get_logger


def _trace_id(request) -> str:
    """AWS X-Amzn-Trace-Id Root when present, else a generated UUID. (When the
    OTel SDK is wired, prefer the active span's trace id instead.)"""
    for part in request.headers.get("x-amzn-trace-id", "").split(";"):
        if part.startswith("Root="):
            return part[5:]
    return uuid.uuid4().hex


def _hash_user(uid: str) -> str:
    """One-way hash so userId is never raw PII in logs."""
    return hashlib.sha256(uid.encode()).hexdigest()[:16]


async def request_logger(request, call_next):
    """Bind requestId + traceId, then log request start and completion
    (duration, status, hashed userId)."""
    structlog.contextvars.bind_contextvars(
        request_id=str(uuid.uuid4()), trace_id=_trace_id(request)
    )
    log, start = get_logger(), time.monotonic()
    op = f"{request.method} {request.url.path}"
    log.info("request started", operation=op)
    response = await call_next(request)
    user = getattr(request.state, "user", None)
    uid = user.get("uid") if isinstance(user, dict) else None
    log.info("request completed", operation=op, status_code=response.status_code,
             duration=round((time.monotonic() - start) * 1000),
             user_id=_hash_user(uid) if uid else "anonymous")
    structlog.contextvars.clear_contextvars()
    return response
