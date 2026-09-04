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
        backend_module = load_backend()
        changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertEqual(backend_module.APP_VERSION, manifest["version"])
        self.assertIn(f"pyin-news/{manifest['version']}", backend)
        self.assertIn(f"## [{manifest['version']}]", changelog)
        for entry_point in manifest["entryPoints"].values():
            self.assertTrue((ROOT / entry_point).is_file(), entry_point)

    def test_source_catalog_is_complete_and_unique(self):
        sources = load_json("sources.json")
        catalog = load_json("source-catalog.json")
        self.assertEqual(len(sources), 226)

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

    def test_vertical_topics_have_real_source_packs(self):
        backend = load_backend()
        sources = load_json("sources.json")
        topic_values = {topic["value"] for topic in backend.TOPIC_CATALOG}
        expected_pack_sizes = {"sports": 13, "gaming": 11, "omarchy": 2}

        self.assertNotIn("canada", topic_values)
        for topic, expected_count in expected_pack_sizes.items():
            self.assertIn(topic, topic_values)
            matching = [
                source for source in sources
                if topic in {str(value).casefold() for value in source.get("topics", [])}
            ]
            self.assertEqual(len(matching), expected_count)

    def test_location_relevance_replaces_a_country_specific_topic(self):
        backend = load_backend()
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            backend.CONFIG_DIR = base / "config"
            backend.STATE_DIR = base / "state"
            backend.DB_PATH = backend.STATE_DIR / "news.sqlite3"
            now = 1_800_000_000
            profile = backend.default_setup_profile()
            profile["complete"] = True
            profile["location"] = {"country": "Canada", "region": "", "city": ""}
            conn = backend.db()
            with conn:
                conn.execute(
                    "INSERT INTO meta(key, value) VALUES('setup_profile', ?)",
                    (json.dumps(profile),),
                )
                conn.executemany(
                    "INSERT INTO articles "
                    "(id, url, title, source, feed_summary, published_ts, fetched_ts, source_topics) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    [
                        (
                            "local-story", "https://example.ca/local", "Community update",
                            "The Tyee", "A regional report.", now, now,
                            json.dumps(["Canada"]),
                        ),
                        (
                            "other-story", "https://example.com/other", "Distant update",
                            "ProPublica", "An unrelated report.", now, now,
                            json.dumps(["United States"]),
                        ),
                    ],
                )
            conn.close()

            with mock.patch.object(backend.time, "time", return_value=now):
                articles, _stats = backend.ranked_articles(15)

        self.assertEqual(articles[0]["id"], "local-story")
        self.assertEqual(articles[0]["reason"], "near you")

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
            self.assertEqual(report["sources"], 226)
            self.assertEqual(report["catalog_sources"], 226)
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

    def test_alerts_match_story_text_not_static_source_geography(self):
        backend = load_backend()
        source_tag_only = {
            "title": "Vehicle fire caused an explosion",
            "feed_summary": "Crews responded early Tuesday morning.",
            "source_topics": json.dumps(["Kamloops", "British Columbia"]),
        }
        title_match = {
            **source_tag_only,
            "title": "Kamloops vehicle fire caused an explosion",
        }
        synopsis_match = {
            **source_tag_only,
            "feed_summary": "The investigation continues in Kamloops.",
        }

        self.assertFalse(backend.alert_matches("Kamloops", source_tag_only))
        self.assertTrue(backend.alert_matches("Kamloops", title_match))
        self.assertTrue(backend.alert_matches("Kamloops", synopsis_match))
        self.assertTrue(backend.alert_matches(
            "war in Iran",
            {"title": "Iranian officials discuss war", "feed_summary": ""},
        ))

    def test_update_status_protects_development_and_finds_stable_fast_forwards(self):
        backend = load_backend()

        def completed(arguments, returncode=0, stdout=""):
            return subprocess.CompletedProcess(arguments, returncode, stdout, "")

        def development_git(*arguments, **_kwargs):
            key = tuple(arguments)
            responses = {
                ("rev-parse", "--show-toplevel"): completed(arguments, stdout=str(backend.PLUGIN_DIR)),
                ("symbolic-ref", "--quiet", "--short", "HEAD"): completed(arguments, stdout="develop\n"),
                ("rev-parse", "HEAD"): completed(arguments, stdout="a" * 40 + "\n"),
                ("status", "--porcelain", "--untracked-files=normal"): completed(arguments),
            }
            return responses[key]

        with mock.patch.object(backend.shutil, "which", return_value="/usr/bin/git"), \
                mock.patch.object(backend, "run_plugin_git", side_effect=development_git), \
                mock.patch.object(backend, "recent_update_result", return_value={}):
            protected = backend.application_update_status(check_remote=True)

        self.assertEqual(protected["state"], "development")
        self.assertFalse(protected["can_check"])
        self.assertFalse(protected["can_install"])

        def stable_git(*arguments, **_kwargs):
            key = tuple(arguments)
            responses = {
                ("rev-parse", "--show-toplevel"): completed(arguments, stdout=str(backend.PLUGIN_DIR)),
                ("symbolic-ref", "--quiet", "--short", "HEAD"): completed(arguments, stdout="main\n"),
                ("rev-parse", "HEAD"): completed(arguments, stdout="a" * 40 + "\n"),
                ("status", "--porcelain", "--untracked-files=normal"): completed(arguments),
                ("fetch", "--quiet", "origin", "HEAD"): completed(arguments),
                ("rev-parse", "FETCH_HEAD"): completed(arguments, stdout="b" * 40 + "\n"),
                ("show", "FETCH_HEAD:manifest.json"): completed(
                    arguments, stdout=json.dumps({"version": "0.20.0"})
                ),
                ("merge-base", "--is-ancestor", "HEAD", "FETCH_HEAD"): completed(arguments),
            }
            return responses[key]

        with mock.patch.object(backend.shutil, "which", return_value="/usr/bin/git"), \
                mock.patch.object(backend, "run_plugin_git", side_effect=stable_git), \
                mock.patch.object(backend, "recent_update_result", return_value={}):
            available = backend.application_update_status(check_remote=True)

        self.assertEqual(available["state"], "available")
        self.assertEqual(available["target_version"], "0.20.0")
        self.assertTrue(available["can_install"])

    def test_update_install_delegates_to_omarchy_after_safe_check(self):
        backend = load_backend()
        update_status = {
            "ok": True,
            "state": "available",
            "update_available": True,
            "can_install": True,
        }
        completed = subprocess.CompletedProcess([], 0, "Updated tech.chuchua.news.\n", "")

        with mock.patch.object(
            backend, "application_update_status", return_value=update_status
        ), mock.patch.object(
            backend.shutil, "which", return_value="/usr/bin/omarchy"
        ), mock.patch.object(
            backend.subprocess, "run", return_value=completed
        ) as run, mock.patch.object(
            backend, "plugin_manifest_version", return_value="0.19.0"
        ), mock.patch.object(
            backend, "write_json_atomic"
        ) as write_result, mock.patch.object(backend, "notify_update_result"):
            payload = backend.install_application_update()

        self.assertTrue(payload["ok"])
        self.assertEqual(payload["state"], "installed")
        run.assert_called_once()
        self.assertEqual(
            run.call_args.args[0],
            ["/usr/bin/omarchy", "plugin", "update", backend.PLUGIN_ID, "--yes"],
        )
        write_result.assert_called_once()

    def test_profile_exposes_manual_confirmed_native_updates(self):
        profile_qml = (ROOT / "ProfilePage.qml").read_text(encoding="utf-8")
        app_qml = (ROOT / "App.qml").read_text(encoding="utf-8")

        self.assertIn("APP & UPDATES", profile_qml)
        self.assertIn("Check for updates", profile_qml)
        self.assertIn("Confirm update", profile_qml)
        self.assertIn('[root.backendPath, "updates", "--install"]', app_qml)
        self.assertIn("Quickshell.execDetached", app_qml)

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
