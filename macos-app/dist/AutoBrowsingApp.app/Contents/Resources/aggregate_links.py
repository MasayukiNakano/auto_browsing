#!/usr/bin/env python3
"""Aggregate per-site link Parquet files while removing duplicates.

Example:
    $ python scripts/aggregate_links.py --base links-output

This script keeps only the most recent record per URL and writes one Parquet
file per site under ``<base>/aggregated`` by default.
"""

from __future__ import annotations

import argparse
import logging
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import pandas as pd

Log = logging.getLogger(__name__)

# Columns that may appear in link parquet files. They are filtered explicitly
# to avoid loading unused data into memory.
BASE_COLUMNS: tuple[str, ...] = ("siteId", "pageUrl", "href", "text")
OPTIONAL_COLUMNS: tuple[str, ...] = ("publishedAt", "timestampMillis")


@dataclass
class AggregationStats:
    """Simple struct to report what happened during aggregation."""

    files_processed: int = 0
    rows_read: int = 0
    rows_written: int = 0
    sites_written: int = 0


def find_parquet_files(base: Path) -> Iterable[Path]:
    """Yield sorted parquet files under ``base``."""

    if not base.exists():
        Log.warning("Base directory %s does not exist", base)
        return []
    return sorted(p for p in base.glob("*.parquet") if p.is_file())


def sanitize_site_name(raw: object) -> str:
    """Convert any site identifier into a safe file name."""

    value = str(raw) if raw is not None else "default"
    return "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in value) or "default"


def read_parquet(path: Path, *, columns: Sequence[str]) -> pd.DataFrame | None:
    """Read a parquet file safely, returning ``None`` on failure."""

    try:
        df = pd.read_parquet(path, columns=list(columns))
    except FileNotFoundError:
        Log.warning("Parquet file vanished while processing: %s", path)
        return None
    except Exception as exc:  # noqa: BLE001
        Log.error("Failed to read %s: %s", path, exc)
        return None

    required = {"siteId", "href"}
    if not required.issubset(df.columns):
        Log.warning("Skip %s: missing required columns %s", path, required)
        return None
    return df


def aggregate_directory(base: Path, output: Path, *, keep_timestamp: bool, dry_run: bool) -> AggregationStats:
    """Aggregate all parquet files under ``base`` and write per-site outputs."""

    stats = AggregationStats()
    files = list(find_parquet_files(base))
    if not files:
        Log.info("No parquet files found in %s", base)
        return stats

    desired_columns = list(BASE_COLUMNS)
    if keep_timestamp:
        desired_columns.append("timestampMillis")
    desired_columns.extend(col for col in OPTIONAL_COLUMNS if col not in desired_columns)

    site_frames: dict[object, list[pd.DataFrame]] = defaultdict(list)
    for path in files:
        stats.files_processed += 1
        df = read_parquet(path, columns=desired_columns)
        if df is None or df.empty:
            continue
        stats.rows_read += len(df)
        for site_id, group in df.groupby("siteId", dropna=False, sort=False):
            site_frames[site_id].append(group)

    if not site_frames:
        Log.info("No valid rows found in %d parquet files", stats.files_processed)
        return stats

    if not dry_run:
        output.mkdir(parents=True, exist_ok=True)

    for site_id, frames in site_frames.items():
        combined = pd.concat(frames, ignore_index=True)
        combined = combined.drop_duplicates(subset=["siteId", "href"], keep="last")

        columns = [col for col in BASE_COLUMNS if col in combined.columns]
        if "publishedAt" in combined.columns:
            columns.append("publishedAt")
        if keep_timestamp and "timestampMillis" in combined.columns:
            columns.append("timestampMillis")

        sanitized = sanitize_site_name(site_id)
        target = output / f"{sanitized}.parquet"
        stats.rows_written += len(combined)
        stats.sites_written += 1

        if dry_run:
            Log.info("[dry-run] Would write %s (%d rows)", target, len(combined))
        else:
            combined[columns].to_parquet(target, index=False)
            Log.info("Wrote %s (%d rows)", target, len(combined))

    return stats


def build_parser() -> argparse.ArgumentParser:
    """Create the CLI argument parser."""

    parser = argparse.ArgumentParser(
        description="Aggregate link parquet files",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--base", type=Path, default=Path("links-output"), help="Input directory containing parquet files.")
    parser.add_argument("--output", type=Path, help="Output directory (defaults to <base>/aggregated).")
    parser.add_argument("--keep-timestamp", action="store_true", help="Retain the timestampMillis column when present.")
    parser.add_argument("--dry-run", action="store_true", help="Scan and report without writing output files.")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging.")
    return parser


def configure_logging(verbose: bool) -> None:
    """Configure root logging based on verbosity."""

    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format="%(levelname)s %(message)s")


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    configure_logging(args.verbose)
    base = args.base
    output = args.output or (base / "aggregated")

    stats = aggregate_directory(base, output, keep_timestamp=args.keep_timestamp, dry_run=args.dry_run)
    Log.info(
        "Processed %d file(s), read %d row(s), wrote %d row(s) across %d site(s)%s",
        stats.files_processed,
        stats.rows_read,
        stats.rows_written,
        stats.sites_written,
        " [dry-run]" if args.dry_run else "",
    )


if __name__ == "__main__":
    main()
