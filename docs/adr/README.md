# Architecture Decision Records

Bu papkadagi ADR lar — KUNIM (Muslim Planner) uchun **majburiy shartnomalar**, insho emas. Har ADR
bitta qarorni, uning kontekstini, rad etilgan variantlarni va qayta ko'rib chiqish uchun aniq
trigger'ni qayd etadi. Implementatsiya bosqichlari shu hujjatlarga qarshi yoziladi: ADR da
`MUST` / `MUST NOT` deb yozilgan narsa kodda shunday bo'lishi shart, undan chetlashish uchun
avval ADR yangilanadi (yoki yangisi qo'shilib, eskisi `Superseded` qilinadi). Mahsulot talablari
manbai `docs/plan.md`; ADR unda yozilgandan tashqari fakt o'ylab topMAYDI — reja sukut saqlagan
joyda qaror `Consequences` bo'limidagi "Open question" punkti sifatida ochiq belgilanadi.
Sarlavhalar inglizcha, matn o'zbekcha bo'lishi mumkin (`CLAUDE.md`, Til bo'limi).

| # | Sarlavha | Status | Nimani bog'laydi |
|---|---|---|---|
| [0001](0001-stack.md) | Technology stack and platform floor | Accepted — 2026-09-12 | Flutter + Riverpod/go_router/Drift, FastAPI + PostgreSQL 16/pgvector + Redis + arq + SQLAdmin, Makefile monorepo; minimal pol: Android 8 (API 26), iOS 16, Dart 3, Python 3.11+ |
| [0002](0002-sync.md) | Offline-first sync protocol and conflict rules | Accepted — 2026-09-12 | Sync jadvallarining majburiy ustunlari, outbox invarianti, `POST /sync/push` va `GET /sync/pull` shakllari, konflikt qoidalari jadvali, tombstone 90 kun / `row_history` 30 kun |
| [0003](0003-dw-platforms.md) | Digital Wellbeing — Android and iOS are two different products | Accepted — 2026-09-12 | Android `UsageStats` (AccessibilityService/QUERY_ALL_PACKAGES/overlay yo'q), iOS FamilyControls/DeviceActivity, `dw_ios_mode` flag, qurilmadan faqat `dw_daily`/`dw_events`/`dw_score` chiqadi |
| [0004](0004-ai-provider.md) | Provider-independent AI layer, models and non-negotiable guardrails | Accepted — 2026-09-12 | `ProviderAdapter` Protocol, `ai_model_policy` jadvali, Voyage/`bge-m3` embeddings `vector(1024)`, citation substring verifikatsiyasi, kvota va xarajat logi |
