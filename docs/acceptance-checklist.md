# Qabul checklist — Bosqich bo'yicha DoD (Definition of Done)

Har bosqich `v0.N` teg bilan test qurilmasiga o'rnatiladi. Har item verifikasiyon qabul qilinadi (pass/fail).

---

## Bosqich 0: Skelet va CI

- [ ] Git monorepo tuzilishi tayyorlangan (`apps/`, `packages/`, `infra/`, `docs/`)
- [ ] Flutter skeleti yaratilgan (Riverpod, go_router, Drift, ARB, tema)
- [ ] FastAPI skeleti yaratilgan (`/health` endpoint, Alembic, SQLAdmin)
- [ ] `docker-compose.yml` ishlaydi (postgres16+pgvector, redis, api, worker, minio)
- [ ] GitHub Actions workflows ta'minlangan (mobile.yml, api.yml, content.yml)
- [ ] `make gen` freezed/drift/riverpod/pigeon/openapi client'ni generatsiya qiladi
- [ ] Android emulator `flutter run` bilan ishlaydi
- [ ] iOS simulator `flutter run` bilan ishlaydi
- [ ] `GET /health` 200 javob qaytaradi
- [ ] CI avtomatik test'larini ishlantiradi (yo'qda bo'lsa verd), red qilmaydi
- [ ] ADR-0001 (Stack) yozilgan
- [ ] ADR-0002 (Sync) yozilgan
- [ ] ADR-0003 (DW Platforms) yozilgan
- [ ] ADR-0004 (AI Provider) yozilgan
- [ ] iOS Family Controls entitlement so'rovi Apple'ga yuborilgan

---

## Bosqich 1: Auth, profil, onboarding, Home shell, tema, i18n

- [ ] Email + parol registratsiya ishlaydi
- [ ] Google OIDC autentifikatsiya ishlaydi
- [ ] Apple Sign In autentifikatsiya ishlaydi (iOS)
- [ ] JWT refresh token rotation ishlaydi
- [ ] Onboarding 5 qadam jag jag o'tadi:
  - [ ] Til tanlash (uz-Latn, uz-Cyrl, ru, en)
  - [ ] Ism / avatar tanlash
  - [ ] Joylashuv + namoz usuli
  - [ ] Maqsadlar asosiy tanlash
  - [ ] Ruxsatlar + maxfiylik consent
- [ ] Login'dan keyin Home sahifasi ko'rsatiladi
- [ ] Logout foydalanuvchi sessiya tozalaydi
- [ ] App restart'da offline'da sessiya saqlanadi
- [ ] Light tema ishlaydi
- [ ] Dark tema ishlaydi
- [ ] System tema ishlaydi
- [ ] 4 til UI elementlari to'g'ri ko'rsatiladi (uz-Latn, uz-Cyrl, ru, en)
- [ ] CI `l10n_check` o'tadi (jami 4 til)

---

## Bosqich 2: Vazifalar, kalendar, odatlar, maqsadlar — offline-first + sync

- [ ] Vazifa qo'shish ishlaydi (offline)
- [ ] Vazifa tahrir ishlaydi (offline)
- [ ] Vazifa o'chirish ishlaydi (offline)
- [ ] Kalendar event qo'shish ishlaydi (offline)
- [ ] Kalendar event tahrir ishlaydi (offline)
- [ ] Odat (habit) qo'shish ishlaydi (offline)
- [ ] Odat o'chirish ishlaydi (offline)
- [ ] Maqsad qo'shish ishlaydi (offline)
- [ ] Ikki qurilma offline tahrir → onlayn → ma'lumot yo'qotilmaydi (sync'da)
- [ ] Konflikt matritsasi avtomatik test o'tadi (ikki in-memory Drift + test API)
- [ ] Airplane-mode demo ishlaydi (aks holda ye offline'da tahrir qilib, ulaninganda sync)
- [ ] Kalendar RRULE subset (daily, weekly, monthly) ishlaydi
- [ ] Streak 7-kunlik badge ko'rsatiladi
- [ ] Streak 30-kunlik badge ko'rsatiladi
- [ ] Streak 100-kunlik badge ko'rsatiladi
- [ ] Home'da Top-3 vazifalar ko'rsatiladi
- [ ] Home'da bugungi bloklar ko'rsatiladi
- [ ] Home'da odatlar ro'yxati ko'rsatiladi

---

## Bosqich 3: Namoz, Qur'on, kun hikmati

- [ ] Namoz vaqtlari Toshkent uchun 12 test sanasida rasmiy jadvalga mos (±1 minut)
- [ ] Namoz bildirishnomasi app start'da ishlaydi
- [ ] Kuniga ≥3 kun × 6 vaqt (18 ta) namoz bildirish rejalashtir
- [ ] App reboot'dan keyin bildirishnomalar ishlaydi
- [ ] Android 13+ `SCHEDULE_EXACT_ALARM` so'raladi
- [ ] Qur'on jadvallar lokal DB'da bilan `quran.sqlite` to'liq offline ishlaydi
- [ ] Qur'on o'qish boshlash ishlaydi
- [ ] Qur'on o'qish holatini saqlash ishlaydi
- [ ] Qur'on bookmark qo'shish ishlaydi
- [ ] Kun hikmati har kuni ko'rsatiladi
- [ ] Kun hikmati manba'sini sho'wni (content manba nomi)
- [ ] `content_tools` CLI Qur'on'ni import qiladi
- [ ] `content_tools` CLI hadis to'plamini (masalan Riyozus-solihin) import qiladi
- [ ] Imported kontentning litsenziyasi tekshiriladi va qo'shiladi

---

## Bosqich 4: Mood, uyqu, sog'liq, ta'lim, kitoblar

- [ ] Mood qaydi qo'shish ishlaydi (offline)
- [ ] Mood qaydi tahrir ishlaydi (offline)
- [ ] Mood qaydi o'chirish ishlaydi (offline)
- [ ] Uyqu ma'lumot qo'shish ishlaydi (offline)
- [ ] Uyqu ma'lumot tahrir ishlaydi (offline)
- [ ] Sog'liq ma'lumot (suv, qadam, kalori) qo'shish ishlaydi (offline)
- [ ] Sog'liq ma'lumot tahrir ishlaydi (offline)
- [ ] Ta'lim element qo'shish ishlaydi (offline)
- [ ] Kitob qo'shish ishlaydi (offline)
- [ ] Har modul add/edit/delete/history loop'iga ega (6 modul)
- [ ] Home "Smart Day" blokida mood/uyqu/sog'liq/ta'lim ko'rsatiladi
- [ ] Ish kategoriyasi qo'shish va tahrir ishlaydi
- [ ] Oila kategoriyasi qo'shish va tahrir ishlaydi
- [ ] Dam olish kategoriyasi qo'shish va tahrir ishlaydi

---

## Bosqich 5: Statistika, review'lar, Bugungi balans, gamifikatsiya

- [ ] Online va offline'da bir xil statistika hisoblaydi (golden test)
- [ ] Review tunda qaida asosida generatsiya qilinadi
- [ ] Review'lar Notification Center'da ko'rsatiladi
- [ ] "Bugungi balans" 7 yo'nalish (Ma'naviyat, Sog'liq, Ish, Ta'lim, Oila, Dam olish, Raqamli) hesob qilinadi
- [ ] Balans formula `docs/balance-formula.md` da spesifikatsion mos

---

## Bosqich 6: Digital Wellbeing — Android va iOS

### Android
- [ ] PACKAGE_USAGE_STATS ruxsati so'raladi
- [ ] In-app disclosure ekrani ko'rsatiladi (Play Permissions Declaration Form talabi)
- [ ] 24 soatlik real foydalanish tizim DW ma'lumotida ±5% to'g'riligi
- [ ] Screen time sessiyalari to'liq qayd qilinadi
- [ ] App kategoriyalari `app_categories.json` override bilan
- [ ] Limit bildirishnomasi 80% da ko'rsatiladi
- [ ] Limit bildirishnomasi 100% da ko'rsatiladi
- [ ] Bildirishnoma tugmalari: Ochish, 15 daq kechiktirish, Bugun uzaytirish
- [ ] Play deklaratsiya hujjati to'liq to'ldirilgan

### iOS
- [ ] FamilyControls + DeviceActivity + ManagedSettings extension'lari o'rnatilgan
- [ ] iOS 16+ da threshold bildirishnomasi ishlaydi
- [ ] DeviceActivityReport extension'da statistika faqat sandbox view'da qayd qilinadi
- [ ] Statistika ilovaga/serverga chiqmaydi
- [ ] Entitlement ruxsat rad etilsa, ikkalasi ham buzilmaydi

### Umumiy
- [ ] Ruxsat rad etilsa ikkalasi ham buzilmaydi (fallback ishlaydi)

---

## Bosqich 7: AI — chat, planner, reschedule, recs, memory, RAG

- [ ] AI chat ishlaydi
- [ ] AI planner ishlaydi
- [ ] AI reschedule ishlaydi
- [ ] AI recommendations ishlaydi
- [ ] AI memory service ishlaydi
- [ ] RAG retrieval ishlaydi
- [ ] Safety to'plami refusal holatlarda 100% ishlaydi
- [ ] Planner proposal sync orqali qo'llanadi (foydalanuvchi qabul/rad qiladi)
- [ ] Faol foydalanuvchi uchun kunlik AI xarajati < $0.05 USD
- [ ] Offline'da Smart Day/Top-3 fallback ishlaydi (AI xizmatisiz)

---

## Bosqich 8: Smart notifications va personalizatsiya

- [ ] Notification engagement tracking ishlaydi
- [ ] Backoff algoritmasi simulyatsiya bilan tekshirilgan
- [ ] 14 kunlik engagement kalkulyatsiyasi to'g'ri
- [ ] Push notification duplikat bo'lmaydi (qurilmalar orasida)
- [ ] Home'da shaxsiy insight ko'rsatiladi (≥14 kun ma'lumot bo'lganda)

---

## Bosqich 9: Xavfsizlik, QA, beta, reliz

### Xavfsizlik
- [ ] OWASP MASVS-L1 checklist 100% qabul qilingan
- [ ] TLS (Caddy) ishlaydi
- [ ] Database SQLCipher shifrlangan
- [ ] Sensitive maydonlar server'da shifrlangan (mood_logs.note, health_logs.note, sleep_logs.note, ai_messages.content, ai_memory.text)
- [ ] JWT token rotation ishlaydi
- [ ] Rate limiting ishlaydi

### Accessibility
- [ ] TalkBack (Android) test qilingan
- [ ] VoiceOver (iOS) test qilingan
- [ ] Text scale 200% qaytarma shart qilmaydi
- [ ] Kontrast ratio ≥ 4.5:1 barcha tekstda

### Performance
- [ ] Cold start < 2 sekund
- [ ] RTL smoke test qilingan (ar pseudo-locale)

### Store preparation
- [ ] Barcha asset'lar 4 tilida tayyorlangang (uz-Latn, uz-Cyrl, ru, en)
- [ ] Privacy policy to'liq yozilgan
- [ ] Play Data Safety Form to'liq to'ldirilgan
- [ ] Play Usage Access deklaratsiya to'liq to'ldirilgan
- [ ] App Store Nutrition Label yaratilgan

### Beta testing
- [ ] TestFlight/Internal testing 20–50 foydalanuvchiga taqsimlangang
- [ ] Crash-free rate ≥ 99.5%
- [ ] Performance metrics qaytarilmadi

### Reliz
- [ ] Android Play Store'ga yuborilgan
- [ ] iOS App Store'ga yuborilgan

---

## Reliz (Bosqich 17)

- [ ] `docs/acceptance-checklist.md` (ТЗ 70) 100% qayd qilingan va tekshirilgan
- [ ] Android qurilma (API 26+) real device'da test qilingan
- [ ] iOS qurilma (iOS 16+) real device'da test qilingan
- [ ] Ikkala do'konga (Play Store, App Store) yuborilgan
- [ ] Reliz qismi versiyoni tag bilan belgilangan (masalan `v1.0`)
- [ ] Release notes to'liq yozilgan
