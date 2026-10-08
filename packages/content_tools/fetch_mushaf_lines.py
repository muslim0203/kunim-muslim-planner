"""Downloads the Madinah mushaf's line layout, page by page.

What this fetches is *where the print breaks its lines*: for each of the 604
pages, which tokens sit on which of the 15 lines. The Qur'an text itself is
not taken from here -- that stays the Tanzil file the database is built from.
Keeping the two apart is deliberate: the text has one source, and this only
says where the printed page puts each word of it.

A token is a word or the ayah-number marker that closes a verse; both carry a
position inside their ayah, so a line is a contiguous range of tokens.

Source: api.quran.com (public, no key), whose word data follows the King Fahd
Complex 15-line Madinah layout.

Usage:
    python fetch_mushaf_lines.py --out .sources/mushaf-lines.json
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

PAGE_COUNT = 604
ENDPOINT = (
    "https://api.quran.com/api/v4/verses/by_page/{page}"
    "?words=true&word_fields=line_number&per_page=50"
)
USER_AGENT = "kunim-content-tools (github.com/muslim0203/kunim-muslim-planner)"


def fetch_page(page: int, attempts: int = 4) -> list[dict]:
    """One page's tokens: `[{"key": "2:255", "pos": 3, "line": 4, "end": false}]`."""
    request = urllib.request.Request(ENDPOINT.format(page=page), headers={"User-Agent": USER_AGENT})
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                verses = json.load(response)["verses"]
            break
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            if attempt == attempts:
                raise SystemExit(f"page {page}: {error}") from error
            time.sleep(attempt * 2)
    else:  # pragma: no cover - the loop always breaks or raises
        raise SystemExit(f"page {page}: giving up")

    tokens: list[dict] = []
    for verse in verses:
        for word in verse["words"]:
            tokens.append(
                {
                    "key": verse["verse_key"],
                    "pos": word["position"],
                    "line": word["line_number"],
                    "end": word["char_type_name"] != "word",
                }
            )
    if not tokens:
        raise SystemExit(f"page {page} came back with no words")
    return tokens


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument(
        "--pause",
        type=float,
        default=0.2,
        help="seconds between requests, to stay a polite guest",
    )
    args = parser.parse_args()

    pages: dict[str, list[dict]] = {}
    for page in range(1, PAGE_COUNT + 1):
        pages[str(page)] = fetch_page(page)
        if page % 50 == 0 or page == PAGE_COUNT:
            print(f"  {page}/{PAGE_COUNT} pages", flush=True)
        time.sleep(args.pause)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(pages, separators=(",", ":")), encoding="utf-8")
    tokens = sum(len(value) for value in pages.values())
    size_mb = args.out.stat().st_size / 1024 / 1024
    print(f"{args.out}: {len(pages)} pages, {tokens} tokens, {size_mb:.1f} MB")


if __name__ == "__main__":
    main()
