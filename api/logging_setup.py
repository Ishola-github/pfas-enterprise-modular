"""
Structured JSON logging for the PFAS Enterprise 5 API.

One logger ("pfas.api") emits one JSON line per record. Every access-log
line carries the operational fields required by the SaaS scaffolding:

    request_id        the X-Request-Id assigned by middleware
    timestamp         UTC ISO 8601 (Z-suffixed)
    method            HTTP verb
    path              request path (query string stripped)
    status_code       HTTP status
    response_ms       latency in milliseconds (integer)
    api_key_id        which key authenticated (or "" for unauthenticated)
    lane              matrix_lane for prediction requests (or "")
    ad_status         AD outcome (in_domain / warning / reject / "")
    prediction_refused  bool — True iff the API blocked the prediction
    model_version     model identifier for the prediction (or "")
    threshold_version threshold-config hash prefix for the prediction (or "")

For non-prediction routes (health, etc.) the request-specific fields are
empty strings or omitted, but request_id / timestamp / response_ms are
always present.
"""

from __future__ import annotations

import datetime as dt
import json
import logging
import sys
from logging import Handler
from pathlib import Path
from typing import Any

LOGGER_NAME = "pfas.api"

_STANDARD_LOGRECORD_ATTRS = frozenset({
    "args", "asctime", "created", "exc_info", "exc_text", "filename",
    "funcName", "levelname", "levelno", "lineno", "message", "module",
    "msecs", "msg", "name", "pathname", "process", "processName",
    "relativeCreated", "stack_info", "thread", "threadName", "taskName",
})


class JsonFormatter(logging.Formatter):
    """Format a log record as a single-line JSON object."""

    def format(self, record: logging.LogRecord) -> str:  # noqa: A003
        payload: dict[str, Any] = {
            "timestamp": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for k, v in record.__dict__.items():
            if k in _STANDARD_LOGRECORD_ATTRS:
                continue
            if k.startswith("_"):
                continue
            try:
                json.dumps(v)
                payload[k] = v
            except TypeError:
                payload[k] = str(v)
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


class PlainFormatter(logging.Formatter):
    """Plain-text fallback (dev only)."""

    def format(self, record: logging.LogRecord) -> str:  # noqa: A003
        ts = dt.datetime.now(dt.timezone.utc).strftime("%H:%M:%S")
        extras = " ".join(
            f"{k}={v!r}" for k, v in record.__dict__.items()
            if k not in _STANDARD_LOGRECORD_ATTRS and not k.startswith("_")
        )
        return f"{ts} {record.levelname:<5} {record.name} :: {record.getMessage()}  {extras}".rstrip()


def configure_logger(
    *,
    level: str = "INFO",
    json_format: bool = True,
    access_log_path: Path | None = None,
) -> logging.Logger:
    """Configure the pfas.api logger. Idempotent."""

    logger = logging.getLogger(LOGGER_NAME)
    logger.setLevel(level.upper())

    for h in list(logger.handlers):
        logger.removeHandler(h)

    formatter: logging.Formatter = JsonFormatter() if json_format else PlainFormatter()

    stdout_handler = logging.StreamHandler(sys.stdout)
    stdout_handler.setFormatter(formatter)
    logger.addHandler(stdout_handler)

    if access_log_path is not None:
        access_log_path.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(access_log_path, encoding="utf-8")
        file_handler.setFormatter(JsonFormatter())
        logger.addHandler(file_handler)

    logger.propagate = False
    return logger


def log_event(
    logger: logging.Logger,
    *,
    level: str = "INFO",
    message: str,
    **fields: Any,
) -> None:
    """Emit a record with structured `extra=` fields."""
    log_fn = getattr(logger, level.lower(), logger.info)
    log_fn(message, extra=fields)
