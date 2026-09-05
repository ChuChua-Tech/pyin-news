"""Ranking must depend on stories and preferences, not process or storage order."""

from copy import deepcopy
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import itertools
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
NOW = 1_800_000_000


def load_backend():
    loader = SourceFileLoader("pyin_ranking_backend", str(ROOT / "bin" / "chuchua-news"))
    spec = spec_from_loader(loader.name, loader)
    module = module_from_spec(spec)
    loader.exec_module(module)
    return module


def isolate_backend(backend, directory):
    base = Path(directory)
    backend.CONFIG_DIR = base / "config"
    backend.STATE_DIR = base / "state"
    backend.DB_PATH = backend.STATE_DIR / "news.sqlite3"
    backend.USER_SOURCES_PATH = backend.CONFIG_DIR / "sources.json"


def candidate(article_id, score=5.0, published=NOW, **changes):
    item = {
        "id": article_id, "source": "Source " + article_id,
        "published_ts": published, "score": score, "reason": "fresh",
        "_components": [("recent", score)], "_topics": set(),
        "_regions": set(), "_types": set(), "_event_features": (set(), set()),
        "_discovery": False, "_must": False, "_alert": False,
    }
    item.update(changes)
    return item


def ordered_fixture(values, order):
    values = list(values)
    if order == "reverse":
        values.reverse()
    elif order == "shuffle":
        random.Random(947).shuffle(values)
    return values


def ranking_snapshot(order):
    """Build a disposable synthetic cache independently in each Python process."""
    backend = load_backend()
    with tempfile.TemporaryDirectory() as directory:
        isolate_backend(backend, directory)
        with mock.patch.object(backend.time, "time", return_value=NOW):
            profile = backend.default_setup_profile()
            profile["complete"] = True
            profile["topics"]["interested"] = ["science"]
            profile["viewpoint"]["discovery_percent"] = 35
            sources = []
            articles = []
            for source_index in range(8):
                regions = ["africa", "asia", "europe", "oceania", "americas", "arctic"]
                types = ["independent", "local", "public", "wire", "specialist", "investigative"]
                source = {
                    "id": f"synthetic-{source_index}", "name": f"Synthetic {source_index}",
                    "languages": ["en"], "custom": True,
                    "regions": ["global"] + [regions[(source_index + index) % len(regions)] for index in range(4)],
                    "types": [types[(source_index + index) % len(types)] for index in range(4)],
                }
                sources.append(source)
                for index in range(26):
                    identity = f"{source_index}-{index:02d}"
                    # Distinct titles avoid clustering the bulk of the cache.
                    glyph = chr(97 + source_index) + chr(97 + index)
                    title = f"glyph{glyph} " + ("quartz" if index % 3 == 0 else "saffron")
                    topic_pool = ["culture", "world", "health", "technology", "business", "environment", "politics"]
                    topics = [topic_pool[(source_index + offset) % len(topic_pool)] for offset in range(4)]
                    if (source_index + index) % 3 == 0:
                        topics.append("science")
                    articles.append((
                        identity, f"https://example.com/{identity}", title,
                        source["name"], "Synthetic feed synopsis.", NOW, NOW,
                        json.dumps(topics),
                    ))
            # Three real clustering candidates exercise representative/source ordering.
            for index in range(3):
                articles.append((
                    f"cluster-{index}", f"https://example.com/cluster-{index}",
                    "Harbor lantern festival opening weekend", sources[index]["name"],
                    "Synthetic festival coverage.", NOW + 1, NOW, '["culture"]',
                ))
            nodes = [
                ("keyword:quartz", "lasting", 2.0, None, "article-feedback", NOW, NOW),
                ("keyword:quartz", "temporary", 2.0, NOW + 86400,
                 "article-feedback", NOW, NOW),
                ("topic:science", "lasting", 2.0, None, "article-feedback", NOW, NOW),
            ]
            conn = backend.db()
            with conn:
                conn.execute("INSERT INTO meta(key, value) VALUES('setup_profile', ?)",
                             (json.dumps(profile),))
                conn.executemany(
                    "INSERT INTO articles "
                    "(id, url, title, source, feed_summary, published_ts, fetched_ts, source_topics) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", ordered_fixture(articles, order),
                )
                conn.executemany(
                    "INSERT INTO interest_nodes "
                    "(term, scope, weight, expires_ts, origin, created_ts, updated_ts) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?)", ordered_fixture(nodes, order),
                )
                conn.executemany(
                    "INSERT INTO curation_terms "
                    "(term, short_weight, long_weight, updated_ts, signal_count) "
                    "VALUES (?, 0.1, 0.0, ?, 1)",
                    ordered_fixture([("keyword:quartz", NOW), ("topic:science", NOW)], order),
                )
            conn.close()
            with mock.patch.object(backend, "source_catalog", return_value=ordered_fixture(sources, order)):
                feed, stats = backend.ranked_articles(14)
                query, query_stats = backend.ranked_articles(14, query="quartz")
                with mock.patch.object(backend, "MAX_RANK_CANDIDATES", 45):
                    bounded, bounded_stats = backend.ranked_articles(14)
            return {
                "feed": feed, "stats": stats, "query": query, "query_stats": query_stats,
                "bounded": bounded, "bounded_stats": bounded_stats,
            }


class RankingTests(unittest.TestCase):
    def setUp(self):
        self.backend = load_backend()

    def select(self, items, limit, personalized=False, discovery_percent=25, has_query=False):
        return self.backend.select_ranked_variant(
            items, limit, "score", "_components", "reason", "_discovery",
            personalized, discovery_percent, has_query,
        )

    def test_equal_score_and_date_use_identity_after_score_and_recency(self):
        items = [candidate("b"), candidate("a"), candidate("older", published=NOW - 1),
                 candidate("higher", score=6, published=NOW - 10)]
        for permutation in itertools.permutations(items):
            selected, _ = self.select(list(permutation), 4)
            self.assertEqual([item["id"] for item in selected], ["higher", "a", "b", "older"])

    def test_diversity_considers_strongest_repeats_with_existing_dimension_caps(self):
        item = candidate(
            "a", score=20, _topics={"a", "b", "c", "d"},
            _regions={"global", "a", "b", "c"}, _types={"a", "b", "c", "d"},
        )
        utility = self.backend._selection_utility(
            item, {}, {"a": 1, "b": 2, "c": 3, "d": 4},
            {"global": 100, "a": 1, "b": 2, "c": 3},
            {"a": 1, "b": 2, "c": 3, "d": 4}, 2, 0.0,
        )
        self.assertAlmostEqual(utility, 20 - (4 + 3 + 2) * 0.18 - (3 + 2) * 0.10 - (4 + 3 + 2) * 0.035)

    def test_diversity_retains_source_penalty(self):
        selected, _ = self.select([
            candidate("a", score=10, source="Shared"),
            candidate("b", score=9.9, source="Shared"),
            candidate("c", score=9.7, source="Other"),
        ], 2)
        self.assertEqual([item["id"] for item in selected], ["a", "c"])

    def test_diversity_pool_boundary_is_stable_and_does_not_mutate_input(self):
        items = [candidate(identity) for identity in "dcba"]
        original = deepcopy(items)
        with mock.patch.object(self.backend, "DIVERSITY_POOL_MIN", 2), \
             mock.patch.object(self.backend, "DIVERSITY_POOL_FACTOR", 1):
            selected = self.backend.diverse_selection(items, 2)
        self.assertEqual([item["id"] for item in selected], ["a", "b"])
        self.assertEqual(items, original)

    def test_cluster_representative_members_and_coverage_ties_are_stable(self):
        features = self.backend.event_features("Harbor lantern festival opening weekend")
        items = [candidate(identity, _event_features=features) for identity in "cba"]
        for permutation in itertools.permutations(items):
            clustered, collapsed = self.backend.cluster_articles(deepcopy(list(permutation)))
            self.assertEqual(collapsed, 2)
            self.assertEqual(len(clustered), 1)
            representative = clustered[0]
            self.assertEqual(representative["id"], "a")
            self.assertEqual(representative["cluster_ids"], ["a", "b", "c"])
            self.assertEqual(representative["coverage_sources"], ["Source a", "Source b", "Source c"])
            self.assertEqual([item["id"] for item in representative["related_articles"]], ["b", "c"])
            self.assertEqual(representative["score"], 6.9)

    def test_equally_similar_bridge_joins_same_cluster_in_every_input_order(self):
        left = {"amber", "birch", "cedar", "drift"}
        right = {"ember", "fjord", "glade", "hazel"}
        items = [candidate("a", _event_features=(left, set())),
                 candidate("b", _event_features=(right, set())),
                 candidate("c", score=4, _event_features=(left | right, set()))]
        for permutation in itertools.permutations(items):
            clusters, collapsed = self.backend.cluster_articles(deepcopy(list(permutation)))
            self.assertEqual(collapsed, 1)
            self.assertEqual([item["cluster_ids"] for item in clusters], [["a", "c"], ["b"]])

    def test_cluster_respects_time_window_and_member_limit(self):
        features = self.backend.event_features("Harbor lantern festival opening weekend")
        items = [candidate("old", _event_features=features,
                           published=NOW - self.backend.EVENT_CLUSTER_WINDOW_SECONDS - 1)]
        items += [candidate(f"new-{index:02d}", _event_features=features)
                  for index in range(self.backend.MAX_CLUSTER_ARTICLES + 3)]
        clustered, collapsed = self.backend.cluster_articles(items)
        self.assertEqual(len(clustered), 2)
        self.assertEqual(collapsed, self.backend.MAX_CLUSTER_ARTICLES + 2)
        self.assertEqual(clustered[0]["cluster_ids"],
                         [f"new-{index:02d}" for index in range(self.backend.MAX_CLUSTER_ARTICLES)])
        self.assertEqual(clustered[1]["cluster_ids"], ["old"])

    def test_discovery_quota_preserves_must_see_and_alert_stories(self):
        items = [candidate("must", score=20, _must=True), candidate("alert", score=19, _alert=True),
                 candidate("chosen", score=18), candidate("discovery", score=2, _discovery=True)]
        before = deepcopy(items)
        selected, target = self.select(items, 3, personalized=True, discovery_percent=100)
        self.assertEqual(target, 3)
        self.assertEqual([item["id"] for item in selected], ["must", "alert", "discovery"])
        self.assertEqual(items, before)

    def test_discovery_lane_does_not_replace_query_results_or_unpersonalized_feed(self):
        items = [candidate("chosen", score=20), candidate("discovery", score=2, _discovery=True)]
        for personalized, has_query in [(True, True), (False, False)]:
            selected, target = self.select(items, 1, personalized=personalized,
                                           discovery_percent=100, has_query=has_query)
            self.assertEqual(target, 0)
            self.assertEqual([item["id"] for item in selected], ["chosen"])

    def test_empty_candidates_and_zero_limit(self):
        self.assertEqual(self.select([], 15), ([], 0))
        self.assertEqual(self.select([candidate("a")], 0), ([], 0))

    def test_tied_interest_and_memory_limits_ignore_insertion_order(self):
        snapshots = []
        for order in ("forward", "reverse", "shuffle"):
            with tempfile.TemporaryDirectory() as directory:
                isolate_backend(self.backend, directory)
                conn = self.backend.db()
                with conn:
                    conn.executemany(
                        "INSERT INTO curation_terms VALUES (?, 1, 0, ?, 1)",
                        ordered_fixture([(f"keyword:term-{index:03d}", NOW) for index in range(245)], order),
                    )
                    conn.executemany(
                        "INSERT INTO curation_sources VALUES (?, 1, 0, ?, 1)",
                        ordered_fixture([(f"Source {index:03d}", NOW) for index in range(205)], order),
                    )
                    nodes = [(f"keyword:term-{index:03d}", scope, 2, None, "article-feedback", NOW, NOW)
                             for index in range(3) for scope in ("lasting", "temporary")]
                    conn.executemany("INSERT INTO interest_nodes VALUES (?, ?, ?, ?, ?, ?, ?)",
                                     ordered_fixture(nodes, order))
                snapshots.append((
                    list(self.backend.profile_weights(conn, NOW)),
                    list(self.backend.source_profile_weights(conn, NOW)),
                    self.backend.active_interest_nodes(conn, NOW),
                ))
                conn.close()
        self.assertEqual(len(snapshots[0][0]), 240)
        self.assertEqual(len(snapshots[0][1]), 200)
        self.assertEqual(snapshots[0], snapshots[1])
        self.assertEqual(snapshots[0], snapshots[2])

    def test_frozen_feed_is_identical_across_hash_seeds_and_database_orders(self):
        baseline = None
        for seed, order in itertools.product(("1", "2", "3", "41"), ("forward", "reverse", "shuffle")):
            with self.subTest(hash_seed=seed, insertion_order=order):
                env = dict(os.environ, PYTHONHASHSEED=seed, PYTHONDONTWRITEBYTECODE="1")
                run = subprocess.run(
                    [sys.executable, str(Path(__file__).resolve()), "--snapshot", order],
                    check=True, capture_output=True, text=True, env=env, timeout=30,
                )
                snapshot = json.loads(run.stdout)
                if baseline is None:
                    baseline = snapshot
                    self.assertEqual(len(snapshot["feed"]), 14)
                    self.assertEqual(snapshot["stats"]["candidate_rows"], 160)
                    self.assertEqual(snapshot["stats"]["duplicates_collapsed"], 2)
                    self.assertEqual(snapshot["bounded_stats"]["candidate_rows"], 45)
                    self.assertEqual(snapshot["query_stats"]["discovery_target"], 0)
                    self.assertGreaterEqual(
                        sum(item["reason"] == "outside your usual mix" for item in snapshot["feed"]),
                        snapshot["stats"]["discovery_target"],
                    )
                self.assertEqual(snapshot, baseline)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--snapshot":
        print(json.dumps(ranking_snapshot(sys.argv[2]), sort_keys=True))
    else:
        unittest.main()
