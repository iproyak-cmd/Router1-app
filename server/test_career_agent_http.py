from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import career_agent_http as career


class CareerAgentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.state_dir = root / "states"
        self.token_dir = root / "tokens"
        self.patchers = [
            patch.object(career, "HH_CLIENT_ID", "client-id"),
            patch.object(career, "HH_CLIENT_SECRET", "client-secret"),
            patch.object(career, "HH_STATE_DIR", self.state_dir),
            patch.object(career, "HH_TOKEN_DIR", self.token_dir),
        ]
        for patcher in self.patchers:
            patcher.start()

    def tearDown(self) -> None:
        for patcher in reversed(self.patchers):
            patcher.stop()
        self.temporary.cleanup()

    def test_state_is_bound_to_one_user_and_one_callback(self) -> None:
        state = career._create_hh_state("installation-123")
        expected = career._user_key("installation-123")
        self.assertEqual(career._consume_hh_state(state), expected)
        self.assertIsNone(career._consume_hh_state(state))

    def test_tampered_state_is_rejected_and_consumed(self) -> None:
        state = career._create_hh_state("installation-123")
        self.assertIsNone(career._consume_hh_state(state + "x"))
        self.assertIsNone(career._consume_hh_state(state))

    def test_tokens_are_stored_separately_with_private_permissions(self) -> None:
        first = career._user_key("installation-first")
        second = career._user_key("installation-second")
        career._write_private_json(
            self.token_dir / f"{first}.json", {"access_token": "first-token"}
        )
        career._write_private_json(
            self.token_dir / f"{second}.json", {"access_token": "second-token"}
        )
        self.assertEqual(career._hh_token("installation-first"), "first-token")
        self.assertEqual(career._hh_token("installation-second"), "second-token")
        self.assertEqual(os.stat(self.token_dir / f"{first}.json").st_mode & 0o777, 0o600)

    def test_vacancy_request_requires_connection(self) -> None:
        with self.assertRaises(PermissionError):
            career._hh_vacancies("installation-123", "Project Manager", "113", 0, 20)

    def test_vacancy_response_is_normalized(self) -> None:
        user_key = career._user_key("installation-123")
        career._write_private_json(
            self.token_dir / f"{user_key}.json", {"access_token": "token"}
        )
        upstream = {
            "found": 1,
            "page": 0,
            "pages": 1,
            "items": [{"id": "42", "name": "Project Manager"}],
        }
        with patch.object(career, "_json_request", return_value=upstream) as request:
            payload = career._hh_vacancies(
                "installation-123", "Project Manager", "113", 0, 20
            )
        self.assertEqual(payload["source"], "hh")
        self.assertEqual(payload["items"][0]["id"], "42")
        self.assertIn("Authorization", request.call_args.kwargs["headers"])

    def test_invalid_installation_id_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            career._create_hh_state("../../etc/passwd")

    def test_application_draft_uses_only_supplied_experience(self) -> None:
        draft = career._application_draft(
            {
                "installation_id": "installation-123",
                "vacancy_title": "Project Manager",
                "company": "Example",
                "experience": "Управлял командой из 12 человек.",
            }
        )
        self.assertEqual(draft["status"], "draft")
        self.assertTrue(draft["requires_approval"])
        self.assertFalse(draft["sent"])
        self.assertIn("Управлял командой из 12 человек.", draft["cover_letter"])

    def test_application_draft_requires_real_experience(self) -> None:
        with self.assertRaises(ValueError):
            career._application_draft(
                {
                    "installation_id": "installation-123",
                    "vacancy_title": "Project Manager",
                    "experience": "",
                }
            )


if __name__ == "__main__":
    unittest.main()
