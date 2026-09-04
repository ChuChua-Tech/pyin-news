import json
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import urlparse
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]


def load_json(name):
    with (ROOT / name).open(encoding="utf-8") as handle:
        return json.load(handle)


def load_backend():
    loader = SourceFileLoader("pyin_release_backend", str(ROOT / "bin" / "chuchua-news"))
    spec = spec_from_loader(loader.name, loader)
    module = module_from_spec(spec)
    loader.exec_module(module)
    return module


class ReleasePackageTests(unittest.TestCase):
    def test_manifest_and_entry_points(self):
        manifest = load_json("manifest.json")
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertEqual(manifest["id"], "tech.chuchua.news")
        self.assertRegex(manifest["version"], r"^\d+\.\d+\.\d+$")
        self.assertEqual(manifest["license"], "MIT")
        self.assertTrue((ROOT / "LICENSE").is_file())
        self.assertTrue((ROOT / "README.md").is_file())
        self.assertTrue((ROOT / "preview.png").is_file())
        backend = (ROOT / "bin" / "chuchua-news").read_text(encoding="utf-8")
        changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertIn(f"pyin-news/{manifest['version']}", backend)
        self.assertIn(f"## [{manifest['version']}]", changelog)
        for entry_point in manifest["entryPoints"].values():
            self.assertTrue((ROOT / entry_point).is_file(), entry_point)

    def test_source_catalog_is_complete_and_unique(self):
        sources = load_json("sources.json")
        catalog = load_json("source-catalog.json")
        self.assertEqual(len(sources), 200)

        names = [source["name"].strip() for source in sources]
        urls = [source["url"].strip() for source in sources]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(len(urls), len(set(urls)))
        self.assertEqual(set(names), set(catalog["sources"]))
        self.assertEqual(catalog["metadataLicense"], "CC0-1.0")

        for source in sources:
            self.assertTrue(source["name"].strip())
            parsed = urlparse(source["url"])
            self.assertIn(parsed.scheme, {"http", "https"})
            self.assertTrue(parsed.netloc)
            self.assertIsInstance(source.get("topics", []), list)

    def test_release_documents_reference_public_commands(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("omarchy plugin add", readme)
        self.assertIn("omarchy plugin update tech.chuchua.news", readme)
        self.assertIn("omarchy plugin remove tech.chuchua.news", readme)
        self.assertIn("Privacy and network boundaries", readme)

    def test_package_contains_no_machine_specific_home_path(self):
        text_suffixes = {".md", ".json", ".qml", ".py", ".yml", ".yaml"}
        machine_home = "/home/" + "chuchuatech"
        offenders = []
        for path in ROOT.rglob("*"):
            if not path.is_file() or (
                path.suffix not in text_suffixes and path.name != "chuchua-news"
            ):
                continue
            if machine_home in path.read_text(encoding="utf-8"):
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [])

    def test_backend_starts_with_an_empty_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            env = os.environ.copy()
            env["XDG_CONFIG_HOME"] = str(base / "config")
            env["XDG_STATE_HOME"] = str(base / "state")
            completed = subprocess.run(
                [sys.executable, str(ROOT / "bin" / "chuchua-news"), "doctor"],
                check=True,
                capture_output=True,
                env=env,
                text=True,
                timeout=30,
            )
            report = json.loads(completed.stdout)
            self.assertTrue(report["ok"])
            self.assertEqual(report["curation_engine"], "v3")
            self.assertEqual(report["sources"], 200)
            self.assertEqual(report["catalog_sources"], 200)
            self.assertFalse(report["setup_complete"])

    def test_feed_parser_repairs_an_isolated_legacy_byte(self):
        backend = load_backend()
        raw = (
            b'<?xml version="1.0" encoding="UTF-8"?>'
            b'<rss><channel><item><title><![CDATA[Legacy\xa0space]]></title>'
            b'<link>https://example.com/story</link>'
            b'<description>Test</description></item></channel></rss>'
        )
        articles = backend.parse_feed(
            {"name": "Encoding Test", "topics": ["test"]}, raw, 1_800_000_000
        )
        self.assertEqual(len(articles), 1)
        self.assertEqual(articles[0]["url"], "https://example.com/story")

    def test_feed_request_does_not_force_compression(self):
        backend = load_backend()
        captured_headers = {}

        class Response:
            headers = {}

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self, _size):
                return b"<rss><channel /></rss>"

        def fake_urlopen(request, timeout):
            self.assertGreater(timeout, 0)
            captured_headers.update(dict(request.header_items()))
            return Response()

        with mock.patch.object(backend.urllib.request, "urlopen", fake_urlopen):
            body, _validators = backend.http_get_conditional(
                "https://example.com/feed", 1024
            )

        self.assertEqual(body, b"<rss><channel /></rss>")
        self.assertNotIn("Accept-encoding", captured_headers)
        self.assertEqual(captured_headers["User-agent"], backend.USER_AGENT)

        captured_headers.clear()
        with mock.patch.object(backend.urllib.request, "urlopen", fake_urlopen):
            backend.http_get_conditional(
                "https://www.cbc.ca/webfeed/rss/rss-topstories", 1024
            )
        self.assertEqual(captured_headers["User-agent"], "Mozilla/5.0")

    def test_alert_notification_carries_an_argv_only_article_deep_link(self):
        backend = load_backend()
        command = backend.alert_notification_command(
            "/usr/bin/omarchy-notification-send",
            True,
            "/usr/bin/omarchy-shell",
            "/tmp/pyin-news.svg",
            "News alert: Kamloops",
            "Example Source\nExample story",
            {"article_id": "article-123"},
        )

        exec_index = command.index("--exec")
        self.assertEqual(
            command[exec_index + 1:exec_index + 6],
            [
                "/usr/bin/omarchy-shell",
                "shell",
                "summon",
                backend.PLUGIN_ID,
                '{"article_id":"article-123"}',
            ],
        )
        self.assertNotIn("bash", command)
        self.assertNotIn("sh", command)

    def test_cached_article_endpoint_supports_notification_deep_links(self):
        backend = load_backend()
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            backend.CONFIG_DIR = base / "config"
            backend.STATE_DIR = base / "state"
            backend.DB_PATH = backend.STATE_DIR / "news.sqlite3"
            conn = backend.db()
            with conn:
                conn.execute(
                    "INSERT INTO articles "
                    "(id, url, title, source, feed_summary, published_ts, fetched_ts) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (
                        "article-123",
                        "https://example.com/story",
                        "A local story",
                        "Example Source",
                        "The publisher-provided synopsis.",
                        1_800_000_000,
                        1_800_000_001,
                    ),
                )
                cursor = conn.execute(
                    "INSERT INTO alerts(query, enabled, created_ts) VALUES(?, 1, ?)",
                    ("Kamloops", 1_800_000_002),
                )
                conn.execute(
                    "INSERT INTO alert_hits(alert_id, article_id, notified_ts) "
                    "VALUES(?, ?, ?)",
                    (cursor.lastrowid, "article-123", 1_800_000_003),
                )
            conn.close()

            payload = backend.get_article("article-123")

        self.assertTrue(payload["ok"])
        self.assertEqual(payload["article"]["id"], "article-123")
        self.assertEqual(payload["article"]["alert_query"], "Kamloops")
        self.assertEqual(payload["article"]["synopsis"], "The publisher-provided synopsis.")
        self.assertEqual(payload["article"]["cluster_ids"], ["article-123"])


if __name__ == "__main__":
    unittest.main()
