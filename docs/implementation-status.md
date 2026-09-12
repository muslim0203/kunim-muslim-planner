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
