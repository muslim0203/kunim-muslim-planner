## Google sign-in — 2026-10-08

- API: `POST /auth/google` verifies a Google ID token (RS256 against Google's
  JWKS, audience in `GOOGLE_CLIENT_IDS`, `email_verified` required), then signs
  into the linked account, links an account with the same address, or creates
  a passwordless one. Links live in `user_identities` (migration 0015). Linking
  an account whose email was never verified clears its password and sessions
  (pre-registration takeover). `DELETE /users/me` also accepts a fresh
  `google_id_token` instead of the password. `GOOGLE_CLIENT_IDS` empty → 503.
- Mobile: `google_sign_in` 7.x, "Google orqali davom etish" on the account
  screen, Google confirmation in the delete dialog. The button is hidden unless
  the build has `KUNIM_GOOGLE_SERVER_CLIENT_ID`.
- Verified here: pytest 602 passed; `flutter analyze` clean; mobile auth and
  account tests pass. **Not verified on a device** — no OAuth clients exist
  yet (Google Cloud setup: `apps/mobile/PLATFORM-SETUP.md`).

## Release signing verification — 2026-09-18

- Android release signing wired in `apps/mobile/android/app/build.gradle.kts`:
  `android/key.properties` (gitignored) or the `KUNIM_ANDROID_*` environment
  variables; without either, release builds fall back to the debug key.
  Procedure: `docs/release-android.md`.
- Verified on this machine with a disposable throwaway key (deleted afterwards):
  `flutter build appbundle --release` produced a 60.5 MB bundle and
  `keytool -printcert -jarfile` reported that test certificate, not the debug one.
  A `key.properties` missing a password fails during configuration with a
  message naming the missing key.
- `flutter build apk --release` without any key still builds (65.8 MB, debug cert).
- `.github/workflows/release-mobile.yml` builds a signed bundle from four
  repository secrets. **Not run yet** — the secrets do not exist.
- No real upload key has been created: that step belongs to the user, since the
  keystore password must not pass through this session.

## Setup verification — 2026-09-12 (supersedes the environment notes below)

- GitHub: main pushed to private muslim0203/kunim-muslim-planner; origin/main tracking configured.
- WSL 2.7.14.0 installed. Docker Desktop 4.90.0, Engine 29.7.2, Compose 5.5.1 installed and running. Windows reported a restart recommendation during WSL setup, but Docker Linux containers work in this session.
- Development Compose stack built and started. API, PostgreSQL/pgvector, Redis, MinIO and worker healthy; minio-init exited 0.
- Alembic revisions 0001 -> 0002_auth -> 0003_profile_preferences applied to real PostgreSQL. Fixed duplicate enum creation in the first two migrations.
- /health/ready returns 200 with database=ok and redis=ok.
- Live PostgreSQL auth smoke: register, login, me, refresh, logout passed. One synthetic setup account remains in the local development database.
- Live Redis queue smoke: enqueued ping -> worker returned pong.
- Worker startup fixed: registered diagnostic job, RedisSettings object, logging settings argument, source import path, dedicated arq healthcheck.
- MinIO images moved to the vendor's quay.io namespace because Docker Hub pulls were denied. Development ports bound to localhost. Local random credentials stored only in ignored .env; Docker build excludes local environments and secrets.
- Apple Developer Agreement accepted with explicit user confirmation. Account portal offers enrollment rather than active program membership. Entitlement form returned Unauthorized. Enrollment page is waiting for user-provided legal name, phone and address. No entitlement request submitted and no paid membership purchased.
- Apple request draft corrected to describe planned capabilities and actual untested iOS scaffold. No invented Team ID, bundle identifier or device-testing claims.
- Initial GitHub Mobile workflow failed; push success does not mean CI is green. CI repair and mobile setup are outside this setup verification.

# Loyiha amalga oshirish holati

## Bosqichlar bo'yicha jarayon

| # | Bosqich | Hafta | Holat | DoD qisqacha |
|---|---|---|---|---|
| 0 | Skelet va CI | 1.5 | 🟡 Jarayonda | CI yashil; Android emulator + iOS simulator'da ishlaydi; `make gen` freezed/drift/riverpod/pigeon/openapi client'ni generatsiya qiladi; ADR-001..004; iOS Family Controls entitlement so'rovi yuborilgan |
| 1 | Auth, profil, onboarding, Home shell, tema, i18n | 2.5 | ⬜ Boshlanmagan | Yangi o'rnatish → onboarding (5 qadam: til, ism/avatar, joylashuv+namoz usuli, maqsadlar, ruxsatlar+maxfiylik) → login → restart offline'da sessiya saqlanadi → logout tozalaydi; 4 til, `l10n_check` CI |
| 2 | Vazifalar, kalendar, odatlar, maqsadlar — offline-first + sync | 4 | ⬜ Boshlanmagan | Ikki qurilma offline tahrir → onlayn → yo'qotishsiz; konflikt matritsasi avtomatik test (ikki in-memory Drift + test API); airplane-mode demo; kalendar RRULE subset; streak 7/30/100 badge; Home'da Top-3 (qo'lda), bugungi bloklar, odatlar |
| 3 | Namoz, Qur'on, kun hikmati | 3 | ⬜ Boshlanmagan | Toshkent 12 test sanasi rasmiy jadvalga mos; reboot'dan keyin bildirishnomalar ishlaydi; Qur'on to'liq offline; har hikmatda manba; `content_tools` import CLI (Qur'on + birinchi hadis to'plami, masalan Riyozus-solihin, litsenziya tekshirilgach) |
| 4 | Mood, uyqu, sog'liq, ta'lim, kitoblar (+ ish, oila, dam olish kategoriyalari) | 2.5 | ⬜ Boshlanmagan | Har modul add/edit/delete/history, offline, Home "Smart Day" blokida; 2-bosqich sync generiklari qayta ishlatiladi |
| 5 | Statistika, review'lar, Bugungi balans, gamifikatsiya | 2 | ⬜ Boshlanmagan | Bir xil ma'lumotda online/offline stat bir xil (golden test); review tunda generatsiya (qoida asosli matn) va Notification Center'da |
| 6 | Digital Wellbeing: Android (2) → iOS (1.5) | 3.5 | ⬜ Boshlanmagan | Android 24 soat real foydalanish tizim Digital Wellbeing bilan ±5%; iOS threshold notification qurilmada ishlaydi; ruxsat rad etilsa ikkalasi ham buzilmaydi; Play deklaratsiya hujjati |
| 7 | AI: chat, planner, reschedule, recs, memory, RAG | 3.5 | ⬜ Boshlanmagan | Safety to'plami refusal holatlarda 100%; planner proposal sync orqali qo'llanadi; faol foydalanuvchi uchun kunlik xarajat < $0.05; offline fallback Smart Day/Top-3 |
| 8 | Smart notifications va personalizatsiya | 1.5 | ⬜ Boshlanmagan | Simulyatsiya qilingan engagement bilan backoff tekshirilgan; qurilmalar aro dublikat push yo'q; Home'da shaxsiy insight (≥14 kun ma'lumot bo'lganda) |
| 9 | Xavfsizlik, QA, beta, reliz | 2 + buffer | ⬜ Boshlanmagan | OWASP MASVS-L1 checklist; TalkBack/VoiceOver, text scale, kontrast; RTL smoke; cold start < 2 s; store asset 4 tilda, privacy policy, Play Data Safety + Usage Access deklaratsiya, App Store nutrition label; TestFlight/Internal 20–50 foydalanuvchi, crash-free ≥ 99.5%; ikkala do'konga yuborilgan |

## Muhit cheklovlari (2026-09-12)

Hozirgi developers-machine muhit holati:

- Python 3.11.8 ✅ o'rnatilgan
- Node 20 ✅ o'rnatilgan  
- Java 17 ✅ o'rnatilgan
- Git ✅ o'rnatilgan
- **Flutter ❌ o'rnatilmagan**
- **Android SDK ❌ o'rnatilmagan**
- **Docker ❌ o'rnatilmagan**
- **PostgreSQL/Redis ❌ o'rnatilmagan**

**Oqibat:** Shuning uchun Flutter builds, Docker Compose, va Postgres-backed tests bu mashinada **TEKSHIRILMAGAN** bo'lib qoladi. Bosqich 0 va keyingi bosqichlarni tugatishda real mobilar, testing environment, va CI pipeline'da verificatsiya qilinishi shart.

---

## 0-bosqich — DoD bo'yicha aniq holat (2026-09-12)

| DoD punkti | Holat | Dalil / to'siq |
|---|---|---|
| Monorepo tuzilishi + `CLAUDE.md` | ✅ | Papka daraxti, git repo, konvensiyalar fayli |
| FastAPI skeleti, `GET /health` 200 | ✅ | `pytest -q` → 4 passed; `ruff check` + `ruff format --check` → passed |
| Alembic migratsiya infratuzilmasi | ⚠️ | Kod va baseline revision yozilgan; **bazaga qo'llanmagan** — PostgreSQL yo'q |
| SQLAdmin `/admin` | ⚠️ | `ADMIN_ENABLED=true` bilan mount bo'lishi tekshirilgan; jonli baza bilan sinalmagan |
| arq worker entrypoint | ✅ | `app.jobs.worker.WorkerSettings` import qilinadi (jobs ro'yxati bo'sh — 2-bosqichdan boshlab to'ladi) |
| Flutter skeleti (`flutter run` bo'sh shell) | ❌ | Manba kod yozilgan, **hech qachon kompilyatsiya qilinmagan** — Flutter SDK yo'q |
| `android/` host loyihasi | ⚠️ | Mavjud: `build.gradle.kts` (minSdk 26), `AndroidManifest.xml` (AccessibilityService / QUERY_ALL_PACKAGES / SYSTEM_ALERT_WINDOW **yo'q**, faqat `<queries>` MAIN/LAUNCHER), `MainActivity.kt`. **Hech qachon qurilmagan** |
| `ios/` host loyihasi | ⚠️ | Faqat `Info.plist` + `AppDelegate.swift`. `Runner.xcodeproj` qo'lda yozilmaydi — `flutter create --platforms=ios .` va macOS kerak (`apps/mobile/PLATFORM-SETUP.md`) |
| 4 til ARB + l10n tekshiruvi | ✅ | `node apps/mobile/tool/check_l10n.mjs` → 4 locale × 20 kalit, passed |
| `make gen` (freezed/drift/riverpod/pigeon/openapi) | ⚠️ | Makefile target yozilgan; **ishga tushirilmagan** — `make` ham, Flutter ham yo'q |
| docker-compose (postgres+pgvector, redis, minio, api, worker) | ⚠️ | YAML valid; **ishga tushirilmagan** — Docker yo'q |
| GitHub Actions CI yashil | ⚠️ | 3 workflow YAML valid; **runner'da ishlamagan** — repo hali remote'ga ulanmagan |
| ADR-0001..0004 | ✅ | `docs/adr/` — 5 fayl, 705 satr |
| iOS Family Controls entitlement so'rovi **yuborilgan** | ❌ | Faqat **matn tayyor** (`docs/ios-family-controls-request.md`). Yuborish uchun Apple Developer akkaunt, Team ID, Bundle ID va App Store Connect yozuvi kerak — bu faqat siz bajara olasiz |
| Android emulator + iOS simulator'da ishlaydi | ❌ | Imkonsiz — SDK'lar yo'q; iOS uchun macOS talab qilinadi |

### 0-bosqichni yopish uchun sizdan kerak bo'ladigan narsalar

1. **Flutter SDK** + Android Studio ichidan **Android SDK** (Windows'da ikkalasi ham ishlaydi).
2. **Docker Desktop** — compose stack va Postgres'li testlar uchun.
3. **GitHub remote** — CI'ni haqiqatda yashil ko'rish uchun.
4. **Apple Developer akkaunt** — entitlement so'rovini yuborish uchun. Javob **haftalar/oylar** olishi yoki **rad etilishi** mumkin, shuning uchun reja bo'yicha bu eng erta bosqichda yuboriladi va iOS relizi unga bog'lanmaydi (`dw_ios_mode = selfreport` zaxira yo'li).
5. **macOS mashinasi** — iOS build/simulator uchun (Windows'da iOS'ni qurib bo'lmaydi).

Final setup validation: pytest 73 passed (13 existing deprecation warnings); Ruff for changed Python files passed; git diff --check passed. Automated auth/profile suites use SQLite fixtures; real PostgreSQL migration/auth and live Redis worker checks were separately executed successfully.

---

## 0-bosqich — YOPILDI (2026-09-12)

Muhit to'siqlari bartaraf etildi. Yuqoridagi "Muhit cheklovlari" bo'limi endi eskirgan:
Flutter 3.47.4 ✅ · Android SDK (platform-36, build-tools 36.0.0) ✅ · Docker + WSL2 ✅ ·
PostgreSQL 16 + pgvector, Redis, MinIO ✅ · GitHub remote (private) ✅

| DoD punkti | Holat | Dalil |
|---|---|---|
| Monorepo + `CLAUDE.md` + ADR-0001..0004 | ✅ | `docs/adr/` 1230 satr |
| FastAPI skeleti, `/health` 200 | ✅ | `pytest` 73 passed; API CI GitHub'da **yashil** |
| Alembic migratsiyalar **bazaga qo'llandi** | ✅ | Jonli PostgreSQL'da `alembic upgrade head` |
| `docker compose up` | ✅ | postgres, redis, minio, api, worker — barchasi sog'lom |
| Flutter shell, `flutter run` | ✅ | `flutter analyze` → No issues found!; `flutter test` → 9 passed |
| **`flutter build apk`** | ✅ | `app-debug.apk` 169 MB; `aapt2 dump badging`: `com.kunim.app`, minSdk 26, targetSdk 36, taqiqlangan ruxsatlar **yo'q** |
| 4 til ARB + l10n CI tekshiruvi | ✅ | 4 locale × 60 kalit |
| `make gen` (build_runner + gen-l10n) | ✅ | Toza holatdan 12 output + 4 locale |
| GitHub Actions CI | ✅ API · Mobile tuzatildi | `.github/workflows/` |
| iOS Family Controls entitlement **yuborilgan** | ❌ | Apple kelishuvi qabul qilingan, lekin **Developer Program pullik a'zoligi yo'q**. So'rov yuborilmagan. Zaxira: `dw_ios_mode=selfreport` (ADR-0003) — iOS relizi bunga bog'liq emas |
| Android emulator / iOS simulator | ⚠️ | APK qurildi, qurilmada ishga tushirilmagan. iOS uchun macOS kerak — bu mashinada imkonsiz |

**Qolgan yagona to'siq:** Apple Developer Program a'zoligi. 6-bosqich (DW iOS) boshlanishidan
oldin rasmiylashtirilsa, entitlement javobi (haftalar/oylar) vaqtida keladi.

## 1-bosqich — qisman

| Modul | Holat | Dalil |
|---|---|---|
| Auth (argon2id, JWT, refresh rotation + reuse detection, RBAC) | ✅ | ADR va testlar bilan |
| Profil + preferences (`/users/me`, `/preferences`) | ✅ | 73 test |
| Auth/onboarding ARB matnlari (4 til) | ✅ | 60 kalit |
| Onboarding va auth **ekranlari** (Flutter) | ⬜ | Hali yozilmagan |
| Email tasdiqlash / parol tiklash endpointlari | ⬜ | Model va servis bor, pochta provayderi yo'q |
