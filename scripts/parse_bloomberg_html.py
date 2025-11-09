#!/usr/bin/env python3
"""Extract Bloomberg article metadata/body from a saved HTML file."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import html
import json
import posixpath
import re
import sys
from pathlib import Path
from urllib.parse import parse_qsl, quote, unquote, urlencode, urlsplit, urlunsplit


NEXT_DATA_PATTERN = re.compile(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    re.DOTALL | re.IGNORECASE,
)
ID_SCHEME = "url-sha1@v1-canonical"
_UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
DROP_KEYS = {
    "gclid",
    "fbclid",
    "igshid",
    "ref",
    "ref_src",
    "spm",
}


def normalize_url_v1(url: str, *, drop_www: bool = True, default_scheme: str = "https") -> str:
    if not url:
        return ""
    u = url
    if "://" not in u:
        u = f"{default_scheme}://{u}"
    try:
        s = urlsplit(u)
    except Exception:
        return url.strip()
    scheme = (s.scheme or default_scheme).lower()

    host = (s.hostname or "").lower()
    try:
        host = host.encode("idna").decode("ascii")
    except Exception:
        pass
    if drop_www and host.startswith("www."):
        host = host[4:]

    port = s.port
    if (scheme == "http" and port == 80) or (scheme == "https" and port == 443):
        port = None

    auth = ""
    if s.username:
        auth = s.username
        if s.password:
            auth += f":{s.password}"
        auth += "@"

    netloc = auth + host + (f":{port}" if port else "")

    path = s.path or "/"
    path = quote(unquote(path), safe="/" + _UNRESERVED)
    try:
        path = posixpath.normpath(path)
    except Exception:
        path = s.path or "/"
    if not path.startswith("/"):
        path = "/" + path
    if path != "/" and path.endswith("/"):
        path = path[:-1]

    q_pairs = [
        (k, v)
        for k, v in parse_qsl(s.query, keep_blank_values=True)
        if k not in DROP_KEYS and not k.lower().startswith("utm_")
    ]
    q_pairs.sort()
    query = urlencode(q_pairs, doseq=True, quote_via=quote)

    return urlunsplit((scheme, netloc, path, query, ""))


def article_id_from_url(url: str) -> tuple[str, str]:
    canonical = normalize_url_v1(url)
    source = canonical or (url or "").strip()
    if not source:
        return "", canonical
    digest = hashlib.sha1(source.encode("utf-8")).hexdigest()
    return digest, canonical


def extract_next_data(payload: str) -> dict:
    match = NEXT_DATA_PATTERN.search(payload)
    if not match:
        raise ValueError("__NEXT_DATA__ block not found in HTML")
    json_text = html.unescape(match.group(1))
    try:
        return json.loads(json_text)
    except json.JSONDecodeError as exc:
        raise ValueError("Failed to decode __NEXT_DATA__ JSON") from exc


def extract_story(blob: dict) -> dict:
    try:
        story = blob["props"]["pageProps"]["story"]
    except KeyError as exc:
        raise ValueError("Story payload missing from __NEXT_DATA__ structure") from exc
    body_blocks = story.get("body", {}).get("content", [])
    paragraphs: list[str] = []
    for block in body_blocks:
        if block.get("type") != "paragraph":
            continue
        fragments = block.get("content", [])
        text = "".join(fragment.get("value", "") for fragment in fragments).strip()
        if text:
            paragraphs.append(text)
    raw_url = story.get("url") or ""
    article_id, canonical = article_id_from_url(raw_url)
    captured = dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    return {
        "title": story.get("headline"),
        "dek": story.get("dek"),
        "url": raw_url,
        "article_id": article_id,
        "id_scheme": ID_SCHEME,
        "publishedAt": story.get("publishedAt"),
        "capturedAt": captured,
        "paragraphs": paragraphs,
        "twitterTitle": story.get("twitterTitle"),
        "twitterDescription": story.get("twitterDescription"),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("html_path", type=Path, help="Path to saved Bloomberg HTML file")
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        help="Destination JSON file (defaults to <html_path>.parsed.json)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    html_text = args.html_path.read_text(encoding="utf-8")
    blob = extract_next_data(html_text)
    story = extract_story(blob)
    output_path = args.output or args.html_path.with_suffix(".parsed.json")
    output_path.write_text(
        json.dumps(story, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"Saved parsed data to {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
