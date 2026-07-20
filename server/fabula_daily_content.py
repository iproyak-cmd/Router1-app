"""Persistent daily content packages for Fabula.

The production /api/fabula/horoscope/{sign} handler should call
DailyContentStore.get_or_create(date, sign, generator). The primary key makes
one immutable package authoritative for each local calendar date and zodiac
sign, even when several app instances request it at the same time.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import sqlite3
from collections.abc import Callable
from pathlib import Path
from typing import Any

VALID_SIGNS = {
    "aries": ("Овен", "♈"),
    "taurus": ("Телец", "♉"),
    "gemini": ("Близнецы", "♊"),
    "cancer": ("Рак", "♋"),
    "leo": ("Лев", "♌"),
    "virgo": ("Дева", "♍"),
    "libra": ("Весы", "♎"),
    "scorpio": ("Скорпион", "♏"),
    "sagittarius": ("Стрелец", "♐"),
    "capricorn": ("Козерог", "♑"),
    "aquarius": ("Водолей", "♒"),
    "pisces": ("Рыбы", "♓"),
}

Generator = Callable[[dt.date, str], dict[str, Any]]


class DailyContentStore:
    def __init__(self, database_path: str | Path):
        self.database_path = str(database_path)
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path, timeout=15)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout=15000")
        return connection

    def _ensure_schema(self) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS fabula_daily_content (
                    content_date TEXT NOT NULL,
                    sign TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    PRIMARY KEY (content_date, sign)
                )
                """
            )

    def get_or_create(
        self,
        content_date: dt.date,
        sign: str,
        generator: Generator | None = None,
    ) -> dict[str, Any]:
        normalized_sign = sign.strip().lower()
        if normalized_sign not in VALID_SIGNS:
            raise ValueError("unsupported zodiac sign")
        day = content_date.isoformat()
        factory = generator or generate_editorial_daily_content
        connection = self._connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT payload_json FROM fabula_daily_content "
                "WHERE content_date = ? AND sign = ?",
                (day, normalized_sign),
            ).fetchone()
            if row is not None:
                connection.commit()
                return json.loads(str(row["payload_json"]))

            payload = factory(content_date, normalized_sign)
            validate_daily_content(
                payload,
                expected_date=day,
                expected_sign=normalized_sign,
            )
            encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
            connection.execute(
                "INSERT INTO fabula_daily_content "
                "(content_date, sign, payload_json, created_at) VALUES (?, ?, ?, ?)",
                (
                    day,
                    normalized_sign,
                    encoded,
                    dt.datetime.now(dt.timezone.utc).isoformat(),
                ),
            )
            connection.commit()
            return payload
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()


def validate_daily_content(
    payload: dict[str, Any],
    *,
    expected_date: str,
    expected_sign: str,
) -> None:
    tarot = payload.get("tarot")
    required_text = (
        "sign_title",
        "symbol",
        "lunar_phase",
        "overview",
        "work",
        "money",
        "love",
        "advice",
        "color",
        "disclaimer",
    )
    if payload.get("date") != expected_date or payload.get("sign") != expected_sign:
        raise ValueError("daily content date or sign mismatch")
    if any(not str(payload.get(field) or "").strip() for field in required_text):
        raise ValueError("daily content has an empty field")
    if not isinstance(tarot, dict) or not str(tarot.get("title") or "").strip():
        raise ValueError("daily tarot is missing")
    if not str(tarot.get("meaning") or "").strip():
        raise ValueError("daily tarot meaning is missing")
    number = payload.get("number")
    if not isinstance(number, int) or not 1 <= number <= 9:
        raise ValueError("daily number must be in range 1..9")


def generate_editorial_daily_content(
    content_date: dt.date,
    sign: str,
) -> dict[str, Any]:
    title, symbol = VALID_SIGNS[sign]
    key = f"{content_date.isoformat()}:{sign}"
    overviews = (
        "Сегодня полезно выбрать один ясный приоритет и дать ему достаточно внимания.",
        "День лучше раскрывается через спокойный темп, точные слова и завершённые дела.",
        "Не всё требует немедленного ответа: пауза поможет увидеть более сильное решение.",
        "Сосредоточьтесь на том, что возвращает ощущение опоры и управляемости.",
        "Сегодня ценнее последовательность, чем резкий рывок или желание успеть всё.",
        "Неожиданная деталь может подсказать практичный следующий шаг.",
    )
    work = (
        "Закройте одну задачу с измеримым результатом прежде, чем открывать следующую.",
        "Проверьте договорённости и сроки: ясность сегодня экономит силы завтра.",
        "Отделите срочное от важного и защитите время для главной задачи.",
        "Сначала зафиксируйте критерий результата, затем выбирайте способ.",
    )
    money = (
        "Сверьте регулярные расходы и не принимайте решение только из-за срочности.",
        "Сравните условия и зафиксируйте цифры письменно перед новым обязательством.",
        "Разумнее укрепить уже работающий источник, чем распыляться на несколько новых.",
        "Отложите импульсивную покупку до момента, когда сможете спокойно сравнить варианты.",
    )
    love = (
        "Говорите прямо и бережно: ясная просьба сегодня лучше намёков.",
        "Тёплый короткий контакт поможет больше, чем попытка решить всё одним разговором.",
        "Оставьте место и близости, и личному пространству.",
        "Не угадывайте чужие мысли: задайте спокойный уточняющий вопрос.",
    )
    advice = (
        "Сделайте следующий шаг достаточно маленьким, чтобы начать без сопротивления.",
        "Оставьте в расписании двадцать минут без экрана и новых задач.",
        "Запишите решение одним предложением и проверьте, действительно ли оно ваше.",
        "Выберите действие, после которого вечер станет спокойнее.",
    )
    colors = (
        "Бордовый",
        "Золотой",
        "Зелёный",
        "Синий",
        "Бирюзовый",
        "Фиолетовый",
        "Серебристый",
    )
    cards = (
        ("Шут", "Новый шаг не требует знания всего маршрута."),
        ("Маг", "Используйте то, что уже есть под рукой."),
        ("Верховная Жрица", "Наблюдение поможет отделить интуицию от тревоги."),
        ("Императрица", "Поддержите то, что растёт через заботу и качество."),
        ("Император", "Структура и ясные правила освободят энергию."),
        ("Влюблённые", "Выбор становится проще, когда совпадает с ценностями."),
        ("Колесница", "Определите направление и защищайте внимание."),
        ("Сила", "Мягкая настойчивость убедительнее давления."),
        ("Отшельник", "Короткое уединение поможет услышать собственный ответ."),
        ("Колесо Фортуны", "Изменение условий можно превратить в возможность."),
        ("Справедливость", "Проверьте факты и последствия до решения."),
        ("Звезда", "Вернитесь к большой цели и подтвердите направление шагом."),
        ("Луна", "Дайте деталям проявиться прежде, чем делать вывод."),
        ("Солнце", "Покажите результат и признайте то, что получилось."),
        ("Мир", "Зафиксируйте завершение прежде, чем идти дальше."),
    )

    def pick(values: tuple[Any, ...], field: str) -> Any:
        digest = hashlib.sha256(f"{key}:{field}".encode()).digest()
        return values[int.from_bytes(digest[:8], "big") % len(values)]

    tarot = pick(cards, "tarot")
    number_digest = hashlib.sha256(f"{key}:number".encode()).digest()
    return {
        "date": content_date.isoformat(),
        "sign": sign,
        "sign_title": title,
        "symbol": symbol,
        "lunar_phase": lunar_phase_for(content_date),
        "overview": pick(overviews, "overview"),
        "work": pick(work, "work"),
        "money": pick(money, "money"),
        "love": pick(love, "love"),
        "advice": pick(advice, "advice"),
        "color": pick(colors, "color"),
        "number": int.from_bytes(number_digest[:8], "big") % 9 + 1,
        "tarot": {"title": tarot[0], "meaning": tarot[1]},
        "disclaimer": "Развлекательная редакционная подборка Fabula.",
    }


def lunar_phase_for(value: dt.date) -> str:
    synodic_month = 29.530588853
    instant = dt.datetime.combine(
        value,
        dt.time(12),
        tzinfo=dt.timezone.utc,
    )
    reference = dt.datetime(2000, 1, 6, 18, 14, tzinfo=dt.timezone.utc)
    age = ((instant - reference).total_seconds() / 86400) % synodic_month
    if age < 1.84566 or age >= 27.68493:
        return "Новолуние"
    if age < 5.53699:
        return "Растущий серп"
    if age < 9.22831:
        return "Первая четверть"
    if age < 12.91963:
        return "Растущая Луна"
    if age < 16.61096:
        return "Полнолуние"
    if age < 20.30228:
        return "Убывающая Луна"
    if age < 23.99361:
        return "Последняя четверть"
    return "Убывающий серп"
