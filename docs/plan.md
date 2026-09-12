# KUNIM (Muslim Planner) — iOS va Android ilovasini ishlab chiqish rejasi

## Kontekst

**Nima uchun:** ТЗ ("ТЗ-МОБИЛ ИЛОВА.docx", 78 bo'lim) bo'yicha "KUNIM" nomli shaxsiy hayot, vaqt va rivojlanish intellektual assistenti yaratiladi. Bu oddiy planner/habit tracker emas: kun tartibi + namoz/Qur'on + odatlar + ruhiy holat + sog'liq/uyqu + ta'lim + oila + Digital Wellbeing (bekorchi skrolling, "vaqtingizni qaytaring") + AI (planner, reschedule, coach, tutor, memory, RAG) bitta ekotizimda. Asosiy tamoyil: *"Foydalanuvchi rejaga moslashmaydi — ilova foydalanuvchiga moslashadi."*

**Hozirgi holat:** `D:\Dasturlarim\Muslim Planner` papkasi bo'sh. Loyiha noldan boshlanadi.

**Qabul qilingan qarorlar:**
| Qaror | Tanlov | Sabab |
|---|---|---|
| Mobil | **Flutter** (Dart 3, Android 8+ / iOS 16+) | Bitta kod bazasi, kuchli custom UI, native modullar Pigeon orqali |
| Backend | **Python / FastAPI** + PostgreSQL 16 (pgvector) + Redis | AI/RAG ekotizimi, async, arq fon vazifalari |
| Admin | **SQLAdmin** (FastAPI ichida, `/admin`) | Yolg'iz dasturchi uchun ~2 kunlik ish; Next.js — 2-bosqichda |
| Jamoa | Yolg'iz dasturchi + Claude Code (~30 soat/hafta) | Bosqichlar kichik, har biri ishlaydigan ilova beradi |
| Muddat | MVP ≈ 24 hafta (buffer bilan 26) | ТЗ 71-bo'lim MVP hajmi |
| Til | Kod inglizcha; UI 4 til (uz-Latn, uz-Cyrl, ru, en) | ТЗ 56; ar/tr/kk/ky uchun ARB qo'shish kifoya |
| AI | Anthropic adapter birinchi, OpenAI-compatible ikkinchi; embeddings Voyage (`voyage-multilingual-2`), dev uchun lokal `bge-m3` | Provider-independent (ТЗ 36) |

**O'zgarmas tamoyillar (solo dev uchun):**
1. Telefondagi SQLite = haqiqat manbai; server = sync + AI + kontent.
2. AI aytadigan har qanday diniy iqtibos `content` jadvalidagi tasdiqlangan yozuvdan keladi. LLM hech qachon manba emas.
3. Android va iOS Digital Wellbeing — bitta UI ostidagi **ikki xil mahsulot**. Bu birinchi kundan qabul qilinadi.
4. Har bosqich oxirida `flutter build apk` + `docker compose up` ishlaydi.

---

## 1. Umumiy arxitektura va monorepo

```
┌──────────────────────────────────────────────────────────────┐
│  apps/mobile (Flutter)                                        │
│  Riverpod + go_router + Drift(SQLCipher, offline-first)       │
│  Native (Pigeon): Android UsageStats / iOS DeviceActivity     │
└───────────────▲───────────────────────────▲───────────────────┘
                │ REST+JSON (dio, JWT)      │ FCM / APNs push
┌───────────────┴───────────────────────────┴───────────────────┐
│  apps/api (FastAPI, async SQLAlchemy 2, Alembic, Pydantic v2)  │
│  modules/* routerlar (ТЗ 52) · sync · ai/* · content · admin   │
│  AIService → SafetyLayer → RAG → ProviderAdapter               │
│  worker (arq): reviews, stats, notifications, AI batch         │
└───────────────┬───────────────────────────┬───────────────────┘
        PostgreSQL 16 (+pgvector)        Redis (cache, queue, rate-limit)
```

```
Muslim Planner/
├── apps/
│   ├── mobile/                 # Flutter
│   ├── api/                    # FastAPI (+ SQLAdmin /admin)
│   └── admin/                  # 2-bosqich (Next.js), hozircha bo'sh
├── packages/
│   ├── kunim_contracts/        # FastAPI OpenAPI → Dart client generatsiya
│   ├── content_tools/          # Python CLI: Qur'on/hadis import, chunking, embedding, checksum
│   └── design_tokens/          # ranglar/typography JSON → Dart theme
├── infra/
│   ├── docker-compose.yml      # postgres16+pgvector, redis, api, worker, minio
│   ├── docker-compose.prod.yml
│   └── Caddyfile               # TLS
├── docs/
│   ├── TZ.md                   # ТЗ markdown nusxasi
│   ├── adr/                    # 0001-stack, 0002-sync, 0003-dw-platforms, 0004-ai-provider
│   ├── content-policy.md       # diniy kontent verifikatsiya jarayoni
│   ├── privacy/                # data map, retention, Play/App Store deklaratsiyalari
│   ├── balance-formula.md, backlog.md, acceptance-checklist.md
├── .github/workflows/          # mobile.yml, api.yml, content.yml
├── Makefile                    # make api | mobile | gen | test
└── CLAUDE.md                   # konvensiyalar (papka qoidalari, "hech qachon hadis o'ylab topma")
```
Melos/Nx ishlatilmaydi — Makefile yetarli.

---

## 2. Mobil ilova (Flutter)

**Paketlar (minimal, har biri asoslangan):**
| Vazifa | Paket | Izoh |
|---|---|---|
| State | `flutter_riverpod` + `riverpod_annotation` + `riverpod_generator` | Compile-time xavfsiz, widget'siz test; BLoC ko'p boilerplate |
| Routing | `go_router` | Deep link (notification tap), `ShellRoute` bottom nav |
| Lokal DB | `drift` + `drift_flutter` + `sqlcipher_flutter_libs` | Type-safe SQL, migratsiya, reaktiv `watch()`, shifrlangan; Isar/Hive'da JOIN yo'q |
| Modellar | `freezed` + `json_serializable` | Immutable DTO, sync op va AI proposal union'lari |
| HTTP | `dio` + `dio_smart_retry` | JWT refresh interceptor, retry |
| i18n | `flutter_localizations` + `intl` + ARB (`gen-l10n`) | `en`, `ru`, `uz`, `uz_Cyrl`; CI da `l10n_check` |
| Xavfsiz saqlash | `flutter_secure_storage` | Refresh token + DB kaliti; access token faqat xotirada |
| Namoz | `adhan_dart` | Offline, barcha usullar, Hanafiy asr |
| Bildirishnoma | `flutter_local_notifications` + `timezone` + `flutter_timezone` | Zoned scheduling |
| Push | `firebase_core` + `firebase_messaging` | iOS'da APNs FCM orqali |
| Geo | `geolocator` + `geocoding` | Bir marta; doimiy kuzatuv yo'q; `assets/cities.json` qo'lda tanlash |
| Audio | `just_audio` + `just_audio_background` + `flutter_cache_manager` | Qur'on stream + kesh (500 MB LRU) |
| Background | `workmanager` | Android agregatsiya, namoz jadvalini yangilash |
| Native bridge | `pigeon` (dev) | Typed channel: UsageStats (Kotlin), Screen Time (Swift). `app_usage` pub paketi ishlatilmaydi (juda qo'pol) |
| Analytics/Crash | `posthog_flutter`, `sentry_flutter` | Sentry API tomonda ham |
| Grafik | `fl_chart` | |
| Boshqa | `uuid`, `connectivity_plus`, `package_info_plus`, `share_plus`, `path_provider`, `url_launcher`, `google_sign_in`, `sign_in_with_apple`, `flutter_svg` | |

Ishlatilmaydi: `get`, `hive`, `isar`, `bloc`, `flutter_hooks`, `graphql`.

**Papka tuzilishi (feature-first):**
```
apps/mobile/lib/
├── main.dart                   # Firebase, Drift, ProviderScope, Sentry bootstrap
├── app/{app.dart, router/app_router.dart, theme/{app_theme,tokens,color_schemes}.dart, l10n/*.arb}
├── core/
│   ├── db/{app_database.dart, tables/*.drift, daos/, migrations.dart}
│   ├── sync/{sync_engine.dart, outbox.dart, sync_models.dart, conflict.dart}
│   ├── network/{api_client.dart, auth_interceptor.dart, error_mapper.dart}
│   ├── auth/{auth_repository.dart, token_store.dart, session_provider.dart}
│   ├── notifications/{local_notifier.dart, push_handler.dart, notification_policy.dart}
│   ├── platform/{usage_stats_api.g.dart, screen_time_api.g.dart}   # pigeon
│   ├── analytics/  utils/{date_ext, hijri, result}.dart
├── features/<feature>/{data, domain, application, presentation}/
│   # onboarding auth profile home planner calendar tasks habits goals prayer quran wisdom
│   # mood sleep health education books work family leisure statistics reviews wellbeing ai
│   # notifications_center settings
└── shared/widgets/             # KunimCard, ProgressRing, EmptyState, ...
```
`CLAUDE.md` qoidalari: feature'lar bir-birining `data/` qatlamini import qilmaydi; har jadval `core/db/tables` da, egasi bitta feature.

**Navigatsiya (ТЗ 54):** Bosh sahifa | Kun tartibi | Statistika | AI | Sozlamalar (mahsulot testidan keyin o'zgarishi mumkin).

**Dizayn tizimi:** yuborilgan mockup asosida — minimalistik, kartochkali, radius 16–20, har modul o'z rangi (namoz yashil, Qur'on ko'k, ruhiy holat binafsha, oila qizil, sog'liq teal, ish sariq, uyqu indigo), progress ring/bar, Material 3 `ColorScheme.fromSeed`, Light/Dark/System. Arab shrifti `Amiri` yoki KFGQPC Uthmanic (litsenziya tekshiriladi). Accessibility: text scale 200%, touch ≥ 48dp, semantics, rangga bog'liq bo'lmagan belgilar. RTL — `ar` pseudo-locale bilan 9-bosqichda smoke test.

---

## 3. Offline-first va sinxronizatsiya

**Har sync jadvalida:** `id UUID(v4, klient)`, `user_id`, `created_at`, `updated_at (UTC)`, `deleted_at`, `server_version BIGINT`, `dirty BOOL (faqat lokal)`.

**Outbox:** `sync_outbox(seq, entity, row_id, op upsert|delete, payload json, attempts, last_error)`. Repository yozuvi = bitta Drift tranzaksiya (row + outbox). `SyncEngine` trigger: app resume, internet qaytdi, foreground'da har 5 daq, N yozuvdan keyin, pull-to-refresh. Batch ≤ 200.

**Endpointlar:**
- `POST /sync/push` — `{device_id, batch_id, changes[]}`; `batch_id` `sync_batches` da saqlanadi (idempotent). Javob: har change uchun `applied|conflict|rejected` + `server_version`.
- `GET /sync/pull?cursor=&limit=500` — `version > cursor`, tombstone'lar bilan, `next_cursor`. Cursor `sync_state` da; yangi qurilma cursor=0.

**Konflikt (`apps/api/app/modules/sync/merge.py`):** row-level last-write-wins (`updated_at`), istisnolar:
- `tasks.completed_at` — max wins (sync hech qachon "bajarilmadi" qilmaydi).
- `habit_logs/prayer_logs/mood_logs/sleep_logs/health_logs` — natural key `(user_id, ref_id, date)`; sonli additiv maydonlar (suv ml, qadam) max.
- `quran_progress.last_ayah_key` LWW; `pages_read_total` max.
- `updated_at` 24 soatdan kelajakda → `rejected`, klient qayta muhrlaydi.
- Soft delete `deleted_at > updated_at` bo'lsa g'olib; tombstone 90 kundan keyin tozalanadi (eski cursor → to'liq resync).
- Server `row_history` (30 kun) — support orqali tiklash uchun.

| Offline (sync) | Faqat onlayn | Faqat lokal (yuklanmaydi) |
|---|---|---|
| tasks, task_categories, calendar_events, habits, habit_logs, goals, milestones, prayer_logs, quran_progress, quran_bookmarks, mood/sleep/health_logs, education_items, books, preferences, app_limits, DW kunlik agregat (upload-only) | auth, avatar, AI chat/planner/reschedule/recs/memory, server statistika, admin | xom `dw_sessions`, `scrolling_events`, notification engagement log (kunlik agregat yuklanadi), AI javob keshi |
| Read-only kesh: `content` (hikmatlar), Qur'on (bundled), namoz preset'lar | | |

---

## 4. Digital Wellbeing — platformalar bo'yicha (ТЗ 47)

### Android (to'liq)
- `PACKAGE_USAGE_STATS` — `Settings.ACTION_USAGE_ACCESS_SETTINGS` intent; oldin **in-app disclosure ekrani** (Play Permissions Declaration Form talabi). DW store listing'da asosiy funksiya sifatida yoziladi.
- `QUERY_ALL_PACKAGES` **so'ralmaydi**; manifest `<queries><intent MAIN/LAUNCHER>` kifoya.
- `AccessibilityService` **ishlatilmaydi** — Play siyosati (faqat nogironlar uchun), ТЗ 46 (boshqa ilova kontentini o'qish taqiqlangan). Shuning uchun scroll-darajali aniqlash yo'q; "bekorchi skrolling" sessiya shaklidan chiqariladi.
- Kotlin `android/.../wellbeing/`: `UsageCollector.kt` (`queryEvents`, ACTIVITY_RESUMED/PAUSED, API 26–28 uchun MOVE_TO_*; 3 s dan kichik bo'shliqlar birlashtiriladi; SCREEN_INTERACTIVE → pickups), `AppCategoryResolver.kt` (`ApplicationInfo.category` + `assets/app_categories.json` override; foydalanuvchi qayta belgilaydi), `UsageWorker.kt` (WorkManager 15 daq + app ochilganda + BOOT_COMPLETED; xom sessiyalarni `usage_sessions_raw` ga yozadi, Dart resume'da import qiladi).
- MVP da foreground service yo'q (Android 14 friction, batareya) → Smart Warning kechikishi ≤ 15 daq. 2-bosqich: opt-in "Focus session" foreground service.
- Limit = faqat bildirishnoma (80% / 100%, amallar: Ochish / 15 daq kechiktirish / Bugun uzaytirish). Overlay bloklash yo'q (`SYSTEM_ALERT_WINDOW` siyosat xavfi).
- Xiaomi/Huawei battery killer → in-app whitelisting yo'riqnomasi; "14:00 dan beri ma'lumot yo'q" halol ko'rsatiladi.

### iOS (cheklangan — qat'iy qabul qilinadi)
- `FamilyControls` + `DeviceActivity` + `ManagedSettings`, iOS 16+ individual avtorizatsiya. Entitlement `com.apple.developer.family-controls` — **so'rov 0-bosqichda yuboriladi** (haftalar/oylar; rad etilishi mumkin; qurilmada dev ishlaydi, App Store'ga tasdiqsiz chiqmaydi).
- `FamilyActivityPicker` opaque token qaytaradi — ilova bundle ID/nomni bilmaydi.
- `DeviceActivityReport` extension (`ios/KunimReport/`): statistika faqat sandboxed SwiftUI view'da; **raqamlar ilovaga/serverga chiqmaydi**.
- `DeviceActivityMonitor` extension (`ios/KunimMonitor/`): kunlik schedule, har limit uchun 80%/100% event → lokal notification + App Group flag `{limitId, level, ts}`; ilova resume'da `dw_events` ga yozadi. Extension xotirasi ~6 MB — minimal kod.
- `ManagedSettingsStore.shield` MVP da o'chiq (Android bilan paritet); 2-bosqichda "Qat'iy rejim".
- iOS "bekorchi vaqt" = threshold eventlar + self-report ("Bu vaqt foydali bo'ldimi?") → Score "taxminiy" deb belgilanadi.
- Feature flag `dw_ios_mode = full | selfreport`; entitlement rad etilsa iOS self-report bilan chiqadi.

### Umumiy model va formulalar
- Klient jadvallari: `dw_sessions(app_key, category, started_at, ended_at, duration_s, hour_of_day, pickup_gap_s, source)`, `dw_daily(date, app_key, category, minutes, sessions, waste_minutes_est)`, `dw_events(type warn80|warn100|snoozed|extended|closed_after_warn|selfreport_*, ts)`. Serverga faqat `dw_daily` (app_key foydalanuvchi ruxsatisiz hash), `dw_events`, `dw_score`. Xom sessiya hech qachon yuklanmaydi.
- **Bekorchi skrolling ehtimoli** (`wellbeing/domain/waste_scorer.dart`, og'irliklar remote-config JSON da):
  `p = sigmoid(w_cat·cat + w_dur·f(dur) + w_night·night + w_reopen·reopen + w_focus·in_focus_block + w_self·self_report)`
  cat: social_shortform 1.0, video 0.8, social 0.7, games 0.6, news 0.4, messaging 0.2, productivity/education/quran 0. f(dur): <3 daq 0, 3–10 0.5, 10–30 1.0, >30 1.2. night: 23:00–05:00. reopen: 5 daq ichida qayta kirish. `waste_min = Σ dur·p` (p > 0.5). Ta'lim/kitob/Qur'on/ish hech qachon bekorchi emas. ML — 2-bosqich (self-report'dan o'rgatiladi).
- **DW Score:** `100 − 30·clamp(total/target−1) − 30·clamp(waste/60) − 15·clamp(night/30) − 15·clamp(breaches/3) + 10·(focus_respected/focus_planned)`, iOS variantida birinchi had yo'q.
- **Vaqtingizni qaytaring:** `baseline = median(waste, DW yoqilgandan keyingi 14 kun)` (oyiga qayta hisob); `daily_recovered = max(0, baseline − today_waste) + warn80 dan 5 daq ichida yopilganda qolgan limit`. Haftalik/oylik yig'indi; kitob/sport/ta'lim/oila/dam olishga taqsimlash taklifi.

---

## 5. AI arxitekturasi (`apps/api/app/ai/`)

```
ai/
├── service.py                 # AIService: safety → context → rag → provider → validate → log
├── providers/{base.py, anthropic_adapter.py, openai_compat_adapter.py, embeddings/{voyage,local_bge_m3}.py}
├── agents/{chat,planner,rescheduler,coach,tutor,analyst,wellbeing,recommender}.py
├── prompts/*.j2  (shared/safety.j2, persona.j2, locale.j2)
├── schemas/      # PlanProposal, RescheduleProposal, Recommendation, WisdomAnswer, Insight
├── rag/{chunker,indexer,retriever,citation}.py
├── memory/{service,extractor}.py
├── safety/{input_filter,output_classifier,rules,religious_guard}.py
├── context/builder.py         # token budjet bilan user kontekst
└── usage/{limiter,cost}.py
```

- **ProviderAdapter** (Protocol): `complete`, `stream`, `complete_structured(schema)`, `embed`. Anthropic: `claude-opus-5` (planner/reschedule/coach), `claude-sonnet-5` (chat/tutor/analyst/recommender), `claude-haiku-4-5` (klassifikatorlar, memory extraction); structured output Pydantic sxema bilan; streaming SSE; prompt caching (statik system + RAG siyosati → cache breakpoint, keyin o'zgaruvchan kontekst); `stop_reason == refusal` → xavfsiz xabar. OpenAI-compat: `openai` SDK + `base_url`, `response_format`. Ikkalasi `tests/ai/test_adapter_contract.py` da fixtures bilan. Model tanlovi `ai_model_policy` jadvalida (admin tahrirlaydi).
- **Agentlar va chiqishlar:** planner → `PlanProposal{blocks[{start,end,task_id?,kind,title,reason}], top3_task_ids, warnings}`; rescheduler → `RescheduleProposal{moves[], drops[], conflicts[]}`; coach (haftalik job) → `CoachMessage`; analyst (oylik) → `Insight[]`; wellbeing → `WellbeingAdvice`; recommender → `Recommendation[]{type,title,body,deeplink,priority,expires_at,reason}`.
- **Proposal oqimi:** `ai_proposals(agent, payload jsonb, status proposed|accepted|modified|rejected, applied_diff)`. Klient diff ko'rsatadi; **server tasks/calendar'ga to'g'ridan-to'g'ri yozmaydi** — qabul oddiy sync yo'li bilan (offline invariantlar saqlanadi). Chat agent tool'lari faqat o'qish: `get_today_plan`, `search_religious_content`, `get_stats`, `get_prayer_times`.
- **RAG:** `content_sources(type, title, author, translator, edition, license, verified_by, verified_at)`, `content(source_id, kind ayah|hadith|quote|article, ref "2:255"/"Bukhari 6018", text_ar, text_by_lang jsonb, grade, topic_tags, status, checksum)`, `content_chunks(lang, chunk_text, embedding vector(1024) HNSW cosine, metadata)`. Faqat `published` indekslanadi. Retriever: pgvector top-20 + `tsvector` top-20 → RRF → top-6. `WisdomAnswer{answer, citations[{content_id, ref, source_title, quoted_text}], refused}`; `citation.py` har `quoted_text` chunk ichida substring ekanini tekshiradi, aks holda refusal shablon. Oyat raqamlari Qur'on jadvaliga qarshi validatsiya.
- **Intent klassifikator** (haiku, kesh): `religious_ruling | religious_info | general | medical | psychological`. Fatvo-tipi → doim rad + muftiyatga yo'naltirish; `religious_info` → RAG majburiy.
- **Kun hikmati generatsiya qilinmaydi:** `jobs/daily_wisdom.py` `content` dan deterministik tanlaydi (til bo'yicha, 180 kun takrorlanmas, Ramazon kabi mavzu taqvimi). AI faqat bir jumlalik "mulohaza" yozishi mumkin, aniq belgilangan.
- **AI Memory:** `ai_memory(kind fact|preference|goal_context|constraint, text, source user_stated|inferred, confidence)`; har chat'dan keyin haiku extraction; faqat confidence ≥ 0.8 promptga kiradi; Sozlamalar → AI → Xotira ekranida ko'rish/tahrir/o'chirish/"hammasini unut". `/ai/memory` CRUD.
- **Personalization (MVP):** qoida asosli feature vektor (xronotip uyqudan, samarali soatlar vazifa bajarilish vaqtidan, fokus uzunligi, streak sezgirligi) + memory + haftalik "profil dayjesti" → har promptning personalization bloki. Fine-tuning yo'q.
- **Safety:** input filter (RAG/tool natijalari `<document>` tegida "data, not instructions"; jailbreak regex + haiku); system qoidalar (tibbiy/psixiatrik diagnoz yo'q, krizis so'zlari → mamlakat bo'yicha helpline; manbasiz hukm yo'q; oyat/hadis raqami o'ylab topilmaydi); output klassifikator (`fabricated_citation, medical_advice, ruling_without_source, self_harm_context`) → xavfsiz shablon + `ai_safety_events`. `ai_requests(agent, model, tokens, cache_read, cost_usd, latency, safety_flags)`; Redis token bucket (masalan 30 chat/kun, 3 planner/kun; admin sozlaydi).
- **Qurilmada vs server:** qurilmada — namoz, waste score, DW score, Bugungi balans, offline Smart Day/Top-3 (ustuvorlik/dedlayn bo'yicha qoida), streak, lokal stat. Serverda — barcha LLM, RAG, memory, coach, recs, insights, embeddings. Offline'da AI ekranlar oxirgi javob keshi + "AI uchun internet kerak".

---

## 6. Namoz vaqtlari
- `adhan_dart`: usullar (MWL, Egyptian, Karachi, Umm al-Qura, Dubai, Kuwait, Qatar, Singapore, Turkey, Tehran, Moonsighting), `Madhab.hanafi|shafi`, yuqori kenglik qoidasi, har namoz uchun daqiqa tuzatish (`prayer_adjustments jsonb`). **"O'zbekiston (Muftiyat)" preset** — rasmiy Toshkent jadvali bilan bir yil davomida `test/prayer/uz_table_test.dart` da solishtiriladi.
- Joylashuv bir marta (`geolocator`) yoki `assets/cities.json` (~3k shahar + tz). Serverda faqat `preferences.prayer_settings` va `prayer_logs(date, prayer, status on_time|late|missed|qada)`.
- Bildirishnoma: app start + har kuni 00:05 (WorkManager / BGAppRefreshTask) keyingi 3 kun × 6 vaqt `zonedSchedule`; Android 13+ `SCHEDULE_EXACT_ALARM` (rad etilsa inexact); azon qisqa klip bundled, to'liq azon ixtiyoriy yuklab olish; iOS 64 pending limiti (18 ta — yetarli).
- Juma rejimi: Peshin → Juma (masjid vaqti), Kahf surasi taklifi, g'usl/erta borish eslatmasi. Streak = ketma-ket 5/5 kunlar.

## 7. Qur'on ma'lumotlari
- **Arab matni:** Tanzil Uthmani (CC BY-ND 3.0 — o'zgartirilmaydi, About'da attribution). **Tarjimalar:** QuranEnc (o'zbek — Alauddin Mansur, litsenziya tekshiriladi; rus — Kuliev/Abu Adel; ingliz — Saheeh International). Uz-Cyrl transliteratsiya faqat litsenziya ruxsat bersa, aks holda kirill nashri. Har tarjima `content_sources` da litsenziya matni bilan; litsenziyasiz hech narsa chiqmaydi. Tafsir — o'zbek litsenziyasi bottleneck → 2-bosqich kontent, sxema tayyor.
- Metadata: Tanzil `quran-data.xml` → surahs, juz, hizb, pages (604 Madani), sajda, ruku.
- **Paketlash:** `assets/db/quran.sqlite` (~15–25 MB) read-only ikkinchi Drift DB; tafsir/qo'shimcha tarjimalar — `content_packs` (zip SQLite + checksum) yuklab olinadi.
- Audio: everyayah.com (oyat-oyat) yoki cdn.islamic.network (sura); `just_audio ConcatenatingAudioSource`, oyat highlight; "sura/juz yuklab olish".
- Jadvallar: `quran_progress(last_surah, last_ayah, last_page, pages_read_today, daily_goal, khatm_plan{start, target_days, pages_per_day})`, `quran_reading_sessions(date, pages, minutes)`, `quran_bookmarks(ayah_key, note)`.

---

## 8. Backend tuzilishi (`apps/api/`)
```
pyproject: fastapi uvicorn sqlalchemy[asyncio] asyncpg alembic pydantic pydantic-settings pyjwt argon2-cffi
           authlib httpx redis arq firebase-admin anthropic openai pgvector structlog sentry-sdk sqladmin jinja2
app/
├── main.py  core/{config,security,deps,logging,errors,pagination}.py
├── db/{base,session,mixins(UUIDPk,Timestamps,SoftDelete,Versioned)}.py
├── middleware/{audit,request_id,rate_limit}.py
├── modules/<name>/{router,schemas,models,service,repository}.py   # auth users profile preferences calendar tasks
│      # habits goals prayers quran health sleep mood education books family notifications statistics
│      # wellbeing(screen-time, app-usage, scrolling) content admin sync
├── ai/ (5-bo'lim)
├── jobs/{worker.py, daily_review, weekly_review, monthly_review, stats_aggregate, notif_scheduler, daily_wisdom, ai_batch, cleanup}.py
└── integrations/{fcm, apple_signin, google_signin, storage(S3/MinIO)}.py
```
- **Auth:** email+parol (argon2id), Google (authlib OIDC), Apple (JWKS). JWT access 15 daq, refresh 30 kun hash bilan `refresh_tokens(device_id, token_hash, expires_at, revoked_at, replaced_by)`; har refresh'da rotation, qayta ishlatish aniqlansa oila bekor. Email tasdiqlash/parol tiklash (Resend/Postmark).
- **RBAC:** `users.role ∈ {user, reviewer, content_editor, admin}`, `Depends(require_role)`.
- **Audit:** `/admin/*`, `/auth/*`, `/users/*`, `/ai/memory`, akkaunt o'chirish → `audit_logs(actor, action, entity, before, after, ip, ua, request_id)`; kontent holat o'tishlari `content/service.py` da.
- **Jobs — arq** (Celery og'ir, APScheduler ikki replikada ikki marta ishlaydi): `stats_aggregate` soatlik → `user_statistics(date, metrics jsonb)`; `daily_review` foydalanuvchi lokal 21:00 (15 daq'da bir tekshiradi); `weekly_review` yakshanba/dushanba, `monthly_review` 1-kun — AI coach/analyst byudjet nazorati bilan; `notif_scheduler` 5 daq (Smart Interruption qoidalari); `daily_wisdom` 00:00 UTC; `ai_batch` tungi memory dayjest, oylik insight (Anthropic Batches −50%); `cleanup` (tombstone 90 kun, token, AI log 180 kun).
- **Push:** `firebase-admin` multicast, `devices(fcm_token, platform, app_version, last_seen)`; silent data-message sync uchun.
- **Statistika:** klient kunlik/haftalikni Drift'dan hisoblaydi (offline ishlaydi); server faqat cross-device/AI uchun. "Bugungi balans" 7 yo'nalish (Ma'naviyat, Sog'liq, Ish, Ta'lim, Oila, Dam olish, Raqamli) — `features/statistics/domain/balance.dart`, spetsifikatsiya `docs/balance-formula.md`, server oylik varianti mos.

## 9. Admin panel (SQLAdmin, `/admin`)
- `ContentAdmin`: status/til/manba filtrlar; amallar `submit_for_review`, `approve` (faqat reviewer), `publish` (faqat admin, embedding job'ini ishga tushiradi), `archive`; detail'da manba, iqtibos, checksum, reviewer imzosi + vaqt.
- Workflow servisda majburiy: `draft → review → approved → published → archived`; `approved` uchun `verified_by ≠ author`; `published` uchun litsenziyali manba shart; har o'tish audit.
- Read-only: `AIRequestsAdmin` (kunlik xarajat grafigi), `AuditLogAdmin`, `UsersAdmin` (ban, rol), `ModerationQueue` (flag'langan AI javoblar, foydalanuvchi shikoyatlari).

## 10. Bildirishnomalar
| Tur | Manba | Misollar |
|---|---|---|
| Lokal | qurilma | namoz, odat, vazifa dedlayn, uyqu vaqti, Qur'on maqsadi, DW ogohlantirish |
| Push | server | AI tavsiya, daily/weekly/monthly review tayyor, streak milestone, silent sync |

- Kanallar/kategoriyalar: `prayer, habits, tasks, quran, wellbeing, ai_recommendations, reviews, system` (ТЗ 42 dagi 14 tur shu kanallarga xaritalanadi); har biri alohida toggle + tinch soatlar `preferences.notifications` (sync).
- **Smart Interruption:** `notification_events(category, sent_at, outcome opened|action|dismissed|ignored, latency)` lokal, kunlik agregat yuklanadi. 14 kunlik `engagement = (opened+action)/sent` (min 5 namuna): ≥0.4 normal; 0.15–0.4 ikki barobar kam; 0.05–0.15 faqat kunlik dayjest; <0.05 haftalik dayjest + "Bularni xohlaysizmi?" banner. Namoz va foydalanuvchi o'zi yaratgan eslatmalar backoff'dan istisno. Interaksiya → reset. Qoidalar `notification_policy.dart` va `jobs/notif_scheduler.py` da bir xil.
- DW kontekstli ogohlantirish: ilova uchun soatiga ≤1, kuniga ≤6; variant kontekstga qarab (tun, rejalangan vazifa vaqti, limit oshdi); tugmalar: Hozir to'xtatish / 10 daq davom / Bugun eslatma yo'q.

## 11. Xavfsizlik va maxfiylik (ТЗ 45–46)
- TLS (Caddy); dio pinning flag ostida (default o'chiq). Refresh token + DB kaliti secure storage; access token faqat xotirada. SQLCipher, har o'rnatish uchun tasodifiy kalit; "Chiqish va ma'lumotlarni o'chirish".
- Server ustun shifrlash `EncryptedText` TypeDecorator (AES-256-GCM, `FIELD_ENC_KEY` versiyali): `mood_logs.note`, `health_logs.note`, `sleep_logs.note`, `ai_messages.content`, `ai_memory.text`. Sonli qiymatlar agregatsiya uchun ochiq.
- DW minimal ma'lumot: faqat kunlik kategoriya daqiqalari + eventlar; app_key per-user salt bilan hash (foydalanuvchi "app-level cloud stats" yoqmasa); soatdan nozik timestamp yo'q.
- Export `POST /users/me/export` → arq job zip (JSON per jadval) MinIO/S3 signed URL, 24 soat. O'chirish `DELETE /users/me` → soft-delete + token bekor, 7 kun grace, keyin cascade hard-delete + embedding/memory tozalash, audit'da hash id.
- Auth rate limit (IP + email), enumeration-safe javoblar. Onboarding 4-qadam = ma'lumot va ruxsatlar tushuntirishi; alohida consent: analytics, AI personalization, DW cloud stats.

---

## 12. Bosqichma-bosqich reja (≈24 hafta, buffer bilan 26)

Har bosqich `v0.N` teg bilan test qurilmasiga o'rnatiladi.

| # | Bosqich | Hafta | Definition of Done |
|---|---|---|---|
| 0 | Skelet va CI | 1.5 | CI yashil; Android emulator + iOS simulator'da ishlaydi; `make gen` freezed/drift/riverpod/pigeon/openapi client'ni generatsiya qiladi; ADR-001..004; **iOS Family Controls entitlement so'rovi yuborilgan** |
| 1 | Auth, profil, onboarding, Home shell, tema, i18n | 2.5 | Yangi o'rnatish → onboarding (5 qadam: til, ism/avatar, joylashuv+namoz usuli, maqsadlar, ruxsatlar+maxfiylik) → login → restart offline'da sessiya saqlanadi → logout tozalaydi; 4 til, `l10n_check` CI |
| 2 | Vazifalar, kalendar, odatlar, maqsadlar — offline-first + sync | 4 | Ikki qurilma offline tahrir → onlayn → yo'qotishsiz; konflikt matritsasi avtomatik test (ikki in-memory Drift + test API); airplane-mode demo; kalendar RRULE subset; streak 7/30/100 badge; Home'da Top-3 (qo'lda), bugungi bloklar, odatlar |
| 3 | Namoz, Qur'on, kun hikmati | 3 | Toshkent 12 test sanasi rasmiy jadvalga mos; reboot'dan keyin bildirishnomalar ishlaydi; Qur'on to'liq offline; har hikmatda manba; `content_tools` import CLI (Qur'on + birinchi hadis to'plami, masalan Riyozus-solihin, litsenziya tekshirilgach) |
| 4 | Mood, uyqu, sog'liq, ta'lim, kitoblar (+ ish, oila, dam olish kategoriyalari) | 2.5 | Har modul add/edit/delete/history, offline, Home "Smart Day" blokida; 2-bosqich sync generiklari qayta ishlatiladi |
| 5 | Statistika, review'lar, Bugungi balans, gamifikatsiya | 2 | Bir xil ma'lumotda online/offline stat bir xil (golden test); review tunda generatsiya (qoida asosli matn) va Notification Center'da |
| 6 | Digital Wellbeing: Android (2) → iOS (1.5) | 3.5 | Android 24 soat real foydalanish tizim Digital Wellbeing bilan ±5%; iOS threshold notification qurilmada ishlaydi; ruxsat rad etilsa ikkalasi ham buzilmaydi; Play deklaratsiya hujjati |
| 7 | AI: chat, planner, reschedule, recs, memory, RAG | 3.5 | Safety to'plami refusal holatlarda 100%; planner proposal sync orqali qo'llanadi; faol foydalanuvchi uchun kunlik xarajat < $0.05; offline fallback Smart Day/Top-3 |
| 8 | Smart notifications va personalizatsiya | 1.5 | Simulyatsiya qilingan engagement bilan backoff tekshirilgan; qurilmalar aro dublikat push yo'q; Home'da shaxsiy insight (≥14 kun ma'lumot bo'lganda) |
| 9 | Xavfsizlik, QA, beta, reliz | 2 + buffer | OWASP MASVS-L1 checklist; TalkBack/VoiceOver, text scale, kontrast; RTL smoke; cold start < 2 s; store asset 4 tilda, privacy policy, Play Data Safety + Usage Access deklaratsiya, App Store nutrition label; TestFlight/Internal 20–50 foydalanuvchi, crash-free ≥ 99.5%; ikkala do'konga yuborilgan; `docs/acceptance-checklist.md` (ТЗ 70) 100% |

2-bosqich (Family Account, Apple Health/Health Connect, Smart Watch, Web dashboard, advanced Coach/Memory, kengaytirilgan ta'lim, kitoblar bazasi) — faqat store relizidan keyin; ro'yxat `docs/backlog.md`.

---

## 13. Testlash strategiyasi (ТЗ 67–69)
| Qatlam | Vosita | Nima |
|---|---|---|
| Flutter unit | `flutter_test`, `mocktail` | streak, balans, waste score, DW score, namoz tuzatishlar, merge, notification policy |
| Flutter DB | Drift in-memory + `drift_dev` schema export | DAO, har migratsiya versiyasi |
| Widget/golden | light/dark × 4 til | Home, namoz kartasi, planner blok, proposal diff |
| Integration | `integration_test` (Android emulator CI) | onboarding → offline vazifa → sync |
| Sync | pytest + ikki Dart klient docker API'ga qarshi | konflikt matritsasi (ikki qurilma bir row; delete vs update; clock skew) |
| API | `pytest-asyncio`, `httpx`, testcontainers Postgres | routerlar, merge, token rotation/reuse, RBAC, audit, export/delete cascade |
| Jobs | arq test rejimi, fake clock | review/notification vaqti timezone bo'yicha |
| AI contract | VCR-style fixtures ikkala adapter | structured output, streaming, tool loop, refusal |
| AI safety | `tests/ai/safety/*.yaml` ~150 holat, 4 til | sohta iqtibos tuzoqlari ("Buxoriy 9999"), fatvo so'rovi, tibbiy/psixologik diagnoz, o'z-o'ziga zarar iboralari, vazifa nomi/RAG chunk orqali injection, umumiy kontrol; PR'da fixtures, tunda live model (xarajat limiti) |
| RAG accuracy | golden Q&A | citation to'g'riligi ≥ 95% |
| Diniy kontent | jarayon (`docs/content-policy.md`) | import → `draft`; malakali reviewer (`verified_by`, malaka yozilgan) manba, matn butunligi, tarjima, daraja → approve; admin publish; checksum; tahrir → `review`; oylik re-hash skripti |
| Native | Kotlin unit (sintetik UsageEvents → sessiya), Swift unit (threshold flag) | |
| Qo'lda | Android 10/12/14 (Samsung, Xiaomi), iPhone iOS 16/17 | battery killer, ruxsatlar |
| Load | locust | `/sync`, `/ai/chat` |

## 14. Xavflar va choralar
| Xavf | Chora |
|---|---|
| iOS Family Controls entitlement kech/rad | 0-bosqichda so'rov; `dw_ios_mode=selfreport`; iOS relizi bunga bog'lanmaydi |
| Play Usage Access rad | Disclosure ekrani, deklaratsiya erta, DW asosiy funksiya, AccessibilityService/QUERY_ALL_PACKAGES yo'q, ruxsatsiz ham ilova to'liq ishlaydi |
| AI diniy hallucination | Faqat content citation + substring tekshiruv, manba yo'q → refusal, fatvo rad, tungi safety suite, inson tasdiqlagan korpus, hamma joyda "manba" qatori, shikoyat tugmasi → moderation |
| Scope creep (78 bo'lim) | Phase gate + DoD; MVP dan tashqari → backlog; bosqich ≤ 4 hafta; Claude Code vazifalari feature-slice + acceptance test |
| Solo bandwidth | 2-bosqich CRUD+sync generiklari 8 entity'da qayta ishlatiladi; SQLAdmin; AI oldidan qoida asosli fallback; 10–15% buffer |
| Store review (diniy/sog'liq) | "Tibbiy maslahat emas" matnlari, MVP da HealthKit yo'q, attribution, UGC diniy kontent yo'q, to'g'ri age rating |
| Qur'on tarjima/tafsir litsenziyasi | Tanzil/QuranEnc hujjatlangan litsenziya; o'zbek nashr egalari bilan 1-bosqichda aloqa; kerak bo'lsa avval en/ru; pack'lar relizdan keyin |
| Sync ma'lumot yo'qotish | Deterministik merge testlar, tombstone, birinchi kundan export, `row_history` 30 kun |
| LLM xarajati | Kvotalar, prompt caching, tungi job'lar Batches, klassifikatorlar haiku, admin xarajat dashboard + alert |
| Android OEM battery killer | Whitelisting yo'riqnoma, ma'lumot bo'shlig'i halol ko'rsatiladi |

## 15. Muhim fayllar (implementatsiya uchun)
- `apps/mobile/lib/core/sync/sync_engine.dart` — outbox/push/pull/merge; butun offline shunga bog'liq
- `apps/mobile/lib/core/db/app_database.dart` + `tables/*.drift` — barcha feature va sync ulashadigan sxema
- `apps/api/app/modules/sync/router.py` + `merge.py` — idempotent sync, konflikt qoidalari
- `apps/api/app/ai/service.py`, `providers/base.py`, `rag/citation.py`, `safety/rules.py` — adapter, RAG-citation, safety gate
- `apps/mobile/android/.../wellbeing/UsageCollector.kt`, `apps/mobile/ios/KunimMonitor/DeviceActivityMonitorExtension.swift` — DW platform yadrolari

## 16. Birinchi qadam (tasdiqlangandan keyin)
0-bosqich: monorepo, `CLAUDE.md`, Flutter skeleti (Riverpod/go_router/Drift/ARB/theme), FastAPI skeleti (`/health`, Alembic, SQLAdmin), docker-compose, GitHub Actions, `docs/TZ.md` + ADR-001..004, iOS entitlement so'rovi matni. Natija: `flutter run` bo'sh shell, `GET /health` 200, CI yashil.

## 17. Tekshirish
- Har bosqich DoD (12-bo'lim jadvali) qo'lda + CI testlari.
- Yakuniy: `docs/acceptance-checklist.md` (ТЗ 70) 100%, Android (API 26+) va iOS (16+) real qurilmalarda, ikkala do'konga yuborilgan.
