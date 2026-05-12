"""
In-process per-API-key token bucket for the PFAS Enterprise 5 API.

This is intentionally **lightweight**:
- in-memory only (no Redis, no Kafka)
- thread-safe via a simple lock
- per-key bucket, not per-IP (auth happens first)

Design:
    refill_rate_per_sec = rate_limit_per_minute / 60
    bucket_capacity     = rate_limit_burst

When a request arrives:
    1. compute refilled tokens since last check (capped at burst)
    2. if tokens >= 1, decrement and allow
    3. else block (return retry-after = time to next token)

A future upgrade to a distributed limiter (Redis, Memcached) slots in by
replacing the `try_acquire` function only.

Per the SaaS scope, this is sufficient for the pre-pilot phase: it
prevents accidental scrape loops and runaway integrations without
introducing operational complexity.
"""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass


@dataclass
class BucketState:
    tokens: float
    last_refill: float


class RateLimiter:
    def __init__(self, per_minute: int, burst: int) -> None:
        self.per_minute = max(1, int(per_minute))
        self.burst = max(1, int(burst))
        self.refill_per_sec = self.per_minute / 60.0
        self._buckets: dict[str, BucketState] = {}
        self._lock = threading.Lock()

    def _refill(self, state: BucketState, now: float) -> None:
        elapsed = max(0.0, now - state.last_refill)
        state.tokens = min(float(self.burst), state.tokens + elapsed * self.refill_per_sec)
        state.last_refill = now

    def try_acquire(self, key: str) -> tuple[bool, float, float]:
        """Try to take 1 token for `key`.

        Returns (allowed, retry_after_seconds, tokens_remaining).
        """
        now = time.monotonic()
        with self._lock:
            state = self._buckets.get(key)
            if state is None:
                state = BucketState(tokens=float(self.burst), last_refill=now)
                self._buckets[key] = state
            else:
                self._refill(state, now)
            if state.tokens >= 1.0:
                state.tokens -= 1.0
                return True, 0.0, state.tokens
            needed = 1.0 - state.tokens
            retry_after = needed / self.refill_per_sec
            return False, retry_after, state.tokens

    def snapshot(self) -> dict[str, dict[str, float]]:
        with self._lock:
            return {
                k: {"tokens": v.tokens, "last_refill": v.last_refill}
                for k, v in self._buckets.items()
            }
