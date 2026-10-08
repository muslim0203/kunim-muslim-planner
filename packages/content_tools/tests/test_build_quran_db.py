"""The Qur'an database builder.

The fixtures here are deliberately not Qur'anic text: what is being tested is
the structure the builder derives (pages, juzs, spans) and that whatever text
it is handed is stored byte for byte. Placeholder words make an accidental
"almost right" verse impossible.

Run from the repository root:
    apps/api/.venv/Scripts/python -m pytest packages/content_tools/tests
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build_quran_db import build, parse_metadata, parse_text  # noqa: E402

# Two surahs, five "ayahs", split over two pages and two juzs.
TEXT = """# Placeholder, not Qur'anic text.
1|1|كلمة أولى
1|2|كلمة ثانية
1|3|كلمة ثالثة
2|1|كلمة رابعة
2|2|كلمة خامسة
"""

META = """<?xml version="1.0" encoding="UTF-8"?>
<quran>
  <suras>
    <sura index="1" ayas="3" start="0" name="الأولى" tname="Al-Ula"
          ename="The First" type="Meccan" order="5" rukus="1"/>
    <sura index="2" ayas="2" start="3" name="الثانية" tname="Ath-Thaniya"
          ename="The Second" type="Medinan" order="87" rukus="2"/>
  </suras>
  <juzs>
    <juz index="1" sura="1" aya="1"/>
    <juz index="2" sura="2" aya="1"/>
  </juzs>
  <hizbs>
    <quarter index="1" sura="1" aya="1"/>
    <quarter index="2" sura="1" aya="3"/>
  </hizbs>
  <pages>
    <page index="1" sura="1" aya="1"/>
    <page index="2" sura="1" aya="3"/>
  </pages>
  <sajdas>
    <sajda index="1" sura="2" aya="2" type="obligatory"/>
  </sajdas>
</quran>
"""


@pytest.fixture
def sources(tmp_path: Path) -> tuple[Path, Path]:
    text = tmp_path / "quran-uthmani.txt"
    meta = tmp_path / "quran-data.xml"
    text.write_text(TEXT, encoding="utf-8")
    meta.write_text(META, encoding="utf-8")
    return text, meta


# The printed layout of the two fixture pages: page 1 keeps line 1 for the
# surah heading, page 2 keeps lines 1 and 2 for a heading and a basmala.
LINES = {
    "1": [
        {"key": "1:1", "pos": 1, "line": 2, "end": False},
        {"key": "1:1", "pos": 2, "line": 2, "end": False},
        {"key": "1:1", "pos": 3, "line": 2, "end": True},
        {"key": "1:2", "pos": 1, "line": 3, "end": False},
        {"key": "1:2", "pos": 2, "line": 3, "end": False},
        {"key": "1:2", "pos": 3, "line": 3, "end": True},
    ],
    "2": [
        {"key": "1:3", "pos": 1, "line": 1, "end": False},
        {"key": "1:3", "pos": 2, "line": 1, "end": False},
        {"key": "1:3", "pos": 3, "line": 1, "end": True},
        {"key": "2:1", "pos": 1, "line": 4, "end": False},
        {"key": "2:1", "pos": 2, "line": 4, "end": False},
        {"key": "2:1", "pos": 3, "line": 4, "end": True},
        {"key": "2:2", "pos": 1, "line": 5, "end": False},
        {"key": "2:2", "pos": 2, "line": 5, "end": False},
        {"key": "2:2", "pos": 3, "line": 5, "end": True},
    ],
}


@pytest.fixture
def lines_file(tmp_path: Path) -> Path:
    path = tmp_path / "mushaf-lines.json"
    path.write_text(json.dumps(LINES), encoding="utf-8")
    return path


@pytest.fixture
def built(sources: tuple[Path, Path], tmp_path: Path) -> sqlite3.Connection:
    text, meta = sources
    out = tmp_path / "quran.sqlite"
    build(text, meta, out, strict=False)
    db = sqlite3.connect(out)
    db.row_factory = sqlite3.Row
    yield db
    db.close()


def test_the_text_is_stored_exactly_as_it_arrived(built: sqlite3.Connection) -> None:
    """The one thing this script must never do is edit the text."""
    rows = built.execute("SELECT text FROM ayahs ORDER BY id").fetchall()
    assert [row["text"] for row in rows] == [
        line.split("|", 2)[2] for line in TEXT.splitlines() if line and not line.startswith("#")
    ]


def test_every_ayah_knows_its_page_and_juz(built: sqlite3.Connection) -> None:
    rows = built.execute("SELECT id, page, juz FROM ayahs ORDER BY id").fetchall()
    assert [(row["page"], row["juz"]) for row in rows] == [
        (1, 1),  # 1:1
        (1, 1),  # 1:2
        (2, 1),  # 1:3 opens page 2
        (2, 2),  # 2:1 opens juz 2
        (2, 2),  # 2:2
    ]


def test_pages_and_juzs_carry_their_span(built: sqlite3.Connection) -> None:
    pages = built.execute("SELECT * FROM pages ORDER BY number").fetchall()
    assert [(p["number"], p["first_ayah_id"], p["last_ayah_id"]) for p in pages] == [
        (1, 1, 2),
        (2, 3, 5),
    ]
    juzs = built.execute("SELECT * FROM juzs ORDER BY number").fetchall()
    assert [(j["number"], j["first_ayah_id"], j["last_ayah_id"]) for j in juzs] == [
        (1, 1, 3),
        (2, 4, 5),
    ]
    # A juz starts on the page its first ayah sits on.
    assert juzs[1]["start_page"] == 2


def test_a_surah_knows_where_it_opens(built: sqlite3.Connection) -> None:
    rows = built.execute(
        "SELECT number, name_latin, revelation, start_page FROM surahs ORDER BY number"
    ).fetchall()
    assert [(r["number"], r["start_page"]) for r in rows] == [(1, 1), (2, 2)]
    assert rows[0]["revelation"] == "meccan"
    assert rows[1]["revelation"] == "medinan"


def test_a_sajda_ayah_is_marked(built: sqlite3.Connection) -> None:
    sajdas = built.execute("SELECT surah, number FROM ayahs WHERE sajda = 1").fetchall()
    assert [(row["surah"], row["number"]) for row in sajdas] == [(2, 2)]


def test_the_build_carries_its_terms_and_a_checksum(
    built: sqlite3.Connection, sources: tuple[Path, Path]
) -> None:
    """A build that lost its attribution must not be shippable."""
    meta = dict(built.execute("SELECT key, value FROM meta").fetchall())
    assert "Tanzil" in meta["attribution"]
    assert "tanzil.net" in meta["source_url"]
    assert "must not be changed" in meta["license"]
    assert meta["text_sha256"] == hashlib.sha256(sources[0].read_bytes()).hexdigest()


def test_a_short_text_is_refused_by_a_real_build(
    sources: tuple[Path, Path], tmp_path: Path
) -> None:
    """A truncated download is a broken Qur'an, not a smaller one."""
    text, meta = sources
    with pytest.raises(SystemExit):
        build(text, meta, tmp_path / "out.sqlite")


def test_a_page_is_stored_line_by_line(
    sources: tuple[Path, Path], lines_file: Path, tmp_path: Path
) -> None:
    """The layout is what makes a page look like the printed one."""
    text, meta = sources
    out = tmp_path / "with-lines.sqlite"
    build(text, meta, out, lines_path=lines_file, strict=False)

    db = sqlite3.connect(out)
    db.row_factory = sqlite3.Row
    rows = db.execute("SELECT * FROM lines ORDER BY page, line").fetchall()
    db.close()

    assert [(r["page"], r["line"], r["kind"]) for r in rows] == [
        (1, 1, "surah"),  # line kept for the heading
        (1, 2, "ayah"),
        (1, 3, "ayah"),
        (2, 1, "ayah"),
        (2, 2, "surah"),  # the second surah opens here
        (2, 3, "basmala"),
        (2, 4, "ayah"),
        (2, 5, "ayah"),
    ]
    first = rows[1]
    assert (first["first_ayah_id"], first["first_pos"]) == (1, 1)
    assert (first["last_ayah_id"], first["last_pos"]) == (1, 3)
    assert rows[4]["surah"] == 2
    assert rows[5]["surah"] == 2


def test_a_layout_that_disagrees_with_the_text_is_refused(
    sources: tuple[Path, Path], tmp_path: Path
) -> None:
    """A layout from another edition would shift every line after the gap."""
    text, meta = sources
    short = dict(LINES)
    short["1"] = LINES["1"][:-1]  # one token fewer than the text has
    path = tmp_path / "short-lines.json"
    path.write_text(json.dumps(short), encoding="utf-8")

    with pytest.raises(SystemExit) as refused:
        build(text, meta, tmp_path / "out.sqlite", lines_path=path, strict=False)

    assert "different number of words" in str(refused.value)


def test_the_printed_grouping_of_joined_words_is_stored(
    sources: tuple[Path, Path], lines_file: Path, tmp_path: Path
) -> None:
    """Where the print writes two words joined, the page has one token."""
    text, meta = sources
    splits = tmp_path / "splits.json"
    # 1:1 has two words; the print joins them into a single token.
    splits.write_text(json.dumps({"1:1": [2]}), encoding="utf-8")
    joined = dict(LINES)
    joined["1"] = [
        {"key": "1:1", "pos": 1, "line": 2, "end": False},
        {"key": "1:1", "pos": 2, "line": 2, "end": True},
        *LINES["1"][3:],
    ]
    lines = tmp_path / "joined-lines.json"
    lines.write_text(json.dumps(joined), encoding="utf-8")

    out = tmp_path / "joined.sqlite"
    build(text, meta, out, lines_path=lines, splits_path=splits, strict=False)

    db = sqlite3.connect(out)
    rows = db.execute("SELECT pos, words FROM ayah_tokens ORDER BY pos").fetchall()
    db.close()
    assert rows == [(1, 2)]


def test_the_parsers_read_tanzils_own_shapes(sources: tuple[Path, Path]) -> None:
    text, meta = sources
    assert len(parse_text(text, strict=False)) == 5
    parsed = parse_metadata(meta)
    assert len(parsed["surahs"]) == 2
    assert parsed["pages"] == [(1, 1), (1, 3)]
    assert parsed["quarters"] == [(1, 1), (1, 3)]
    assert parsed["sajdas"] == {(2, 2): "obligatory"}
