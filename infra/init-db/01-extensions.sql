-- KUNIM: PostgreSQL extensions required by the API.
-- Runs automatically on first container start because this file is mounted
-- into /docker-entrypoint-initdb.d/ (see infra/docker-compose.yml). It only
-- executes on an EMPTY data directory — it will NOT re-run against an
-- existing `pgdata` volume. Re-run manually (psql -f) after a schema wipe
-- if extensions are ever missing.

-- pgvector: vector similarity search, used for embeddings (RAG / semantic
-- search over published content).
CREATE EXTENSION IF NOT EXISTS vector;

-- pg_trgm: trigram matching, used for fuzzy/ILIKE-style text search.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- NOTE (phase 7): `unaccent` may be added here later if the RAG tsvector
-- search path needs accent-insensitive matching (e.g. Cyrillic/Latin Uzbek
-- text normalization). Not required by earlier phases — left commented out
-- on purpose so this file stays a faithful record of what phase introduced
-- each extension.
-- CREATE EXTENSION IF NOT EXISTS unaccent;
