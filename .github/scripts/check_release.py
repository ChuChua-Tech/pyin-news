"""Check the committed release archive, independently of checkout-only files."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads((ROOT / "manifest.json").read_text())
version = manifest["version"]
ref = os.environ.get("GITHUB_REF", "")
if ref.startswith("refs/tags/") and ref != f"refs/tags/v{version}":
    raise SystemExit(f"Release tag {ref} does not match manifest version {version}")

with tempfile.TemporaryDirectory(prefix="pyin-release-") as directory:
    base = Path(directory)
    archive = base / "package.tar"
    subprocess.run(["git", "archive", "HEAD", "-o", str(archive)], cwd=ROOT, check=True)
    package = base / "package"
    with tarfile.open(archive) as source:
        forbidden = {"agents.md", "notes.md", "roadmap.md", ".env"}
        for member in source.getmembers():
            path = Path(member.name)
            if path.name.casefold() in forbidden or "__pycache__" in path.parts:
                raise SystemExit(f"Local-only file in release: {member.name}")
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
    print(f"v{version}: release archive passes empty-profile doctor and bootstrap")
