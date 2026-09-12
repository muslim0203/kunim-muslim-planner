# Backlog — 2-bosqich va relizdan keyin

Quyidagi xususiyatlar MVP'dan tashqarida qolib go'l; faqat App Store va Play Store'ga relizdan keyin ishlanadi.

| # | Item | Nega MVP dan tashqarida | Manba (plan bo'limi) |
|---|---|---|---|
| 1 | Family Account | MVP'da individual auth; oila izni/monitoring qo'shilishi kompleks | 12-bo'lim, 2-bosqich ro'yxati |
| 2 | Apple Health integratsiya | iOS Health/HealthKit uchun extra test, compliance | 12-bo'lim, 2-bosqich ro'yxati |
| 3 | Health Connect integratsiya (Android) | Apple Health kabi — extra servisi qo'shilish | 12-bo'lim, 2-bosqich ro'yxati |
| 4 | Smart Watch qo'llab-quvvatlash | Separate ilova/paket, native develop | 12-bo'lim, 2-bosqich ro'yxati |
| 5 | Web dashboard (admin paneliga qo'shimcha) | MVP'da SQLAdmin `.../admin`; Next.js dashboard 2-bosqichda | 12-bo'lim, 2-bosqich ro'yxati; 1-bo'lim (Admin) |
| 6 | Advanced Coach/Memory | MVP'da rule-based; ML fine-tuning va advanced scheduling 2-bosqichda | 12-bo'lim, 2-bosqich ro'yxati |
| 7 | Kengaytirilgan ta'lim kontenti | Bosqich 4'da bazaviy modullar; 2-bosqichda advanced courses | 12-bo'lim, 2-bosqich ro'yxati |
| 8 | Kitoblar bazasi kengaytma | Bosqich 4'da lokal kitoblar; distributed content_packs — 2-bosqichda | 12-bo'lim, 2-bosqich ro'yxati |
| 9 | Next.js admin veb-interfeysi | Hozircha SQLAdmin `/admin` yetarli; to'liq Next.js 2-bosqichda | 1-bo'lim (Admin) |
| 10 | Tafsir (commentary) kontent | Qur'on: 7-bo'lim; uz tarjima litsenziyasi bottleneck; tafsir 2-bosqichda | 7-bo'lim (Qur'on ma'lumotlari) |
| 11 | ML-based waste scoring | MVP'da sigmoid-based formula; machine learning 2-bosqichda self-report'dan o'rgatiladi | 4-bo'lim (Bekorchi skrolling ehtimoli) |
| 12 | iOS "Qat'iy rejim" (ManagedSettingsStore.shield) | DeviceActivityReport/Monitor extension'lar MVP'da, shield bloklash 2-bosqichda | 4-bo'lim (iOS), 5-bo'lim (risk log) |
| 13 | Android Focus session foreground service | MVP da foreground service yo'q (batareya + Android 14 friction); opt-in "Focus session" 2-bosqichda | 4-bo'lim (Android) |
| 14 | Content packs (advanced tarjimalar, tafsir) | Qur'on bundled; qo'shimcha tarjimalar/tafsir ZIP sifatida yuklab olinadi 2-bosqichdan | 7-bo'lim (Qur'on paketlash) |

---

## ADR jarayonida aniqlangan qoplanmagan ehtiyojlar (2026-09-12)

Bular backlog emas — **MVP uchun kerak**, lekin rejada egasi yo'q. Tegishli bosqichda
kimdir ularni o'z zimmasiga olishi shart.

| # | Ehtiyoj | Kim ko'targan | Qachon kerak |
|---|---|---|---|
| 1 | **Remote-config mexanizmi** — `dw_ios_mode` bayrog'i va waste-scorer og'irliklari uchun. ADR-0003 va reja 4-bo'limi uni nazarda tutadi, lekin hech bir ADR uni egallamagan | ADR-0003 | 6-bosqich (DW) |
| 2 | **`GET /sync/limits`** endpointi — klient batch/o'lcham limitlarini kodga qattiq yozish o'rniga serverdan olishi uchun. Rejaning endpoint ro'yxatida yo'q | ADR-0002 | 2-bosqich (sync) |
| 3 | **Email yetkazib berish provayderi** (Resend/Postmark) — email tasdiqlash va parol tiklash modellari/servislari yozilgan, lekin endpoint ochilmagan va hech narsa yuborilmaydi | T-101 (auth) | 1-bosqich oxiri |
| 4 | **Bugungi balans ball formulasi** — 7 yo'nalish sanalgan, lekin og'irliklar va hisob formulasi rejada yo'q (`docs/balance-formula.md` da TODO) | T-004 | 5-bosqichdan oldin |
| 5 | **Obyekt saqlash (S3/MinIO) ulanishi** — avatar yuklash va ma'lumot eksporti uchun. Hozircha `avatar_url` satri qabul qilinadi | T-102 (profil) | 1–9 bosqich |
