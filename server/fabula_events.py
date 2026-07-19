"""Fabula download and activation events for the Router1 FastAPI service.

Register with the production FastAPI app and pass the existing admin notifier:

    register_fabula_event_routes(app, notify_admin=send_admin_notification)

The module keeps analytics locally, never stores a raw phone or IP address, and
rate-limits Telegram notifications without blocking downloads or app startup.
"""

from __future__ import annotations

import hashlib
import hmac
import inspect
import json
import os
import secrets
import sqlite3
import time
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, Field


NotifyAdmin = Callable[[str], Awaitable[None] | None]
ALLOWED_APP_EVENTS = {"app_opened", "vpn_connected"}
DOWNLOAD_TARGETS = {
    "android": "/fabula/android/Fabula.apk",
    "windows": "/fabula/windows/FabulaSetup.exe",
}
_EVENT_SALT = os.environ.get("FABULA_EVENT_SALT") or secrets.token_hex(32)


class FabulaEventPayload(BaseModel):
    event: str = Field(min_length=3, max_length=48)
    installation_id: str = Field(min_length=8, max_length=128)
    platform: str = Field(min_length=2, max_length=32)
    app_version: str = Field(min_length=3, max_length=32)
    phone: str | None = Field(default=None, max_length=64)
    details: dict[str, Any] = Field(default_factory=dict)


class FabulaEventStore:
    def __init__(self, path: str | Path) -> None:
        self.path = str(path)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.execute("PRAGMA journal_mode=WAL")
        return connection

    def _initialize(self) -> None:
        Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS fabula_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    created_at INTEGER NOT NULL,
                    event TEXT NOT NULL,
                    platform TEXT NOT NULL,
                    app_version TEXT NOT NULL DEFAULT '',
                    installation_hash TEXT NOT NULL DEFAULT '',
                    phone_hash TEXT NOT NULL DEFAULT '',
                    source TEXT NOT NULL DEFAULT '',
                    campaign TEXT NOT NULL DEFAULT '',
                    ip_hash TEXT NOT NULL DEFAULT '',
                    details_json TEXT NOT NULL DEFAULT '{}'
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_fabula_events_created ON fabula_events(created_at)"
            )

    def add(
        self,
        *,
        event: str,
        platform: str,
        app_version: str = "",
        installation_id: str = "",
        phone: str = "",
        source: str = "",
        campaign: str = "",
        ip: str = "",
        details: dict[str, Any] | None = None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO fabula_events (
                    created_at, event, platform, app_version,
                    installation_hash, phone_hash, source, campaign,
                    ip_hash, details_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    int(time.time()),
                    event,
                    platform,
                    app_version,
                    _digest(installation_id),
                    _digest(phone),
                    source[:120],
                    campaign[:160],
                    _digest(ip),
                    json.dumps(details or {}, ensure_ascii=False)[:2000],
                ),
            )

    def recently_notified(self, key: str, window_seconds: int) -> bool:
        marker = f"notify:{key}"
        threshold = int(time.time()) - window_seconds
        with self._connect() as connection:
            row = connection.execute(
                "SELECT 1 FROM fabula_events WHERE event = ? AND created_at >= ? LIMIT 1",
                (marker, threshold),
            ).fetchone()
            if row:
                return True
            connection.execute(
                """
                INSERT INTO fabula_events (created_at, event, platform)
                VALUES (?, ?, 'internal')
                """,
                (int(time.time()), marker),
            )
            return False


def _digest(value: str) -> str:
    if not value:
        return ""
    return hashlib.sha256(f"{_EVENT_SALT}:{value}".encode()).hexdigest()[:24]


def _masked_phone(phone: str | None) -> str:
    digits = "".join(character for character in (phone or "") if character.isdigit())
    return f"***{digits[-4:]}" if len(digits) >= 4 else "не указан"


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for", "").split(",", 1)[0].strip()
    if forwarded:
        return forwarded
    return request.client.host if request.client else ""


async def _notify(callback: NotifyAdmin, text: str) -> None:
    try:
        result = callback(text)
        if inspect.isawaitable(result):
            await result
    except Exception:
        # A Telegram outage must never block a download or protected connection.
        return


def register_fabula_event_routes(
    app: FastAPI,
    *,
    notify_admin: NotifyAdmin,
    database_path: str | Path = "/opt/vpn_bot/fabula_events.db",
) -> None:
    store = FabulaEventStore(database_path)

    @app.get("/api/fabula/download/{platform}", include_in_schema=False)
    async def fabula_download(platform: str, request: Request) -> RedirectResponse:
        normalized = platform.strip().lower()
        target = DOWNLOAD_TARGETS.get(normalized)
        if target is None:
            raise HTTPException(status_code=404, detail="Unknown Fabula platform")
        source = request.query_params.get("utm_source", "direct")[:120]
        campaign = request.query_params.get("utm_campaign", "")[:160]
        ip = _client_ip(request)
        store.add(
            event="download_clicked",
            platform=normalized,
            source=source,
            campaign=campaign,
            ip=ip,
            details={"user_agent": request.headers.get("user-agent", "")[:300]},
        )
        notify_key = f"download:{normalized}:{_digest(ip)}"
        if not store.recently_notified(notify_key, 60):
            await _notify(
                notify_admin,
                "\n".join(
                    [
                        f"📥 Fabula: начато скачивание {normalized.title()}",
                        f"Источник: {source}",
                        f"Кампания: {campaign or 'не указана'}",
                    ]
                ),
            )
        return RedirectResponse(url=target, status_code=302)

    @app.post("/api/fabula/event", include_in_schema=False)
    async def fabula_event(
        payload: FabulaEventPayload,
        request: Request,
        authorization: str | None = Header(default=None),
    ) -> dict[str, bool]:
        expected = os.environ.get("APP_API_TOKEN", "")
        supplied = (authorization or "").removeprefix("Bearer ").strip()
        if not expected or not hmac.compare_digest(supplied, expected):
            raise HTTPException(status_code=401, detail="Unauthorized")
        event = payload.event.strip().lower()
        if event not in ALLOWED_APP_EVENTS:
            raise HTTPException(status_code=422, detail="Unsupported Fabula event")
        store.add(
            event=event,
            platform=payload.platform,
            app_version=payload.app_version,
            installation_id=payload.installation_id,
            phone=payload.phone or "",
            ip=_client_ip(request),
            details=payload.details,
        )
        dedupe_window = 6 * 60 * 60 if event == "app_opened" else 5 * 60
        notify_key = f"{event}:{_digest(payload.installation_id)}"
        if not store.recently_notified(notify_key, dedupe_window):
            title = "🚀 Fabula: приложение открыто" if event == "app_opened" else "🛡 Fabula: подключение включено"
            lines = [
                title,
                f"Устройство: {payload.platform}",
                f"Версия: {payload.app_version}",
                f"Телефон: {_masked_phone(payload.phone)}",
            ]
            server_code = str(payload.details.get("server_code", "")).strip()
            if server_code:
                lines.append(f"Сервер: {server_code}")
            await _notify(notify_admin, "\n".join(lines))
        return {"ok": True}
