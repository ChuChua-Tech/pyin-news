"""Event identity and visit snapshots survive real cache and preference changes."""

from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stdout
import io
import json
import tempfile
import unittest
from unittest import mock

from test_ranking import load_backend, isolate_backend, NOW


class EventDeskTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.backend = load_backend()
        isolate_backend(self.backend, temporary.name)
        self.sources = [{"id": name.lower(), "name": name, "custom": True,
                         "url": "https://example.test/" + name, "topics": [],
                         "languages": ["en"], "types": ["independent"], "regions": ["global"]}
                        for name in ("Alpha", "Beta", "Gamma")]
        for patcher in (
            mock.patch.object(self.backend.time, "time", return_value=NOW),
            mock.patch.object(self.backend, "source_catalog", return_value=self.sources),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.profile = self.backend.default_setup_profile()
        self.profile["complete"] = True
        self.save_profile()
        self.add("a", "Alpha", NOW - 100)

    def save_profile(self):
        self.backend.save_setup_profile(json.dumps(self.profile))

    def add(self, identity, source="Beta", published=NOW, title=None):
        conn = self.backend.db()
        with conn:
            conn.execute(
                "INSERT INTO articles(id,url,title,source,feed_summary,published_ts,fetched_ts) "
                "VALUES (?,?,?,?,?,?,?)",
                (identity, "https://example.test/" + identity,
                 title or "Harbor lantern festival opening weekend", source,
                 "Reporting from the harbor.", published, NOW),
            )
        conn.close()

    def sql(self, query, parameters=()):
        conn = self.backend.db()
        try:
            with conn:
                return [tuple(row) for row in conn.execute(query, parameters)]
        finally:
            conn.close()

    def coverage(self, article="a"):
        return self.backend.event_coverage(article)

    def seen(self, snapshot):
        return self.backend.mark_event_seen(snapshot["event_id"], snapshot["seen_through"])

    def test_identity_survives_new_arrivals_title_edits_and_ranking_representative(self):
        first = self.coverage()
        self.add("b")
        self.assertEqual(self.coverage("b")["event_id"], first["event_id"])
        feed, _ = self.backend.ranked_articles(10)
        self.assertEqual(feed[0]["event_id"], first["event_id"])
        self.sql("INSERT INTO read_articles(article_id,read_ts) VALUES ('b',?)", (NOW,))
        second_feed, _ = self.backend.ranked_articles(10)
        self.assertEqual(second_feed[0]["id"], "a")
        self.assertEqual(second_feed[0]["event_id"], first["event_id"])
        self.sql("UPDATE articles SET title = 'Publisher corrected this headline' WHERE id = 'a'")
        self.assertEqual(self.coverage()["event_id"], first["event_id"])

    def test_first_visit_and_repeated_reads_do_not_acknowledge(self):
        first = self.coverage()
        self.assertTrue(first["first_visit"])
        self.assertEqual(first["new_count"], 0)
        self.assertEqual(self.coverage(), first)
        self.assertEqual(self.sql("SELECT seen_through FROM news_events"), [(None,)])
        self.seen(first)
        self.assertFalse(self.coverage()["first_visit"])

    def test_late_older_reporting_is_new_and_sorted_by_publication_time(self):
        self.seen(self.coverage())
        self.add("b", published=NOW - 1000)
        result = self.coverage()
        self.assertEqual([row["id"] for row in result["articles"]], ["b", "a"])
        self.assertEqual([row["is_new"] for row in result["articles"]], [True, False])
        self.assertEqual(result["source_count"], 2)

    def test_delayed_acknowledgement_does_not_swallow_newer_snapshot(self):
        first = self.coverage()
        self.seen(first)
        self.add("b")
        second = self.coverage()
        self.seen(first)
        self.assertEqual(self.coverage()["new_count"], 1)
        self.seen(second)
        self.seen(first)
        self.assertEqual(self.coverage()["new_count"], 0)

    def test_seen_watermark_cannot_point_to_a_different_event_or_future(self):
        first = self.coverage()
        self.add("unrelated", title="Galactic observatory maps distant exoplanet atmospheres")
        other = self.coverage("unrelated")
        for sequence in (0, -1, other["seen_through"], other["seen_through"] + 1):
            with self.assertRaises(ValueError):
                self.backend.mark_event_seen(first["event_id"], sequence)
        self.assertTrue(self.coverage()["first_visit"])

    def test_window_stays_anchored_instead_of_chaining_forever(self):
        first = self.coverage()
        self.add("b", published=NOW + 3 * 86400)
        self.assertEqual(self.coverage("b")["event_id"], first["event_id"])
        self.add("c", published=NOW + 6 * 86400)
        self.assertNotEqual(self.coverage("c")["event_id"], first["event_id"])

    def test_unrelated_stories_and_empty_headlines_do_not_group(self):
        first = self.coverage()
        self.add("b", title="Harbor council election results announced tonight")
        self.add("c", title="Today")
        self.add("d", title="Today")
        self.assertEqual(len({first["event_id"], *(self.coverage(i)["event_id"] for i in "bcd")}), 4)

    def test_publisher_and_keyword_filters_apply_without_reassigning_events(self):
        self.add("b")
        event_id = self.coverage()["event_id"]
        self.profile["disabled_source_ids"] = ["beta"]
        self.save_profile()
        self.assertEqual([row["id"] for row in self.coverage()["articles"]], ["a"])
        self.profile["blocked_keywords"] = ["lantern"]
        self.save_profile()
        self.assertEqual(self.coverage()["articles"], [])
        self.profile["blocked_keywords"] = []
        self.profile["disabled_source_ids"] = []
        self.save_profile()
        self.assertEqual(self.coverage()["event_id"], event_id)
        self.assertEqual(self.coverage()["article_count"], 2)

    def test_read_coverage_remains_but_dismissed_coverage_is_hidden(self):
        self.add("b")
        self.sql("INSERT INTO read_articles(article_id,read_ts) VALUES ('a',?)", (NOW,))
        self.sql("INSERT INTO dismissed_articles(article_id,dismissed_ts) VALUES ('b',?)", (NOW,))
        result = self.coverage()
        self.assertEqual([row["id"] for row in result["articles"]], ["a"])
        self.assertTrue(result["articles"][0]["read"])

    def test_timeline_includes_all_reports_from_the_same_publisher(self):
        for index in range(40):
            self.add(f"b{index:02d}", "Alpha")
        result = self.coverage()
        self.assertEqual(result["article_count"], 41)
        self.assertEqual(result["source_count"], 1)
        self.assertTrue(all(row["cluster_ids"] == [row["id"]] for row in result["articles"]))

    def test_retention_keeps_identity_until_the_last_cached_report_expires(self):
        first = self.coverage()
        self.add("b")
        self.coverage()
        self.seen(first)
        self.sql("DELETE FROM articles WHERE id = 'a'")
        remaining = self.coverage("b")
        self.assertEqual(remaining["event_id"], first["event_id"])
        self.assertFalse(remaining["first_visit"])
        self.sql("DELETE FROM articles WHERE id = 'b'")
        self.assertEqual(self.sql("SELECT * FROM event_articles"), [])
        self.assertEqual(self.sql("SELECT * FROM news_events"), [])

    def test_reset_forgets_visits_without_losing_identity_or_marking_read(self):
        first = self.coverage()
        self.seen(first)
        self.backend.reset_learning()
        result = self.coverage()
        self.assertEqual(result["event_id"], first["event_id"])
        self.assertTrue(result["first_visit"])
        self.assertEqual(self.sql("SELECT opened_count,last_opened_ts FROM articles"), [(0, None)])
        self.assertEqual(self.sql("SELECT * FROM read_articles"), [])
        self.assertEqual(self.sql("SELECT * FROM curation_signals"), [])

    def test_simultaneous_backfills_assign_each_article_once(self):
        for index in range(12):
            self.add(f"b{index}")

        def index_cache(_):
            conn = self.backend.db()
            try:
                with conn:
                    self.backend.ensure_event_index(conn)
            finally:
                conn.close()

        with ThreadPoolExecutor(max_workers=3) as workers:
            list(workers.map(index_cache, range(3)))
        self.assertEqual(self.sql("SELECT COUNT(*), COUNT(DISTINCT article_id) FROM event_articles"), [(13, 13)])
        self.assertEqual(self.sql("SELECT COUNT(*) FROM news_events"), [(1,)])

    def test_cli_read_and_acknowledge_are_separate_operations(self):
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(self.backend.main(["event", "--article-id", "a"]), 0)
        result = json.loads(output.getvalue())
        self.assertTrue(result["first_visit"])
        with redirect_stdout(io.StringIO()):
            self.assertEqual(self.backend.main([
                "event-seen", "--id", result["event_id"], "--through", str(result["seen_through"])
            ]), 0)
        self.assertFalse(self.coverage()["first_visit"])

    def test_missing_story_returns_an_actionable_error(self):
        with self.assertRaisesRegex(ValueError, "no longer in the local cache"):
            self.coverage("missing")


if __name__ == "__main__":
    unittest.main()
