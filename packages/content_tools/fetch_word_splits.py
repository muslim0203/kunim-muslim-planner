"""Works out how the printed page groups the words of an ayah.

Almost everywhere, one space-separated word of the Tanzil text is one word on
the printed page. In a handful of ayahs the mushaf writes two of them joined,
so the page has one token fewer, and a reader laying the page out word by word
would drift by one for the rest of the line.

This script asks the layout source for those ayahs' own words and records how
many text words each printed token covers. Nothing about the text changes:
the tokens are the same letters in the same order, only grouped as the print
groups them.

Usage:
    python fetch_word_splits.py --text .sources/quran-uthmani.txt \
        --keys 2:181 8:6 13:37 37:130 --out .sources/word-splits.json
"""

from __future__ import annotations

import argparse
import json
import urllib.request
from pathlib import Path

ENDPOINT = "https://api.quran.com/api/v4/verses/by_key/{key}?words=true&word_fields=text_uthmani"
USER_AGENT = "kunim-content-tools (github.com/muslim0203/kunim-muslim-planner)"


def letters(text: str) -> str:
    """The bare letters of a word: vowel marks, pause signs and the other
    Qur'anic annotations are dropped, because the two sources differ in which
    of them they carry. Only used for comparing; nothing is stored this way."""
    return "".join(
        char
        for char in text
        if not ("ً" <= char <= "ٟ")
        and not ("ۖ" <= char <= "ۭ")
        and not ("ؐ" <= char <= "ؚ")
        and char not in "ٰـ"
        and not char.isspace()
    )


def text_words(path: Path) -> dict[str, list[str]]:
    words: dict[str, list[str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        surah, number, text = line.split("|", 2)
        words[f"{surah}:{number}"] = text.split()
    return words


def printed_words(key: str) -> list[str]:
    request = urllib.request.Request(ENDPOINT.format(key=key), headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        verse = json.load(response)["verse"]
    # `text_uthmani`, not `text`: the default field is the glyph encoding of
    # the print's own font, which is not the Unicode text we compare against.
    return [word["text_uthmani"] for word in verse["words"] if word["char_type_name"] == "word"]


def group(key: str, words: list[str], printed: list[str]) -> list[int]:
    """How many text words each printed token covers, in order."""
    counts: list[int] = []
    index = 0
    for token in printed:
        wanted = letters(token)
        taken = ""
        covered = 0
        while index < len(words) and letters(taken) != wanted:
            taken += words[index]
            index += 1
            covered += 1
        if letters(taken) != wanted:
            raise SystemExit(f"{key}: printed token {token!r} is not in the text")
        counts.append(covered)
    if index != len(words):
        raise SystemExit(f"{key}: {len(words) - index} text words left over")
    return counts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--text", required=True, type=Path)
    parser.add_argument("--keys", required=True, nargs="+")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    words = text_words(args.text)
    splits: dict[str, list[int]] = {}
    for key in args.keys:
        if key not in words:
            raise SystemExit(f"{key} is not an ayah")
        counts = group(key, words[key], printed_words(key))
        splits[key] = counts
        joined = [n for n in counts if n > 1]
        print(f"{key}: {len(counts)} printed tokens, {len(joined)} of them joined")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(splits, indent=2), encoding="utf-8")
    print(f"{args.out} written")


if __name__ == "__main__":
    main()
