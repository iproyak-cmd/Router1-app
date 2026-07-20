import os
import unittest
from unittest.mock import patch

from fabula_chat import (
    DEFAULT_MODEL,
    FabulaChatPayload,
    SlidingWindowLimiter,
    build_openrouter_payload,
)


class FabulaChatTests(unittest.TestCase):
    def test_builds_bounded_russian_companion_request(self):
        payload = FabulaChatPayload.from_dict(
            {
                "installation_id": "installation-123",
                "name": "Анна",
                "messages": [
                    {"role": "user", "content": f"сообщение {index}"}
                    for index in range(12)
                ],
            }
        )
        with patch.dict(os.environ, {}, clear=True):
            result = build_openrouter_payload(payload)

        self.assertEqual(result["model"], DEFAULT_MODEL)
        self.assertEqual(len(result["messages"]), 13)
        self.assertIn("Анна", result["messages"][0]["content"])
        self.assertEqual(result["provider"]["data_collection"], "deny")
        self.assertLessEqual(result["max_tokens"], 300)

    def test_rate_limiter_rejects_after_limit(self):
        limiter = SlidingWindowLimiter(limit=2, window_seconds=60)
        self.assertTrue(limiter.allowed("one"))
        self.assertTrue(limiter.allowed("one"))
        self.assertFalse(limiter.allowed("one"))
        self.assertTrue(limiter.allowed("another"))


if __name__ == "__main__":
    unittest.main()
