# Architecture Decision Records

Bu papkadagi ADR lar — KUNIM (Muslim Planner) uchun **majburiy shartnomalar**, insho emas.
Implementatsiya bosqichlari shu hujjatlarga qarshi yoziladi: ADR da qayd etilgan qoida kodda
shunday bo'lishi shart. Undan chetlashish uchun avval ADR yangilanadi (yoki yangisi qo'shilib,
eskisi `Superseded` qilinadi) — kod birinchi o'zgarmaydi.

Mahsulot talablari manbai — `docs/plan.md`. ADR undan tashqari **fakt o'ylab topmaydi**: reja
sukut saqlagan yoki ziddiyatli joyda qaror shu yerda qabul qilinadi va ADR oxiridagi
**"Rejada aniqlanmagan — shu yerda hal qilindi"** bo'limida ochiq sanab o'tiladi.

Sarlavhalar va identifikatorlar inglizcha, matn o'zbekcha (`CLAUDE.md`, Til bo'limi).

## Indeks

| # | Sarlavha | Holat | Nimani bog'laydi |
|---|---|---|---|
| [0001](0001-stack.md) | Technology stack and platform floor | Qabul qilingan — 2026-09-12 | Flutter + Riverpod/go_router/Drift+SQLCipher; FastAPI + async SQLAlchemy 2 + PostgreSQL 16/pgvector + Redis + arq + SQLAdmin; Makefile monorepo. Minimal pol: Android 8 (API 26), iOS 16, Dart 3, Python 3.11+ |
| [0002](0002-sync.md) | Offline-first sync protocol and conflict rules | Qabul qilingan — 2026-09-12 | Majburiy ustunlar, klient UUIDv4, outbox invarianti, `POST /sync/push` va `GET /sync/pull` wire kontrakti, `batch_id` idempotentligi, 24 qatorli konflikt matritsasi, tombstone 90 kun / `row_history` 30 kun, jadval tasnifi, AI invarianti |
| [0003](0003-dw-platforms.md) | Digital Wellbeing — Android and iOS are two different products | Qabul qilingan — 2026-09-12 | Android `UsageStatsManager` + WorkManager 15 daq (AccessibilityService / QUERY_ALL_PACKAGES / SYSTEM_ALERT_WINDOW **yo'q**); iOS FamilyControls/DeviceActivity, `dw_ios_mode` flag; qurilmadan faqat `dw_daily`, `dw_events`, `dw_score` chiqadi |
| [0004](0004-ai-provider.md) | Provider-independent AI layer, models and non-negotiable guardrails | Qabul qilingan — 2026-09-12 | `ProviderAdapter` Protocol, `ai_model_policy` jadvali (model va narx DB da), Voyage `voyage-multilingual-2` / lokal `bge-m3` — `vector(1024)`, citation substring verifikatsiyasi, fatvo refusal, kvota va xarajat logi |

## Shablon (MADR, o'zbekcha)

Yangi ADR `000N-<qisqa-ingliz-nom>.md` sifatida yaratiladi va quyidagi tuzilishga amal qiladi:

```markdown
# ADR-000N: <English title>

**Holat:** Taklif qilingan | Qabul qilingan | Rad etilgan | Superseded by ADR-000M
**Sana:** YYYY-MM-DD

---

## Kontekst
<!-- Qanday kuchlar ta'sir qilmoqda; nima uchun bu qaror hozir kerak. -->

## Qaror
<!-- Nima tanlandi. Aniq, o'lchanadigan, taxminsiz. Jadval va kod bloklari bu yerda. -->

## Sabablar
<!-- Nega aynan shu. -->

## Ko'rib chiqilgan alternativalar (va nega rad etilgan)
<!-- Jadval: | Variant | Nega rad etildi | -->

## Oqibatlar
### Ijobiy
### Salbiy

## Amalga oshirish uchun majburiy qoidalar
<!-- Raqamlangan ro'yxat. Implementatsiya agenti to'g'ridan-to'g'ri shu ro'yxatga qarshi ishlaydi. -->

## Rejada aniqlanmagan — shu yerda hal qilindi
<!-- Jadval: | Savol | Qaror |. Reja sukut saqlagan yoki ziddiyatli bo'lgan har bir nuqta. -->

## Qachon qayta ko'riladi
<!-- Aniq trigger'lar, "kerak bo'lganda" emas. -->
```

### Qoidalar

1. Har ADR **bitta** qarorni qamrab oladi.
2. Qabul qilingan ADR **tahrirlanmaydi** — u faqat yangisi bilan almashtiriladi
   (`Superseded by ADR-000M`). Imlo va havola tuzatishlari bundan mustasno.
3. "Rejada aniqlanmagan" bo'limi bo'sh bo'lishi mumkin, lekin **olib tashlanmaydi** — u
   rejadagi bo'shliqlarni kuzatish uchun.
4. "Qachon qayta ko'riladi" da o'lchanadigan trigger bo'lishi shart (metrika, sana, tashqi
   hodisa) — "kerak bo'lganda" qabul qilinmaydi.
