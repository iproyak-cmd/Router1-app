"""Authenticated standalone HTTP service for the Fabula companion."""

from __future__ import annotations

import hmac
import json
import os
import threading
from collections import Counter
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from fabula_chat import (
    FabulaChatPayload,
    SlidingWindowLimiter,
    request_openrouter,
)


HOST = os.environ.get("FABULA_CHAT_HOST", "127.0.0.1")
PORT = int(os.environ.get("FABULA_CHAT_PORT", "8012"))
API_TOKEN = os.environ.get("APP_API_TOKEN", "").strip()
CLIENT_API_TOKEN = os.environ.get("FABULA_CLIENT_API_TOKEN", "").strip()
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "").strip()
LIMITER = SlidingWindowLimiter(
    limit=int(os.environ.get("FABULA_CHAT_DAILY_LIMIT", "50")),
    window_seconds=24 * 60 * 60,
)
ANONYMOUS_LIMITER = SlidingWindowLimiter(
    limit=int(os.environ.get("FABULA_CHAT_ANONYMOUS_DAILY_LIMIT", "10")),
    window_seconds=24 * 60 * 60,
)
METRICS: Counter[str] = Counter()
METRICS_LOCK = threading.Lock()

if not API_TOKEN:
    raise SystemExit("APP_API_TOKEN is required")
if not OPENROUTER_API_KEY:
    raise SystemExit("OPENROUTER_API_KEY is required")


class Handler(BaseHTTPRequestHandler):
    server_version = "FabulaCompanion/1.0"

    def do_GET(self) -> None:
        if self.path == "/health":
            with METRICS_LOCK:
                metrics = dict(METRICS)
            self._json(HTTPStatus.OK, {"ok": True, "requests": metrics})
            return
        self._json(HTTPStatus.NOT_FOUND, {"detail": "not found"})

    def do_POST(self) -> None:
        if self.path != "/api/fabula/chat":
            self._json(HTTPStatus.NOT_FOUND, {"detail": "not found"})
            return
        authorized = self._authorized()
        if not authorized and not self._anonymous_allowed():
            self._count("anonymous_limit")
            self._json(HTTPStatus.UNAUTHORIZED, {"detail": "unauthorized"})
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            content_length = 0
        if not 1 <= content_length <= 50_000:
            self._json(HTTPStatus.BAD_REQUEST, {"detail": "invalid request size"})
            return
        try:
            raw = json.loads(self.rfile.read(content_length).decode("utf-8"))
            if not isinstance(raw, dict):
                raise ValueError("payload must be an object")
            payload = FabulaChatPayload.from_dict(raw)
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
            self._json(HTTPStatus.UNPROCESSABLE_ENTITY, {"detail": str(error)})
            return
        if not LIMITER.allowed(payload.installation_id):
            self._count("installation_limit")
            self._json(
                HTTPStatus.TOO_MANY_REQUESTS,
                {"detail": "daily message limit reached"},
            )
            return
        try:
            reply = request_openrouter(payload)
        except RuntimeError:
            self._count("openrouter_failure")
            self._json(
                HTTPStatus.SERVICE_UNAVAILABLE,
                {"detail": "companion temporarily unavailable"},
            )
            return
        self._count("success_authorized" if authorized else "success_anonymous")
        self._json(HTTPStatus.OK, {"reply": reply})

    def _authorized(self) -> bool:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return False
        supplied = header[7:].strip()
        return hmac.compare_digest(supplied, API_TOKEN) or (
            bool(CLIENT_API_TOKEN)
            and hmac.compare_digest(supplied, CLIENT_API_TOKEN)
        )

    def _anonymous_allowed(self) -> bool:
        address = self.headers.get("X-Forwarded-For", "").split(",", 1)[0].strip()
        if not address:
            address = self.client_address[0]
        return ANONYMOUS_LIMITER.allowed(f"ip:{address}")

    @staticmethod
    def _count(name: str) -> None:
        with METRICS_LOCK:
            METRICS[name] += 1

    def _json(self, status: HTTPStatus, payload: dict[str, object]) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: object) -> None:
        # Do not write message bodies or user identifiers to application logs.
        super().log_message(format, *args)


def main() -> None:
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
