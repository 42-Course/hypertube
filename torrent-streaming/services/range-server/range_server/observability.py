"""Structured stderr logging helpers for range-server.

Logs from this service use the ``[backend:range-server]`` prefix and sorted JSON
payloads so Docker output, tests, and sibling services can parse them
consistently.
"""

from __future__ import annotations

import json
import sys
import traceback
from typing import Any

from . import config

def backend_debug_enabled() -> bool:
    """Return whether backend debug logs should be emitted to stderr."""

    return config.BACKEND_DEBUG_STDERR != "0"


def backend_log(event: str, level: str = "debug", **payload: Any) -> None:
    """Emit one structured backend log record when debug logging is enabled."""

    if not backend_debug_enabled():
        return
    # Keep the prefix, service field, and sorted payload stable for log parsers.
    record = {"service": config.SERVICE, "level": level, "event": event, **payload}
    print(f"[backend:{config.SERVICE}] {json.dumps(record, sort_keys=True)}", file=sys.stderr, flush=True)


def backend_error(event: str, **payload: Any) -> None:
    """Emit an error-level backend log record."""

    backend_log(event, level="error", **payload)


def backend_exception(event: str, exc: BaseException | None = None, **payload: Any) -> None:
    """Log exception metadata and print the traceback for debugging."""

    if exc is not None:
        payload = {
            **payload,
            "error_class": exc.__class__.__name__,
            "message": str(exc),
        }
    backend_error(event, **payload)
    traceback.print_exc(file=sys.stderr)
