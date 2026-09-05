"""Only real syndication feeds become successful, durable source-health checks."""

import hashlib
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
HTML = b'<html><head><title>Access denied</title></head><body>Please sign in.</body></html>'
SOURCE = {"id": "custom-fixture", "name": "Fixture News", "url": "https://example.test/rss", "topics": ["science"]}
RSS = (
    b'<rss version="2.0"><channel><title>Fixture News</title><link>https://example.test/</link>'
    b'<description>Science news</description><item><title>A useful discovery</title>'
    b'<link>https://example.test/story</link><description>Science research findings.</description>'
    b'</item></channel></rss>'
)
EMPTY_RSS = b'<rss version="2.0"><channel><title>Quiet news</title><link>https://example.test/</link><description>No stories</description></channel></rss>'


def load_backend():
    loader = SourceFileLoader("pyin_feed_health_backend", str(ROOT / "bin" / "chuchua-news"))
    spec = spec_from_loader(loader.name, loader)
    backend = module_from_spec(spec)
    loader.exec_module(backend)
    return backend


class FeedHealthTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.backend = self.new_backend()
        clock = mock.patch.object(self.backend.time, "time", return_value=NOW)
        self.clock = clock.start()
        self.addCleanup(clock.stop)
        notifications = mock.patch.object(self.backend, "send_alert_notifications", return_value=0)
        notifications.start()
        self.addCleanup(notifications.stop)
        self.backend.save_setup_profile(json.dumps(self.backend.default_setup_profile()))
        self.backend.USER_SOURCES_PATH.write_text(json.dumps([SOURCE]), encoding="utf-8")

    def new_backend(self):
        backend = load_backend()
        backend.CONFIG_DIR = self.base / "config" / backend.APP_ID
        backend.STATE_DIR = self.base / "state" / backend.APP_ID
        backend.DB_PATH = backend.STATE_DIR / "news.sqlite3"
        backend.USER_SOURCES_PATH = backend.CONFIG_DIR / "sources.json"
        return backend

    def refresh_with(self, body, etag='"good"', error=None, background=False):
        with mock.patch.object(
            self.backend, "http_get_conditional", return_value=(body, {"etag": etag, "last_modified": ""}),
            side_effect=error,
        ) as request:
            result = self.backend.refresh(background=background, interval_minutes=5)
        return result, request

    def fetch_state(self):
        conn = self.backend.db()
        try:
            row = conn.execute("SELECT * FROM source_fetch_state WHERE source_id = ?", (SOURCE["id"],)).fetchone()
            return dict(row) if row else {}
        finally:
            conn.close()

    def cached_articles(self):
        conn = self.backend.db()
        try:
            return [dict(row) for row in conn.execute("SELECT * FROM articles ORDER BY id")]
        finally:
            conn.close()

    def health(self):
        with mock.patch.object(self.backend, "http_get_conditional", side_effect=AssertionError("Health must not fetch")):
            return self.backend.source_health()

    def cli_environment(self):
        return {**os.environ, "XDG_CONFIG_HOME": str(self.base / "config"),
                "XDG_STATE_HOME": str(self.base / "state"), "PYTHONDONTWRITEBYTECODE": "1"}

    def install_legacy_fetch_state(self):
        conn = self.backend.db()
        with conn:
            conn.execute("DROP TABLE source_fetch_state")
            conn.execute(
                "CREATE TABLE source_fetch_state (source_id TEXT PRIMARY KEY, url TEXT NOT NULL, "
                "etag TEXT NOT NULL DEFAULT '', last_modified TEXT NOT NULL DEFAULT '', "
                "content_hash TEXT NOT NULL DEFAULT '', last_checked_ts INTEGER NOT NULL DEFAULT 0, "
                "last_success_ts INTEGER NOT NULL DEFAULT 0, unchanged_streak INTEGER NOT NULL DEFAULT 0, "
                "consecutive_failures INTEGER NOT NULL DEFAULT 0, next_fetch_ts INTEGER NOT NULL DEFAULT 0)"
            )
            conn.execute(
                "INSERT INTO source_fetch_state (source_id, url, etag, content_hash, last_success_ts) VALUES (?, ?, ?, ?, ?)",
                (SOURCE["id"], SOURCE["url"], '"legacy-html"', hashlib.sha256(HTML).hexdigest(), NOW - 120),
            )
        conn.close()

    def test_supported_feed_formats_extract_articles_and_accept_empty_feeds(self):
        atom = (
            b'<feed xmlns="http://www.w3.org/2005/Atom"><title>Fixture</title>'
            b'<id>https://example.test/</id><updated>2026-09-04T12:00:00Z</updated>'
            b'<entry><title>A useful discovery</title><id>https://example.test/story</id>'
            b'<link href="https://example.test/story"/><summary>Science research findings.</summary>'
            b'<updated>2026-09-04T12:00:00Z</updated></entry></feed>'
        )
        rdf = (
            b'<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/">'
            b'<channel rdf:about="https://example.test/rss"><title>Fixture</title><link>https://example.test/</link>'
            b'<description>Science news</description><items><rdf:Seq/></items></channel>'
            b'<item rdf:about="https://example.test/story"><title>A useful discovery</title>'
            b'<link>https://example.test/story</link><description>Science research findings.</description></item></rdf:RDF>'
        )
        for body in (RSS, atom, atom.replace(b"http://www.w3.org/2005/Atom", b"http://purl.org/atom/ns#"), rdf):
            with self.subTest(body=body[:90]):
                articles = self.backend.parse_feed(SOURCE, body, NOW)
                self.assertEqual(len(articles), 1)
                self.assertEqual(articles[0]["title"], "A useful discovery")
                self.assertEqual(articles[0]["url"], "https://example.test/story")
                self.assertEqual(articles[0]["feed_summary"], "Science research findings.")
        for body in (
            EMPTY_RSS,
            atom[:atom.index(b"<entry>")] + b"</feed>",
            rdf[:rdf.index(b"<item rdf:")] + b"</rdf:RDF>",
        ):
            with self.subTest(empty=body[:90]):
                self.assertEqual(self.backend.parse_feed(SOURCE, body, NOW), [])

    def test_html_and_xml_documents_with_feed_looking_children_are_rejected(self):
        for body in (
            HTML, b'<html xmlns="http://www.w3.org/1999/xhtml"><body/></html>',
            b'<document><item><title>Misleading</title><link>https://example.test/story</link></item></document>',
            b'<feed><entry><title>Widget</title><link href="https://example.test/story"/></entry></feed>',
            b'<feed xmlns="https://example.test/widgets"><entry/></feed>',
            b'<rss/>', b'<rss><wrapper><channel/></wrapper></rss>',
            b'<rss xmlns="https://example.test/widgets"><channel/></rss>',
            b'<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description/></rdf:RDF>',
            b'<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><channel/></rdf:RDF>',
        ):
            with self.subTest(body=body):
                with self.assertRaises(ValueError):
                    self.backend.parse_feed(SOURCE, body, NOW)

    def test_non_feed_first_attempt_has_no_success_timestamp_and_survives_restart(self):
        result, _ = self.refresh_with(HTML)
        self.assertFalse(result["ok"])
        self.assertEqual(result["sources_ok"], 0)
        self.assertEqual(result["inserted"], 0)
        self.assertIn("HTML", result["errors"][0]["error"])
        state = self.fetch_state()
        self.assertEqual(state["last_checked_ts"], NOW)
        self.assertEqual(state["last_success_ts"], 0)
        self.assertEqual(state["last_error"], result["errors"][0]["error"])
        restarted = self.new_backend().source_health()
        self.assertEqual(restarted["counts"], {"total": 1, "healthy": 0, "failing": 1, "unchecked": 0})
        self.assertEqual(restarted["sources"][0]["last_success_age"], "never")
        self.assertEqual(restarted["sources"][0]["last_error"], state["last_error"])

    def test_failure_preserves_cached_stories_and_last_validated_success(self):
        first, _ = self.refresh_with(RSS)
        self.assertEqual(first["inserted"], 1)
        cached = self.cached_articles()
        previous = self.fetch_state()
        self.clock.return_value = NOW + 120
        failed, _ = self.refresh_with(HTML, etag='"invalid-html"')
        self.assertTrue(failed["ok"])
        self.assertEqual(failed["total"], 1)
        self.assertEqual(self.cached_articles(), cached)
        state = self.fetch_state()
        self.assertEqual(state["last_success_ts"], NOW)
        self.assertEqual(state["last_checked_ts"], NOW + 120)
        self.assertEqual(state["etag"], previous["etag"])
        self.assertEqual(state["content_hash"], previous["content_hash"])
        self.assertEqual(self.health()["sources"][0]["status"], "failing")

    def test_empty_valid_feed_recovers_a_failed_source(self):
        self.refresh_with(HTML)
        self.clock.return_value = NOW + 60
        result, _ = self.refresh_with(EMPTY_RSS)
        self.assertTrue(result["ok"])
        self.assertEqual(result["sources_ok"], 1)
        self.assertEqual(result["total"], 0)
        state = self.fetch_state()
        self.assertEqual(state["last_success_ts"], NOW + 60)
        self.assertEqual(state["last_error"], "")
        self.assertEqual(state["consecutive_failures"], 0)
        self.assertEqual(self.health()["sources"][0]["status"], "healthy")

    def test_304_recovers_using_only_the_last_validated_feed_validators(self):
        self.refresh_with(RSS)
        self.clock.return_value = NOW + 60
        self.refresh_with(HTML, etag='"invalid"')
        self.clock.return_value = NOW + 120
        result, request = self.refresh_with(None)
        self.assertEqual(request.call_args.kwargs["etag"], '"good"')
        self.assertEqual(result["sources_not_modified"], 1)
        self.assertEqual(result["sources_ok"], 1)
        self.assertEqual(result["total"], 1)
        health = self.health()["sources"][0]
        self.assertEqual(health["status"], "healthy")
        self.assertEqual(health["last_error"], "")
        self.assertEqual(health["last_success_ts"], NOW + 120)

    def test_same_valid_body_recovers_without_rewriting_cached_articles(self):
        self.refresh_with(RSS)
        cached = self.cached_articles()
        self.clock.return_value = NOW + 60
        self.refresh_with(None, error=TimeoutError("publisher timed out"))
        self.clock.return_value = NOW + 120
        result, _ = self.refresh_with(RSS)
        self.assertEqual(result["sources_unchanged"], 1)
        self.assertEqual(result["updated"], 0)
        self.assertEqual(self.cached_articles(), cached)
        self.assertEqual(self.health()["sources"][0]["last_error"], "")

    def test_legacy_html_hash_and_304_cannot_bypass_validation_after_schema_migration(self):
        self.install_legacy_fetch_state()
        self.assertEqual(self.new_backend().source_health()["sources"][0]["status"], "unchecked")
        for body in (HTML, None):
            with self.subTest(body=body):
                result, request = self.refresh_with(body)
                self.assertEqual(request.call_args.kwargs["etag"], "")
                self.assertEqual(request.call_args.kwargs["last_modified"], "")
                self.assertEqual(result["sources_ok"], 0)
                self.assertEqual(result["sources_unchanged"], 0)
                self.assertEqual(result["sources_not_modified"], 0)
                self.assertEqual(self.fetch_state()["last_success_ts"], 0)

    def test_concurrent_health_cli_processes_can_migrate_the_legacy_state(self):
        self.install_legacy_fetch_state()
        processes = []
        try:
            for _ in range(6):
                processes.append(subprocess.Popen(
                    [sys.executable, str(ROOT / "bin" / "chuchua-news"), "sources", "--health"],
                    env=self.cli_environment(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                ))
            for process in processes:
                stdout, stderr = process.communicate(timeout=20)
                self.assertEqual(process.returncode, 0, stdout + stderr)
                payload = json.loads(stdout)
                self.assertTrue(payload["ok"])
                self.assertEqual(payload["sources"][0]["id"], SOURCE["id"])
                self.assertEqual(payload["sources"][0]["status"], "unchecked")
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=5)
        self.assertEqual(self.fetch_state()["etag"], '"legacy-html"')

    def test_html_body_is_rejected_even_if_a_cached_hash_was_marked_validated(self):
        state = {"validated_feed": 1, "content_hash": hashlib.sha256(HTML).hexdigest(), "etag": '"wrong"'}
        with mock.patch.object(self.backend, "http_get_conditional", return_value=(HTML, {})):
            result = self.backend.fetch_source(SOURCE, NOW, state)
        self.assertEqual(result["status"], "error")
        self.assertIn("HTML", result["error"])

    def test_background_backoff_keeps_the_previous_failure_visible_without_new_attempt(self):
        self.refresh_with(HTML)
        previous = self.fetch_state()
        self.clock.return_value = NOW + 1
        result, request = self.refresh_with(RSS, background=True)
        request.assert_not_called()
        self.assertEqual(result["sources_skipped"], 1)
        self.assertEqual(result["sources_attempted"], 0)
        self.assertEqual(self.fetch_state(), previous)
        self.assertEqual(self.health()["counts"]["failing"], 1)
        self.refresh_with(HTML)
        self.assertEqual(self.fetch_state()["consecutive_failures"], 2)
        self.assertGreater(self.fetch_state()["next_fetch_ts"], previous["next_fetch_ts"])

    def test_failure_does_not_bypass_configured_retention_or_bookmark_protection(self):
        self.refresh_with(RSS)
        conn = self.backend.db()
        with conn:
            conn.execute("UPDATE articles SET published_ts = ?", (NOW - 100 * 86400,))
        conn.close()
        result, _ = self.refresh_with(HTML)
        self.assertEqual(result["total"], 0)
        self.refresh_with(RSS.replace(b"discovery", b"discovery today"))
        article = self.cached_articles()[0]
        conn = self.backend.db()
        with conn:
            conn.execute("UPDATE articles SET published_ts = ?", (NOW - 100 * 86400,))
            conn.execute("INSERT INTO bookmarks(article_id, saved_ts) VALUES (?, ?)", (article["id"], NOW))
        conn.close()
        result, _ = self.refresh_with(HTML)
        self.assertEqual(result["total"], 1)

    def test_changing_a_sources_url_discards_old_health_and_conditional_validators(self):
        self.refresh_with(RSS)
        changed = {**SOURCE, "url": "https://example.test/new-feed"}
        self.backend.USER_SOURCES_PATH.write_text(json.dumps([changed]), encoding="utf-8")
        health = self.health()["sources"][0]
        self.assertEqual(health["status"], "unchecked")
        self.assertEqual(health["last_success_ts"], 0)
        _, request = self.refresh_with(HTML)
        self.assertEqual(request.call_args.args[0], changed["url"])
        self.assertEqual(request.call_args.kwargs["etag"], "")
        self.assertEqual(self.fetch_state()["last_success_ts"], 0)

    def test_health_respects_active_sources_and_all_includes_disabled_sources(self):
        second = {**SOURCE, "id": "custom-disabled", "name": "Disabled News", "url": "https://example.test/disabled"}
        self.backend.USER_SOURCES_PATH.write_text(json.dumps([SOURCE, second]), encoding="utf-8")
        profile = self.backend.load_setup_profile()
        profile.update(complete=True, disabled_source_ids=[second["id"]])
        self.backend.save_setup_profile(json.dumps(profile))
        self.refresh_with(HTML)
        self.assertEqual(self.health()["counts"]["total"], 1)
        all_sources = self.backend.source_health(active_only=False)
        self.assertEqual(all_sources["counts"], {"total": 2, "healthy": 0, "failing": 1, "unchecked": 1})
        self.assertEqual([row["id"] for row in all_sources["sources"]], [SOURCE["id"], second["id"]])
        self.assertFalse(all_sources["sources"][1]["active"])

    def test_source_health_cli_reads_durable_failure_after_a_new_process_starts(self):
        self.refresh_with(None, error=TimeoutError("publisher timed out"))
        result = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "chuchua-news"), "sources", "--health"],
            env=self.cli_environment(),
            capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["counts"]["failing"], 1)
        self.assertEqual(payload["sources"][0]["last_error"], "TimeoutError: publisher timed out")
        self.assertEqual(payload["sources"][0]["last_checked_ts"], NOW)


if __name__ == "__main__":
    unittest.main()
