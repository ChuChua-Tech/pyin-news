import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]


def load_json(name):
    with (ROOT / name).open(encoding="utf-8") as handle:
        return json.load(handle)


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


if __name__ == "__main__":
    unittest.main()
