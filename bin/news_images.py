"""Feed image discovery and bounded, on-demand raster caching (standard library)."""
from __future__ import annotations

import fcntl
import hashlib
from html.parser import HTMLParser
import http.client
import ipaddress
from pathlib import Path
import socket
import ssl
import struct
import tempfile
import time
import urllib.parse

MEDIA = "{http://search.yahoo.com/mrss/}"
MAX_BYTES = 2 * 1024 * 1024
MAX_PIXELS = 12_000_000
CACHE_BYTES = 32 * 1024 * 1024
CACHE_FILES = 128
CACHE_AGE = 7 * 86400
FAILURE_AGE = 3600


def image_url(value: str, base: str = "") -> str:
    """Resolve relative references without rewriting signed CDN query strings."""
    try:
        value = str(value or "").strip()
        if len(value) > 4096 or any(ord(c) < 32 for c in value):
            return ""
        parsed = urllib.parse.urlsplit(urllib.parse.urljoin(base, value))
        if not value or parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.password:
            return ""
        if parsed.port not in (None, 80, 443):
            return ""
        return urllib.parse.urlunsplit(parsed._replace(fragment=""))
    except ValueError:
        return ""


def useful_size(attrs: dict) -> bool:
    for name in ("width", "height"):
        try:
            if attrs.get(name) and float(str(attrs[name]).removesuffix("px")) < 40:
                return False
        except ValueError:
            pass
    return True


class FeedImages(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.urls: list[str] = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "img" and useful_size(values) and len(self.urls) < 8:
            self.urls.append(values.get("src") or values.get("data-src") or "")


def extract_image(entry, summary: str, base: str) -> str:
    candidates = []
    elements = list(entry.iter())
    for node in elements:
        if node.tag == MEDIA + "thumbnail" and useful_size(node.attrib):
            candidates.append(node.get("url", ""))
    for node in elements:
        if (node.tag == MEDIA + "content" and
                (node.get("medium") == "image" or node.get("type", "").startswith("image/")
                 or (not node.get("medium") and not node.get("type")
                     and urllib.parse.urlsplit(image_url(node.get("url", ""), base)).path.lower().endswith((".jpg", ".jpeg", ".png", ".webp"))))):
            if useful_size(node.attrib):
                candidates.append(node.get("url", ""))
        elif node.tag.rsplit("}", 1)[-1] in ("enclosure", "link") and node.get("type", "").startswith("image/"):
            if node.tag.endswith("enclosure") or node.get("rel") == "enclosure":
                candidates.append(node.get("url") or node.get("href") or "")
        elif node.tag.rsplit("}", 1)[-1] == "img" and useful_size(node.attrib):
            candidates.append(node.get("src", ""))
    parser = FeedImages()
    try:
        parser.feed(str(summary or "")[:100_000])
    except (ValueError, AssertionError):
        pass  # Malformed optional image markup must not break the story feed.
    candidates.extend(parser.urls)
    for candidate in candidates:
        result = image_url(candidate, base)
        if result:
            return result
    return ""


def raster_size(data: bytes) -> tuple[int, int]:
    """Read raster dimensions before handing any bytes to the UI decoder."""
    if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24 and data[12:16] == b"IHDR":
        # Animated images are deliberately excluded.
        if b"acTL" in data:
            raise ValueError("animated image")
        return struct.unpack(">II", data[16:24])
    if data.startswith(b"\xff\xd8"):
        offset = 2
        while offset + 4 <= len(data):
            if data[offset] != 255:
                raise ValueError("invalid JPEG marker")
            while offset < len(data) and data[offset] == 255:
                offset += 1
            if offset >= len(data):
                break
            marker = data[offset]; offset += 1
            if marker in (0xD9, 0xDA):
                break
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                continue
            length = int.from_bytes(data[offset:offset + 2], "big")
            if length < 2 or offset + length > len(data):
                break
            if marker in (0xC0, 0xC1, 0xC2) and length >= 8:
                height, width = struct.unpack(">HH", data[offset + 3:offset + 7])
                return width, height
            offset += length
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP" and len(data) >= 30:
        kind = data[12:16]
        if kind == b"VP8X":
            if data[20] & 2:
                raise ValueError("animated image")
            return 1 + int.from_bytes(data[24:27], "little"), 1 + int.from_bytes(data[27:30], "little")
        if kind == b"VP8 " and data[23:26] == b"\x9d\x01\x2a":
            return int.from_bytes(data[26:28], "little") & 0x3FFF, int.from_bytes(data[28:30], "little") & 0x3FFF
        if kind == b"VP8L" and data[20] == 0x2F:
            bits = int.from_bytes(data[21:25], "little")
            return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    raise ValueError("unsupported raster image")


def download_image(url: str) -> bytes:
    deadline = time.monotonic() + 10
    for _ in range(5):
        url = image_url(url)
        if not url:
            raise ValueError("invalid image URL")
        parsed = urllib.parse.urlsplit(url)
        host = parsed.hostname.encode("idna").decode("ascii")
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        addresses = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
        if not addresses or any(not ipaddress.ip_address(a[4][0]).is_global for a in addresses):
            raise ValueError("image host is not public")
        timeout = max(0.1, min(4, deadline - time.monotonic()))
        if time.monotonic() >= deadline:
            raise TimeoutError("image deadline")
        # Connect to the checked address, not a second DNS lookup. Retain the
        # publisher hostname for TLS verification and the HTTP Host header.
        sock = socket.create_connection(addresses[0][4][:2], timeout=timeout)
        connection_type = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
        connection = connection_type(host, port, timeout=timeout)
        try:
            if parsed.scheme == "https":
                sock = ssl.create_default_context().wrap_socket(sock, server_hostname=host)
            connection.sock = sock
            target = urllib.parse.urlunsplit(("", "", parsed.path or "/", parsed.query, ""))
            connection.request("GET", target, headers={
                "User-Agent": "PYIN-News/0.24.0", "Accept": "image/jpeg,image/png,image/webp",
                "Accept-Encoding": "identity",
            })
            response = connection.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                url = image_url(response.getheader("Location", ""), url)
                continue
            if response.status != 200:
                raise ValueError("image unavailable")
            if int(response.getheader("Content-Length", "0")) > MAX_BYTES:
                raise ValueError("image too large")
            chunks = []; size = 0
            while size <= MAX_BYTES:
                if time.monotonic() >= deadline:
                    raise TimeoutError("image deadline")
                sock.settimeout(max(0.1, min(4, deadline - time.monotonic())))
                chunk = response.read1(min(65536, MAX_BYTES + 1 - size))
                if not chunk:
                    break
                chunks.append(chunk); size += len(chunk)
            if size > MAX_BYTES:
                raise ValueError("image too large")
            return b"".join(chunks)
        finally:
            connection.close()
            sock.close()
    raise ValueError("too many image redirects")


def prune_cache(directory: Path, now: float) -> None:
    files = []
    for path in directory.iterdir():
        if path.name.startswith(".image-"):
            path.unlink(missing_ok=True)
            continue
        if path.suffix not in (".img", ".miss"):
            continue
        stat = path.stat()
        age = FAILURE_AGE if path.suffix == ".miss" else CACHE_AGE
        if now - stat.st_mtime >= age:
            path.unlink(missing_ok=True)
        else:
            files.append((stat.st_mtime, stat.st_size, path))
    total = sum(f[1] for f in files)
    # Reserve one download, so limits also hold immediately after writing.
    while files and (total > CACHE_BYTES - MAX_BYTES or len(files) >= CACHE_FILES):
        oldest = min(files); files.remove(oldest)
        total -= oldest[1]; oldest[2].unlink(missing_ok=True)


def cached_image(url: str, directory: Path) -> str:
    url = image_url(url)
    if not url:
        return ""
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    identity = hashlib.sha256(url.encode()).hexdigest()
    target = directory / (identity + ".img")
    failed = directory / (identity + ".miss")
    # One downloader across windows/processes; a busy cache is a quiet fallback.
    with (directory / ".lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return ""
        now = time.time()
        prune_cache(directory, now)
        if target.is_file():
            return target.resolve().as_uri()
        if failed.exists():
            return ""
        temporary = None
        try:
            data = download_image(url)
            width, height = raster_size(data)
            if not (40 <= width <= 6000 and 40 <= height <= 6000 and width * height <= MAX_PIXELS):
                raise ValueError("unsuitable image dimensions")
            if len(data) > MAX_BYTES:
                raise ValueError("image too large")
            with tempfile.NamedTemporaryFile(dir=directory, prefix=".image-", delete=False) as out:
                temporary = Path(out.name)
                out.write(data)
            temporary.replace(target)
            return target.resolve().as_uri()
        except (OSError, ValueError, http.client.HTTPException):
            failed.touch(mode=0o600)
            return ""
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)
