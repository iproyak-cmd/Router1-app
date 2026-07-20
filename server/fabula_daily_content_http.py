"""Minimal authenticated HTTP service for persistent Fabula daily content."""

from __future__ import annotations

import datetime as dt
import hmac
import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse
from zoneinfo import ZoneInfo

from fabula_daily_content import DailyContentStore

HOST = os.environ.get("FABULA_CONTENT_HOST", "127.0.0.1")
PORT = int(os.environ.get("FABULA_CONTENT_PORT", "8011"))
DATABASE_PATH = os.environ.get(
    "FABULA_CONTENT_DB",
    "/opt/vpn_bot/fabula_daily_content.db",
)
API_TOKEN = os.environ.get("APP_API_TOKEN", "").strip()
TIMEZONE = ZoneInfo(os.environ.get("FABULA_TIMEZONE", "Europe/Moscow"))

if not API_TOKEN:
    raise SystemExit("APP_API_TOKEN is required")

STORE = DailyContentStore(DATABASE_PATH)


class Handler(BaseHTTPRequestHandler):
    server_version = "FabulaDailyContent/1.0"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(HTTPStatus.OK, {"ok": True})
            return
        prefix = "/api/fabula/horoscope/"
        if not parsed.path.startswith(prefix):
            self._json(HTTPStatus.NOT_FOUND, {"detail": "not found"})
            return
        if not self._authorized():
            self._json(HTTPStatus.UNAUTHORIZED, {"detail": "unauthorized"})
            return

        sign = unquote(parsed.path[len(prefix) :]).strip("/").lower()
        query = parse_qs(parsed.query)
        raw_date = (query.get("date") or [""])[0].strip()
        try:
            content_date = (
                dt.date.fromisoformat(raw_date)
                if raw_date
                else dt.datetime.now(TIMEZONE).date()
            )
            payload = STORE.get_or_create(content_date, sign)
        except ValueError as error:
            self._json(HTTPStatus.BAD_REQUEST, {"detail": str(error)})
            return
        except Exception:
            self._json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"detail": "daily content unavailable"},
            )
            return
        self._json(HTTPStatus.OK, payload)

    def _authorized(self) -> bool:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return False
        return hmac.compare_digest(header[7:].strip(), API_TOKEN)

    def _json(self, status: HTTPStatus, payload: dict) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: object) -> None:
        super().log_message(format, *args)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
