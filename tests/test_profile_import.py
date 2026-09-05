"""Profile transfer must preserve preferences or leave the saved state untouched."""

from copy import deepcopy
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
NOW = 1_800_000_000


def load_backend():
    loader = SourceFileLoader("pyin_profile_import_backend", str(ROOT / "bin" / "chuchua-news"))
    spec = spec_from_loader(loader.name, loader)
    module = module_from_spec(spec)
    loader.exec_module(module)
    return module


class ProfileImportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.backend = load_backend()
        self.backend.CONFIG_DIR = self.base / "config" / self.backend.APP_ID
        self.backend.STATE_DIR = self.base / "state" / self.backend.APP_ID
        self.backend.DB_PATH = self.backend.STATE_DIR / "news.sqlite3"
        self.backend.USER_SOURCES_PATH = self.backend.CONFIG_DIR / "sources.json"
        clock = mock.patch.object(self.backend.time, "time", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)
        self.profile = self.make_profile()
        self.backend.save_setup_profile(json.dumps(self.profile))
        self.profile = self.backend.load_setup_profile()
        conn = self.backend.db()
        with conn:
            conn.executemany(
                "INSERT INTO interest_nodes "
                "(term, scope, weight, expires_ts, origin, created_ts, updated_ts) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                [
                    ("topic:linux", "lasting", 4.5, None, "article-feedback", NOW - 600, NOW - 300),
                    ("source:example news", "temporary", -7.0, NOW + 86400,
                     "article-feedback", NOW - 500, NOW - 200),
                    ("keyword:expired", "temporary", -3.0, NOW - 1,
                     "article-feedback", NOW - 90000, NOW - 90000),
                ],
            )
        conn.close()

    def make_profile(self):
        profile = self.backend.default_setup_profile()
        profile.update({
            "complete": True,
            "location": {"country": "Canada", "region": "British Columbia", "city": "Kamloops"},
            "languages": ["en", "fr"],
            "topics": {"must": ["omarchy"], "interested": ["gaming", "science"], "muted": ["sports"]},
            "blocked_keywords": ["celebrity gossip", "lottery"],
            "source_types": ["independent", "local"],
            "disabled_source_ids": ["custom-disabled"],
            "custom_sources": [{
                "id": "custom-local-news", "name": "Local News",
                "url": "https://example.com/feed.xml", "topics": ["local", "science"],
                "languages": ["en", "fr"],
            }],
            "viewpoint": {"mode": "broad", "discovery_percent": 40},
            "reading_minutes": 30,
            "behavior": {"mark_read_on_back": False},
            "navigation": {"items": ["bookmarks", "alerts"]},
            "notifications": {"enabled": False, "quiet_start": "21:30", "quiet_end": "08:15", "max_per_day": 2},
            "ai": {"mode": "off", "system_model": "", "system_effort": "",
                   "local_url": "http://127.0.0.1:11434/v1", "local_model": "custom-model"},
            "privacy": {"learn_from_opens": False, "retention_days": 21},
        })
        profile["appearance"] = {
            "theme": "omarchy", "density": "compact", "background": "plain",
            "footer_link": {"label": "My community", "url": "https://example.com/community"},
        }
        return profile

    def snapshot(self):
        """Compare stored values exactly, including expired interests and metadata."""
        conn = self.backend.db()
        try:
            return {
                "meta": [tuple(row) for row in conn.execute(
                    "SELECT key, value FROM meta WHERE key IN ('setup_profile', 'selected_topics') ORDER BY key"
                )],
                "graph": [tuple(row) for row in conn.execute(
                    "SELECT term, scope, weight, expires_ts, origin, created_ts, updated_ts "
                    "FROM interest_nodes ORDER BY term, scope"
                )],
            }
        finally:
            conn.close()

    def graph(self):
        return [row[:4] for row in self.snapshot()["graph"]]

    def incoming_profile(self):
        profile = deepcopy(self.profile)
        profile["location"]["city"] = "Vancouver"
        profile["topics"] = {"must": ["sports"], "interested": ["gaming"], "muted": []}
        return profile

    def node(self, **changes):
        node = {"term": "entity:example person", "scope": "lasting", "weight": 3.5,
                "expires_ts": None, "origin": "article-feedback",
                "created_ts": NOW - 90, "updated_ts": NOW - 60}
        node.update(changes)
        return node

    def wrapper(self, version=3, graph=None):
        payload = {"format": "chuchua-news-profile", "format_version": version,
                   "profile": self.incoming_profile()}
        if version != 1 or graph is not None:
            payload["interest_graph"] = [self.node()] if graph is None else graph
        return payload

    def write_payload(self, payload):
        path = self.base / "import.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def import_payload(self, payload):
        return self.backend.import_setup_profile(str(self.write_payload(payload)))

    def assert_rejected(self, payload):
        before = self.snapshot()
        with self.assertRaises(ValueError):
            self.import_payload(payload)
        self.assertEqual(self.snapshot(), before)

    def test_current_export_roundtrip_preserves_preferences_and_explicit_interests(self):
        path = self.base / "export.json"
        result = self.backend.export_setup_profile(str(path))
        self.assertTrue(result["ok"])
        exported = json.loads(path.read_text(encoding="utf-8"))
        expected_graph = sorted(
            (node["term"], node["scope"], node["weight"], node["expires_ts"])
            for node in exported["interest_graph"]
        )
        self.backend.save_setup_profile(json.dumps(self.incoming_profile()))
        result = self.backend.import_setup_profile(str(path))
        self.assertTrue(result["ok"])
        self.assertEqual(self.backend.load_setup_profile(), self.profile)
        self.assertEqual(self.graph(), expected_graph)
        self.assertEqual(
            json.loads(dict(self.snapshot()["meta"])["selected_topics"]),
            self.profile["topics"]["must"] + self.profile["topics"]["interested"],
        )
        self.assertEqual(result["profile"]["ai"]["mode"], "off")
        self.assertEqual(result["profile"]["custom_sources"], self.profile["custom_sources"])

    def test_importing_valid_incomplete_profile_finishes_setup(self):
        payload = self.wrapper()
        payload["profile"]["complete"] = False
        self.assertTrue(self.import_payload(payload)["profile"]["complete"])
        self.assertEqual(self.backend.load_setup_profile(), self.incoming_profile())

    def test_all_density_and_background_combinations_survive_save_export_and_import(self):
        for density in ("calm", "compact", "classic"):
            for background in ("plain", "paper"):
                with self.subTest(density=density, background=background):
                    profile = self.incoming_profile()
                    profile["appearance"].update(density=density, background=background)
                    self.backend.save_setup_profile(json.dumps(profile))
                    self.assertEqual(self.backend.load_setup_profile(), profile)
                    path = self.base / "appearance-profile.json"
                    self.backend.export_setup_profile(str(path))
                    self.backend.save_setup_profile(json.dumps(self.profile))
                    result = self.backend.import_setup_profile(str(path))
                    self.assertTrue(result["ok"])
                    self.assertEqual(result["profile"], profile)
                    self.assertEqual(self.backend.load_setup_profile(), profile)

    def test_legacy_profiles_without_background_use_plain_and_preserve_other_choices(self):
        paper_profile = deepcopy(self.profile)
        paper_profile["appearance"]["background"] = "paper"
        for version in range(1, 6):
            for wrapped in (False, True):
                with self.subTest(version=version, wrapped=wrapped):
                    self.backend.save_setup_profile(json.dumps(paper_profile))
                    legacy = self.incoming_profile()
                    legacy["version"] = version
                    del legacy["appearance"]["background"]
                    payload = {**self.wrapper(), "profile": legacy} if wrapped else legacy
                    result = self.import_payload(payload)
                    self.assertTrue(result["ok"])
                    self.assertEqual(result["profile"], self.incoming_profile())
                    self.assertEqual(self.backend.load_setup_profile()["appearance"]["background"], "plain")

    def test_new_profiles_require_background_and_reject_malformed_values_atomically(self):
        payload = self.wrapper()
        del payload["profile"]["appearance"]["background"]
        self.assert_rejected(payload)
        for version in (5, 6):
            for invalid in ("unknown", "", None, False, [], {}):
                with self.subTest(version=version, background=invalid):
                    payload = self.wrapper()
                    payload["profile"]["version"] = version
                    payload["profile"]["appearance"]["background"] = invalid
                    self.assert_rejected(payload)

    def test_exported_long_source_interest_is_not_truncated(self):
        source_term = "source:" + "community newsroom " + "a" * 141
        self.assertEqual(len(source_term.removeprefix("source:")), 160)
        conn = self.backend.db()
        with conn:
            conn.execute(
                "INSERT INTO interest_nodes "
                "(term, scope, weight, expires_ts, origin, created_ts, updated_ts) "
                "VALUES (?, 'lasting', -4.5, NULL, 'article-feedback', ?, ?)",
                (source_term, NOW - 90, NOW - 60),
            )
        conn.close()
        path = self.base / "long-source.json"
        self.backend.export_setup_profile(str(path))
        self.backend.import_setup_profile(str(path))
        self.assertIn((source_term, "lasting", -4.5, None), self.graph())

    def test_supported_wrapper_versions_ignore_legacy_ranker_mode(self):
        for version in (1, 2, 3):
            with self.subTest(version=version):
                payload = self.wrapper(version)
                payload["profile"]["ranker_mode"] = "v1"
                result = self.import_payload(payload)
                self.assertTrue(result["ok"])
                self.assertEqual(self.backend.load_setup_profile(), self.incoming_profile())
                self.assertNotIn("ranker_mode", result["profile"])

    def test_v1_and_raw_profiles_without_graph_preserve_all_existing_interests(self):
        for payload in (self.wrapper(1), self.incoming_profile()):
            with self.subTest(wrapped="profile" in payload):
                before = self.snapshot()["graph"]
                self.assertTrue(self.import_payload(payload)["ok"])
                self.assertEqual(self.snapshot()["graph"], before)
                self.assertEqual(self.backend.load_setup_profile(), self.incoming_profile())

    def test_legacy_raw_profile_versions_are_migrated(self):
        for version in range(1, self.backend.SETUP_PROFILE_VERSION + 1):
            with self.subTest(version=version):
                profile = self.incoming_profile()
                profile["version"] = version
                profile["ranker_mode"] = "v2"
                self.assertTrue(self.import_payload(profile)["ok"])
                self.assertEqual(self.backend.load_setup_profile(), self.incoming_profile())

    def test_historical_profiles_without_later_fields_keep_choices_and_gain_defaults(self):
        for version in range(1, self.backend.SETUP_PROFILE_VERSION + 1):
            historical = self.incoming_profile()
            historical["version"] = version
            historical["ranker_mode"] = "v1"
            expected = self.incoming_profile()
            if version < 2:
                del historical["behavior"]
                del historical["blocked_keywords"]
                expected["behavior"] = {"mark_read_on_back": True}
                expected["blocked_keywords"] = []
            if version < 8:
                del historical["ai"]["system_model"]
                del historical["ai"]["system_effort"]
                if version >= 3:
                    historical["ai"]["system_preset"] = "configured"
            if version < 4:
                del historical["navigation"]
                expected["navigation"] = {"items": ["bookmarks", "history", "alerts", "refresh"]}
            if version < 5:
                del historical["custom_sources"]
                del historical["appearance"]["footer_link"]
                expected["custom_sources"] = []
                expected["appearance"]["footer_link"] = {"label": "", "url": ""}
            if version < 6:
                del historical["appearance"]["background"]
                expected["appearance"]["background"] = "plain"
            for wrapped in (False, True):
                with self.subTest(version=version, wrapped=wrapped):
                    payload = {
                        "format": "chuchua-news-profile", "format_version": 1,
                        "profile": historical,
                    } if wrapped else historical
                    before_graph = self.snapshot()["graph"]
                    self.assertTrue(self.import_payload(payload)["ok"])
                    self.assertEqual(self.backend.load_setup_profile(), expected)
                    self.assertEqual(self.snapshot()["graph"], before_graph)

    def test_explicit_empty_graph_clears_existing_interests(self):
        for version in (2, 3):
            with self.subTest(version=version):
                self.assertTrue(self.import_payload(self.wrapper(version, []))["ok"])
                self.assertEqual(self.graph(), [])

    def test_unrelated_or_unsupported_payloads_leave_saved_state_untouched(self):
        payloads = [
            {}, {"hello": "world"}, {"profile": {}}, [], None,
            {"version": self.backend.SETUP_PROFILE_VERSION},
            {**self.wrapper(), "format": "another-app-profile"},
            {key: value for key, value in self.wrapper().items() if key != "format_version"},
            {key: value for key, value in self.wrapper().items() if key != "format"},
            {**self.wrapper(), "format_version": 0},
            {**self.wrapper(), "format_version": 4},
            {**self.wrapper(), "format_version": True},
            {**self.wrapper(), "format_version": "3"},
            {**self.wrapper(), "profile": {}},
            {**self.wrapper(), "profile": []},
            {**self.wrapper(), "profile": {**self.incoming_profile(), "version": self.backend.SETUP_PROFILE_VERSION + 1}},
            {**self.incoming_profile(), "version": self.backend.SETUP_PROFILE_VERSION + 1},
            {**self.incoming_profile(), "version": True},
            {key: value for key, value in self.incoming_profile().items() if key != "version"},
        ]
        for index, payload in enumerate(payloads):
            with self.subTest(case=index):
                self.assert_rejected(payload)

    def test_modern_wrappers_require_an_explicit_graph_array(self):
        for version in (2, 3):
            for invalid in ("missing", None, {}, "[]"):
                with self.subTest(version=version, graph=invalid):
                    payload = self.wrapper(version)
                    if invalid == "missing":
                        del payload["interest_graph"]
                    else:
                        payload["interest_graph"] = invalid
                    self.assert_rejected(payload)

    def test_malformed_nested_settings_do_not_enable_ai_or_reset_preferences(self):
        cases = [
            (("ai",), []), (("ai", "mode"), []), (("ai", "mode"), {"value": "off"}),
            (("ai", "mode"), "unknown-provider"), (("complete",), "false"),
            (("behavior", "mark_read_on_back"), "false"),
            (("notifications", "enabled"), 0), (("privacy", "learn_from_opens"), []),
            (("topics", "must"), "linux"), (("languages",), ["en", {}]),
            (("custom_sources",), [{"name": [], "url": "https://example.com/feed"}]),
            (("custom_sources",), [{"name": "Broken", "url": "not-a-url"}]),
            (("location", "country"), {}),
        ]
        for keys, invalid in cases:
            with self.subTest(path=".".join(keys), invalid=invalid):
                payload = self.wrapper()
                target = payload["profile"]
                for key in keys[:-1]:
                    target = target[key]
                target[keys[-1]] = invalid
                self.assert_rejected(payload)

    def test_malformed_interest_nodes_fail_the_entire_import(self):
        invalid_nodes = [
            None, "topic:linux", {},
            self.node(term="not-a-typed-target"), self.node(term="unsupported:value"),
            self.node(term="topic:"), self.node(term="topic:---"),
            self.node(term=["topic:linux"]),
            self.node(scope="forever"), self.node(scope=[]),
            self.node(weight="4.5"), self.node(weight=True), self.node(weight=None),
            self.node(weight=float("nan")), self.node(weight=float("inf")),
            self.node(weight=float("-inf")),
            self.node(weight=10.1), self.node(weight=-10.1),
            self.node(expires_ts=NOW + 60),
            self.node(scope="temporary", expires_ts="tomorrow"),
            self.node(scope="temporary", expires_ts=True),
            self.node(scope="temporary", expires_ts=[]),
            self.node(scope="temporary", expires_ts=None),
            self.node(scope="temporary", expires_ts=0),
            self.node(scope="temporary", expires_ts=-1),
            self.node(scope="temporary", expires_ts=2**63),
        ]
        for index, invalid in enumerate(invalid_nodes):
            with self.subTest(case=index):
                self.assert_rejected(self.wrapper(graph=[self.node(), invalid]))

    def test_local_ai_requires_explicit_nonblank_url_and_model(self):
        for field in ("local_url", "local_model"):
            for invalid in ("", " \t\n "):
                with self.subTest(field=field, value=invalid):
                    payload = self.wrapper()
                    payload["profile"]["ai"]["mode"] = "local"
                    payload["profile"]["ai"][field] = invalid
                    self.assert_rejected(payload)

    def test_custom_source_ids_cannot_silently_reassign_disabled_sources(self):
        for invalid in ("", "not-custom", "custom-UPPERCASE"):
            with self.subTest(source_id=invalid):
                payload = self.wrapper()
                payload["profile"]["custom_sources"][0]["id"] = invalid
                payload["profile"]["disabled_source_ids"] = [invalid]
                self.assert_rejected(payload)
        payload = self.wrapper()
        original = payload["profile"]["custom_sources"][0]
        duplicate = deepcopy(original)
        duplicate.update(name="Another publisher", url="https://example.org/rss")
        payload["profile"]["custom_sources"].append(duplicate)
        payload["profile"]["disabled_source_ids"] = [original["id"]]
        self.assert_rejected(payload)

    def test_expired_valid_interests_are_skipped_after_validation(self):
        payload = self.wrapper(graph=[
            self.node(),
            self.node(term="subject:expired subject", scope="temporary", expires_ts=NOW - 1),
            self.node(term="subject:expires now", scope="temporary", expires_ts=NOW),
            self.node(term="subject:active subject", scope="temporary", expires_ts=NOW + 60, weight=-7.0),
            self.node(term="subject:neutral subject", weight=0.005),
        ])
        result = self.import_payload(payload)
        self.assertEqual(result["imported_interest_nodes"], 2)
        self.assertEqual(self.graph(), [
            ("entity:example person", "lasting", 3.5, None),
            ("subject:active subject", "temporary", -7.0, NOW + 60),
        ])
        self.assert_rejected(self.wrapper(graph=[
            self.node(scope="temporary", expires_ts=NOW - 1, weight="invalid")
        ]))

    def test_large_valid_graph_is_imported_without_silent_truncation(self):
        graph = [self.node(term=f"keyword:subject {index}") for index in range(501)]
        result = self.import_payload(self.wrapper(graph=graph))
        self.assertEqual(result["imported_interest_nodes"], 501)
        self.assertEqual(len(self.graph()), 501)
        self.assertEqual({row[0] for row in self.graph()}, {node["term"] for node in graph})

    def test_duplicate_normalized_interests_are_rejected(self):
        self.assert_rejected(self.wrapper(graph=[
            self.node(), self.node(term="Entity:Example Person", weight=-4.0)
        ]))

    def test_malformed_json_leaves_saved_state_untouched(self):
        path = self.base / "malformed.json"
        path.write_text('{"profile":', encoding="utf-8")
        before = self.snapshot()
        with self.assertRaises(ValueError):
            self.backend.import_setup_profile(str(path))
        self.assertEqual(self.snapshot(), before)

    def test_duplicate_json_fields_cannot_override_ai_preferences(self):
        path = self.base / "duplicate-fields.json"
        original = json.dumps(self.wrapper())
        duplicated = original.replace('"mode": "off"', '"mode": "off", "mode": "system"', 1)
        self.assertNotEqual(original, duplicated)
        path.write_text(duplicated, encoding="utf-8")
        before = self.snapshot()
        with self.assertRaises(ValueError):
            self.backend.import_setup_profile(str(path))
        self.assertEqual(self.snapshot(), before)

    def test_oversized_file_is_rejected_without_changing_saved_state(self):
        path = self.base / "too-large.json"
        path.write_bytes(b" " * (1024 * 1024) + json.dumps(self.wrapper()).encode("utf-8"))
        before = self.snapshot()
        with self.assertRaises(ValueError):
            self.backend.import_setup_profile(str(path))
        self.assertEqual(self.snapshot(), before)

    def test_graph_write_failure_rolls_back_settings_and_graph_together(self):
        conn = self.backend.db()
        with conn:
            conn.execute(
                "CREATE TRIGGER reject_imported_interest BEFORE INSERT ON interest_nodes "
                "BEGIN SELECT RAISE(ABORT, 'injected graph failure'); END"
            )
        conn.close()
        before = self.snapshot()
        with self.assertRaises(sqlite3.DatabaseError):
            self.import_payload(self.wrapper())
        self.assertEqual(self.snapshot(), before)

    def test_cli_import_rejection_returns_json_error_and_does_not_mutate_state(self):
        path = self.write_payload({"unrelated": "document"})
        before = self.snapshot()
        env = os.environ.copy()
        env["XDG_CONFIG_HOME"] = str(self.base / "config")
        env["XDG_STATE_HOME"] = str(self.base / "state")
        completed = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "chuchua-news"), "setup", "--import", str(path)],
            capture_output=True, text=True, env=env, timeout=30,
        )
        self.assertNotEqual(completed.returncode, 0)
        report = json.loads(completed.stdout)
        self.assertFalse(report["ok"])
        self.assertTrue(report["error"])
        self.assertNotIn("Traceback", completed.stderr)
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
