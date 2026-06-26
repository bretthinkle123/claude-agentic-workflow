import logging, os
import structlog

# Singleton structured logger. All modules import get_logger() from
# logging/__init__.py — never configure a second structlog instance elsewhere.
_REDACT = {"authorization", "password", "token", "secret", "api_key", "cookie"}


def _redact(_, __, event_dict):
    """Drop sensitive fields before they are rendered — never log secrets/PII."""
    for key in list(event_dict):
        if key.lower() in _REDACT:
            event_dict[key] = "[REDACTED]"
    return event_dict


structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,   # request-scoped fields
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        _redact,
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(
        logging.getLevelName(os.environ.get("LOG_LEVEL", "INFO"))
    ),
)


def get_logger():
    """Return the configured structlog logger, bound with the service name."""
    return structlog.get_logger(service=os.environ.get("SERVICE_NAME", "app"))
