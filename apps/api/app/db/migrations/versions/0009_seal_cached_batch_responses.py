"""drop cached push responses that hold plaintext encrypted-column values

Revision ID: 0009_seal_cached_batch_responses
Revises: 0008_wellbeing_logs
Create Date: 2026-09-14

Data-only migration; no schema change.

From this revision on, `SyncRepository.save_batch` stores every
`EncryptedText` column inside a cached result's `server_row` sealed, and
`SyncRepository.stored_response` opens it again when a retried push is
replayed -- refusing anything that is not valid ciphertext.

Between `0008_wellbeing_logs` and that fix, a `conflict` answer for
`mood_logs`, `sleep_logs`, `health_logs` or `family_logs` could have been
cached in `sync_batches.response` with its note in plaintext. Those cache
rows are DELETED here, not encrypted in place:

- Deleting a cached response is exactly what ADR-0002 section 3 retention
  already does to every batch after 7 days, and the ADR says why that is
  safe: a `batch_id` with no cached answer is processed as a new batch, every
  change is an upsert by `id`, and the merge rules are idempotent, so
  re-applying the batch converges on the same server state. The retry is
  answered from current state rather than from the cached answer -- which is
  what any client retrying after 7 days already gets.
- Encrypting in place would make this frozen migration depend on the
  application's cipher code and on `FIELD_ENC_KEY` being configured wherever
  migrations run, for a cache that expires within a week anyway.
- Such rows can only exist on databases where `0008` was applied before this
  fix (development databases); everywhere else this is a no-op.

`ENCRYPTED_COLUMNS` is a frozen snapshot of the `EncryptedText` columns that
existed at `0008`. Columns added later need no sweep: the generic sealing
covers them from their first write. `tests/test_sync_privacy.py` checks the
snapshot is still encrypted in the models. A value that already looks like
ciphertext (`v<version>:<base64url>`) is left alone.

PostgreSQL only: `response` is JSONB there, and the SQLite test databases are
built by `create_all` and never hold legacy rows. `downgrade()` is a no-op --
a dropped cache entry cannot be restored and does not need to be.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0009_seal_cached_batch_responses"
down_revision: str | None = "0008_wellbeing_logs"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

ENCRYPTED_COLUMNS: dict[str, tuple[str, ...]] = {
    "family_logs": ("note",),
    "health_logs": ("note",),
    "mood_logs": ("note",),
    "sleep_logs": ("note",),
}

CIPHERTEXT_PATTERN = r"^v[0-9]+:[A-Za-z0-9_-]+$"

_DELETE_PLAINTEXT_CACHE = sa.text(
    """
    DELETE FROM sync_batches AS b
    WHERE EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(b.response -> 'results', '[]'::jsonb)) AS r(result)
        WHERE r.result ->> 'entity' = CAST(:entity AS text)
          AND jsonb_typeof(r.result -> 'server_row') = 'object'
          AND jsonb_typeof(r.result -> 'server_row' -> CAST(:column AS text)) = 'string'
          AND (r.result -> 'server_row' ->> CAST(:column AS text)) !~ CAST(:pattern AS text)
    )
    """
)


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    for entity, columns in ENCRYPTED_COLUMNS.items():
        for column in columns:
            bind.execute(
                _DELETE_PLAINTEXT_CACHE,
                {"entity": entity, "column": column, "pattern": CIPHERTEXT_PATTERN},
            )


def downgrade() -> None:
    # Deleted cache entries are not restorable and are not needed: see above.
    pass
