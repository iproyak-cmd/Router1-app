"""Fabula Career Agent OAuth service.

Provides OAuth entry and callback endpoints for Habr Career. Secrets are read
from environment variables. Authorization codes and access tokens are never
written to logs or returned to the browser.
"""

from __future__ import annotations

import hashlib
import hmac
import html
import json
import os
import secrets
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen

HOST = os.environ.get("CAREER_AGENT_HOST", "127.0.0.1")
PORT = int(os.environ.get("CAREER_AGENT_PORT", "8013"))
HABR_CLIENT_ID = os.environ.get("HABR_CLIENT_ID", "").strip()
HABR_CLIENT_SECRET = os.environ.get("HABR_CLIENT_SECRET", "").strip()
HABR_REDIRECT_URI = os.environ.get(
    "HABR_REDIRECT_URI", "https://router1.tech/api/auth/habr/callback"
).strip()
HABR_AUTHORIZE_URL = os.environ.get(
    "HABR_AUTHORIZE_URL", "https://career.habr.com/integrations/oauth/authorize"
).strip()
HABR_TOKEN_URL = os.environ.get(
    "HABR_TOKEN_URL", "https://career.habr.com/integrations/oauth/token"
).strip()
STATE_TTL_SECONDS = 600
STATE_FILE = Path(os.environ.get("HABR_STATE_FILE", "/opt/vpn_bot/.habr_oauth_state"))
TOKEN_FILE = Path(os.environ.get("HABR_TOKEN_FILE", "/opt/vpn_bot/.habr_oauth_token.json"))


def _require_habr_config() -> None:
    if not HABR_CLIENT_ID or not HABR_CLIENT_SECRET:
        raise RuntimeError("Habr OAuth credentials are not configured")


def _state_signature(nonce: str, issued_at: int) -> str:
    payload = f"{nonce}.{issued_at}".encode("utf-8")
    return hmac.new(HABR_CLIENT_SECRET.encode("utf-8"), payload, hashlib.sha256).hexdigest()


def _create_state() -> str:
    _require_habr_config()
    nonce = secrets.token_urlsafe(32)
    issued_at = int(time.time())
    signature = _state_signature(nonce, issued_at)
    state = f"{nonce}.{issued_at}.{signature}"
    STATE_FILE.write_text(state, encoding="utf-8")
    os.chmod(STATE_FILE, 0o600)
    return state


def _consume_state(received: str) -> bool:
    try:
        expected = STATE_FILE.read_text(encoding="utf-8").strip()
        STATE_FILE.unlink(missing_ok=True)
        nonce, issued_text, signature = received.split(".", 2)
        issued_at = int(issued_text)
    except (OSError, ValueError):
        return False
    if not hmac.compare_digest(received, expected):
        return False
    if int(time.time()) - issued_at > STATE_TTL_SECONDS:
        return False
    return hmac.compare_digest(signature, _state_signature(nonce, issued_at))


def _exchange_code(code: str) -> dict[str, object]:
    _require_habr_config()
    body = urlencode(
        {
            "grant_type": "authorization_code",
            "client_id": HABR_CLIENT_ID,
            "client_secret": HABR_CLIENT_SECRET,
            "redirect_uri": HABR_REDIRECT_URI,
            "code": code,
        }
    ).encode("utf-8")
    request = Request(
        HABR_TOKEN_URL,
        data=body,
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "Fabula-Career-Agent/1.0",
        },
    )
    with urlopen(request, timeout=15) as response:
        raw = response.read(1024 * 1024)
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict) or not payload.get("access_token"):
        raise ValueError("Habr token response did not contain access_token")
    payload["received_at"] = int(time.time())
    TOKEN_FILE.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    os.chmod(TOKEN_FILE, 0o600)
    return payload


class Handler(BaseHTTPRequestHandler):
    server_version = "FabulaCareerAgent/0.2"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._text(HTTPStatus.OK, "ok")
            return
        if parsed.path == "/api/auth/habr/login":
            self._habr_login()
            return
        if parsed.path == "/api/auth/habr/callback":
            self._habr_callback(parsed.query)
            return
        if parsed.path == "/api/auth/hh/callback":
            self._hh_callback(parsed.query)
            return
        self._html(HTTPStatus.NOT_FOUND, "Not found", "Unknown endpoint.")

    def _habr_login(self) -> None:
        try:
            state = _create_state()
        except RuntimeError:
            self._html(
                HTTPStatus.SERVICE_UNAVAILABLE,
                "Fabula Career Agent",
                "Habr OAuth is not configured on the server.",
            )
            return
        target = HABR_AUTHORIZE_URL + "?" + urlencode(
            {
                "client_id": HABR_CLIENT_ID,
                "redirect_uri": HABR_REDIRECT_URI,
                "response_type": "code",
                "state": state,
            }
        )
        self.send_response(HTTPStatus.FOUND)
        self.send_header("Location", target)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()

    def _habr_callback(self, raw_query: str) -> None:
        query = parse_qs(raw_query, keep_blank_values=True)
        oauth_error = (query.get("error") or [""])[0].strip()
        if oauth_error:
            description = (query.get("error_description") or [""])[0].strip()
            self._html(
                HTTPStatus.BAD_REQUEST,
                "Fabula Career Agent",
                html.escape(description or "Habr authorization was cancelled."),
            )
            return
        code = (query.get("code") or [""])[0].strip()
        state = (query.get("state") or [""])[0].strip()
        if not code or not state or not _consume_state(state):
            self._html(
                HTTPStatus.BAD_REQUEST,
                "Fabula Career Agent",
                "Authorization request is invalid or expired. Start the connection again.",
            )
            return
        try:
            _exchange_code(code)
        except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
            self._html(
                HTTPStatus.BAD_GATEWAY,
                "Fabula Career Agent",
                "Habr returned an OAuth error. The connection was not saved.",
            )
            return
        self._html(
            HTTPStatus.OK,
            "Fabula Career Agent",
            "Habr Career account connected successfully. You can close this page.",
        )

    def _hh_callback(self, raw_query: str) -> None:
        query = parse_qs(raw_query, keep_blank_values=True)
        oauth_error = (query.get("error") or [""])[0].strip()
        if oauth_error:
            description = (query.get("error_description") or [""])[0].strip()
            self._html(
                HTTPStatus.BAD_REQUEST,
                "Fabula Career Agent",
                html.escape(description or "HeadHunter authorization was cancelled."),
            )
            return
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
<html lang=\"ru\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"robots\" content=\"noindex,nofollow\"><title>{html.escape(title)}</title></head>
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
        return


def main() -> None:
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
