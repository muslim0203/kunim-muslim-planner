"""Checks a built `quran.sqlite` before it ships.

`build_quran_db.py` validates what it builds, but the file that reaches a
device is the one committed to `apps/mobile/assets/db/`, which may have been
built months earlier on someone else's machine. This script is the gate on
that artifact: run in CI whenever the asset or the builders change.

Two kinds of check, and both matter for the same reason:

* Completeness -- 114 surahs, 6236 ayahs, 604 pages, 30 juz. A file that does
  not add up to those is a broken or partial download, not a Qur'an, and
  shipping it would show users a text with holes in it.
* Terms -- Tanzil permits verbatim copies provided the text is unchanged, the
  source is named and a link to tanzil.net is shown. Those facts live in the
  `meta` table so the app can display them, so a build that lost them cannot
  be shipped lawfully. The recorded `text_sha256` must also be present: it is
  what makes "unchanged" checkable at all.

Exits non-zero with every problem listed, rather than stopping at the first.

Usage:
    python verify_quran_db.py apps/mobile/assets/db/quran.sqlite
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

from build_quran_db import (
    ATTRIBUTION,
    AYAH_COUNT,
    JUZ_COUNT,
    PAGE_COUNT,
    SURAH_COUNT,
)

REQUIRED_TABLES = {"surahs", "ayahs", "pages", "juzs", "meta"}
REQUIRED_META = ("attribution", "license", "source_url", "edition", "text_sha256")


def verify(path: Path) -> list[str]:
    """Return a list of problems; empty means the database is shippable."""
    if not path.exists():
        return [f"{path} does not exist"]

    problems: list[str] = []
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        tables = {
            row[0]
            for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")
        }
        missing_tables = REQUIRED_TABLES - tables
        if missing_tables:
            # Without these there is nothing left to count.
            return [f"missing tables: {sorted(missing_tables)}"]

        counts = {
            "surahs": ("SELECT COUNT(*) FROM surahs", SURAH_COUNT),
            "ayahs": ("SELECT COUNT(*) FROM ayahs", AYAH_COUNT),
            "pages": ("SELECT COUNT(DISTINCT page) FROM ayahs", PAGE_COUNT),
            "juz": ("SELECT COUNT(DISTINCT juz) FROM ayahs", JUZ_COUNT),
        }
        for label, (query, expected) in counts.items():
            actual = connection.execute(query).fetchone()[0]
            if actual != expected:
                problems.append(f"{label}: found {actual}, expected {expected}")

        meta = dict(connection.execute("SELECT key, value FROM meta"))
        for key in REQUIRED_META:
            if not str(meta.get(key, "")).strip():
                problems.append(f"meta.{key} is missing or empty")

        if meta.get("attribution") != ATTRIBUTION:
            problems.append(
                f"meta.attribution is {meta.get('attribution')!r}, expected {ATTRIBUTION!r}"
            )
        if "tanzil.net" not in str(meta.get("source_url", "")):
            problems.append("meta.source_url does not point at tanzil.net")
    finally:
        connection.close()

    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path, help="path to quran.sqlite")
    args = parser.parse_args(argv)

    problems = verify(args.database)
    if problems:
        print(f"{args.database}: NOT shippable", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print(f"{args.database}: complete and carries its terms")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
