import os
import urllib.error
import unittest
from unittest.mock import Mock, patch

from fabula_chat import (
    DEFAULT_MODEL,
    FabulaChatPayload,
    SlidingWindowLimiter,
    build_openrouter_payload,
    request_openrouter,
)


class FabulaChatTests(unittest.TestCase):
    @patch("fabula_chat.urllib.request.urlopen")
    @patch("fabula_chat.time.sleep")
    def test_retries_temporary_openrouter_failure(self, sleep, urlopen):
        response = Mock()
        response.read.return_value = (
            b'{"choices":[{"message":{"content":"reply"}}]}'
        )
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        urlopen.side_effect = [urllib.error.URLError("temporary"), response]
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": "sk-or-test"}):
            payload = FabulaChatPayload.from_dict(
                {
                    "installation_id": "installation-123456",
                    "name": "",
                    "messages": [{"role": "user", "content": "Привет"}],
                }
            )
            self.assertEqual(request_openrouter(payload), "reply")
        self.assertEqual(urlopen.call_count, 2)
        sleep.assert_called_once_with(1)

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
