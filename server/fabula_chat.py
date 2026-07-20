"""Safe OpenRouter gateway for the Fabula companion."""

from __future__ import annotations

import hmac
import json
import os
import threading
import time
import urllib.error
import urllib.request
from collections import defaultdict, deque
from dataclasses import dataclass
from typing import Any


OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
DEFAULT_MODEL = "openrouter/free"
SYSTEM_PROMPT = """Ты — Fabula, тёплая и тактичная собеседница для женщин.
Твоя основная задача — внимательно слушать, помогать человеку назвать чувства и спокойнее посмотреть на ситуацию.

Правила:
- отвечай естественно, тепло и без канцелярита;
- не осуждай, не морализируй и не ставь диагнозы;
- не называй себя психологом или врачом;
- не принимай решения за человека и не утверждай, что знаешь чужие мысли;
- сначала прояви понимание, затем задай не больше одного уместного вопроса;
- совет давай только по просьбе или мягко предложи его;
- обращайся на «ты» и отвечай только по-русски;
- обычный ответ ограничивай 700 символами;
- эзотерические трактовки подавай как способ рефлексии, а не достоверный прогноз.

Если человек сообщает о непосредственной опасности для себя или другого человека, не продолжай эзотерическое толкование: спокойно предложи срочно связаться с местной экстренной службой и человеком, который может быть рядом."""


@dataclass(frozen=True)
class ChatMessage:
    role: str
    content: str


@dataclass(frozen=True)
class FabulaChatPayload:
    installation_id: str
    name: str
    messages: list[ChatMessage]

    @classmethod
    def from_dict(cls, value: dict[str, Any]) -> "FabulaChatPayload":
        installation_id = str(value.get("installation_id", "")).strip()
        name = str(value.get("name", "")).strip()
        raw_messages = value.get("messages")
        if not 8 <= len(installation_id) <= 128:
            raise ValueError("invalid installation_id")
        if len(name) > 80:
            raise ValueError("name is too long")
        if not isinstance(raw_messages, list) or not 1 <= len(raw_messages) <= 12:
            raise ValueError("messages must contain 1 to 12 items")
        messages: list[ChatMessage] = []
        for raw in raw_messages:
            if not isinstance(raw, dict):
                raise ValueError("invalid message")
            role = str(raw.get("role", ""))
            content = str(raw.get("content", "")).strip()
            if role not in {"user", "assistant"}:
                raise ValueError("unsupported role")
            if not 1 <= len(content) <= 2000:
                raise ValueError("invalid message content")
            messages.append(ChatMessage(role=role, content=content))
        return cls(installation_id=installation_id, name=name, messages=messages)


class SlidingWindowLimiter:
    def __init__(self, limit: int, window_seconds: int) -> None:
        self.limit = limit
        self.window_seconds = window_seconds
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def allowed(self, key: str) -> bool:
        now = time.time()
        threshold = now - self.window_seconds
        with self._lock:
            events = self._events[key]
            while events and events[0] < threshold:
                events.popleft()
            if len(events) >= self.limit:
                return False
            events.append(now)
            return True


def build_openrouter_payload(payload: FabulaChatPayload) -> dict[str, Any]:
    name_hint = (
        f"Пользовательницу зовут {payload.name.strip()}. "
        if payload.name.strip()
        else ""
    )
    messages: list[dict[str, str]] = [
        {"role": "system", "content": f"{SYSTEM_PROMPT}\n\n{name_hint}".strip()}
    ]
    messages.extend(
        {"role": message.role, "content": message.content}
        for message in payload.messages[-12:]
    )
    return {
        "model": os.environ.get("OPENROUTER_MODEL", DEFAULT_MODEL),
        "messages": messages,
        "max_tokens": 260,
        "temperature": 0.8,
        "provider": {"data_collection": "deny"},
        "usage": {"include": True},
    }


def request_openrouter(payload: FabulaChatPayload) -> str:
    api_key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is required")
    body = json.dumps(build_openrouter_payload(payload), ensure_ascii=False).encode()
    request = urllib.request.Request(
        OPENROUTER_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://fabula.router1.tech",
            "X-OpenRouter-Title": "Fabula",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=40) as response:
            result = json.loads(response.read().decode())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise RuntimeError("OpenRouter unavailable") from error
    try:
        answer = result["choices"][0]["message"]["content"].strip()
    except (KeyError, IndexError, TypeError, AttributeError) as error:
        raise RuntimeError("OpenRouter returned an invalid response") from error
    if not answer:
        raise RuntimeError("OpenRouter returned an empty response")
    return answer[:3000]


def register_fabula_chat_routes(app: Any) -> None:
    from fastapi import Header, HTTPException

    limiter = SlidingWindowLimiter(
        limit=int(os.environ.get("FABULA_CHAT_DAILY_LIMIT", "50")),
        window_seconds=24 * 60 * 60,
    )

    @app.post("/api/fabula/chat", include_in_schema=False)
    async def fabula_chat(
        payload: dict[str, Any],
        authorization: str | None = Header(default=None),
    ) -> dict[str, str]:
        expected = os.environ.get("APP_API_TOKEN", "").strip()
        supplied = (authorization or "").removeprefix("Bearer ").strip()
        if not expected or not hmac.compare_digest(supplied, expected):
            raise HTTPException(status_code=401, detail="Unauthorized")
        try:
            validated = FabulaChatPayload.from_dict(payload)
        except ValueError as error:
            raise HTTPException(status_code=422, detail=str(error)) from error
        if not limiter.allowed(validated.installation_id):
            raise HTTPException(status_code=429, detail="Daily message limit reached")
        try:
            return {"reply": request_openrouter(validated)}
        except RuntimeError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
