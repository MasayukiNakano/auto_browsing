#!/usr/bin/env python3
"""Aggregate link Parquet files and drop duplicates.

This script scans the `links-output` directory for per-site Parquet files
(e.g. `bloomberg.parquet`) and produces de-duplicated datasets in
`links-output/aggregated/<siteId>.parquet`.

Requirements:
    pip install pandas pyarrow
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable

import pandas as pd


def find_parquet_files(base: Path) -> Iterable[Path]:
    if not base.exists():
        return []
    return sorted(p for p in base.glob("*.parquet") if p.is_file())


def aggregate(base: Path, output: Path, keep_timestamp: bool) -> None:
    files = list(find_parquet_files(base))
    if not files:
        print(f"No parquet files found in {base}")
        return

    output.mkdir(parents=True, exist_ok=True)

    frames = []
    for parquet in files:
        try:
            df = pd.read_parquet(parquet)
        except Exception as exc:  # noqa: BLE001
            print(f"Skip {parquet}: {exc}")
            continue
        if "siteId" not in df.columns or "href" not in df.columns:
            print(f"Skip {parquet}: required columns missing")
            continue
        frames.append(df)

    if not frames:
        print("No valid parquet files to process")
        return

    combined = pd.concat(frames, ignore_index=True)
    subset = ["siteId", "href"]
    combined = combined.drop_duplicates(subset=subset, keep="last")

    for site_id, group in combined.groupby("siteId", dropna=False):
        site = str(site_id) if pd.notna(site_id) else "default"
        sanitized = "".join(ch if ch.isalnum() or ch in ("_", "-", ".") else "_" for ch in site)
        target = output / f"{sanitized}.parquet"
        columns = ["siteId", "pageUrl", "href", "text"]
        if keep_timestamp and "timestampMillis" in group.columns:
            columns.append("timestampMillis")
        group[columns].to_parquet(target, index=False)
        print(f"Wrote {target} ({len(group)} rows)")


def main() -> None:
    parser = argparse.ArgumentParser(description="Aggregate link parquet files")
    parser.add_argument("--base", type=Path, default=Path("links-output"), help="input directory (default: links-output)")
    parser.add_argument("--output", type=Path, default=None, help="output directory (default: <base>/aggregated)")
    parser.add_argument("--keep-timestamp", action="store_true", help="retain timestamp column in the output")
    args = parser.parse_args()

    base = args.base
    output = args.output or (base / "aggregated")
    aggregate(base, output, args.keep_timestamp)


if __name__ == "__main__":
    main()
