"""Deliberate views survive repeat visits without manufacturing learned interests."""

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
NOW = 1_800_000_000


def load_backend():
    loader = SourceFileLoader("pyin_reading_history_backend", str(ROOT / "bin" / "chuchua-news"))
    spec = spec_from_loader(loader.name, loader)
    module = module_from_spec(spec)
    loader.exec_module(module)
    return module


class ReadingHistoryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.backend = self.new_backend()
        clock = mock.patch.object(self.backend.time, "time", return_value=NOW)
        self.clock = clock.start()
        self.addCleanup(clock.stop)
        profile = self.backend.default_setup_profile()
        profile["complete"] = True
        self.backend.save_setup_profile(json.dumps(profile))
        conn = self.backend.db()
        with conn:
            conn.executemany(
                "INSERT INTO articles "
                "(id, url, title, source, feed_summary, published_ts, fetched_ts, source_topics) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    ("linux-story", "https://example.test/linux", "Linux Foundation improves laptop battery support",
                     "Linux News", "Linux developers improve battery monitoring technology and power management.",
                     NOW - 3600, NOW, '["linux", "technology"]'),
                    ("space-story", "https://example.test/space", "Mars Reconnaissance Orbiter discovers an ancient riverbed",
                     "Space News", "Planetary science studies ancient water and geological formations on Mars.",
                     NOW - 7200, NOW, '["science", "space"]'),
                ],
            )
        conn.close()

    def new_backend(self):
        """A fresh backend instance uses the same isolated database as a new CLI call."""
        backend = load_backend()
        backend.CONFIG_DIR = self.base / "config" / backend.APP_ID
        backend.STATE_DIR = self.base / "state" / backend.APP_ID
        backend.DB_PATH = backend.STATE_DIR / "news.sqlite3"
        backend.USER_SOURCES_PATH = backend.CONFIG_DIR / "sources.json"
        return backend

    def rows(self, query, parameters=()):
        conn = self.backend.db()
        try:
            return [tuple(row) for row in conn.execute(query, parameters)]
        finally:
            conn.close()

    def learned_state(self):
        return {
            "signals": self.rows("SELECT * FROM curation_signals ORDER BY article_id, signal"),
            "terms": self.rows("SELECT * FROM curation_terms ORDER BY term"),
            "sources": self.rows("SELECT * FROM curation_sources ORDER BY source"),
        }

    def stored_state(self):
        return {
            **self.learned_state(),
            "views": self.rows(
                "SELECT id, opened_count, last_opened_ts FROM articles ORDER BY id"
            ),
            "feedback": self.rows("SELECT * FROM article_feedback ORDER BY article_id, action, target"),
            "interests": self.rows("SELECT * FROM interest_nodes ORDER BY term, scope"),
            "bookmarks": self.rows("SELECT * FROM bookmarks ORDER BY article_id"),
        }

    def cli_environment(self):
        return {
            **os.environ,
            "XDG_CONFIG_HOME": str(self.base / "config"),
            "XDG_STATE_HOME": str(self.base / "state"),
            "PYTHONDONTWRITEBYTECODE": "1",
        }

    def assert_acknowledged_view(self, result, opens, timestamp, history_count=1):
        self.assertTrue(result["ok"])
        self.assertEqual(result["article_id"], "linux-story")
        self.assertEqual(result["opens"], opens)
        self.assertEqual(result["last_opened_ts"], timestamp)
        self.assertEqual(result["counts"]["history"], history_count)

    def test_open_acknowledges_persisted_history_values(self):
        result = self.backend.record_open("linux-story")
        self.assert_acknowledged_view(result, 1, NOW)
        self.assertTrue(result["applied"])
        self.assertTrue(result["learned"])
        self.assertEqual(
            self.rows("SELECT opened_count, last_opened_ts FROM articles WHERE id = 'linux-story'"),
            [(result["opens"], result["last_opened_ts"])],
        )
        history = self.new_backend().list_history()
        self.assertEqual(history["count"], 1)
        self.assertEqual(history["articles"][0]["id"], "linux-story")
        self.assertEqual(history["articles"][0]["opens"], 1)

    def test_each_repeat_view_updates_history_without_relearning(self):
        first = self.backend.record_open("linux-story")
        self.assertTrue(first["applied"])
        learned = self.learned_state()
        self.assertTrue(learned["terms"])
        for opens, timestamp in ((2, NOW), (3, NOW + 120), (4, NOW + 86400)):
            with self.subTest(opens=opens):
                self.clock.return_value = timestamp
                result = self.new_backend().record_open("linux-story")
                self.assert_acknowledged_view(result, opens, timestamp)
                self.assertFalse(result["applied"])
                self.assertEqual(result["learned"], [])
                self.assertEqual(self.learned_state(), learned)
                history = self.backend.list_history()
                self.assertEqual(history["count"], 1)
                self.assertEqual(history["articles"][0]["opens"], opens)
                self.assertEqual(history["articles"][0]["last_opened_ts"], timestamp)

    def test_reopening_an_older_story_moves_it_to_the_top_of_history(self):
        self.backend.record_open("linux-story")
        self.clock.return_value = NOW + 30
        self.backend.record_open("space-story")
        self.assertEqual(
            [article["id"] for article in self.backend.list_history()["articles"]],
            ["space-story", "linux-story"],
        )
        self.clock.return_value = NOW + 60
        result = self.backend.record_open("linux-story")
        self.assert_acknowledged_view(result, 2, NOW + 60, history_count=2)
        history = self.backend.list_history(limit=1)
        self.assertEqual(history["count"], 2)
        self.assertEqual(history["returned"], 1)
        self.assertEqual(history["articles"][0]["id"], "linux-story")

    def test_non_open_signals_neither_create_views_nor_change_the_latest_view(self):
        self.backend.record_open("linux-story")
        self.clock.return_value = NOW + 90
        for signal in ("engaged", "external", "summary"):
            with self.subTest(signal=signal):
                for article_id in ("linux-story", "space-story"):
                    first = self.backend.record_open(article_id, signal)
                    self.assertTrue(first["applied"])
                    self.assertEqual(first["signal"], signal)
                    self.assertEqual(first["counts"]["history"], 1)
                    expected_opens, expected_time = (1, NOW) if article_id == "linux-story" else (0, None)
                    self.assertEqual(first["article_id"], article_id)
                    self.assertEqual(first["opens"], expected_opens)
                    self.assertEqual(first["last_opened_ts"], expected_time)
                    learned = self.learned_state()
                    repeat = self.backend.record_open(article_id, signal)
                    self.assertFalse(repeat["applied"])
                    self.assertEqual(self.learned_state(), learned)
        self.assertEqual(
            self.rows("SELECT id, opened_count, last_opened_ts FROM articles ORDER BY id"),
            [("linux-story", 1, NOW), ("space-story", 0, None)],
        )

    def test_disabling_learning_keeps_repeat_history_and_its_navigation_count(self):
        profile = self.backend.load_setup_profile()
        profile["privacy"]["learn_from_opens"] = False
        self.backend.save_setup_profile(json.dumps(profile))
        for opens in (1, 2):
            self.clock.return_value = NOW + opens
            result = self.backend.record_open("linux-story")
            self.assert_acknowledged_view(result, opens, NOW + opens)
            self.assertFalse(result["learning_enabled"])
            self.assertFalse(result["applied"])
            self.assertEqual(result["learned"], [])
        for signal in ("engaged", "external", "summary"):
            self.assertFalse(self.backend.record_open("linux-story", signal)["applied"])
        self.backend.set_bookmark("linux-story", True)
        self.assertEqual(self.learned_state(), {"signals": [], "terms": [], "sources": []})
        self.assertEqual(self.backend.list_history()["articles"][0]["opens"], 2)

    def test_invalid_article_or_signal_leaves_existing_history_and_learning_untouched(self):
        self.backend.record_open("linux-story")
        before = self.stored_state()
        for article_id, signal in (("missing", "open"), ("missing", "engaged"),
                                   ("linux-story", "not-a-reading-signal")):
            with self.subTest(article_id=article_id, signal=signal):
                with self.assertRaises(ValueError):
                    self.backend.record_open(article_id, signal)
                self.assertEqual(self.stored_state(), before)

    def test_invalid_open_cli_returns_an_error_without_mutating_history(self):
        self.backend.record_open("linux-story")
        before = self.stored_state()
        result = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "chuchua-news"), "opened", "--id", "missing"],
            env=self.cli_environment(), text=True, capture_output=True, timeout=20,
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"], "article not found")
        self.assertEqual(self.stored_state(), before)

    def test_failed_learning_transaction_does_not_leave_a_phantom_view(self):
        before = self.stored_state()
        with mock.patch.object(self.backend, "apply_article_signal", side_effect=RuntimeError("storage failure")):
            with self.assertRaisesRegex(RuntimeError, "storage failure"):
                self.backend.record_open("linux-story")
        self.assertEqual(self.stored_state(), before)
        self.assertEqual(self.backend.list_history()["count"], 0)

    def test_no_signal_removes_prior_inferences_and_persists_across_future_visits(self):
        for signal in ("open", "engaged", "external", "summary"):
            self.backend.record_open("linux-story", signal)
        self.backend.set_bookmark("linux-story", True)
        self.assertEqual(len(self.learned_state()["signals"]), 5)
        result = self.backend.record_article_feedback("linux-story", "not-interest")
        self.assertEqual(set(result["removed_signals"]), {"open", "engaged", "external", "summary", "bookmark"})
        self.assertEqual(self.learned_state(), {"signals": [], "terms": [], "sources": []})

        self.clock.return_value = NOW + 86400
        backend = self.new_backend()
        for signal in ("open", "engaged", "external", "summary"):
            with self.subTest(signal=signal):
                result = backend.record_open("linux-story", signal)
                self.assertFalse(result["applied"])
                self.assertEqual(result["learned"], [])
                self.assert_acknowledged_view(result, 2, NOW + 86400)
        backend.set_bookmark("linux-story", False)
        self.assertTrue(backend.set_bookmark("linux-story", True)["bookmarked"])
        self.assertEqual(self.learned_state(), {"signals": [], "terms": [], "sources": []})
        self.assertEqual(backend.list_history()["articles"][0]["opens"], 2)

    def test_no_signal_can_be_set_before_the_first_view_and_is_scoped_to_one_story(self):
        explicit = self.backend.record_article_feedback("linux-story", "follow", "topic:linux")
        self.backend.record_article_feedback("linux-story", "not-interest")
        result = self.backend.record_open("linux-story")
        self.assert_acknowledged_view(result, 1, NOW)
        self.assertFalse(result["applied"])
        self.assertTrue(self.backend.record_open("space-story")["applied"])
        self.assertEqual(
            self.rows("SELECT DISTINCT article_id FROM curation_signals ORDER BY article_id"),
            [("space-story",)],
        )
        self.assertEqual(
            self.rows("SELECT term, weight FROM interest_nodes"),
            [("topic:linux", explicit["weight"])],
        )

    def test_no_signal_still_allows_an_explicit_show_less_action(self):
        self.backend.record_article_feedback("linux-story", "not-interest")
        result = self.backend.dismiss_article("linux-story")
        self.assertTrue(result["dismissed"])
        self.assertEqual(
            self.rows("SELECT signal FROM curation_signals WHERE article_id = 'linux-story'"),
            [("dismiss",)],
        )
        self.assertTrue(self.rows("SELECT term FROM curation_terms WHERE short_weight < 0"))
        self.assertEqual(self.backend.list_history()["count"], 0)

    def test_reset_clears_no_signal_and_views_while_preserving_explicit_preferences(self):
        self.backend.record_article_feedback("linux-story", "follow", "topic:linux")
        interests = self.rows("SELECT * FROM interest_nodes ORDER BY term, scope")
        profile = self.backend.load_setup_profile()
        self.backend.record_open("linux-story")
        self.backend.set_bookmark("linux-story", True)
        self.backend.record_article_feedback("linux-story", "not-interest")
        result = self.backend.reset_learning()
        self.assertTrue(result["reset"])
        self.assertEqual(self.backend.list_history()["count"], 0)
        self.assertEqual(self.backend.library_counts()["history"], 0)
        self.assertEqual(self.rows("SELECT * FROM interest_nodes ORDER BY term, scope"), interests)
        self.assertEqual(self.backend.load_setup_profile(), profile)
        self.assertEqual(self.backend.list_bookmarks()["count"], 1)
        self.assertEqual(self.learned_state(), {"signals": [], "terms": [], "sources": []})
        result = self.new_backend().record_open("linux-story")
        self.assertTrue(result["applied"])
        self.assert_acknowledged_view(result, 1, NOW)

    def test_concurrent_open_cli_calls_count_each_view_but_learn_only_once(self):
        processes = []
        try:
            for _ in range(6):
                processes.append(subprocess.Popen(
                    [sys.executable, str(ROOT / "bin" / "chuchua-news"), "opened", "--id", "linux-story"],
                    env=self.cli_environment(), text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                ))
            payloads = []
            for process in processes:
                stdout, stderr = process.communicate(timeout=20)
                self.assertEqual(process.returncode, 0, stdout + stderr)
                payloads.append(json.loads(stdout))
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=5)
        self.assertEqual(sorted(payload["opens"] for payload in payloads), [1, 2, 3, 4, 5, 6])
        self.assertEqual(sum(payload["applied"] for payload in payloads), 1)
        self.assertTrue(all(payload["counts"]["history"] == 1 for payload in payloads))
        self.assertEqual(
            self.rows("SELECT opened_count FROM articles WHERE id = 'linux-story'"), [(6,)]
        )
        self.assertEqual(
            self.rows("SELECT signal FROM curation_signals WHERE article_id = 'linux-story'"),
            [("open",)],
        )
        self.assertEqual(self.backend.list_history()["count"], 1)


if __name__ == "__main__":
    unittest.main()
