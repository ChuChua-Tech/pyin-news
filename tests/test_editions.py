"""Finite editions retain their selection and acknowledge progress durably."""
from concurrent.futures import ThreadPoolExecutor
import json
import unittest
from unittest import mock
from test_ranking import load_backend, isolate_backend, NOW
import tempfile


class EditionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.backend = load_backend()
        isolate_backend(self.backend, self.tmp.name)
        self.sources = [{"id": "fixture", "name": "Fixture", "custom": True,
                         "url": "https://example.test/rss", "topics": [],
                         "languages": ["en"], "types": ["independent"], "regions": ["global"]}]
        for patcher in (mock.patch.object(self.backend.time, "time", return_value=NOW),
                        mock.patch.object(self.backend, "source_catalog", return_value=self.sources)):
            patcher.start()
            self.addCleanup(patcher.stop)
        profile = self.backend.default_setup_profile()
        profile["complete"] = True
        self.backend.save_setup_profile(json.dumps(profile))
        self.add("a", "Lunar telescope observes distant galaxies")
        self.add("b", "Coastal farmers grow resilient wheat")
        self.add("c", "Parliament approves railway funding")

    def sql(self, statement, params=()):
        conn = self.backend.db()
        try:
            with conn:
                return [tuple(row) for row in conn.execute(statement, params)]
        finally:
            conn.close()

    def add(self, identity, title):
        self.sql("INSERT INTO articles(id,url,title,source,feed_summary,published_ts,fetched_ts) VALUES (?,?,?,?,?,?,?)",
                 (identity, "https://example.test/" + identity, title, "Fixture", "A short synopsis.", NOW, NOW))

    def create(self, minutes=5):
        return self.backend.create_edition(minutes)["edition"]

    def test_quiet_selection_is_finite_and_never_replaced_by_refresh_or_restart(self):
        original = self.create()
        self.assertEqual(original["total"], 3)
        self.assertLessEqual(original["estimated_seconds"], 300)
        self.assertEqual(len({a["event_id"] for a in original["articles"]}), 3)
        self.sql("UPDATE articles SET title='A corrected headline',feed_summary='New text'")
        self.add("d", "Orchestra premieres symphony downtown")
        self.assertEqual(self.create(30), original)
        restarted = load_backend()
        isolate_backend(restarted, self.tmp.name)
        self.assertEqual(restarted.current_edition()["edition"], original)

    def test_open_pauses_without_completing_and_skip_does_not_teach_or_hide(self):
        edition = self.create()
        article = edition["articles"][1]["id"]
        opened = self.backend.update_edition(edition["id"], article, "open")["edition"]
        self.assertEqual(opened["cursor_id"], article)
        self.assertEqual(opened["completed"], 0)
        skipped = self.backend.update_edition(edition["id"], article, "skip")["edition"]
        self.assertEqual(skipped["completed"], 1)
        for table in ("read_articles", "dismissed_articles", "curation_signals"):
            self.assertEqual(self.sql("SELECT COUNT(*) FROM " + table), [(0,)])
        self.assertEqual(self.backend.update_edition(edition["id"], article, "done")["edition"], skipped)

    def test_done_marks_read_and_finishes_only_after_every_slot(self):
        edition = self.create()
        for index, article in enumerate(edition["articles"]):
            current = self.backend.update_edition(edition["id"], article["id"], "done")["edition"]
            self.assertEqual(current["completed"], index + 1)
            self.assertEqual(current["finished_ts"] is not None, index == edition["total"] - 1)
        self.assertEqual(self.sql("SELECT COUNT(*) FROM read_articles"), [(3,)])
        self.assertEqual(self.sql("SELECT COUNT(*) FROM curation_signals"), [(0,)])
        self.assertEqual(self.backend.current_edition()["edition"], current)
        self.add("d", "Orchestra premieres symphony downtown")
        new = self.create()
        self.assertNotEqual(new["id"], edition["id"])
        self.assertEqual([a["id"] for a in new["articles"]], ["d"])
        with self.assertRaises(ValueError):
            self.backend.update_edition(edition["id"], "d", "done")
        self.assertEqual(self.backend.current_edition()["edition"], new)

    def test_feed_read_and_restore_do_not_refill_or_undo_edition_progress(self):
        edition = self.create()
        identity = edition["articles"][0]["id"]
        self.backend.set_read_state(identity, True)
        self.assertEqual(self.backend.current_edition()["edition"]["completed"], 1)
        self.backend.set_read_state(identity, False)
        self.assertEqual(self.backend.current_edition()["edition"]["completed"], 1)
        self.assertEqual(self.backend.current_edition()["edition"]["total"], edition["total"])

    def test_cache_retention_protects_current_edition_then_releases_old_stories(self):
        edition = self.create()
        self.add("extra", "Chess championship opens overseas")
        self.sql("UPDATE articles SET published_ts = ?", (NOW - 120 * 86400,))
        result = dict(source=self.sources[0], articles=[], error="offline", status="error", validators={})
        with mock.patch.object(self.backend, "fetch_source", return_value=result), \
             mock.patch.object(self.backend, "send_alert_notifications", return_value=0):
            self.backend.refresh()
            self.assertEqual(self.sql("SELECT COUNT(*) FROM articles"), [(edition["total"],)])
            for article in edition["articles"]:
                self.backend.update_edition(edition["id"], article["id"], "skip")
            self.assertEqual(self.create()["total"], 0)
            self.backend.refresh()
            self.assertEqual(self.sql("SELECT COUNT(*) FROM articles"), [(0,)])

    def test_empty_edition_has_a_finish_and_invalid_budget_changes_nothing(self):
        self.sql("DELETE FROM articles")
        edition = self.create()
        self.assertEqual(edition["remaining"], 0)
        self.assertEqual(edition["finished_ts"], NOW)
        with self.assertRaises(ValueError):
            self.create(6)
        self.assertEqual(self.backend.current_edition()["edition"], edition)

    def test_concurrent_starts_and_progress_are_serialized(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            first, second = list(pool.map(self.create, [5, 15]))
        self.assertEqual(first["id"], second["id"])
        with ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(lambda a: self.backend.update_edition(first["id"], a["id"], "done"), first["articles"]))
        edition = self.backend.current_edition()["edition"]
        self.assertEqual(edition["remaining"], 0)
        self.assertEqual(edition["total"], first["total"])

    def test_synopsis_estimate_respects_budget_and_current_filters(self):
        self.sql("UPDATE articles SET feed_summary = ?", ("word " * 350,))
        self.backend.set_read_state("b", True)
        edition = self.create()
        self.assertNotIn("b", [a["id"] for a in edition["articles"]])
        self.assertLessEqual(edition["estimated_seconds"], 300)
        self.assertTrue(all(a["reading_seconds"] >= 60 for a in edition["articles"]))

    def test_migration_preserves_old_data_and_cold_open_keeps_progress(self):
        conn = self.backend.db()
        conn.executescript("DROP TABLE edition_items; DROP TABLE daily_editions; "
                           "UPDATE meta SET value='1:old' WHERE key='db_schema_state';")
        conn.close()
        edition = self.create()
        self.assertEqual(edition["total"], 3)
        identity = edition["articles"][0]["id"]
        self.backend.update_edition(edition["id"], identity, "open")
        restarted = load_backend()
        isolate_backend(restarted, self.tmp.name)
        self.assertEqual(restarted.current_edition()["edition"]["cursor_id"], identity)


if __name__ == "__main__":
    unittest.main()
