"""Rule 1 of `CLAUDE.md`, enforced on the way out.

> Hech qachon oyat, hadis yoki diniy hukm o'ylab topilmaydi.

The prompt already forbids it. This exists because a prompt is a request and
a check is a guarantee: the one thing this app must never do is put a
sentence about religion in front of a user on a model's authority. Until the
`content` table and its citation check exist (plan section 5), the answer to
"may the analyst say something religious?" is simply no -- not "only with a
citation".

**A flag discards the whole answer**, not the offending sentence. Editing a
model's answer to make it acceptable leaves the rest of it unexamined, and
the fallback costs the user nothing: the phone's own rule-based analysis is
already on screen.

The cost of a false positive is therefore low and the cost of a miss is high,
which is why the lists below lean towards flagging. What they deliberately do
*not* flag is a bare mention: "Qur'on o'qish" is the name of a widget the
user created, and an analysis that cannot name it is useless. A scripture
word becomes a flag when something is attributed to it -- a chapter-and-verse
number, or a verb of saying.
"""

from __future__ import annotations

import re
from typing import Final

# --- Normalisation ---------------------------------------------------------
# The same word reaches us spelled several ways: `Qur'on` with a turned comma
# (U+2018, what the app's own Uzbek strings use), with a straight quote, or
# with a modifier letter. Matching each spelling in every pattern would be
# unreadable and would quietly miss the fourth one.
_APOSTROPHES: Final[str] = "‘’ʻʼ`´"
_APOSTROPHE_RE: Final[re.Pattern[str]] = re.compile(f"[{_APOSTROPHES}]")


def normalise(text: str) -> str:
    """Lowercase, and fold every apostrophe variant onto `'`."""
    return _APOSTROPHE_RE.sub("'", text).lower()


# --- The patterns ----------------------------------------------------------

# Arabic, including the presentation forms a copied ayah usually carries.
# The analyst writes Uzbek, Russian or English; Arabic script in its answer
# is a quoted verse or invocation and nothing else.
_ARABIC_RE: Final[re.Pattern[str]] = re.compile("[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]")

# Naming a hadith collection is citing one. There is no innocent reason for
# the analyst to mention `Sahih Muslim` while reporting how many days the
# sport widget was done.
_COLLECTIONS: Final[tuple[str, ...]] = (
    r"buxoriy",
    r"bukhari",
    r"sahih\s+muslim",
    r"sahih\s+al",
    r"imom\s+muslim",
    r"tirmiz(iy|hi)",
    r"abu\s+d[ao]'?[uv]ud",
    r"nas[oa]'?[iy]",
    r"ibn\s+m[oa]j[ah]",
    r"musnad",
    r"muwatta",
    r"muvatto",
    r"bayhaq",
    r"бухорий",  # buxoriy
    r"муслима",  # muslima (genitive)
)
_COLLECTION_RE: Final[re.Pattern[str]] = re.compile("|".join(_COLLECTIONS))

# A ruling -- what is obligatory, recommended, permitted or forbidden -- is
# the mufti's to give, never a planner's. These words carry no other sense.
_RULINGS: Final[tuple[str, ...]] = (
    r"halol",
    r"halal",
    r"har[oa]m",
    r"fat[vw][oa]",
    r"v?[ow]ojib",
    r"wajib",
    r"farz",
    r"fard[hz]?",
    r"sunnat",
    r"sunnah",
    r"makruh",
    r"makr[ou]h",
    r"mustah[ao]b",
    r"gunoh",
    r"savob",
    r"халол",  # halol
    r"харом",  # harom
    r"фатво",  # fatvo
    r"суннат",  # sunnat
    r"гунох",  # gunoh
    r"савоб",  # savob
)
_RULING_RE: Final[re.Pattern[str]] = re.compile(r"\b(?:" + "|".join(_RULINGS) + r")\w*")

# Words naming a scripture. On their own these are allowed: they are what the
# user's own widgets are called.
_SCRIPTURE: Final[str] = (
    r"(?:qur'?[oa]n|quran|koran|қур|куран"
    r"|sura|surah|surasi|oyat|ayah|ayat|hadis|hadith|hadeeth"
    r"|сура|оят|аят"
    r"|ҳадис|хадис)\w*"
)

# ...but a scripture word with a chapter-and-verse number beside it is a
# citation. The number must be *near* the word: the analysis is full of
# clock times ("7:30"), and a bare `\d+:\d+` would flag every one of them.
_REFERENCE_RE: Final[re.Pattern[str]] = re.compile(
    _SCRIPTURE + r"[^\n]{0,24}?\d{1,3}\s*[:,]\s*\d{1,3}"
    r"|\d{1,3}\s*[:,]\s*\d{1,3}[^\n]{0,24}?" + _SCRIPTURE
)

# ...and a scripture word with a verb of saying beside it is an attribution:
# "the Qur'an says", "it is related in a hadith".
_CLAIM_VERBS: Final[str] = (
    r"(?:aytil|aytadi|aytgan|aytib|deyil|degan|dedi|deydi|buyur|keltiril"
    r"|yozil|zikr\s+qilin|ta'?kidla|says|said|states?|mentions?|teach|tells"
    r"|commands?|relate[sd]?|narrat"
    r"|говорит|сказа"
    r"|упомина|учит"
    r"|айтил|дейил)\w*"
)
_ATTRIBUTION_RE: Final[re.Pattern[str]] = re.compile(
    _SCRIPTURE + r"[^\n]{0,40}?" + _CLAIM_VERBS + r"|" + _CLAIM_VERBS + r"[^\n]{0,40}?" + _SCRIPTURE
)

_CHECKS: Final[tuple[tuple[str, re.Pattern[str]], ...]] = (
    ("arabic_script", _ARABIC_RE),
    ("hadith_collection", _COLLECTION_RE),
    ("ruling_without_source", _RULING_RE),
    ("scripture_reference", _REFERENCE_RE),
    ("scripture_attribution", _ATTRIBUTION_RE),
)


class ReligiousContentError(Exception):
    """A model's answer claimed something religious. The answer is discarded."""

    def __init__(self, flags: tuple[str, ...]) -> None:
        super().__init__(", ".join(flags))
        self.flags = flags


def inspect(*texts: str | None) -> tuple[str, ...]:
    """Flag names every one of `texts` triggered, in a stable order.

    Empty means nothing was found. Reported into `ai_requests.safety_flags`
    whether or not the answer was discarded, so a pattern that starts firing
    on ordinary sentences is visible before anyone complains.
    """
    joined = normalise("\n".join(text for text in texts if text))
    return tuple(name for name, pattern in _CHECKS if pattern.search(joined))


def assert_clean(*texts: str | None) -> None:
    """Raise `ReligiousContentError` if any of `texts` claims something religious."""
    flags = inspect(*texts)
    if flags:
        raise ReligiousContentError(flags)
