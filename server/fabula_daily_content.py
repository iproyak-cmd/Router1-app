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

from fabula_ephemeris import SIGN_ORDER, SIGN_TITLES, ephemeris_for

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
                stored = json.loads(str(row["payload_json"]))
                if stored.get("engine_version") == 3 and stored.get("basis"):
                    connection.commit()
                    return stored

            payload = factory(content_date, normalized_sign)
            validate_daily_content(
                payload,
                expected_date=day,
                expected_sign=normalized_sign,
            )
            encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
            connection.execute(
                "INSERT INTO fabula_daily_content "
                "(content_date, sign, payload_json, created_at) VALUES (?, ?, ?, ?) "
                "ON CONFLICT(content_date, sign) DO UPDATE SET "
                "payload_json=excluded.payload_json, created_at=excluded.created_at",
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
        "color_meaning",
        "number_meaning",
        "energy_reason",
        "mood_title",
        "mood_detail",
        "affirmation",
        "lunar_guidance",
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
    for field in ("focus", "action", "question"):
        if not str(tarot.get(field) or "").strip():
            raise ValueError(f"daily tarot {field} is missing")
    energy = payload.get("energy")
    if not isinstance(energy, int) or not 1 <= energy <= 100:
        raise ValueError("daily energy must be in range 1..100")
    number = payload.get("number")
    if not isinstance(number, int) or not 1 <= number <= 9:
        raise ValueError("daily number must be in range 1..9")


def generate_editorial_daily_content(
    content_date: dt.date,
    sign: str,
) -> dict[str, Any]:
    title, symbol = VALID_SIGNS[sign]
    key = f"{content_date.isoformat()}:{sign}"
    sky = ephemeris_for(content_date, sign)
    transits = sky["transits"]

    planet_focus = {
        "moon": ("настроение и привычные реакции", "не спешить с эмоциональными выводами"),
        "mercury": ("разговоры, документы и решения", "перепроверить формулировки и детали"),
        "venus": ("отношения, симпатии и чувство меры", "выбрать бережный и честный тон"),
        "mars": ("действия, границы и запас энергии", "направить силы в одну конкретную задачу"),
        "jupiter": ("возможности, обучение и расширение планов", "увидеть перспективу без лишних обещаний"),
        "saturn": ("обязательства, сроки и устойчивость", "укрепить порядок и не брать лишнего"),
    }

    def transit_sentence(index: int, fallback: str) -> str:
        if index >= len(transits):
            moon = sky["positions"]["moon"]
            moon_sign = SIGN_TITLES[SIGN_ORDER.index(moon["sign"])]
            return f"Луна сегодня в {moon_sign}: {fallback}"
        transit = transits[index]
        focus, action = planet_focus[transit.planet]
        if transit.tone == "supportive":
            effect = "поддерживает сферу"
        elif transit.tone == "challenging":
            effect = "обращает внимание на сферу"
        else:
            effect = "усиливает сферу"
        return (
            f"{transit.planet_title} в {transit.sign_title}, {transit.aspect} к вашему знаку, "
            f"{effect} «{focus}». Полезно {action}."
        )

    moon = sky["positions"]["moon"]
    moon_title = VALID_SIGNS[moon["sign"]][0]
    moon_degree = int(moon["longitude"] % 30)
    overview = (
        f"Луна сегодня в знаке «{moon_title}» ({moon_degree}°), фаза — "
        f"{sky['lunar_phase'].lower()}. "
        f"{transit_sentence(0, 'сначала прислушайтесь к состоянию, затем выбирайте темп дня.')}"
    )
    work = transit_sentence(1, "зафиксируйте один измеримый результат на сегодня.")
    money = transit_sentence(2, "сверьте цифры и отложите импульсивное решение.")
    love = transit_sentence(3, "скажите о важном прямо, но без давления.")
    advice = transit_sentence(4, "оставьте место для паузы и корректировки планов.")
    colors = (
        ("Бордовый", "Добавьте его небольшим акцентом, когда нужна собранность и уверенность."),
        ("Золотой", "Тёплая деталь поддержит ощущение ценности и поможет замечать достигнутое."),
        ("Зелёный", "Используйте его рядом с собой, чтобы легче сохранять спокойный рабочий ритм."),
        ("Синий", "Этот цвет помогает визуально снизить шум и удерживать ясность в разговорах."),
        ("Бирюзовый", "Подойдёт для дня, когда важно соединить лёгкость, свежесть и точность."),
        ("Фиолетовый", "Небольшой акцент напомнит оставить место интуиции и нестандартному взгляду."),
        ("Серебристый", "Холодный блеск поддержит внимание к деталям и ощущение внутреннего порядка."),
    )
    cards = (
        ("Шут", "Карта нового опыта и свободы от лишних ожиданий. Сегодня не нужно видеть весь маршрут: достаточно честно выбрать первый шаг.", "новое начало", "Сделайте один безопасный пробный шаг вместо долгой подготовки.", "Что я попробовала бы, если бы не требовала от себя идеального результата?"),
        ("Маг", "Ресурсов уже больше, чем кажется. Карта предлагает перестать ждать идеальных условий и собрать решение из того, что есть под рукой.", "личная сила", "Назовите три доступных ресурса и используйте хотя бы один сегодня.", "Какой мой навык сейчас недооценён?"),
        ("Верховная Жрица", "Тишина и наблюдение сегодня полезнее поспешного ответа. Отличайте спокойное внутреннее знание от тревожной фантазии.", "интуиция", "Возьмите паузу перед важным ответом и запишите первые спокойные ощущения.", "Что я уже знаю, хотя пока не могу доказать?"),
        ("Императрица", "Рост приходит через заботу, качество и способность принимать хорошее. Поддержите то, что уже начинает давать жизнь и результат.", "созидание", "Улучшите одну вещь через внимание к комфорту и качеству.", "Что в моей жизни сейчас просит заботы, а не контроля?"),
        ("Император", "Ясные правила и границы возвращают управляемость. Структура сегодня не ограничивает, а освобождает силы для главного.", "порядок", "Зафиксируйте одно правило, срок или границу, которые снимут неопределённость.", "Где мне пора стать автором правил своей жизни?"),
        ("Иерофант", "Опора может прийти через проверенное знание, наставника или собственные ценности. Не всякую задачу нужно решать в одиночку.", "ценности", "Сверьте решение с принципом, которому действительно доверяете.", "Чьё зрелое мнение поможет мне увидеть ситуацию шире?"),
        ("Влюблённые", "Это карта не только отношений, но и выбора в согласии с собой. Правильное решение соединяет желание, ценности и ответственность.", "честный выбор", "Назовите, чему вы говорите «да» и от чего ради этого отказываетесь.", "Какой выбор позволит мне не предавать себя?"),
        ("Колесница", "Энергия появляется, когда определено направление. Разные желания можно собрать в одно движение, если перестать менять цель на ходу.", "направление", "Выберите один результат дня и защитите для него время.", "Куда я действительно хочу приехать, а не просто быстро двигаться?"),
        ("Сила", "Мягкая настойчивость сегодня убедительнее давления. Управлять импульсом — не подавлять его, а направлять без борьбы с собой.", "внутренняя устойчивость", "Проведите сложный разговор спокойнее и короче, чем обычно.", "Где доброта к себе сделает меня сильнее?"),
        ("Отшельник", "Короткое уединение поможет отделить свой ответ от чужого шума. Это не уход от мира, а настройка внутреннего компаса.", "ясность", "Оставьте двадцать минут без сообщений и чужих мнений.", "Какой ответ становится слышен, когда вокруг тихо?"),
        ("Колесо Фортуны", "Условия меняются, и не всё зависит от контроля. Карта предлагает заметить поворот раньше и использовать открывшееся окно.", "перемены", "Пересмотрите план с учётом нового обстоятельства вместо сопротивления ему.", "Какую возможность я пока называю неудобством?"),
        ("Справедливость", "Факты, последствия и честные договорённости важнее красивых объяснений. Решение должно выдерживать проверку ясностью.", "равновесие", "Проверьте цифры, обещания и вторую сторону важного решения.", "Как выглядело бы справедливое решение для всех участников?"),
        ("Повешенный", "Пауза меняет угол зрения. То, что кажется остановкой, может быть временем отказаться от бесполезного усилия и увидеть другой путь.", "новый взгляд", "Не продавливайте один застрявший вопрос; сформулируйте его наоборот.", "Что станет возможным, если я перестану торопить эту ситуацию?"),
        ("Смерть", "Карта говорит о завершении этапа, а не о буквальном событии. Освободите место, которое занимает уже закончившаяся история.", "завершение", "Закройте или удалите одну вещь, которую держите только по привычке.", "С чем я готова попрощаться, чтобы двигаться дальше?"),
        ("Умеренность", "Нужный результат рождается из меры, сочетания и постепенности. Сегодня полезнее настроить ритм, чем делать резкий рывок.", "баланс", "Снизьте крайность: добавьте отдыха к работе или действия к размышлениям.", "Чего в моей жизни сейчас слишком много, а чего не хватает?"),
        ("Дьявол", "Карта подсвечивает привязки, соблазны и скрытую цену привычек. Честное признание возвращает больше свободы, чем самокритика.", "освобождение", "Назовите выгоду привычки, от которой хотите отказаться, и найдите ей безопасную замену.", "Что управляет мной сильнее, чем я готова признать?"),
        ("Башня", "Ненадёжная конструкция требует пересмотра. Быстрая честность может сначала встряхнуть, но затем вернуть опору на реальность.", "правда", "Исправьте одну слабую точку до того, как она потребует больше сил.", "Какую очевидную правду я откладываю?"),
        ("Звезда", "После напряжения снова видно направление. Надежда становится опорой, когда подтверждается небольшим реальным действием.", "надежда", "Сделайте один шаг в сторону большой цели, даже если он кажется скромным.", "Какое будущее всё ещё зовёт меня?"),
        ("Луна", "Не все детали сейчас видны, а эмоции могут усиливать догадки. Не отрицайте интуицию, но дайте фактам время проявиться.", "неопределённость", "Отделите в записи факты от предположений и не принимайте решение на пике тревоги.", "Что здесь факт, а что — моя интерпретация?"),
        ("Солнце", "Ясность, жизненность и признание результата выходят на первый план. Не уменьшайте хорошее и позвольте себе быть заметной.", "радость", "Покажите результат, поблагодарите помощника или отметьте собственный прогресс.", "Что хорошее я могу сегодня признать без оговорок?"),
        ("Суд", "Пришло время услышать важный внутренний вызов и собрать уроки прошлого. Не повторять — значит сделать новый осознанный выбор.", "пробуждение", "Сформулируйте, чему научил вас завершившийся этап, и примените вывод сегодня.", "К какой версии себя я уже готова перейти?"),
        ("Мир", "Цикл подходит к завершению. Прежде чем начинать следующее, признайте пройденный путь и закрепите полученный результат.", "целостность", "Завершите последнее небольшое действие и отдельно отметьте итог.", "Что уже завершено, но ещё не признано мной?"),
    )

    def pick(values: tuple[Any, ...], field: str) -> Any:
        digest = hashlib.sha256(f"{key}:{field}".encode()).digest()
        return values[int.from_bytes(digest[:8], "big") % len(values)]

    tarot = pick(cards, "tarot")
    color = pick(colors, "color")
    number_digest = hashlib.sha256(f"{key}:number".encode()).digest()
    number = int.from_bytes(number_digest[:8], "big") % 9 + 1
    number_meanings = {
        1: "Инициатива: выберите один первый шаг.",
        2: "Диалог: ищите баланс между своими и чужими потребностями.",
        3: "Выражение: оформите мысль в слова, образ или действие.",
        4: "Основа: укрепите порядок, границы и договорённости.",
        5: "Гибкость: оставьте место перемене и новому опыту.",
        6: "Забота: поддержите отношения, дом или собственное состояние.",
        7: "Глубина: проверяйте смысл и не спешите с выводами.",
        8: "Результат: считайте ресурсы и доводите важное до итога.",
        9: "Завершение: отпустите лишнее и соберите урок дня.",
    }
    supportive = sum(item.tone == "supportive" for item in transits)
    challenging = sum(item.tone == "challenging" for item in transits)
    neutral = max(0, len(transits) - supportive - challenging)
    phase_adjustment = {
        "Новолуние": -5,
        "Растущий серп": 1,
        "Первая четверть": 5,
        "Растущая Луна": 7,
        "Полнолуние": 9,
        "Убывающая Луна": 2,
        "Последняя четверть": -2,
        "Убывающий серп": -6,
    }.get(sky["lunar_phase"], 0)
    energy = max(42, min(96, 64 + supportive * 6 - challenging * 4 + neutral * 2 + phase_adjustment))
    energy_reason = (
        f"Оценка собрана из {len(transits)} значимых транзитов к вашему солнечному знаку: "
        f"поддерживающих — {supportive}, напряжённых — {challenging}. "
        f"Фаза «{sky['lunar_phase']}» также учтена в темпе дня."
    )
    mood_by_sign = {
        "aries": ("Собранный импульс", "Эмоциям нужен выход через конкретное действие, но без лишней резкости."),
        "taurus": ("Спокойная устойчивость", "Лучше всего работает знакомый ритм, телесный комфорт и ясные границы."),
        "gemini": ("Живое любопытство", "Мысли движутся быстрее обычного: фиксируйте важное и не распыляйтесь."),
        "cancer": ("Тонкая чувствительность", "Состояние сильнее реагирует на атмосферу и качество близкого общения."),
        "leo": ("Тёплая уверенность", "Хочется проявиться и получить отклик; выбирайте искренность вместо демонстративности."),
        "virgo": ("Внимательная ясность", "Порядок в мелочах успокаивает, но не требуйте от себя идеальности."),
        "libra": ("Потребность в гармонии", "Настроение зависит от честного баланса между собой и ожиданиями других."),
        "scorpio": ("Глубокая сосредоточенность", "Поверхностные ответы не удовлетворяют; направьте интенсивность в одну важную тему."),
        "sagittarius": ("Жажда пространства", "Полезны движение, новый взгляд и разговор, который расширяет перспективу."),
        "capricorn": ("Деловая устойчивость", "Внутреннее спокойствие приходит через понятный план и завершённый результат."),
        "aquarius": ("Свободный взгляд", "Необычная идея может поднять настроение, если дать ей практичную форму."),
        "pisces": ("Мягкая восприимчивость", "Берегите внимание от перегруза и оставьте время на восстановление."),
    }
    mood_title, mood_detail = mood_by_sign[moon["sign"]]
    lunar_guidance = {
        "Новолуние": "Определите одно намерение на новый цикл и начните с самого маленького действия.",
        "Растущий серп": "Поддерживайте то, что уже начало расти, не требуя быстрого результата.",
        "Первая четверть": "Сверьте направление и примите одно решение, которое давно откладывали.",
        "Растущая Луна": "Продолжайте начатое: сейчас последовательность важнее скорости.",
        "Полнолуние": "Заметьте результат, снизьте перегрузку и не решайте важное на пике эмоций.",
        "Убывающая Луна": "Завершайте незакрытое и освобождайте место от лишних обязательств.",
        "Последняя четверть": "Подведите промежуточные итоги и оставьте только то, что действительно работает.",
        "Убывающий серп": "Снизьте темп, восстановитесь и подготовьте пространство для нового цикла.",
    }[sky["lunar_phase"]]
    affirmations = (
        "Я выбираю ясный следующий шаг и сохраняю право двигаться в своём темпе.",
        "Я слышу свои потребности и говорю о них спокойно и прямо.",
        "Я могу опираться на факты, доверяя при этом своим ощущениям.",
        "Мне не нужно делать всё сразу, чтобы сегодняшний день имел значение.",
        "Я замечаю собственный прогресс и поддерживаю то, что помогает мне расти.",
        "Я отпускаю лишнее и направляю внимание туда, где оно приносит результат.",
    )
    return {
        "engine_version": 3,
        "date": content_date.isoformat(),
        "sign": sign,
        "sign_title": title,
        "symbol": symbol,
        "lunar_phase": sky["lunar_phase"],
        "overview": overview,
        "work": work,
        "money": money,
        "love": love,
        "advice": advice,
        "color": color[0],
        "color_meaning": color[1],
        "number": number,
        "number_meaning": number_meanings[number],
        "energy": energy,
        "energy_reason": energy_reason,
        "mood_title": mood_title,
        "mood_detail": mood_detail,
        "affirmation": pick(affirmations, "affirmation"),
        "lunar_guidance": lunar_guidance,
        "tarot": {
            "title": tarot[0],
            "meaning": tarot[1],
            "focus": tarot[2],
            "action": tarot[3],
            "question": tarot[4],
        },
        "basis": {
            "calculated_at_utc": sky["calculated_at_utc"],
            "reference": sky["reference"],
            "positions": sky["positions"],
            "aspects": [
                {
                    "planet": item.planet,
                    "aspect": item.aspect,
                    "orb": round(item.orb, 3),
                }
                for item in transits
            ],
        },
        "disclaimer": "Интерпретация реальных эфемерид; астрология не является научным прогнозом.",
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
