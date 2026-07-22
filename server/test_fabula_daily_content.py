import datetime as dt
import tempfile
import unittest
from pathlib import Path

from fabula_daily_content import (
    DailyContentStore,
    generate_editorial_daily_content,
    lunar_phase_for,
)


class DailyContentStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = DailyContentStore(Path(self.temp.name) / "fabula.db")

    def tearDown(self):
        self.temp.cleanup()

    def test_package_is_immutable_for_date_and_sign(self):
        day = dt.date(2026, 7, 20)
        first = self.store.get_or_create(day, "libra")

        def replacement(content_date, sign):
            payload = generate_editorial_daily_content(content_date, sign)
            payload["overview"] = "This must not replace stored content"
            return payload

        second = self.store.get_or_create(day, "libra", replacement)
        self.assertEqual(first, second)
        self.assertNotEqual(
            second["overview"],
            "This must not replace stored content",
        )

    def test_separate_packages_exist_for_each_date_and_sign(self):
        first = self.store.get_or_create(dt.date(2026, 7, 20), "libra")
        next_day = self.store.get_or_create(dt.date(2026, 7, 21), "libra")
        other_sign = self.store.get_or_create(dt.date(2026, 7, 20), "leo")

        self.assertEqual(first["date"], "2026-07-20")
        self.assertEqual(next_day["date"], "2026-07-21")
        self.assertEqual(other_sign["sign"], "leo")
        self.assertNotEqual(first, next_day)
        self.assertNotEqual(first, other_sign)

    def test_forecast_contains_real_ephemeris_basis(self):
        payload = self.store.get_or_create(dt.date(2026, 7, 22), "libra")
        self.assertEqual(payload["engine_version"], 3)
        self.assertEqual(
            payload["basis"]["reference"],
            "geocentric true ecliptic of date",
        )
        self.assertIn("moon", payload["basis"]["positions"])
        self.assertIn("°", payload["overview"])
        self.assertTrue(1 <= payload["energy"] <= 100)
        self.assertIn("транзит", payload["energy_reason"])
        self.assertTrue(payload["mood_title"])
        self.assertTrue(payload["affirmation"])
        self.assertTrue(payload["lunar_guidance"])
        self.assertTrue(payload["tarot"]["action"])
        self.assertTrue(payload["tarot"]["question"])

    def test_full_major_arcana_can_be_selected(self):
        cards = {
            generate_editorial_daily_content(
                dt.date(2026, 1, 1) + dt.timedelta(days=offset),
                sign,
            )["tarot"]["title"]
            for offset in range(90)
            for sign in ("libra", "leo", "pisces", "taurus")
        }
        self.assertEqual(len(cards), 22)

    def test_rejects_unknown_sign(self):
        with self.assertRaises(ValueError):
            self.store.get_or_create(dt.date(2026, 7, 20), "unknown")

    def test_known_new_moon_reference(self):
        self.assertEqual(lunar_phase_for(dt.date(2000, 1, 6)), "Новолуние")


if __name__ == "__main__":
    unittest.main()
