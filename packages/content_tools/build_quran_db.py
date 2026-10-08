"""Builds `assets/db/quran.sqlite` from the Tanzil sources.

The Arabic text is copied verbatim, byte for byte, from Tanzil's Uthmani text
(`docs/content-policy.md`): this script never edits, normalises or re-orders a
single letter of it. Everything it adds is structure -- which ayah sits on
which page of the 604-page Madinah mushaf, which juz it belongs to, where the
sajdas are -- taken from Tanzil's own metadata.

Terms the built database carries with it (and the app shows in About):
Tanzil permits verbatim copies, requires that the text stay unchanged, that
the source (Tanzil Project) be named, and that a link to tanzil.net be shown.
Those three facts are written into the `meta` table, so a build can never be
shipped without them.

Usage:
    python build_quran_db.py --text quran-uthmani.txt \
        --meta quran-data.xml --out ../../apps/mobile/assets/db/quran.sqlite

Standard library only, so it runs with a bare Python and needs no venv.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

# What a complete, correct build looks like. A source file that does not add
# up to these is a broken download, not a Qur'an.
SURAH_COUNT = 114
AYAH_COUNT = 6236
PAGE_COUNT = 604
JUZ_COUNT = 30

ATTRIBUTION = "Tanzil Project (tanzil.net)"
LICENSE = (
    "Verbatim copies may be distributed; the text must not be changed, the "
    "source (Tanzil Project) must be named and tanzil.net must be linked."
)

SCHEMA = """
CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE surahs (
  number           INTEGER PRIMARY KEY,
  ayah_count       INTEGER NOT NULL,
  name_ar          TEXT NOT NULL,
  name_latin       TEXT NOT NULL,
  name_en          TEXT NOT NULL,
  revelation       TEXT NOT NULL,
  revelation_order INTEGER NOT NULL,
  ruku_count       INTEGER NOT NULL,
  start_page       INTEGER NOT NULL
);

CREATE TABLE ayahs (
  id     INTEGER PRIMARY KEY,
  surah  INTEGER NOT NULL REFERENCES surahs(number),
  number INTEGER NOT NULL,
  text   TEXT NOT NULL,
  page   INTEGER NOT NULL,
  juz    INTEGER NOT NULL,
  quarter INTEGER NOT NULL,
  sajda  INTEGER NOT NULL DEFAULT 0,
  -- How many of this ayah's leading words are the basmala. Tanzil prints it
  -- inside the first ayah of every surah that has one; the mushaf gives it a
  -- line of its own. Recording the boundary keeps the stored text exactly as
  -- Tanzil publishes it while letting the page be laid out as it is printed.
  basmala_words INTEGER NOT NULL DEFAULT 0,
  UNIQUE (surah, number)
);
CREATE INDEX ix_ayahs_page ON ayahs(page);
CREATE INDEX ix_ayahs_juz ON ayahs(juz);

CREATE TABLE pages (
  number        INTEGER PRIMARY KEY,
  first_ayah_id INTEGER NOT NULL REFERENCES ayahs(id),
  last_ayah_id  INTEGER NOT NULL REFERENCES ayahs(id),
  juz           INTEGER NOT NULL
);

-- Where the printed page breaks its lines. A line is a contiguous range of
-- tokens, a token being a word of an ayah or the marker that closes it, so
-- the app can lay a page out exactly as the mushaf does -- which is how
-- people who memorise from it know where a verse sits.
-- The few ayahs whose words the print joins: one row per printed token,
-- saying how many space-separated words of the text it covers. Ayahs without
-- rows here are one word to one token, which is almost all of them.
CREATE TABLE ayah_tokens (
  ayah_id INTEGER NOT NULL REFERENCES ayahs(id),
  pos     INTEGER NOT NULL,
  words   INTEGER NOT NULL,
  PRIMARY KEY (ayah_id, pos)
);

CREATE TABLE lines (
  page          INTEGER NOT NULL,
  line          INTEGER NOT NULL,
  kind          TEXT NOT NULL,       -- 'ayah', 'surah' or 'basmala'
  surah         INTEGER,             -- set on 'surah' and 'basmala' lines
  first_ayah_id INTEGER,             -- set on 'ayah' lines
  first_pos     INTEGER,
  last_ayah_id  INTEGER,
  last_pos      INTEGER,
  PRIMARY KEY (page, line)
);

CREATE TABLE juzs (
  number        INTEGER PRIMARY KEY,
  first_ayah_id INTEGER NOT NULL REFERENCES ayahs(id),
  last_ayah_id  INTEGER NOT NULL REFERENCES ayahs(id),
  start_page    INTEGER NOT NULL
);
"""


@dataclass(frozen=True)
class Surah:
    number: int
    ayah_count: int
    name_ar: str
    name_latin: str
    name_en: str
    revelation: str
    revelation_order: int
    ruku_count: int


@dataclass(frozen=True)
class Ayah:
    surah: int
    number: int
    text: str


def parse_text(path: Path, strict: bool = True) -> list[Ayah]:
    """Reads Tanzil's `sura|aya|text` file. Comment and blank lines are the
    file's own header and footer, not verses."""
    ayahs: list[Ayah] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        surah, number, text = line.split("|", 2)
        ayahs.append(Ayah(int(surah), int(number), text))
    if strict and len(ayahs) != AYAH_COUNT:
        raise SystemExit(f"{path}: {len(ayahs)} ayahs, expected {AYAH_COUNT}")
    return ayahs


def parse_metadata(path: Path) -> dict[str, object]:
    """Reads Tanzil's `quran-data.xml`: surahs, and the ayah each page, juz,
    hizb quarter and sajda starts at."""
    root = ET.parse(path).getroot()

    surahs = [
        Surah(
            number=int(node.attrib["index"]),
            ayah_count=int(node.attrib["ayas"]),
            name_ar=node.attrib["name"],
            name_latin=node.attrib["tname"],
            name_en=node.attrib["ename"],
            revelation=node.attrib["type"].lower(),
            revelation_order=int(node.attrib["order"]),
            ruku_count=int(node.attrib["rukus"]),
        )
        for node in root.findall("./suras/sura")
    ]

    def starts(path: str) -> list[tuple[int, int]]:
        """Tanzil names the containers and their children separately -- the
        240 hizb quarters live in `<hizbs>` as `<quarter>` -- so the caller
        gives the whole path rather than a tag to pluralise."""
        return [(int(node.attrib["sura"]), int(node.attrib["aya"])) for node in root.findall(path)]

    sajdas = {
        (int(node.attrib["sura"]), int(node.attrib["aya"])): node.attrib.get("type", "recommended")
        for node in root.findall("./sajdas/sajda")
    }

    return {
        "surahs": surahs,
        "pages": starts("./pages/page"),
        "juzs": starts("./juzs/juz"),
        # 240 of them: eight quarters to a hizb, two hizbs to a juz.
        "quarters": starts("./hizbs/quarter"),
        "sajdas": sajdas,
    }


def _starts_to_spans(
    starts: list[tuple[int, int]], index_of: dict[tuple[int, int], int]
) -> list[int]:
    """Turns "unit N starts at this ayah" into the unit number of every ayah."""
    if not starts:
        raise SystemExit("metadata carries no unit starts")
    boundaries = [index_of[key] for key in starts]
    unit_of = [0] * (len(index_of) + 1)
    for unit, first in enumerate(boundaries, start=1):
        last = boundaries[unit] - 1 if unit < len(boundaries) else len(index_of)
        for ayah_id in range(first, last + 1):
            unit_of[ayah_id] = unit
    return unit_of


def _basmala_word_counts(ayahs: list[Ayah], strict: bool = True) -> dict[int, int]:
    """How many leading words of each ayah are the basmala.

    Every surah but Al-Fatiha (whose basmala is its first ayah) and At-Tawba
    (which has none) opens with it, and Tanzil carries it inside that first
    ayah. The words are compared with Al-Fatiha's own first ayah rather than
    assumed, so a text that spells it differently is caught here instead of
    silently shifting a line.
    """
    basmala = [_letters(word) for word in ayahs[0].text.split()]
    counts: dict[int, int] = {}
    for ayah_id, ayah in enumerate(ayahs, start=1):
        if ayah.number != 1 or ayah.surah in (1, 9):
            continue
        words = [_letters(word) for word in ayah.text.split()]
        # Letters only: the vowelling of the basmala is not identical before
        # every surah (before Surah 95 it carries a shadda), and that is a
        # property of the text, not a mistake to normalise away -- the text
        # itself is stored untouched either way.
        if words[: len(basmala)] != basmala:
            if strict:
                raise SystemExit(
                    f"surah {ayah.surah} does not open with the basmala; the "
                    "text is not the expected edition"
                )
            continue
        counts[ayah_id] = len(basmala)
    return counts


def _letters(word: str) -> str:
    """The word without its vowel marks, for comparing spellings."""
    return "".join(char for char in word if not ("ً" <= char <= "ٟ" or char in "ٰـ۟۠"))


def build_lines(
    tokens_by_page: dict[str, list[dict]],
    index_of: dict[tuple[int, int], int],
    words_per_ayah: dict[int, int],
) -> list[tuple]:
    """Turns the downloaded tokens into one row per printed line.

    Lines with no tokens are the ones the print reserves for a surah heading
    and, where the surah has one, its basmala; which surah they belong to is
    read from the first token of the next line that has one.
    """
    rows: list[tuple] = []
    seen_positions: dict[int, int] = {}

    for page_key in sorted(tokens_by_page, key=int):
        page = int(page_key)
        by_line: dict[int, list[dict]] = {}
        for token in tokens_by_page[page_key]:
            surah, number = (int(part) for part in token["key"].split(":"))
            ayah_id = index_of[(surah, number)]
            by_line.setdefault(int(token["line"]), []).append(
                {"ayah_id": ayah_id, "pos": int(token["pos"])}
            )
            seen_positions[ayah_id] = max(seen_positions.get(ayah_id, 0), int(token["pos"]))

        if not by_line:
            raise SystemExit(f"page {page} has no tokens")
        last_line = max(by_line)

        for line in range(1, last_line + 1):
            on_line = by_line.get(line)
            if on_line:
                rows.append(
                    (
                        page,
                        line,
                        "ayah",
                        None,
                        on_line[0]["ayah_id"],
                        on_line[0]["pos"],
                        on_line[-1]["ayah_id"],
                        on_line[-1]["pos"],
                    )
                )
                continue

            # An empty line belongs to the surah that opens after it.
            following = next(
                (by_line[later] for later in range(line + 1, last_line + 1) if later in by_line),
                None,
            )
            if following is None:
                raise SystemExit(f"page {page} line {line} opens nothing")
            ayah_id = following[0]["ayah_id"]
            surah = next(key[0] for key, value in index_of.items() if value == ayah_id)
            gap_start = line
            while gap_start - 1 >= 1 and (gap_start - 1) not in by_line:
                gap_start -= 1
            # Two reserved lines mean heading then basmala; one is a heading
            # alone (Al-Fatiha, whose basmala is its first ayah, and
            # At-Tawba, which has none).
            kind = "surah" if line == gap_start else "basmala"
            rows.append((page, line, kind, surah, None, None, None, None))

    missing = [
        ayah_id
        for ayah_id, words in words_per_ayah.items()
        if seen_positions.get(ayah_id) != words + 1
    ]
    if missing:
        raise SystemExit(
            f"{len(missing)} ayahs are split into a different number of words "
            f"than the text has (first: ayah {missing[0]}, "
            f"layout {seen_positions.get(missing[0])}, "
            f"text {words_per_ayah[missing[0]] + 1}). The layout and the text "
            "must come from the same edition."
        )
    return rows


def build(
    text_path: Path,
    meta_path: Path,
    out_path: Path,
    lines_path: Path | None = None,
    splits_path: Path | None = None,
    strict: bool = True,
) -> None:
    """[strict] is what makes a real build refuse anything but a complete
    Qur'an; the tests turn it off to work on a handful of ayahs."""
    ayahs = parse_text(text_path, strict=strict)
    meta = parse_metadata(meta_path)
    surahs: list[Surah] = meta["surahs"]  # type: ignore[assignment]
    if strict and len(surahs) != SURAH_COUNT:
        raise SystemExit(f"{meta_path}: {len(surahs)} surahs, expected {SURAH_COUNT}")

    index_of = {(a.surah, a.number): i for i, a in enumerate(ayahs, start=1)}
    basmala_words = _basmala_word_counts(ayahs, strict=strict)
    page_of = _starts_to_spans(meta["pages"], index_of)  # type: ignore[arg-type]
    juz_of = _starts_to_spans(meta["juzs"], index_of)  # type: ignore[arg-type]
    quarter_of = _starts_to_spans(meta["quarters"], index_of)  # type: ignore[arg-type]
    sajdas: dict[tuple[int, int], str] = meta["sajdas"]  # type: ignore[assignment]

    if strict and max(page_of) != PAGE_COUNT:
        raise SystemExit(f"{max(page_of)} pages, expected {PAGE_COUNT}")
    if strict and max(juz_of) != JUZ_COUNT:
        raise SystemExit(f"{max(juz_of)} juzs, expected {JUZ_COUNT}")

    # How many printed tokens each ayah has, where the print does not simply
    # follow the text's own spaces.
    splits: dict[int, list[int]] = {}
    if splits_path is not None:
        for key, counts in json.loads(splits_path.read_text(encoding="utf-8")).items():
            surah, number = (int(part) for part in key.split(":"))
            ayah_id = index_of[(surah, number)]
            covered = sum(counts) + basmala_words.get(ayah_id, 0)
            if covered != len(ayahs[ayah_id - 1].text.split()):
                raise SystemExit(
                    f"{key}: the printed tokens cover {covered} words, the "
                    f"text has {len(ayahs[ayah_id - 1].text.split())}"
                )
            splits[ayah_id] = counts

    line_rows: list[tuple] = []
    if lines_path is not None:
        line_rows = build_lines(
            json.loads(lines_path.read_text(encoding="utf-8")),
            index_of,
            {
                ayah_id: len(splits[ayah_id])
                if ayah_id in splits
                else len(ayah.text.split()) - basmala_words.get(ayah_id, 0)
                for ayah_id, ayah in enumerate(ayahs, start=1)
            },
        )
        pages_with_lines = {row[0] for row in line_rows}
        if strict and len(pages_with_lines) != PAGE_COUNT:
            raise SystemExit(
                f"{len(pages_with_lines)} pages have a line layout, expected {PAGE_COUNT}"
            )

    digest = hashlib.sha256(text_path.read_bytes()).hexdigest()

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()
    db = sqlite3.connect(out_path)
    try:
        db.executescript(SCHEMA)

        surah_start_page = {surah.number: page_of[index_of[(surah.number, 1)]] for surah in surahs}
        db.executemany(
            "INSERT INTO surahs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    s.number,
                    s.ayah_count,
                    s.name_ar,
                    s.name_latin,
                    s.name_en,
                    s.revelation,
                    s.revelation_order,
                    s.ruku_count,
                    surah_start_page[s.number],
                )
                for s in surahs
            ],
        )

        db.executemany(
            "INSERT INTO ayahs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    ayah_id,
                    ayah.surah,
                    ayah.number,
                    ayah.text,
                    page_of[ayah_id],
                    juz_of[ayah_id],
                    quarter_of[ayah_id],
                    1 if (ayah.surah, ayah.number) in sajdas else 0,
                    basmala_words.get(ayah_id, 0),
                )
                for ayah_id, ayah in enumerate(ayahs, start=1)
            ],
        )

        for table, unit_of in (("pages", page_of), ("juzs", juz_of)):
            spans: dict[int, list[int]] = {}
            for ayah_id in range(1, len(ayahs) + 1):
                spans.setdefault(unit_of[ayah_id], []).append(ayah_id)
            db.executemany(
                f"INSERT INTO {table} VALUES (?, ?, ?, ?)",
                [
                    (
                        unit,
                        ids[0],
                        ids[-1],
                        juz_of[ids[0]] if table == "pages" else page_of[ids[0]],
                    )
                    for unit, ids in sorted(spans.items())
                ],
            )

        db.executemany(
            "INSERT INTO ayah_tokens VALUES (?, ?, ?)",
            [
                (ayah_id, pos, words)
                for ayah_id, counts in sorted(splits.items())
                for pos, words in enumerate(counts, start=1)
            ],
        )

        db.executemany(
            "INSERT INTO lines VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            line_rows,
        )

        db.executemany(
            "INSERT INTO meta VALUES (?, ?)",
            [
                ("edition", "Tanzil Uthmani"),
                ("attribution", ATTRIBUTION),
                ("license", LICENSE),
                ("source_url", "https://tanzil.net/download/"),
                ("text_sha256", digest),
                ("ayah_count", str(len(ayahs))),
                ("page_count", str(max(page_of))),
                ("line_layout", "KFGQPC 15-line Madinah layout" if line_rows else ""),
                ("built_at", datetime.now(UTC).isoformat(timespec="seconds")),
            ],
        )
        db.commit()
        db.execute("VACUUM")
    finally:
        db.close()

    size_mb = out_path.stat().st_size / 1024 / 1024
    print(
        f"{out_path} built: {len(ayahs)} ayahs, {max(page_of)} pages, "
        f"{len(line_rows)} printed lines, {size_mb:.1f} MB"
    )
    print(f"text sha256 {digest}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--text", required=True, type=Path, help="quran-uthmani.txt")
    parser.add_argument("--meta", required=True, type=Path, help="quran-data.xml")
    parser.add_argument("--out", required=True, type=Path, help="quran.sqlite")
    parser.add_argument(
        "--lines",
        type=Path,
        help="mushaf-lines.json from fetch_mushaf_lines.py",
    )
    parser.add_argument(
        "--splits",
        type=Path,
        help="word-splits.json from fetch_word_splits.py",
    )
    args = parser.parse_args()
    build(
        args.text,
        args.meta,
        args.out,
        lines_path=args.lines,
        splits_path=args.splits,
    )


if __name__ == "__main__":
    main()
