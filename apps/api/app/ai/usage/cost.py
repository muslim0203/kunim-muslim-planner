"""What a call cost, in dollars.

Recorded per request in `ai_requests.cost_usd` so the spend-per-active-user
figure the plan commits to (< $0.05/day, section 11 phase 7) is a query and
not a guess.

The table is a **cached copy of published list prices**, read on 2026-10-29,
and it is only ever used for reporting -- never to decide whether to make a
call. A price that has moved makes the report wrong, not the product; an
unknown model is recorded as a zero cost and logged, which shows up as a
suspiciously cheap model in the same report.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Final, NamedTuple

import structlog

logger = structlog.get_logger(__name__)


class ModelPrice(NamedTuple):
    """US dollars per million tokens."""

    input_usd: Decimal
    output_usd: Decimal

    # Tokens served from the prompt cache. Roughly a tenth of the input
    # price, which is the whole reason the analyst's system prompt is a
    # frozen string.
    cache_read_usd: Decimal

    # Writing the prefix into the cache costs more than sending it plainly
    # would have. So caching only pays off once a prefix is read back more
    # often than it is written, and a cost figure that leaves this out makes
    # caching look free. Measured 2026-10-29: the analyst's first call of a
    # window writes ~1,460 tokens, and leaving them unpriced under-reported
    # that call by 40% ($0.0054 against a real $0.0090).
    cache_write_usd: Decimal


_MILLION: Final[Decimal] = Decimal(1_000_000)

# Cache writes are the input price times this, for the five-minute window.
_CACHE_WRITE_MULTIPLIER: Final[Decimal] = Decimal("1.25")


def _price(input_usd: str, output_usd: str, cache_read_usd: str) -> ModelPrice:
    """A row of the table, with the cache-write price derived from input.

    Derived rather than listed: it is a published multiple of the input
    price, and two numbers that must move together are better kept as one.
    """
    base = Decimal(input_usd)
    return ModelPrice(
        input_usd=base,
        output_usd=Decimal(output_usd),
        cache_read_usd=Decimal(cache_read_usd),
        cache_write_usd=base * _CACHE_WRITE_MULTIPLIER,
    )


PRICES: Final[dict[str, ModelPrice]] = {
    "claude-sonnet-5-5": _price("2.00", "10.00", "0.20"),
    "claude-opus-5-5": _price("4.00", "20.00", "0.20"),
    "claude-haiku-5-5": _price("0.10", "0.50", "0.01"),
}


def estimate_usd(
    model: str,
    *,
    input_tokens: int,
    output_tokens: int,
    cache_read_tokens: int = 0,
    cache_write_tokens: int = 0,
) -> Decimal:
    """Cost of one call, rounded to the micro-dollar the column stores.

    The four counts do not overlap: `input_tokens` is what the provider
    reports as uncached input, and tokens read from or written to the cache
    are reported separately and priced separately. All four have to be
    passed, or the figure is wrong in the direction that flatters us.
    """
    price = PRICES.get(model)
    if price is None:
        logger.warning("ai_cost_unknown_model", model=model)
        return Decimal("0")

    total = (
        price.input_usd * input_tokens
        + price.output_usd * output_tokens
        + price.cache_read_usd * cache_read_tokens
        + price.cache_write_usd * cache_write_tokens
    ) / _MILLION
    return total.quantize(Decimal("0.000001"))
