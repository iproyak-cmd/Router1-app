"""Astronomical basis for Fabula's daily sun-sign interpretation."""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass

import astronomy


SIGN_ORDER = (
    "aries", "taurus", "gemini", "cancer", "leo", "virgo",
    "libra", "scorpio", "sagittarius", "capricorn", "aquarius", "pisces",
)

SIGN_TITLES = (
    "Овне", "Тельце", "Близнецах", "Раке", "Льве", "Деве",
    "Весах", "Скорпионе", "Стрельце", "Козероге", "Водолее", "Рыбах",
)

PLANETS = (
    ("moon", "Луна", astronomy.Body.Moon),
    ("mercury", "Меркурий", astronomy.Body.Mercury),
    ("venus", "Венера", astronomy.Body.Venus),
    ("mars", "Марс", astronomy.Body.Mars),
    ("jupiter", "Юпитер", astronomy.Body.Jupiter),
    ("saturn", "Сатурн", astronomy.Body.Saturn),
)

ASPECTS = (
    (0.0, 8.0, "соединение", "strong"),
    (60.0, 5.0, "секстиль", "supportive"),
    (90.0, 6.0, "квадрат", "challenging"),
    (120.0, 6.0, "тригон", "supportive"),
    (180.0, 7.0, "оппозиция", "challenging"),
)


@dataclass(frozen=True)
class Transit:
    planet: str
    planet_title: str
    longitude: float
    sign_title: str
    aspect: str
    tone: str
    orb: float


def _angular_distance(first: float, second: float) -> float:
    return abs((first - second + 180.0) % 360.0 - 180.0)


def _phase_title(angle: float) -> str:
    if angle < 22.5 or angle >= 337.5:
        return "Новолуние"
    if angle < 67.5:
        return "Растущий серп"
    if angle < 112.5:
        return "Первая четверть"
    if angle < 157.5:
        return "Растущая Луна"
    if angle < 202.5:
        return "Полнолуние"
    if angle < 247.5:
        return "Убывающая Луна"
    if angle < 292.5:
        return "Последняя четверть"
    return "Убывающий серп"


def ephemeris_for(content_date: dt.date, sign: str) -> dict:
    """Return real geocentric longitudes and strongest aspects to a sun sign."""
    instant = astronomy.Time.Make(
        content_date.year, content_date.month, content_date.day, 12, 0, 0.0
    )
    sign_midpoint = SIGN_ORDER.index(sign) * 30.0 + 15.0
    positions: dict[str, dict] = {}
    transits: list[Transit] = []

    sun_longitude = float(astronomy.SunPosition(instant).elon)
    positions["sun"] = {
        "title": "Солнце",
        "longitude": round(sun_longitude, 3),
        "sign": SIGN_ORDER[int(sun_longitude // 30) % 12],
    }
    for key, title, body in PLANETS:
        longitude = float(astronomy.EclipticLongitude(body, instant))
        positions[key] = {
            "title": title,
            "longitude": round(longitude, 3),
            "sign": SIGN_ORDER[int(longitude // 30) % 12],
        }
        distance = _angular_distance(longitude, sign_midpoint)
        candidates = []
        for angle, allowed_orb, aspect_title, tone in ASPECTS:
            orb = abs(distance - angle)
            if orb <= allowed_orb:
                candidates.append((orb / allowed_orb, orb, aspect_title, tone))
        if candidates:
            _, orb, aspect_title, tone = min(candidates)
            transits.append(
                Transit(
                    planet=key,
                    planet_title=title,
                    longitude=longitude,
                    sign_title=SIGN_TITLES[int(longitude // 30) % 12],
                    aspect=aspect_title,
                    tone=tone,
                    orb=orb,
                )
            )

    transits.sort(key=lambda item: (item.orb, item.planet != "moon"))
    return {
        "calculated_at_utc": f"{content_date.isoformat()}T12:00:00Z",
        "reference": "geocentric true ecliptic of date",
        "sun_sign_midpoint": sign_midpoint,
        "lunar_phase_angle": round(float(astronomy.MoonPhase(instant)), 3),
        "lunar_phase": _phase_title(float(astronomy.MoonPhase(instant))),
        "positions": positions,
        "transits": transits,
    }
