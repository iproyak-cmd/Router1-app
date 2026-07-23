"""Minimal Career Agent HTTP service for the initial HeadHunter OAuth callback.

This bootstrap service deliberately does not exchange or persist authorization
codes yet. It validates the callback shape without echoing sensitive query
parameters and returns a small no-store HTML page.
"""

from __future__ import annotations

import html
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOST = os.environ.get("CAREER_AGENT_HOST", "127.0.0.1")
PORT = int(os.environ.get("CAREER_AGENT_PORT", "8013"))


class Handler(BaseHTTPRequestHandler):
    server_version = "FabulaCareerAgent/0.1"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._text(HTTPStatus.OK, "ok")
            return
        if parsed.path != "/api/auth/hh/callback":
            self._html(HTTPStatus.NOT_FOUND, "Not found", "Unknown endpoint.")
            return

        query = parse_qs(parsed.query, keep_blank_values=True)
        oauth_error = (query.get("error") or [""])[0].strip()
        if oauth_error:
            description = (query.get("error_description") or [""])[0].strip()
            safe_description = html.escape(description or "HeadHunter authorization was cancelled.")
            self._html(
                HTTPStatus.BAD_REQUEST,
                "Fabula Career Agent",
                safe_description,
            )
            return

        # During bootstrap we intentionally do not log, display, exchange or
        # store the authorization code. Token exchange is the next stage after
        # HH approves the registered application.
        self._html(
            HTTPStatus.OK,
            "Fabula Career Agent",
            "Fabula Career Agent connected successfully",
        )

    def _text(self, status: HTTPStatus, body: str) -> None:
        encoded = body.encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _html(self, status: HTTPStatus, title: str, message: str) -> None:
        encoded = f"""<!doctype html>
<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"robots\" content=\"noindex,nofollow\"><title>{html.escape(title)}</title></head>
<body style=\"font-family:system-ui,sans-serif;max-width:680px;margin:72px auto;padding:0 24px;color:#171717\"><h1>{html.escape(title)}</h1><p>{message}</p></body></html>""".encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Pragma", "no-cache")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: object) -> None:
        # OAuth query strings can contain short-lived authorization codes.
        # Do not emit request lines until structured redacted logging exists.
        return


def main() -> None:
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
