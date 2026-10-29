"""What goes into an agent and what is allowed back out.

The input models double as the wire shape of `POST /ai/analysis` (re-exported
from `app.modules.ai.schemas`): one definition, validated once, rather than a
wire model and an agent model that drift apart.

Two rules run through the output models:

* **The server holds no vocabulary of its own.** Which life areas exist, and
  which widget kinds the app can create, arrive *in the request* --
  `available_kinds`, and the areas the client measured. A proposal is checked
  against what the client sent, so a newer app version can propose a widget
  kind this server has never heard of without a deploy. Same reasoning as
  `habits.kind` (`app.modules.habits.sync_entities`).
* **Numbers are bounded, text is only sanity-bounded.** A target of 10^9 or a
  reminder at minute 5000 would reach the user's widget editor, so those are
  clamped hard. The text limits are generous on purpose: they exist to catch
  an answer that went wrong, not to trim a sentence that ran two words long.
"""

from __future__ import annotations

from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

# Lowercase identifier, as used for widget kinds and focus areas. A shape
# constraint rather than an allow-list -- see the module docstring.
Slug = Annotated[
    str,
    StringConstraints(min_length=1, max_length=32, pattern=r"^[a-z][a-z0-9_]*$"),
]

# How an area is doing, as the phone's own rule-based analysis classified it
# (`features/insights/domain/area_insight.dart`). Passed through so the model
# describes the same picture the user is already looking at.
AreaState = Annotated[str, StringConstraints(min_length=1, max_length=16, pattern=r"^[a-z]+$")]


class AreaFact(BaseModel):
    """One life area's measured record over the window.

    Every field is a count the user could verify on their own grid. There is
    no field here the model may fill in -- it only ever reads these.
    """

    model_config = ConfigDict(extra="forbid")

    area: Slug
    state: AreaState

    # The widget the area's trouble is about, as the user named it. Free text
    # the user wrote, so it is quoted into the prompt as data; see
    # `app.ai.agents.analyst`.
    widget: str | None = Field(default=None, max_length=80)

    planned_days: int = Field(ge=0, le=400)
    done_days: int = Field(ge=0, le=400)

    # Last week's share minus the week before's, in points.
    trend: int = Field(default=0, ge=-100, le=100)

    # False says the daily amount was never once reached: the amount is too
    # big, which is a different problem from not starting.
    ever_met_target: bool = True

    daily_target: int | None = Field(default=None, ge=1, le=100_000)
    reminder_minutes: int | None = Field(default=None, ge=0, le=1439)


class AnalystFacts(BaseModel):
    """Everything the analyst is given. Also the body of `POST /ai/analysis`."""

    model_config = ConfigDict(extra="forbid")

    window_days: int = Field(default=14, ge=1, le=400)

    # Which language to answer in. The app's own four; anything else is
    # answered in English rather than refused.
    locale: Annotated[str, StringConstraints(min_length=2, max_length=10)] = "uz"

    areas: list[AreaFact] = Field(default_factory=list, max_length=12)

    # The sign-up answers (`features/onboarding`). All optional: a device
    # where the questions were skipped still gets an analysis of what it can
    # measure.
    occupation: Slug | None = None
    interests: list[Slug] = Field(default_factory=list, max_length=24)
    focus_areas: list[Slug] = Field(default_factory=list, max_length=24)
    daily_minutes: int | None = Field(default=None, ge=5, le=600)

    # The widget kinds this client build can create. A proposal outside this
    # set is dropped.
    available_kinds: list[Slug] = Field(default_factory=list, max_length=32)

    @model_validator(mode="after")
    def _something_to_analyse(self) -> AnalystFacts:
        """Refuse a request with nothing in it.

        With neither a measured area nor an area the user asked for, there is
        nothing to analyse and a paid call would only produce invention. 422
        here is better than a plausible-looking answer about nothing.
        """
        if not self.areas and not self.focus_areas:
            raise ValueError("at least one measured area or focus area is required")
        return self


class AiAreaNote(BaseModel):
    """What the model says about one area, and how urgent it thinks it is."""

    model_config = ConfigDict(extra="forbid")

    area: Slug
    note: str = Field(max_length=400)
    priority: int = Field(ge=1, le=3)


class AiWidgetProposal(BaseModel):
    """A widget the model suggests. Created only if the user accepts it."""

    model_config = ConfigDict(extra="forbid")

    kind: Slug
    title: str = Field(max_length=60)
    daily_target: int = Field(ge=1, le=100_000)
    reminder_minutes: int | None = Field(default=None, ge=0, le=1439)
    reason: str = Field(max_length=400)


class AiAnalysis(BaseModel):
    """The analyst's whole answer. Stored as a proposal payload, never applied."""

    model_config = ConfigDict(extra="forbid")

    summary: str = Field(max_length=600)
    areas: list[AiAreaNote] = Field(default_factory=list)
    widgets: list[AiWidgetProposal] = Field(default_factory=list)


# The schema sent to the provider as `output_config.format`.
#
# Written out by hand rather than generated from `AiAnalysis`, for two
# reasons: strict JSON schema wants `additionalProperties: false` and every
# property in `required`, which Pydantic does not emit; and the bytes of this
# dict are part of the request, so a Pydantic upgrade that reorders its
# output must not silently change what we send. `tests/test_ai_analysis.py`
# asserts the two stay in step.
ANALYSIS_JSON_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "summary": {"type": "string"},
        "areas": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "area": {"type": "string"},
                    "note": {"type": "string"},
                    "priority": {"type": "integer", "enum": [1, 2, 3]},
                },
                "required": ["area", "note", "priority"],
                "additionalProperties": False,
            },
        },
        "widgets": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "kind": {"type": "string"},
                    "title": {"type": "string"},
                    "daily_target": {"type": "integer"},
                    "reminder_minutes": {"type": ["integer", "null"]},
                    "reason": {"type": "string"},
                },
                "required": [
                    "kind",
                    "title",
                    "daily_target",
                    "reminder_minutes",
                    "reason",
                ],
                "additionalProperties": False,
            },
        },
    },
    "required": ["summary", "areas", "widgets"],
    "additionalProperties": False,
}
