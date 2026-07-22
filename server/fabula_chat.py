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
DEFAULT_MODEL = "google/gemini-2.5-flash"
SYSTEM_PROMPT = """Ты — личный ассистент в приложении Fabula: спокойный, внимательный и практичный помощник для женщин.
Твоя задача — понимать текущие жизненные приоритеты пользовательницы, удерживать контекст и помогать сделать один полезный следующий шаг без давления.

Правила:
- отвечай естественно, тепло и без канцелярита;
- не осуждай, не морализируй и не ставь диагнозы;
- не называй себя психологом или врачом;
- не принимай решения за человека и не утверждай, что знаешь чужие мысли;
- не ограничивайся пересказом чувств: отдели факт от предположения и предложи конкретное действие, если запрос это допускает;
- учитывай предыдущие сообщения и не спрашивай повторно то, что уже известно;
- если данных недостаточно, задай один точный вопрос; если достаточно — сразу помогай;
- при нескольких проблемах помоги выбрать приоритет по срочности, безопасности и влиянию на жизнь;
- не заваливай вариантами: обычно давай один следующий шаг и максимум три коротких варианта;
- обращайся на «ты» и отвечай только по-русски;
- не изображай романтического партнёра и не навязывай флирт;
- обычный ответ ограничивай 700 символами;
- возвращай только готовый ответ пользователю: без анализа, черновика, служебных заметок, заголовков Draft/Analysis/Reasoning и рассуждений о том, как отвечать;
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
    assistant_name: str
    assistant_gender: str
    messages: list[ChatMessage]
    birthday: str = ""
    sign: str = ""
    cycle_configured: bool = False
    journal_started: bool = False

    @classmethod
    def from_dict(cls, value: dict[str, Any]) -> "FabulaChatPayload":
        installation_id = str(value.get("installation_id", "")).strip()
        name = str(value.get("name", "")).strip()
        assistant_name = str(value.get("assistant_name", "")).strip()
        assistant_gender = str(value.get("assistant_gender", "male")).strip()
        raw_messages = value.get("messages")
        if not 8 <= len(installation_id) <= 128:
            raise ValueError("invalid installation_id")
        if len(name) > 80:
            raise ValueError("name is too long")
        if len(assistant_name) > 24:
            raise ValueError("assistant name is too long")
        if assistant_gender not in {"male", "female"}:
            raise ValueError("invalid assistant gender")
        birthday = str(value.get("birthday", "")).strip()
        sign = str(value.get("sign", "")).strip()
        if len(birthday) > 20 or len(sign) > 24:
            raise ValueError("invalid profile context")
        if not isinstance(raw_messages, list) or not 1 <= len(raw_messages) <= 24:
            raise ValueError("messages must contain 1 to 24 items")
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
        return cls(
            installation_id=installation_id,
            name=name,
            assistant_name=assistant_name,
            assistant_gender=assistant_gender,
            messages=messages,
            birthday=birthday,
            sign=sign,
            cycle_configured=value.get("cycle_configured") is True,
            journal_started=value.get("journal_started") is True,
        )


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
    assistant_hint = (
        f"Тебя зовут {payload.assistant_name}. Всегда представляйся и говори от имени {payload.assistant_name}. "
        if payload.assistant_name
        else ""
    )
    gender_hint = (
        "Ты женщина: говори о себе в женском роде. "
        if payload.assistant_gender == "female"
        else "Ты мужчина: говори о себе в мужском роде. "
    )
    profile_hint = " ".join(
        part for part in (
            f"Дата рождения пользовательницы: {payload.birthday}." if payload.birthday else "",
            f"Знак: {payload.sign}." if payload.sign else "",
            "Модуль цикла заполнен." if payload.cycle_configured else "Модуль цикла ещё не заполнен; если это уместно по теме разговора, мягко предложи его настроить.",
            "В личном дневнике уже есть запись." if payload.journal_started else "Личный дневник пока пуст; предлагай запись только когда она действительно поможет сохранить важную мысль.",
        ) if part
    )
    messages: list[dict[str, str]] = [
        {
            "role": "system",
            "content": f"{SYSTEM_PROMPT}\n\n{name_hint}{profile_hint} {gender_hint}{assistant_hint}".strip(),
        }
    ]
    messages.extend(
        {"role": message.role, "content": message.content}
        for message in payload.messages[-24:]
    )
    return {
        "model": os.environ.get("OPENROUTER_MODEL", DEFAULT_MODEL),
        "messages": messages,
        # Reasoning models may spend part of the budget before producing the
        # visible answer. Keep enough room for the final Russian reply.
        "max_tokens": 800,
        "temperature": 0.45,
        "usage": {"include": True},
    }


_INTERNAL_DRAFT_MARKERS = (
    "we need ",
    "we should ",
    "the user ",
    "need answer",
    "final answer",
    "draft:",
    "analysis:",
    "reasoning:",
)


def _is_safe_user_reply(answer: str) -> bool:
    """Reject obvious model scratchpads before they reach the client/history."""
    normalized = " ".join(answer.lower().split())
    if not normalized or any(marker in normalized for marker in _INTERNAL_DRAFT_MARKERS):
        return False
    letters = [character for character in answer if character.isalpha()]
    cyrillic = [
        character
        for character in letters
        if "а" <= character.lower() <= "я" or character.lower() == "ё"
    ]
    return bool(letters) and len(cyrillic) / len(letters) >= 0.55


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
    last_error: Exception | None = None
    # Keep the whole retry window below nginx/client timeouts so the app always
    # receives a structured error instead of a dropped connection.
    for attempt in range(2):
        try:
            with urllib.request.urlopen(request, timeout=18) as response:
                result = json.loads(response.read().decode())
            answer = result["choices"][0]["message"]["content"].strip()
            if _is_safe_user_reply(answer):
                return answer[:3000]
            raise ValueError("unsafe or non-Russian response")
        except urllib.error.HTTPError as error:
            last_error = error
            try:
                detail = error.read().decode("utf-8", errors="replace")[:800]
            except Exception:
                detail = "unreadable response"
            print(
                f"OpenRouter HTTP {error.code}: {detail}",
                flush=True,
            )
            if attempt < 1 and error.code >= 500:
                time.sleep(attempt + 1)
                continue
            break
        except (
            urllib.error.URLError,
            TimeoutError,
            json.JSONDecodeError,
            KeyError,
            IndexError,
            TypeError,
            AttributeError,
            ValueError,
        ) as error:
            last_error = error
            if attempt < 1:
                time.sleep(attempt + 1)
    raise RuntimeError("OpenRouter unavailable after retries") from last_error


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

def register_fabula_proxy_routes(app: Any) -> None:
    """Register the public route in Router1 site_api and proxy it to FR."""

    from fastapi import Header, HTTPException

    @app.post("/api/fabula/chat", include_in_schema=False)
    def fabula_chat_proxy(
        payload: dict[str, Any],
        authorization: str | None = Header(default=None),
    ) -> dict[str, str]:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        if authorization:
            headers["Authorization"] = authorization
        upstream = urllib.request.Request(
            os.environ.get(
                "FABULA_CHAT_UPSTREAM_URL",
                "http://127.0.0.1:8012/api/fabula/chat",
            ),
            data=body,
            method="POST",
            headers=headers,
        )
        try:
            with urllib.request.urlopen(upstream, timeout=52) as response:
                result = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            try:
                upstream_error = json.loads(error.read().decode("utf-8"))
                detail = str(upstream_error.get("detail", "Fabula unavailable"))
            except Exception:
                detail = "Fabula unavailable"
            raise HTTPException(status_code=error.code, detail=detail) from error
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            raise HTTPException(
                status_code=503,
                detail="Fabula temporarily unavailable",
            ) from error
        reply = str(result.get("reply", "")).strip()
        if not reply:
            raise HTTPException(status_code=503, detail="Fabula returned no reply")
        return {"reply": reply}
