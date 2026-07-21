import os
import urllib.error
import unittest
from unittest.mock import Mock, patch

from fabula_chat import (
    DEFAULT_MODEL,
    FabulaChatPayload,
    SlidingWindowLimiter,
    _is_safe_user_reply,
    build_openrouter_payload,
    request_openrouter,
)


class FabulaChatTests(unittest.TestCase):
    def test_rejects_internal_reasoning_and_accepts_final_russian_reply(self):
        self.assertFalse(
            _is_safe_user_reply(
                "We need respond empathetically. The user is tired. Draft:"
            )
        )
        self.assertTrue(
            _is_safe_user_reply(
                "Похоже, постоянный поиск заработка не даёт тебе спокойно отдохнуть."
            )
        )

    @patch("fabula_chat.urllib.request.urlopen")
    @patch("fabula_chat.time.sleep")
    def test_retries_when_provider_returns_internal_draft(self, sleep, urlopen):
        draft = Mock()
        draft.read.return_value = b'{"choices":[{"message":{"content":"We need answer. Draft:"}}]}'
        draft.__enter__ = Mock(return_value=draft)
        draft.__exit__ = Mock(return_value=False)
        final = Mock()
        final.read.return_value = (
            '{"choices":[{"message":{"content":"Понимаю, почему это выматывает."}}]}'
            .encode("utf-8")
        )
        final.__enter__ = Mock(return_value=final)
        final.__exit__ = Mock(return_value=False)
        urlopen.side_effect = [draft, final]
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": "sk-or-test"}):
            payload = FabulaChatPayload.from_dict(
                {
                    "installation_id": "installation-123456",
                    "name": "",
                    "messages": [{"role": "user", "content": "Мне тяжело"}],
                }
            )
            self.assertEqual(request_openrouter(payload), "Понимаю, почему это выматывает.")
        sleep.assert_called_once_with(1)

    @patch("fabula_chat.urllib.request.urlopen")
    @patch("fabula_chat.time.sleep")
    def test_retries_temporary_openrouter_failure(self, sleep, urlopen):
        response = Mock()
        response.read.return_value = (
            '{"choices":[{"message":{"content":"Готовый ответ"}}]}'
            .encode("utf-8")
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
            self.assertEqual(request_openrouter(payload), "Готовый ответ")
        self.assertEqual(urlopen.call_count, 2)
        sleep.assert_called_once_with(1)

    def test_builds_bounded_russian_companion_request(self):
        payload = FabulaChatPayload.from_dict(
            {
                "installation_id": "installation-123",
                "name": "Анна",
                "assistant_name": "Марк",
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
        self.assertIn("Марк", result["messages"][0]["content"])
        self.assertIn("мужском роде", result["messages"][0]["content"])
        self.assertNotIn("provider", result)
        self.assertEqual(result["max_tokens"], 500)

    def test_rate_limiter_rejects_after_limit(self):
        limiter = SlidingWindowLimiter(limit=2, window_seconds=60)
        self.assertTrue(limiter.allowed("one"))
        self.assertTrue(limiter.allowed("one"))
        self.assertFalse(limiter.allowed("one"))
        self.assertTrue(limiter.allowed("another"))

    def test_female_assistant_uses_feminine_voice(self):
        payload = FabulaChatPayload.from_dict({
            "installation_id": "installation-123",
            "name": "Анна",
            "assistant_name": "София",
            "assistant_gender": "female",
            "messages": [{"role": "user", "content": "Привет"}],
        })
        prompt = build_openrouter_payload(payload)["messages"][0]["content"]
        self.assertIn("София", prompt)
        self.assertIn("женском роде", prompt)


if __name__ == "__main__":
    unittest.main()
