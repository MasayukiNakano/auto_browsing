#!/usr/bin/env python3
"""Extract Bloomberg article metadata/body from a saved HTML file."""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path


NEXT_DATA_PATTERN = re.compile(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    re.DOTALL | re.IGNORECASE,
)


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
    return {
        "title": story.get("headline"),
        "dek": story.get("dek"),
        "url": story.get("url"),
        "twitterTitle": story.get("twitterTitle"),
        "twitterDescription": story.get("twitterDescription"),
        "paragraphs": paragraphs,
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
