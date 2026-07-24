"""Fabula Career Agent OAuth and vacancy API.

OAuth states and tokens are stored per Fabula installation. Authorization
codes and access tokens are never written to logs or returned to clients.
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
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen

HOST = os.environ.get("CAREER_AGENT_HOST", "127.0.0.1")
PORT = int(os.environ.get("CAREER_AGENT_PORT", "8013"))
STATE_TTL_SECONDS = 600
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
USER_AGENT = os.environ.get(
    "HH_USER_AGENT", "Fabula-Career-Agent/1.0 (support@router1.tech)"
).strip()

HH_CLIENT_ID = os.environ.get("HH_CLIENT_ID", "").strip()
HH_CLIENT_SECRET = os.environ.get("HH_CLIENT_SECRET", "").strip()
HH_REDIRECT_URI = os.environ.get(
    "HH_REDIRECT_URI", "https://router1.tech/api/auth/hh/callback"
).strip()
HH_AUTHORIZE_URL = os.environ.get(
    "HH_AUTHORIZE_URL", "https://hh.ru/oauth/authorize"
).strip()
HH_TOKEN_URL = os.environ.get("HH_TOKEN_URL", "https://api.hh.ru/token").strip()
HH_API_URL = os.environ.get("HH_API_URL", "https://api.hh.ru").rstrip("/")
HH_STATE_DIR = Path(
    os.environ.get("HH_STATE_DIR", "/opt/vpn_bot/career-agent/hh-states")
)
HH_TOKEN_DIR = Path(
    os.environ.get("HH_TOKEN_DIR", "/opt/vpn_bot/career-agent/hh-tokens")
)

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
HABR_STATE_FILE = Path(
    os.environ.get("HABR_STATE_FILE", "/opt/vpn_bot/.habr_oauth_state")
)
HABR_TOKEN_FILE = Path(
    os.environ.get("HABR_TOKEN_FILE", "/opt/vpn_bot/.habr_oauth_token.json")
)


def _require_config(client_id: str, client_secret: str, provider: str) -> None:
    if not client_id or not client_secret:
        raise RuntimeError(f"{provider} OAuth credentials are not configured")


def _installation_id(raw: str) -> str:
    value = raw.strip()
    if not 8 <= len(value) <= 128:
        raise ValueError("invalid installation_id")
    if any(not (character.isalnum() or character in "-_.:") for character in value):
        raise ValueError("invalid installation_id")
    return value


def _user_key(installation_id: str) -> str:
    return hashlib.sha256(installation_id.encode("utf-8")).hexdigest()


def _prepare_private_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    os.chmod(path, 0o700)


def _write_private_json(path: Path, payload: dict[str, Any]) -> None:
    _prepare_private_directory(path.parent)
    temporary = path.with_suffix(path.suffix + f".{secrets.token_hex(6)}.tmp")
    try:
        temporary.write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        os.chmod(temporary, 0o600)
        temporary.replace(path)
        os.chmod(path, 0o600)
    finally:
        temporary.unlink(missing_ok=True)


def _json_request(
    url: str,
    *,
    method: str = "GET",
    data: bytes | None = None,
    headers: dict[str, str] | None = None,
) -> dict[str, Any]:
    request_headers = {
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
        **(headers or {}),
    }
    request = Request(url, data=data, method=method, headers=request_headers)
    with urlopen(request, timeout=15) as response:
        raw = response.read(MAX_RESPONSE_BYTES + 1)
    if len(raw) > MAX_RESPONSE_BYTES:
        raise ValueError("upstream response is too large")
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("upstream response is not an object")
    return payload


def _hh_state_signature(nonce: str, issued_at: int, user_key: str) -> str:
    payload = f"{nonce}.{issued_at}.{user_key}".encode("utf-8")
    return hmac.new(HH_CLIENT_SECRET.encode("utf-8"), payload, hashlib.sha256).hexdigest()


def _create_hh_state(installation_id: str) -> str:
    _require_config(HH_CLIENT_ID, HH_CLIENT_SECRET, "HeadHunter")
    user_key = _user_key(_installation_id(installation_id))
    nonce = secrets.token_urlsafe(32)
    issued_at = int(time.time())
    signature = _hh_state_signature(nonce, issued_at, user_key)
    state = f"{nonce}.{issued_at}.{signature}"
    _write_private_json(
        HH_STATE_DIR / f"{nonce}.json",
        {"state": state, "user_key": user_key, "issued_at": issued_at},
    )
    return state


def _consume_hh_state(received: str) -> str | None:
    try:
        nonce, issued_text, signature = received.split(".", 2)
        issued_at = int(issued_text)
        state_path = HH_STATE_DIR / f"{nonce}.json"
        stored = json.loads(state_path.read_text(encoding="utf-8"))
        state_path.unlink(missing_ok=True)
        user_key = str(stored["user_key"])
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        return None
    if not hmac.compare_digest(received, str(stored.get("state", ""))):
        return None
    if int(time.time()) - issued_at > STATE_TTL_SECONDS or issued_at > int(time.time()) + 30:
        return None
    expected = _hh_state_signature(nonce, issued_at, user_key)
    return user_key if hmac.compare_digest(signature, expected) else None


def _exchange_hh_code(code: str, user_key: str) -> None:
    _require_config(HH_CLIENT_ID, HH_CLIENT_SECRET, "HeadHunter")
    body = urlencode(
        {
            "grant_type": "authorization_code",
            "client_id": HH_CLIENT_ID,
            "client_secret": HH_CLIENT_SECRET,
            "redirect_uri": HH_REDIRECT_URI,
            "code": code,
        }
    ).encode("utf-8")
    payload = _json_request(
        HH_TOKEN_URL,
        method="POST",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    if not payload.get("access_token"):
        raise ValueError("HeadHunter token response did not contain access_token")
    payload["received_at"] = int(time.time())
    _write_private_json(HH_TOKEN_DIR / f"{user_key}.json", payload)


def _hh_token(installation_id: str) -> str | None:
    path = HH_TOKEN_DIR / f"{_user_key(_installation_id(installation_id))}.json"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        token = str(payload.get("access_token", "")).strip()
    except (OSError, ValueError, AttributeError, json.JSONDecodeError):
        return None
    return token or None


def _hh_vacancies(
    installation_id: str, text: str, area: str, page: int, per_page: int
) -> dict[str, Any]:
    token = _hh_token(installation_id)
    if not token:
        raise PermissionError("HeadHunter account is not connected")
    query = urlencode(
        {
            "text": text[:200],
            "area": area[:20],
            "page": min(max(page, 0), 20),
            "per_page": min(max(per_page, 1), 50),
            "order_by": "publication_time",
        }
    )
    payload = _json_request(
        f"{HH_API_URL}/vacancies?{query}",
        headers={"Authorization": f"Bearer {token}"},
    )
    items = payload.get("items")
    if not isinstance(items, list):
        raise ValueError("HeadHunter vacancies response did not contain items")
    return {
        "source": "hh",
        "found": int(payload.get("found", 0)),
        "page": int(payload.get("page", page)),
        "pages": int(payload.get("pages", 0)),
        "items": items,
    }


def _application_draft(payload: dict[str, Any]) -> dict[str, Any]:
    installation_id = _installation_id(str(payload.get("installation_id", "")))
    title = str(payload.get("vacancy_title", "")).strip()[:200]
    company = str(payload.get("company", "")).strip()[:200]
    experience = str(payload.get("experience", "")).strip()[:4000]
    if not title or not experience:
        raise ValueError("vacancy_title and experience are required")

    greeting = f"Здравствуйте, команда {company}!" if company else "Здравствуйте!"
    cover_letter = (
        f"{greeting}\n\n"
        f"Меня заинтересовала вакансия «{title}». "
        "Мой релевантный опыт:\n"
        f"{experience}\n\n"
        "Буду рад обсудить задачи позиции и подробнее рассказать о результатах, "
        "которые могут быть полезны вашей команде."
    )
    return {
        "draft_id": secrets.token_urlsafe(18),
        "installation_key": _user_key(installation_id),
        "status": "draft",
        "vacancy_title": title,
        "company": company,
        "resume_focus": experience,
        "cover_letter": cover_letter,
        "requires_approval": True,
        "sent": False,
    }


def _habr_state_signature(nonce: str, issued_at: int) -> str:
    payload = f"{nonce}.{issued_at}".encode("utf-8")
    return hmac.new(
        HABR_CLIENT_SECRET.encode("utf-8"), payload, hashlib.sha256
    ).hexdigest()


def _create_habr_state() -> str:
    _require_config(HABR_CLIENT_ID, HABR_CLIENT_SECRET, "Habr")
    nonce = secrets.token_urlsafe(32)
    issued_at = int(time.time())
    state = f"{nonce}.{issued_at}.{_habr_state_signature(nonce, issued_at)}"
    HABR_STATE_FILE.write_text(state, encoding="utf-8")
    os.chmod(HABR_STATE_FILE, 0o600)
    return state


def _consume_habr_state(received: str) -> bool:
    try:
        expected = HABR_STATE_FILE.read_text(encoding="utf-8").strip()
        HABR_STATE_FILE.unlink(missing_ok=True)
        nonce, issued_text, signature = received.split(".", 2)
        issued_at = int(issued_text)
    except (OSError, ValueError):
        return False
    return (
        hmac.compare_digest(received, expected)
        and 0 <= int(time.time()) - issued_at <= STATE_TTL_SECONDS
        and hmac.compare_digest(signature, _habr_state_signature(nonce, issued_at))
    )


def _exchange_habr_code(code: str) -> None:
    _require_config(HABR_CLIENT_ID, HABR_CLIENT_SECRET, "Habr")
    body = urlencode(
        {
            "grant_type": "authorization_code",
            "client_id": HABR_CLIENT_ID,
            "client_secret": HABR_CLIENT_SECRET,
            "redirect_uri": HABR_REDIRECT_URI,
            "code": code,
        }
    ).encode("utf-8")
    payload = _json_request(
        HABR_TOKEN_URL,
        method="POST",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    if not payload.get("access_token"):
        raise ValueError("Habr token response did not contain access_token")
    payload["received_at"] = int(time.time())
    _write_private_json(HABR_TOKEN_FILE, payload)


class Handler(BaseHTTPRequestHandler):
    server_version = "FabulaCareerAgent/0.3"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._text(HTTPStatus.OK, "ok")
        elif parsed.path == "/api/auth/hh/login":
            self._hh_login(parsed.query)
        elif parsed.path == "/api/auth/hh/callback":
            self._hh_callback(parsed.query)
        elif parsed.path == "/api/career/hh/status":
            self._hh_status(parsed.query)
        elif parsed.path == "/api/career/hh/vacancies":
            self._hh_vacancies(parsed.query)
        elif parsed.path == "/api/auth/habr/login":
            self._habr_login()
        elif parsed.path == "/api/auth/habr/callback":
            self._habr_callback(parsed.query)
        else:
            self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/api/career/applications/draft":
            self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length < 1 or length > 16_384:
                raise ValueError("invalid body length")
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("invalid payload")
            draft = _application_draft(payload)
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
            self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid_request"})
            return
        self._json(HTTPStatus.CREATED, draft)

    def _hh_login(self, raw_query: str) -> None:
        query = parse_qs(raw_query, keep_blank_values=True)
        installation_id = (query.get("installation_id") or [""])[0]
        try:
            state = _create_hh_state(installation_id)
        except ValueError:
            self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid_installation_id"})
            return
        except RuntimeError:
            self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "hh_not_configured"})
            return
        target = HH_AUTHORIZE_URL + "?" + urlencode(
            {
                "client_id": HH_CLIENT_ID,
                "redirect_uri": HH_REDIRECT_URI,
                "response_type": "code",
                "state": state,
            }
        )
        self.send_response(HTTPStatus.FOUND)
        self.send_header("Location", target)
        self._security_headers()
        self.end_headers()

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
        code = (query.get("code") or [""])[0].strip()
        state = (query.get("state") or [""])[0].strip()
        user_key = _consume_hh_state(state) if code and state else None
        if not user_key:
            self._html(
                HTTPStatus.BAD_REQUEST,
                "Fabula Career Agent",
                "Authorization request is invalid or expired. Start the connection again.",
            )
            return
        try:
            _exchange_hh_code(code, user_key)
        except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
            self._html(
                HTTPStatus.BAD_GATEWAY,
                "Fabula Career Agent",
                "HeadHunter returned an OAuth error. The connection was not saved.",
            )
            return
        self._html(
            HTTPStatus.OK,
            "Fabula Career Agent",
            "HeadHunter account connected successfully. You can return to Fabula.",
        )

    def _hh_status(self, raw_query: str) -> None:
        query = parse_qs(raw_query, keep_blank_values=True)
        installation_id = (query.get("installation_id") or [""])[0]
        try:
            connected = _hh_token(installation_id) is not None
        except ValueError:
            self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid_installation_id"})
            return
        self._json(HTTPStatus.OK, {"source": "hh", "connected": connected})

    def _hh_vacancies(self, raw_query: str) -> None:
        query = parse_qs(raw_query, keep_blank_values=True)
        try:
            payload = _hh_vacancies(
                (query.get("installation_id") or [""])[0],
                (query.get("text") or [""])[0],
                (query.get("area") or ["113"])[0],
                int((query.get("page") or ["0"])[0]),
                int((query.get("per_page") or ["20"])[0]),
            )
        except (ValueError, TypeError):
            self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid_request"})
            return
        except PermissionError:
            self._json(HTTPStatus.UNAUTHORIZED, {"error": "hh_not_connected"})
            return
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError):
            self._json(HTTPStatus.BAD_GATEWAY, {"error": "hh_upstream_error"})
            return
        self._json(HTTPStatus.OK, payload)

    def _habr_login(self) -> None:
        try:
            state = _create_habr_state()
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
        self._security_headers()
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
        if not code or not state or not _consume_habr_state(state):
            self._html(
                HTTPStatus.BAD_REQUEST,
                "Fabula Career Agent",
                "Authorization request is invalid or expired. Start the connection again.",
            )
            return
        try:
            _exchange_habr_code(code)
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

    def _security_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("Pragma", "no-cache")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")

    def _text(self, status: HTTPStatus, body: str) -> None:
        encoded = body.encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self._security_headers()
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        encoded = json.dumps(
            payload, ensure_ascii=False, separators=(",", ":")
        ).encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self._security_headers()
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _html(self, status: HTTPStatus, title: str, message: str) -> None:
        encoded = f"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>{html.escape(title)}</title></head>
<body style="font-family:system-ui,sans-serif;max-width:680px;margin:72px auto;padding:0 24px;color:#171717"><h1>{html.escape(title)}</h1><p>{message}</p></body></html>""".encode(
            "utf-8"
        )
        self.send_response(int(status))
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self._security_headers()
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
