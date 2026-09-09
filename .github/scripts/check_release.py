"""Validate both the installed Git tree and the independently exported package."""

import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[2]
# Omarchy installs the repository, not just git archive. Only these application,
# documentation and CI files, plus executable test fixtures, belong in that tree.
# New runtime paths require an explicit review of this list. Agent-discoverable
# instructions/configuration and arbitrary Markdown are deliberately excluded.
PACKAGE_FILES = frozenset("""
.gitattributes .gitignore .github/scripts/check_release.py .github/workflows/validate.yml
AboutPage.qml AiModelPicker.qml App.qml ArticleImageCache.qml BarWidget.qml
DailyEditionPage.qml EventDeskPage.qml FeedProbe.qml JournalismLoader.qml
PaperBackground.qml ProfilePage.qml PyinMasthead.qml ReadingPreferences.qml
SetupWizard.qml SourceHealthSection.qml StoryThumbnail.qml Reading.js
CHANGELOG.md CONTRIBUTING.md LICENSE NOTICE.md README.md RELEASING.md
assets/pyin-news.svg assets/summary-format.json
bin/chuchua-news bin/news_ai.py bin/news_http.py bin/news_images.py
manifest.json preview.png source-catalog.json sources.json tests/native_ai_contract.py
""".split())
PACKAGE_DIRECTORIES = {str(parent) for name in PACKAGE_FILES for parent in PurePosixPath(name).parents}


def validate_package_file(name: str) -> None:
    path = PurePosixPath(name)
    normalized = str(path) == name and not path.is_absolute() and ".." not in path.parts
    test_file = re.fullmatch(r"tests/test_[a-z0-9_]+\.(?:py|cjs)", name) is not None
    if not normalized or (name not in PACKAGE_FILES and not test_file):
        raise ValueError(f"Unapproved release path: {name}")


def validate_git_tree(root: Path, ref: str = "HEAD") -> list[str]:
    # Check before exporting: export-ignore must not conceal an installed file.
    records = subprocess.check_output(
        ["git", "ls-tree", "-r", "--full-tree", "-z", ref], cwd=root
    ).decode("utf-8").split("\0")
    names = []
    for record in filter(None, records):
        header, name = record.split("\t", 1)
        mode, kind, _oid = header.split()
        if mode not in {"100644", "100755"} or kind != "blob":
            raise ValueError(f"Non-regular file in release tree: {name}")
        validate_package_file(name)
        names.append(name)
    return names


def validate_archive(source: tarfile.TarFile) -> None:
    for member in source.getmembers():
        if member.isfile():
            validate_package_file(member.name)
        elif member.isdir() and member.name.rstrip("/") in PACKAGE_DIRECTORIES:
            continue
        else:
            raise ValueError(f"Non-package entry in release archive: {member.name}")


def main() -> None:
    manifest = json.loads((ROOT / "manifest.json").read_text())
    version = manifest["version"]
    ref = os.environ.get("GITHUB_REF", "")
    if ref.startswith("refs/tags/") and ref != f"refs/tags/v{version}":
        raise SystemExit(f"Release tag {ref} does not match manifest version {version}")
    validate_git_tree(ROOT)
    with tempfile.TemporaryDirectory(prefix="pyin-release-") as directory:
        base = Path(directory)
        archive = base / "package.tar"
        subprocess.run(["git", "archive", "HEAD", "-o", str(archive)], cwd=ROOT, check=True)
        package = base / "package"
        with tarfile.open(archive) as source:
            validate_archive(source)
            source.extractall(package, filter="data")
        archived = json.loads((package / "manifest.json").read_text())
        if archived["version"] != version:
            raise SystemExit("Working version differs from committed release archive")
        env = os.environ.copy()
        for kind in ("CONFIG", "STATE", "CACHE"):
            env[f"XDG_{kind}_HOME"] = str(base / kind.lower())
        backend = package / "bin" / "chuchua-news"
        for command in ("doctor", "bootstrap"):
            result = subprocess.run(
                [sys.executable, str(backend), command], env=env,
                check=True, capture_output=True, text=True, timeout=30,
            )
            payload = json.loads(result.stdout)
            if payload.get("ok") is not True:
                raise SystemExit(f"Exported package failed {command}: {payload}")
        # Bootstrap doesn't summarize. Exercise the archived data loader too,
        # without network, inference or the checkout's local-only files.
        probe = """from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import sys
loader = SourceFileLoader('exported_news', sys.argv[1])
spec = spec_from_loader(loader.name, loader)
module = module_from_spec(spec)
loader.exec_module(module)
module.summary_format()
"""
        subprocess.run([sys.executable, "-c", probe, str(backend)], env=env, check=True, timeout=30)
        print(f"v{version}: installed tree and archive pass package policy, empty-profile startup and summary format checks")


if __name__ == "__main__":
    main()
