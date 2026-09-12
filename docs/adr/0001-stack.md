# ADR-0001: Technology stack and platform floor

**Holat:** Qabul qilingan
**Sana:** 2026-09-12

---

## Kontekst

KUNIM (Muslim Planner) — bitta dasturchi + Claude Code tomonidan ~24 hafta ichida MVP holatiga
olib chiqiladigan mahsulot (`docs/plan.md`, 12-bo'lim). Stek bir vaqtning o'zida quyidagilarni
qoplashi kerak:

1. iOS va Android uchun bitta kod bazasi, kuchli custom UI (kartochkali dizayn tizimi, progress
   ring, 4 til, Light/Dark/System).
2. Har ikki platformada **native** Digital Wellbeing modullari (Android `UsageStatsManager`,
   iOS `DeviceActivity`) — ya'ni typed platform-channel ko'prigi shart (ADR-0003).
3. **Offline-first** lokal baza: telefondagi SQLite = haqiqat manbai (`CLAUDE.md`, 4-qoida).
   Sxema relyatsion (tasks × categories × logs × goals × milestones), JOIN va versiyalangan
   migratsiya kerak; "row + outbox bitta tranzaksiyada" invarianti bajarilishi shart (ADR-0002).
4. Server tomonda AI/RAG: embedding saqlash, vektor qidiruv, LLM adapterlar, fon vazifalari
   (ADR-0004).
5. Yolg'iz dasturchi uchun arzon admin panel — kontent moderatsiyasi 3-bosqichdayoq kerak.

Bu ADR shu ehtiyojlar uchun tanlangan texnologiyalarni va **minimal platforma polini** qayd etadi.
Barcha keyingi bosqichlar shu ro'yxatga qarshi implementatsiya qilinadi.

---

## Qaror

### Mobil

| Qatlam | Tanlov |
|---|---|
| Framework | **Flutter**, **Dart 3** |
| State | `flutter_riverpod` + `riverpod_annotation` + `riverpod_generator` |
| Routing | `go_router` (deep link, `ShellRoute` bottom nav) |
| Lokal DB | `drift` + `drift_flutter` + `sqlcipher_flutter_libs` |
| Modellar | `freezed` + `json_serializable` |
| HTTP | `dio` + `dio_smart_retry` |
| Native ko'prik | `pigeon` (typed channel; Kotlin `UsageStats`, Swift Screen Time) |
| Fon | `workmanager` |
| Secret | `flutter_secure_storage` |

Paketlarning to'liq ro'yxati `docs/plan.md` 2-bo'limida; u ro'yxat shu ADR bilan birga majburiy.

### Backend

| Qatlam | Tanlov |
|---|---|
| API | **FastAPI**, async **SQLAlchemy 2** (`asyncpg`), **Pydantic v2** |
| Migratsiya | **Alembic** (yagona yo'l) |
| Baza | **PostgreSQL 16** + **pgvector** |
| Kesh / navbat / rate-limit | **Redis** |
| Fon vazifalari | **arq** |
| Admin panel | **SQLAdmin**, FastAPI ichida `/admin` |
| Runtime | **Python 3.11+** |

### Monorepo

Struktura `docs/plan.md` 1-bo'limidagidek: `apps/{mobile,api,admin}`,
`packages/{kunim_contracts,content_tools,design_tokens}`, `infra/`, `docs/`.
Orkestratsiya vositasi — oddiy **`Makefile`** (`make api | mobile | gen | test | lint`).

### Minimal platforma poli (binding)

| Maydon | Minimal qiymat | Sabab |
|---|---|---|
| Android | **8.0, API 26** (`minSdkVersion 26`) | `UsageStatsManager.queryEvents`: API 26–28 da `MOVE_TO_FOREGROUND/BACKGROUND`, 29+ da `ACTIVITY_RESUMED/PAUSED` — bitta kod yo'li bilan qoplanadi |
| Android target | Play ning o'sha paytdagi majburiy eng yuqori `targetSdk` si | Qiymat `apps/mobile/android/app/build.gradle` da bitta joyda saqlanadi |
| iOS | **16.0** (`IPHONEOS_DEPLOYMENT_TARGET 16.0`) | `FamilyControls` individual (non-guardian) avtorizatsiya iOS 16 dan |
| Dart | **3.x** (`sdk: '>=3.4.0 <4.0.0'`) | null-safety, `sealed` class, pattern matching, `freezed` 2.x |
| Python | **3.11+** (`requires-python >=3.11`) | `asyncio.TaskGroup`, `arq`/SQLAlchemy 2 async stack |
| PostgreSQL | **16** | pgvector HNSW, `jsonb`, `tsvector`, partial index |

---

## Sabablar

- **Bitta UI tili (Dart) + bitta server tili (Python)** — yolg'iz dasturchi uchun kontekst
  almashuvi minimal, Claude Code uchun kod bazasi bir jinsli.
- **Drift + SQLCipher** ADR-0002 dagi "lokal row + outbox bitta tranzaksiyada" invariantini
  texnik jihatdan kafolatlaydi, JOIN va versiyalangan migratsiya beradi, shifrlash uchun
  qo'shimcha qatlam talab qilmaydi.
- **pgvector** AI RAG uchun alohida vektor baza (Qdrant/Weaviate) va uning operatsion yukini
  olib tashlaydi; MVP miqyosida (≤ 1M chunk) HNSW yetarli.
- **arq** async FastAPI stack'iga tabiiy mos: bitta Redis, bitta `worker.py`; lider saylash
  muammosi yo'q, `cron` vazifasi bir marta ishlaydi.
- **SQLAdmin** ~2 kunlik ish evaziga kontent moderatsiya workflow'ini (`draft → review →
  approved → published → archived`) beradi.
- **API 26 / iOS 16** — DW modullari uchun texnik jihatdan mumkin bo'lgan eng past pol; undan
  pastga tushish ikkala DW mahsulotini ham yo'q qiladi (ADR-0003).

---

## Ko'rib chiqilgan alternativalar (va nega rad etilgan)

| Variant | Nega rad etildi |
|---|---|
| **React Native** | Custom kartochkali UI va bitta render quvuri Flutter'da barqarorroq (Impeller); DW native modullari RN da ham to'liq yozilishi kerak — ya'ni RN hech narsa tejamaydi; Drift darajasidagi type-safe relyatsion lokal ORM ekvivalenti RN ekotizimida yo'q. |
| **Kotlin Multiplatform** | UI har platformada alohida yoziladi → bitta dasturchi uchun 2× UI ishi. |
| **Node.js (NestJS/Express) backend** | AI/RAG quvuri (pgvector klientlari, LLM SDK'lari, embedding) va `content_tools` import CLI baribir Python bo'lardi → server ikki tilga bo'linardi. Pydantic v2 + SQLAlchemy 2 + Alembic juftligi TS ORM'laridan (Prisma migratsiya cheklovlari) kuchliroq. |
| **Celery** | Broker + result backend + beat konfiguratsiyasi va operatsion og'irligi solo dev uchun ortiqcha; sync/async ko'prigi FastAPI bilan noqulay. |
| **APScheduler** | Ikki replikada bir vazifa ikki marta ishlaydi (lider saylash yo'q) — `daily_review` / `notif_scheduler` uchun qabul qilib bo'lmaydi (dublikat push). |
| **Isar / Hive** | JOIN yo'q; KUNIM sxemasi relyatsion. Migratsiya va shifrlash zaif; "row + outbox bitta tranzaksiyada" invarianti kafolatlanmaydi (ADR-0002 buzilardi). |
| **Melos / Nx** | Bitta Flutter app + bitta Python app uchun ortiqcha qatlam; `Makefile` yetarli. |
| **BLoC** | Riverpod bilan bir xil natijaga sezilarli ko'p boilerplate bilan yetadi; compile-time xavfsiz provider grafigi, `ProviderContainer` bilan widget'siz test va `riverpod_generator` Riverpod'da arzonroq. |
| **Next.js admin MVP da** | Alohida frontend loyiha + auth + deploy quvuri kerak bo'lardi; kontent moderatsiyasi uchun jadval CRUD + amallar yetarli. |
| **MySQL / server tomonda SQLite** | pgvector, `jsonb`, `tsvector` FTS va partial index KUNIM'da bir vaqtda kerak. |

---

## Oqibatlar

### Ijobiy

- Bitta `make gen` buyrug'i freezed/drift/riverpod/pigeon/openapi-client'ni generatsiya qiladi —
  kontrakt drift'i CI da ushlanadi (`make gen && git diff --exit-code`).
- Klient DTO'lari `packages/kunim_contracts` orqali server OpenAPI'sidan generatsiya qilinadi →
  qo'lda yozilgan model nomuvofiqligi yo'q.
- Infratuzilma 5 konteynerga sig'adi: `postgres`, `redis`, `api`, `worker`, `minio`.
- Drift'ning reaktiv `watch()` oqimlari offline-first UI ni to'g'ridan-to'g'ri quvvatlaydi.

### Salbiy

- Generatsiyaga bog'liqlik: `make gen` unutilganda kompilyatsiya xatolari.
- SQLAdmin admin UI ni cheklaydi — xarajat grafigi kabi narsalar faqat read-only ko'rinish.
- API 26 poli Android foydalanuvchilarining kichik eski qismini yo'qotadi.
- SQLCipher APK/IPA hajmini ~2–3 MB oshiradi.
- Flutter va Docker ushbu ishlab chiqish mashinasida o'rnatilmagan (`CLAUDE.md`, "Muhit") →
  mobil va konteyner tekshiruvlari `docs/implementation-status.md` da "tekshirilmagan" deb
  belgilanadi.

---

## Amalga oshirish uchun majburiy qoidalar

1. Mobil ilova **faqat** Flutter/Dart 3 da yoziladi. Quyidagi paketlar loyihaga **kirmaydi**:
   `get`, `hive`, `isar`, `bloc`, `flutter_hooks`, `graphql`, `app_usage`.
2. State — faqat Riverpod (`riverpod_generator`); navigatsiya — faqat `go_router` yo'nalishlari,
   to'g'ridan-to'g'ri `Navigator.push` ishlatilmaydi.
3. Lokal baza — faqat Drift + SQLCipher. DB kaliti har o'rnatishda tasodifiy generatsiya
   qilinadi va `flutter_secure_storage` da saqlanadi.
4. Native ko'prik — faqat `pigeon` generatsiya qilgan typed channel (`core/platform/*.g.dart`).
   Qo'lda `MethodChannel` yozilmaydi.
5. Backend modul shakli qat'iy: `modules/<name>/{router,schemas,models,service,repository}.py`.
   Router biznes-mantiq saqlamaydi; repository'dan tashqarida xom SQL yozilmaydi.
6. Har qanday sxema o'zgarishi faqat Alembic migratsiyasi orqali. Prod'da `create_all()` yoki
   qo'lda DDL ishlatilmaydi.
7. Fon vazifalari faqat `arq` (`apps/api/app/jobs/worker.py`); `celery`, `apscheduler`,
   `schedule` paketlari `pyproject.toml` ga qo'shilmaydi.
8. CI polni tekshiradi: `minSdkVersion == 26`, `IPHONEOS_DEPLOYMENT_TARGET == 16.0`,
   `requires-python >= 3.11`, PostgreSQL 16 image tegi. **Polni pasaytirish yangi ADR talab
   qiladi.**
9. Generatsiya qilingan fayllar (`*.g.dart`, `*.freezed.dart`, `*.drift.dart`) qo'lda
   tahrirlanmaydi — `make gen`.
10. Monorepo orkestratsiyasi — faqat `Makefile`. `melos.yaml` / `nx.json` qo'shilmaydi.

---

## Rejada aniqlanmagan — shu yerda hal qilindi

| Savol | Qaror |
|---|---|
| Android `targetSdk` | Reja faqat `minSdk` ni nazarda tutgan. Play ning o'sha paytdagi majburiy eng yuqori `targetSdk` siga rioya qilinadi; qiymat `apps/mobile/android/app/build.gradle` da bitta joyda. |
| PostgreSQL image tegi | `pgvector/pgvector:pg16` (extension oldindan o'rnatilgan). |
| `apps/admin` (Next.js) qachon ochiladi | Reja faqat "2-bosqich" deydi, mezon bermaydi. SQLAdmin bilan bajarib bo'lmaydigan **birinchi** admin talabi paydo bo'lgunicha bo'sh qoladi. |
| Dart SDK cheklovi | `sdk: '>=3.4.0 <4.0.0'`, `pubspec.yaml` da qat'iy. |
| Python paket menejeri | `uv`; `uv.lock` commit qilinadi, `pyproject.toml` PEP 621 formatida. |
| Redis topologiyasi | Bitta instans, mantiqiy DB indekslari bilan ajratiladi (`0` = arq navbati, `1` = kesh/rate-limit). |

---

## Qachon qayta ko'riladi

1. Play/App Store yangi majburiy target talabi polni ko'tarishga majbur qilsa, yoki Android 8 /
   iOS 16 ulushi qo'llab-quvvatlashga arzimay qolsa;
2. SQLAdmin bilan bajarib bo'lmaydigan admin talabi paydo bo'lsa (`apps/admin` ochiladi);
3. arq job kechikishi ≥ 1000 faol foydalanuvchida p95 > 5 daqiqaga chiqsa;
4. pgvector HNSW qidiruvi `content_chunks` ≥ 5M qatorda p95 > 300 ms bersa.
