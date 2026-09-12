# KUNIM (Muslim Planner) — konvensiyalar

Mahsulot talablari manbai: `docs/plan.md`. Bosqich holati: `docs/implementation-status.md`.

## Monorepo
```
apps/api      FastAPI + PostgreSQL16(pgvector) + Redis   (Python 3.11+)
apps/mobile   Flutter (Riverpod, go_router, Drift/SQLCipher)
apps/admin    2-bosqich (Next.js) — hozircha bo'sh
packages/     kunim_contracts · content_tools · design_tokens
infra/        docker-compose, Dockerfile, Caddyfile
docs/         plan, ADR, content-policy, privacy, checklist
```
Melos/Nx ishlatilmaydi — `Makefile` yetarli.

## Til
- **Kod, identifikator, kommentariya, commit, ADR sarlavhasi — inglizcha.**
- **UI matni — hech qachon kodda hardcode qilinmaydi**: `apps/mobile/lib/app/l10n/*.arb` (`uz`, `uz_Cyrl`, `ru`, `en`).
- Hujjatlar (`docs/`) o'zbekcha bo'lishi mumkin.

## Qat'iy qoidalar
1. **Hech qachon oyat, hadis yoki diniy hukm o'ylab topilmaydi.** Har qanday diniy iqtibos `content` jadvalidagi `published` yozuvdan keladi va `quoted_text` chunk ichida substring sifatida tekshiriladi. Manba yo'q → refusal shabloni. LLM hech qachon manba emas.
2. **Lokal yozuv + outbox bitta tranzaksiyada.** Repository hech qachon row'ni outbox'siz yozmaydi.
3. **Server foydalanuvchi ma'lumotiga AI nomidan yozmaydi.** AI faqat `ai_proposals` yaratadi; foydalanuvchi qabul qilgach klient lokal yozadi va odatdagi sync orqali yuboradi.
4. **Telefondagi SQLite = haqiqat manbai.** Server = sync + AI + kontent.
5. **Android va iOS Digital Wellbeing — ikki xil mahsulot.** iOS raqamlari `DeviceActivityReport` sandbox'idan chiqmaydi; iOS Score "taxminiy" deb belgilanadi.
6. `AccessibilityService`, `QUERY_ALL_PACKAGES`, `SYSTEM_ALERT_WINDOW` ishlatilmaydi.
7. Secret va shaxsiy ma'lumot logga chiqmaydi. Xom DW sessiyalari hech qachon serverga yuklanmaydi.

## Flutter qoidalari
- Feature-first: `features/<name>/{data,domain,application,presentation}`.
- Feature boshqa feature'ning `data/` qatlamini import qilmaydi; umumiy narsa `core/` yoki `shared/` da.
- Har jadval `core/db/tables/` da, egasi bitta feature.
- Generatsiya qilingan fayllar (`*.g.dart`, `*.freezed.dart`) qo'lda tahrirlanmaydi — `make gen`.
- Ishlatilmaydi: `get`, `hive`, `isar`, `bloc`, `flutter_hooks`, `graphql`, `app_usage`.

## Backend qoidalari
- Modul = `modules/<name>/{router,schemas,models,service,repository}.py`. Router biznes-mantiq saqlamaydi.
- Async SQLAlchemy 2 (`asyncpg`), migratsiya faqat Alembic orqali.
- Sync jadvallarida majburiy: `id UUID`, `user_id`, `created_at`, `updated_at (UTC)`, `deleted_at`, `server_version BIGINT`.
- Fon vazifalari — `arq` (Celery/APScheduler emas).

## Buyruqlar
```
make api        # FastAPI dev server
make test-api   # pytest
make gen        # freezed/drift/riverpod/pigeon/openapi client
make lint       # ruff + dart analyze
```

## Muhit (2026-09-12 holati, ushbu mashinada)
Python 3.11.8 ✅ · Node 20 ✅ · Java 17 ✅ · Git ✅
Flutter ❌ o'rnatilmagan · Android SDK ❌ · Docker ❌ · PostgreSQL/Redis ❌
→ Flutter va Docker'ga bog'liq tekshiruvlar shu mashinada bajarilmaydi; `docs/implementation-status.md` da "tekshirilmagan" deb belgilanadi.
