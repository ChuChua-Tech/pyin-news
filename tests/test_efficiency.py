"""Optimizations must preserve migration, ingestion, and result semantics."""

from contextlib import closing
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
NOW = 1_800_000_000
SOURCE = {"id": "fixture", "name": "Fixture", "url": "https://example.test/rss", "topics": ["science"]}


class EfficiencyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        loader = SourceFileLoader("pyin_efficiency_backend", str(ROOT / "bin/chuchua-news"))
        self.backend = module_from_spec(spec_from_loader(loader.name, loader))
        loader.exec_module(self.backend)
        self.backend.CONFIG_DIR = self.base / "config"
        self.backend.STATE_DIR = self.base / "state"
        self.backend.DB_PATH = self.backend.STATE_DIR / "news.sqlite3"
        self.backend.USER_SOURCES_PATH = self.backend.CONFIG_DIR / "sources.json"
        self.backend.ensure_dirs()
        self.backend.USER_SOURCES_PATH.write_text(json.dumps([SOURCE]))
        patch = mock.patch.object(self.backend.time, "time", return_value=NOW)
        self.clock = patch.start()
        self.addCleanup(patch.stop)
        self.backend.db().close()

    def article(self, identity, **changes):
        item = dict(id=identity, url=f"https://example.test/{identity}",
                    title="Lunar science research mission", source="Fixture",
                    feed_summary="Science research findings.", published_ts=NOW,
                    fetched_ts=NOW, source_topics='["science"]')
        item.update(changes)
        return item

    def ingest(self, articles=(), status="changed"):
        result = dict(source=SOURCE, articles=list(articles), error="", status=status,
                      validators={}, content_hash="fixture")
        with mock.patch.object(self.backend, "fetch_source", return_value=result), \
             mock.patch.object(self.backend, "send_alert_notifications", return_value=0):
            return self.backend.refresh()

    def scores(self):
        with closing(sqlite3.connect(self.backend.DB_PATH)) as conn, conn:
            return dict(conn.execute("SELECT id, trend_score FROM articles"))

    def test_current_database_open_skips_ddl_and_preserves_fts_writes(self):
        statements = []
        connect = sqlite3.connect

        def traced(*args, **kwargs):
            conn = connect(*args, **kwargs)
            conn.set_trace_callback(statements.append)
            return conn

        with mock.patch.object(self.backend.sqlite3, "connect", side_effect=traced):
            self.backend.db().close()
        self.assertFalse(any("CREATE " in sql or "table_info" in sql for sql in statements))
        self.ingest([self.article("a")])
        self.assertEqual(self.backend.search_articles("lunar")["stats"]["matches"], 1)
        self.ingest([self.article("a", title="Ocean carbon mapping")])
        self.assertEqual(self.backend.search_articles("lunar")["stats"]["matches"], 0)
        self.assertEqual(self.backend.search_articles("ocean")["stats"]["matches"], 1)

    def test_schema_changes_repair_missing_tables_indexes_and_fts(self):
        self.ingest([self.article("a")])
        with closing(sqlite3.connect(self.backend.DB_PATH)) as conn, conn:
            conn.execute("DROP TABLE source_fetch_state")
            conn.execute("DROP INDEX idx_articles_published")
            conn.execute("DROP TABLE articles_fts")
        conn = self.backend.db()
        self.assertEqual(conn.execute("SELECT COUNT(*) FROM source_fetch_state").fetchone()[0], 0)
        self.assertIsNotNone(conn.execute("SELECT 1 FROM sqlite_master WHERE name='idx_articles_published'").fetchone())
        conn.close()
        self.assertEqual(self.backend.search_articles("lunar")["stats"]["matches"], 1)

    def test_version_markers_still_run_migrations(self):
        with closing(sqlite3.connect(self.backend.DB_PATH)) as conn, conn:
            conn.execute("DELETE FROM meta WHERE key = 'db_schema_state'")
        with mock.patch.object(self.backend, "_migrate_curation_schema", wraps=self.backend._migrate_curation_schema) as migrate:
            self.backend.db().close()
            self.assertEqual(migrate.call_count, 1)
            self.backend.db().close()
            self.assertEqual(migrate.call_count, 1)
            with closing(sqlite3.connect(self.backend.DB_PATH)) as conn, conn:
                conn.execute("UPDATE meta SET value='5' WHERE key='curation_schema_version'")
                conn.execute("INSERT INTO meta VALUES ('ranker_mode', 'old')")
            self.backend.db().close()
            self.assertEqual(migrate.call_count, 2)
        with closing(sqlite3.connect(self.backend.DB_PATH)) as conn, conn:
            self.assertIsNone(conn.execute("SELECT 1 FROM meta WHERE key='ranker_mode'").fetchone())

    def test_batched_ingestion_counts_repeated_ids_and_preserves_reader_state(self):
        self.ingest([self.article("existing")])
        with closing(sqlite3.connect(self.backend.DB_PATH)) as conn, conn:
            conn.execute("UPDATE articles SET content='Full body', opened_count=3, ai_summary='Saved AI' WHERE id='existing'")
            conn.execute("INSERT INTO bookmarks VALUES ('existing', ?)", (NOW,))
            conn.execute("INSERT INTO read_articles VALUES ('existing', ?, '')", (NOW,))
        articles = [self.article(str(i)) for i in range(501)]
        articles += [self.article("existing", feed_summary=""), self.article("0", title="Corrected lunar research")]
        statements = []
        connect = sqlite3.connect

        def traced(*args, **kwargs):
            conn = connect(*args, **kwargs)
            conn.set_trace_callback(statements.append)
            return conn

        with mock.patch.object(self.backend.sqlite3, "connect", side_effect=traced), \
             mock.patch.object(self.backend, "match_new_alerts", wraps=self.backend.match_new_alerts) as alerts:
            result = self.ingest(articles)
        self.assertEqual(sum(sql.startswith("SELECT id FROM articles WHERE id IN (") for sql in statements), 2)
        self.assertFalse(any(sql.startswith("SELECT 1 FROM articles WHERE id =") for sql in statements))
        self.assertEqual((result["inserted"], result["updated"]), (501, 2))
        self.assertEqual(len(alerts.call_args.args[1]), 501)
        self.assertEqual(len({item["id"] for item in alerts.call_args.args[1]}), 501)
        with closing(sqlite3.connect(self.backend.DB_PATH)) as conn, conn:
            row = conn.execute("SELECT content, opened_count, ai_summary, feed_summary FROM articles WHERE id='existing'").fetchone()
            self.assertEqual(row, ("Full body", 3, "Saved AI", "Science research findings."))
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM read_articles").fetchone()[0], 1)
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM bookmarks").fetchone()[0], 1)

    def test_unchanged_refresh_skips_rebuild_but_corrected_headlines_do_not(self):
        self.ingest([self.article("a"), self.article("b", source="Other")])
        self.backend.USER_SOURCES_PATH.write_text(json.dumps([SOURCE, {**SOURCE, "id": "other", "name": "Other", "url": "https://other.test/rss"}]))
        self.ingest(status="unchanged")
        self.assertEqual(self.scores(), {"a": 1, "b": 1})
        with mock.patch.object(self.backend, "rebuild_trend_scores", wraps=self.backend.rebuild_trend_scores) as rebuild:
            self.clock.return_value = NOW + 60
            self.ingest(status="not_modified")
            rebuild.assert_not_called()
            with closing(sqlite3.connect(self.backend.DB_PATH)) as conn:
                self.assertEqual(conn.execute("SELECT value FROM meta WHERE key='trend_scores_updated'").fetchone()[0], str(NOW + 60))
            self.ingest([self.article("b", source="Other", title="Ocean carbon mapping")])
            self.assertEqual(rebuild.call_count, 1)
        self.assertEqual(self.scores(), {"a": 0, "b": 0})

    def test_unchanged_refresh_rebuilds_when_a_report_ages_out(self):
        self.backend.USER_SOURCES_PATH.write_text(json.dumps([SOURCE, {**SOURCE, "id": "other", "name": "Other", "url": "https://other.test/rss"}]))
        self.ingest([self.article("a"), self.article("b", source="Other", published_ts=NOW - self.backend.TREND_WINDOW_SECONDS + 1)])
        self.assertEqual(self.scores(), {"a": 1, "b": 1})
        self.clock.return_value = NOW + 2
        self.ingest(status="unchanged")
        self.assertEqual(self.scores(), {"a": 0, "b": 0})

    def test_scope_expiry_and_pruning_invalidate_trends(self):
        self.ingest([self.article("a")])
        with mock.patch.object(self.backend, "rebuild_trend_scores", wraps=self.backend.rebuild_trend_scores) as rebuild:
            self.clock.return_value = NOW + self.backend.TREND_CACHE_MAX_AGE_SECONDS + 1
            self.ingest(status="unchanged")
            self.assertEqual(rebuild.call_count, 1)
            self.backend.USER_SOURCES_PATH.write_text(json.dumps([{**SOURCE, "name": "Renamed"}]))
            self.ingest(status="unchanged")
            self.assertEqual(rebuild.call_count, 2)
            with closing(sqlite3.connect(self.backend.DB_PATH)) as conn, conn:
                conn.execute("UPDATE articles SET published_ts=? WHERE id='a'", (NOW - 400 * 86400,))
            self.ingest(status="unchanged")
            self.assertEqual(rebuild.call_count, 3)
        self.assertEqual(self.scores(), {})

    def test_search_formats_only_returned_results_without_reducing_match_counts(self):
        self.ingest([self.article(str(i), title=f"Lunar science mission {i} //") for i in range(40)])
        for query in ("lunar", "lu", "//"):
            with self.subTest(query=query), mock.patch.object(self.backend, "feedback_targets_for_article", wraps=self.backend.feedback_targets_for_article) as feedback:
                result = self.backend.search_articles(query, 3)
                self.assertEqual(result["stats"]["matches"], 40)
                self.assertEqual(result["stats"]["returned"], 3)
                self.assertEqual(feedback.call_count, 3)
                for article in result["articles"]:
                    self.assertFalse(any(key.startswith("_") for key in article))
                    self.assertIn("feedback_targets", article)
                    self.assertEqual(article["summary"], "Science research findings.")
                json.dumps(result)

    def test_catalog_cache_observes_edits_overrides_profiles_and_caller_mutation(self):
        self.backend.DEFAULT_SOURCES_PATH = self.base / "default.json"
        self.backend.DEFAULT_SOURCES_PATH.write_text(json.dumps([SOURCE]))
        profile = {"custom_sources": []}
        first = self.backend.source_catalog(profile)
        first[0]["topics"].append("mutated")
        self.assertNotIn("mutated", self.backend.source_catalog(profile)[0]["topics"])
        stamp = self.backend.USER_SOURCES_PATH.stat()
        self.backend.USER_SOURCES_PATH.write_text(json.dumps([{**SOURCE, "name": "Changed"}]))
        os.utime(self.backend.USER_SOURCES_PATH, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        self.assertEqual(self.backend.source_catalog(profile)[0]["name"], "Changed")
        self.backend.USER_SOURCES_PATH.unlink()
        self.assertEqual(self.backend.source_catalog(profile)[0]["name"], "Fixture")
        profile["custom_sources"].append({**SOURCE, "name": "Custom", "url": "https://custom.test/rss"})
        self.assertEqual([item["name"] for item in self.backend.source_catalog(profile)], ["Fixture", "Custom"])
        self.assertEqual(len(self.backend.source_catalog(profile, include_profile=False)), 1)
        self.backend.SOURCE_CATALOG_PATH = self.base / "metadata.json"
        self.backend.SOURCE_CATALOG_PATH.write_text(json.dumps({"sources": {"Fixture": {"regions": ["old"]}}}))
        self.assertEqual(self.backend.source_catalog(profile)[0]["regions"], ["old"])
        self.backend.SOURCE_CATALOG_PATH.write_text(json.dumps({"sources": {"Fixture": {"regions": ["new"]}}}))
        self.assertEqual(self.backend.source_catalog(profile)[0]["regions"], ["new"])


if __name__ == "__main__":
    unittest.main()
