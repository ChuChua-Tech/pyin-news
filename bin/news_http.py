"""Bounded public-web GETs with DNS and peer checks on every connection/hop.

No proxy environment, cookie jar, credentials, automatic redirects or hostname
re-resolution at connect time. Local AI has a separate, explicitly local path.
"""
from __future__ import annotations

import http.client
import ipaddress
import socket
import ssl
import time
import urllib.error
import urllib.parse


def global_address(value: str):
    if "%" in value:
        raise ValueError("scoped addresses are not public web targets")
    address = ipaddress.ip_address(value)
    if (not address.is_global or address.is_multicast or address.is_reserved
            or address.is_loopback or address.is_link_local or address.is_unspecified):
        raise ValueError("web target is not a public global address")
    if isinstance(address, ipaddress.IPv6Address) and (
        address.ipv4_mapped or address.sixtofour or address.teredo
        or address in ipaddress.ip_network("64:ff9b::/96")
    ):
        raise ValueError("translated addresses are not public web targets")
    return address


def public_url(value: str) -> str:
    if not isinstance(value, str) or not value or len(value) > 8192:
        raise ValueError("invalid web URL")
    if any(ord(c) <= 32 or ord(c) == 127 for c in value) or "\\" in value:
        raise ValueError("invalid characters in web URL")
    parsed = urllib.parse.urlsplit(value)
    if (parsed.scheme not in ("http", "https") or not parsed.hostname
            or parsed.username is not None or parsed.password is not None
            or parsed.port not in (None, 80, 443)):
        raise ValueError("only public HTTP(S) URLs on standard ports are supported")
    host = parsed.hostname.encode("idna").decode("ascii").lower()
    if "%" in host or host.rstrip(".") == "localhost" or host.rstrip(".").endswith(".localhost"):
        raise ValueError("web target is not public")
    try:
        ipaddress.ip_address(host)
    except ValueError:
        pass  # Names and alternative numeric forms are checked after resolution.
    else:
        global_address(host)
    authority = "[" + host + "]" if ":" in host else host
    if parsed.port is not None:
        authority += ":" + str(parsed.port)
    return urllib.parse.urlunsplit((parsed.scheme, authority, parsed.path or "/", parsed.query, ""))


def checked_peer(sock, expected) -> None:
    peer = global_address(sock.getpeername()[0])
    if peer != expected:
        raise ValueError("connected peer differs from the validated web target")


def get(url: str, max_bytes: int, *, timeout: float = 14,
        headers: dict[str, str] | None = None) -> tuple[bytes, object, int]:
    """Fetch one public resource, checking all redirects before sending bytes."""
    deadline = time.monotonic() + timeout

    def remaining():
        value = deadline - time.monotonic()
        if value <= 0:
            raise TimeoutError("public web request deadline")
        return min(value, 5)

    for hop in range(6):
        url = public_url(url)
        parsed = urllib.parse.urlsplit(url)
        host = parsed.hostname
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        remaining()
        addresses = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
        if not addresses:
            raise ValueError("web host has no public address")
        # Reject mixed public/private answers; do not merely pick a public one.
        validated = [(entry, global_address(entry[4][0])) for entry in addresses]
        sock = None
        error = None
        for (family, kind, protocol, _, endpoint), expected in validated[:16]:
            if family not in (socket.AF_INET, socket.AF_INET6) or kind != socket.SOCK_STREAM:
                raise ValueError("unsupported web address family")
            candidate = socket.socket(family, kind, protocol)
            try:
                candidate.settimeout(remaining())
                # endpoint is the numeric sockaddr returned by the checked DNS
                # lookup. socket.connect performs no second hostname lookup.
                candidate.connect(endpoint)
                checked_peer(candidate, expected)
                if parsed.scheme == "https":
                    candidate = ssl.create_default_context().wrap_socket(candidate, server_hostname=host)
                    checked_peer(candidate, expected)
                sock = candidate
                break
            except ValueError:
                candidate.close()
                # Security-policy failures never fall through to another IP.
                raise
            except OSError as exc:
                candidate.close()
                error = exc
        if sock is None:
            raise OSError("could not connect to a public web address") from error
        connection = http.client.HTTPConnection(host, port, timeout=timeout)
        connection.auto_open = 0  # Never fall back to an unchecked reconnect.
        connection.sock = sock
        response = None
        try:
            request_headers = {k: v for k, v in (headers or {}).items()
                               if k.lower() in {"user-agent", "accept", "if-none-match", "if-modified-since"}}
            request_headers.update({"Host": parsed.netloc, "Accept-Encoding": "identity", "Connection": "close"})
            target = urllib.parse.urlunsplit(("", "", parsed.path or "/", parsed.query, ""))
            sock.settimeout(remaining())
            connection.request("GET", target, headers=request_headers)
            response = connection.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader("Location")
                if (not location or hop == 5 or "\\" in location
                        or any(ord(c) <= 32 or ord(c) == 127 for c in location)):
                    raise ValueError("invalid or excessive web redirects")
                url = urllib.parse.urljoin(url, location)
                continue
            if response.status == 304:
                return b"", response.headers, 304
            if response.status != 200:
                raise urllib.error.HTTPError(url, response.status, response.reason, response.headers, None)
            length = response.getheader("Content-Length")
            if length is not None and (int(length) < 0 or int(length) > max_bytes):
                raise ValueError("response exceeded size limit")
            chunks = []
            size = 0
            while size <= max_bytes:
                # HTTPConnection may close its socket handle after reading a
                # Connection: close response. The response's file still owns
                # the connection and retains the bounded socket timeout.
                remaining()
                chunk = response.read1(min(65536, max_bytes + 1 - size))
                if not chunk:
                    break
                chunks.append(chunk)
                size += len(chunk)
            if size > max_bytes:
                raise ValueError("response exceeded size limit")
            return b"".join(chunks), response.headers, response.status
        finally:
            if response is not None:
                response.close()
            connection.close()
            sock.close()
    raise ValueError("too many web redirects")
