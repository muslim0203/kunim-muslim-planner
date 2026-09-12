# ADR-0003: Digital Wellbeing — Android and iOS are two different products

**Holat:** Qabul qilingan
**Sana:** 2026-09-12

---

## Kontekst

Digital Wellbeing (DW) — KUNIM ning asosiy farqlovchi funksiyasi: ekran vaqti, "bekorchi
skrolling" bahosi, limitlar, Smart Warning va "Vaqtingizni qaytaring". Lekin ikki platforma
texnik jihatdan tubdan farq qiladi:

- Android'da ilova `UsageStatsManager` orqali **haqiqiy raqamlarni** (qaysi ilova, qancha
  daqiqa, qachon) o'qiy oladi.
- iOS'da Screen Time API (`FamilyControls` / `DeviceActivity` / `ManagedSettings`) raqamlarni
  ilovaga **umuman bermaydi**: tanlangan ilovalar opaque token sifatida keladi va statistika
  faqat sandbox'langan `DeviceActivityReport` extension ichida ko'rinadi.

Buni MVP oxirida "tekislashga" urinish loyihani buzadi. Shuning uchun reja birinchi kundan
(`docs/plan.md` Kontekst 3, 4-bo'lim; `CLAUDE.md` 5-qoida) bu farqni qabul qiladi.

---

## Qaror

**Android DW va iOS DW — bitta UI ostidagi ikki xil mahsulot.** Umumiy narsa — ekranlar,
terminologiya va `dw_score` formulasining tuzilishi; ma'lumot manbalari va aniqlik darajasi
umumiy **emas**. iOS Score UI da **"taxminiy"** deb belgilanadi.

### Android (to'liq)

- Ruxsat: **`PACKAGE_USAGE_STATS`**, `Settings.ACTION_USAGE_ACCESS_SETTINGS` intent orqali.
  Intent'dan **oldin in-app disclosure ekrani ko'rsatiladi** (nima yig'iladi, nima uchun,
  qayerda saqlanadi) — Play Permissions Declaration Form talabi. DW store listing'da asosiy
  funksiya sifatida deklaratsiya qilinadi.
- **`AccessibilityService` ishlatilmaydi.** Sabab: Play siyosati bu API ni faqat nogironlik
  ehtiyojlari uchun ruxsat etadi; boshqa ilova kontentini o'qish ТЗ 46 bo'yicha ham taqiqlangan.
  Natija: **scroll darajasidagi aniqlash yo'q** — "bekorchi skrolling" faqat sessiya shaklidan
  (kategoriya, davomiylik, vaqt, qayta ochish) baholanadi.
- **`QUERY_ALL_PACKAGES` so'ralmaydi.** Sabab: Play uni "sensitive" deb hisoblaydi va alohida
  asos talab qiladi; manifest `<queries><intent MAIN/LAUNCHER>` filtri kerakli ilovalarni
  ko'rish uchun yetarli.
- **Overlay bloklash yo'q — `SYSTEM_ALERT_WINDOW` so'ralmaydi.** Sabab: boshqa ilova ustiga
  majburlovchi ekran chiqarish Play siyosati xavfi va rad etilish sababi (ТЗ 46). Limit =
  **faqat bildirishnoma** (80% / 100%; amallar: Ochish / 15 daq kechiktirish / Bugun uzaytirish).
- Native modul `android/.../wellbeing/`:
  - `UsageCollector.kt` — `queryEvents`, `ACTIVITY_RESUMED/PAUSED`, API 26–28 uchun `MOVE_TO_*`;
    3 soniyadan kichik bo'shliqlar birlashtiriladi; `SCREEN_INTERACTIVE` → pickups.
  - `AppCategoryResolver.kt` — `ApplicationInfo.category` + `assets/app_categories.json`
    override; foydalanuvchi qayta belgilay oladi.
  - `UsageWorker.kt` — **WorkManager 15 daqiqalik** agregatsiya + app ochilganda +
    `BOOT_COMPLETED`; xom sessiyalarni `usage_sessions_raw` ga yozadi, Dart resume'da import
    qiladi.
- **MVP da foreground service yo'q** (Android 14 friction, batareya). Shuning uchun
  **Smart Warning kechikishi ≤ 15 daqiqa** deb qabul qilinadi va bu UI da halol ko'rsatiladi.
  Opt-in "Focus session" foreground service — 2-bosqich.
- OEM battery killer (Xiaomi/Huawei) → in-app whitelisting yo'riqnomasi; ma'lumot bo'shlig'i
  ("14:00 dan beri ma'lumot yo'q") yashirilmaydi.

### iOS (cheklangan — qat'iy qabul qilinadi)

- Stack: **`FamilyControls` + `DeviceActivity` + `ManagedSettings`**, **iOS 16+** individual
  (non-guardian) avtorizatsiya.
- `com.apple.developer.family-controls` entitlement **so'rovi 0-bosqichda yuboriladi**. Jarayon
  haftalar/oylar davom etishi va **rad etilishi mumkin**; qurilmada dev ishlaydi, App Store'ga
  tasdiqsiz chiqmaydi. Reja shu xavf bilan tuziladi.
- `FamilyActivityPicker` **opaque token** qaytaradi — **ilova bundle ID yoki nomini hech qachon
  bilmaydi** va bilishga urinmaydi.
- `DeviceActivityReport` extension (`ios/KunimReport/`): statistika **faqat sandbox'langan
  SwiftUI view ichida** ko'rsatiladi. Bu raqamlar **ilovaga yoki serverga uzatilmaydi** — na
  App Group orqali, na boshqa yo'l bilan.
- `DeviceActivityMonitor` extension (`ios/KunimMonitor/`): kunlik schedule; har limit uchun
  80% / 100% threshold event → lokal notification + App Group bayrog'i `{limitId, level, ts}`.
  **Faqat shu threshold eventlar** App Group orqali ilovaga o'tadi; ilova resume'da ularni
  `dw_events` ga yozadi. Extension xotira limiti ~6 MB — kod minimal bo'lishi shart.
- `ManagedSettingsStore.shield` **MVP da o'chiq** (Android bilan paritet uchun); "Qat'iy rejim"
  — 2-bosqich.
- iOS "bekorchi vaqt" = threshold eventlar + self-report ("Bu vaqt foydali bo'ldimi?") →
  natijadagi Score **"taxminiy"** deb belgilanadi.
- **Feature flag `dw_ios_mode = full | selfreport`:**
  - `full` — entitlement berilgan va `DeviceActivity` ishlayapti;
  - `selfreport` — entitlement yo'q yoki foydalanuvchi avtorizatsiya bermagan; DW faqat qo'lda
    self-report bilan ishlaydi.
- **iOS relizi entitlement berilishiga bog'lanmaydi.** `dw_ios_mode = selfreport` bilan ilova
  to'liq ishlaydigan holatda do'konga chiqa olishi shart; bu CI va QA da alohida ssenariy.

### Umumiy ma'lumot modeli chegarasi

Ikkala platformada ham qurilmadan **faqat** quyidagilar chiqadi:

| Serverga chiqadi | Izoh |
|---|---|
| `dw_daily(date, app_key, category, minutes, sessions, waste_minutes_est)` | `app_key` **per-user salt bilan hash**; **soatdan nozik timestamp yo'q** |
| `dw_events(type, ts)` | `type ∈ warn80, warn100, snoozed, extended, closed_after_warn, selfreport_*` |
| `dw_score` | Kunlik hisoblangan ball |

**Qurilmadan hech qachon chiqmaydi:**

- xom `dw_sessions(app_key, category, started_at, ended_at, duration_s, hour_of_day,
  pickup_gap_s, source)` va `usage_sessions_raw` (`CLAUDE.md` 7-qoida);
- `scrolling_events`, xom notification engagement log (ulardan faqat kunlik agregat chiqadi);
- iOS `DeviceActivityReport` ichidagi har qanday raqam.

`dw_daily` / `dw_events` / `dw_score` yuklash yo'nalishi **upload-only** — server bu jadvallarni
klientga qaytarmaydi (ADR-0002, 21–22-qoidalar).

### Umumiy formulalar

- DW Score ikkala platformada bir xil kod yo'lida hisoblanadi, lekin **iOS variantida birinchi
  had (`total/target`) yo'q**, chunki umumiy ekran vaqti iOS'da mavjud emas.
- Bekorchi skrolling ehtimoli (`wellbeing/domain/waste_scorer.dart`) og'irliklari remote-config
  JSON da; **ta'lim / kitob / Qur'on / ish kategoriyalari hech qachon bekorchi deb
  belgilanmaydi**.
- DW kontekstli ogohlantirish chastotasi: bir ilova uchun soatiga ≤ 1, kuniga ≤ 6.

---

## Sabablar

- **Ikkita mahsulot deb tan olish — eng arzon yo'l.** Platformalarni tenglashtirishga urinish
  yoki Android imkoniyatini behuda sarflaydi, yoki iOS'da amalga oshmaydigan va'da beradi.
- **Taqiqlangan API'lardan voz kechish relizni himoya qiladi.** `AccessibilityService`,
  `QUERY_ALL_PACKAGES`, `SYSTEM_ALERT_WINDOW` — uchalasi ham Play'da rad etilish yoki kechikish
  xavfi; ular bergan qo'shimcha aniqlik shu xavfga arzimaydi.
- **Foreground service'siz WorkManager** batareya va Android 14 friction'ini yo'q qiladi;
  ≤ 15 daqiqalik kechikish mahsulot va'dasiga ochiq yoziladi va shuning uchun muammo emas.
- **Minimal ma'lumot chegarasi** Play Data Safety va App Store nutrition label
  deklaratsiyalarini sodda qiladi va maxfiylik va'dasini texnik jihatdan bajariladigan qiladi.
- **`dw_ios_mode` bayrog'i** entitlement rad etilishi xavfini reliz blokeridan konfiguratsiya
  masalasiga aylantiradi.

---

## Ko'rib chiqilgan alternativalar (va nega rad etilgan)

| Variant | Nega rad etildi |
|---|---|
| **Android `AccessibilityService` bilan scroll aniqlash** | Play siyosati (faqat nogironlik ehtiyojlari uchun) va ТЗ 46 taqiqi (boshqa ilova kontentini o'qish); ilova butunlay rad etilishi mumkin. |
| **`QUERY_ALL_PACKAGES`** | Play "sensitive permission" deb alohida asos talab qiladi; `<queries><intent MAIN/LAUNCHER>` filtri bilan ehtiyoj to'liq qoplanadi. |
| **`SYSTEM_ALERT_WINDOW` bilan overlay bloklash** | ТЗ 46 va Play siyosati xavfi, agressiv UX; bildirishnoma bilan bir xil maqsadga yetiladi. |
| **MVP da foreground service** | Android 14 da doimiy bildirishnoma va batareya narxi; "Focus session" sifatida opt-in 2-bosqichga ko'chirildi. |
| **iOS `ManagedSettings.shield` ni MVP da yoqish** | Android'da ekvivalenti yo'q (overlay rad etilgan) → paritet buziladi; App Store review xavfi. |
| **iOS raqamlarini extension'dan App Group orqali chiqarish** | Apple Screen Time maxfiylik modelini buzadi, review'da rad etiladi va KUNIM ning maxfiylik va'dasiga zid. |
| **Bitta umumiy DW mahsulot (platformalarni tenglashtirish)** | Yoki Android imkoniyati behuda ketadi, yoki iOS'da amalga oshmaydigan va'da beriladi. |
| **iOS relizini entitlement'ga bog'lash** | Rad etilish yoki kechikish butun iOS relizini bloklardi; `selfreport` rejimi bu bog'liqlikni uzadi. |
| **`app_usage` pub paketi** | Juda qo'pol (event darajasi yo'q, API 26–28 farqlarini qoplamaydi); `pigeon` + Kotlin to'g'ridan-to'g'ri ishlatiladi (ADR-0001). |
| **Xom sessiyalarni serverga yuklab, waste score'ni serverda hisoblash** | Eng nozik ma'lumotni serverga ko'chirardi; hisob-kitob qurilmada arzon va offline ishlaydi. |

---

## Oqibatlar

### Ijobiy

- Ruxsat rad etilganda (Android Usage Access yoki iOS FamilyControls) ilova **buzilmaydi** —
  DW ekrani tushuntirish va self-report bilan ishlaydi (6-bosqich DoD talabi).
- Server DW ma'lumotining minimal qismini ko'radi → store deklaratsiyalari sodda, maxfiylik
  auditida himoya qilish oson.
- iOS relizi entitlement javobini kutmaydi.
- Waste score va DW score qurilmada hisoblanadi → offline ishlaydi, server yuki yo'q.

### Salbiy

- Ikki platforma uchun ikki xil DW holat mashinasi va ikki xil QA ssenariysi kerak; 6-bosqich
  Android (2 hafta) va iOS (1.5 hafta) sifatida alohida rejalashtirilgan.
- `AccessibilityService` yo'qligi "bekorchi skrolling" aniqligini pasaytiradi; o'rniga sessiya
  shakli + self-report, ML esa 2-bosqichga qoldiriladi.
- Foreground service yo'qligi Smart Warning ni real vaqtli emas, ≤ 15 daqiqa kechikishli qiladi.
- iOS raqamlari sandbox'dan chiqmagani uchun cross-device DW statistikasi iOS'da to'liq bo'lmaydi
  va iOS Score doimo "taxminiy" qoladi.
- `app_key` per-qurilma salt bilan hash qilingani uchun foydalanuvchi qurilma almashtirsa server
  tomondagi tarixiy `app_key` lar mos kelmaydi (quyida, ongli savdo).

---

## Amalga oshirish uchun majburiy qoidalar

1. `AndroidManifest.xml` da **hech qachon** `QUERY_ALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`
   bo'lmaydi va `AccessibilityService` deklaratsiya qilinmaydi. CI manifest'ni grep bilan
   tekshiradi va topilsa build yiqiladi.
2. `PACKAGE_USAGE_STATS` uchun tizim intent'i **faqat** in-app disclosure ekranidan keyin
   ochiladi. Disclosure matni `l10n` da, 4 tilda.
3. Android agregatsiya — **faqat WorkManager, 15 daqiqa**; MVP da `startForegroundService`
   chaqirilmaydi.
4. Limitlar **faqat bildirishnoma** bilan amalga oshiriladi; hech qanday bloklovchi UI yo'q.
5. iOS `DeviceActivityReport` extension'idan ilovaga yoki App Group'ga **hech qanday raqam
   yozilmaydi**. Extension faqat SwiftUI view render qiladi. Kod ko'rib chiqishda bu alohida
   tekshiriladi.
6. App Group orqali **faqat** `{limitId, level, ts}` shaklidagi threshold event bayroqlari
   o'tadi.
7. Serverga **faqat** `dw_daily`, `dw_events`, `dw_score` yuboriladi. `dw_sessions`,
   `usage_sessions_raw`, `scrolling_events` uchun sync entity **yaratilmaydi**; ular
   `SYNC_ENTITIES` ro'yxatiga kirmaydi (ADR-0002).
8. `dw_daily.app_key` — per-user salt bilan hash (`HMAC-SHA256(salt, package_name)`), salt
   qurilmada `flutter_secure_storage` da generatsiya qilinadi va **serverga yuborilmaydi**.
   Foydalanuvchi "app-level cloud stats" consent'ini bermasa `app_key` umuman yuborilmaydi —
   faqat `category` darajasidagi agregat chiqadi.
9. Yuborilayotgan DW yozuvlarida **soatdan nozik timestamp bo'lmaydi**: `dw_daily` — sana,
   `dw_events.ts` — soatga yaxlitlanadi.
10. `dw_ios_mode` bayrog'i remote-config'dan keladi va `selfreport` qiymatida barcha DW
    ekranlari ishlashi shart; bu holat uchun alohida QA ssenariysi bo'ladi.
11. iOS Score ko'rsatilgan har joyda "taxminiy" belgisi bo'ladi (UI matni `l10n` da).
12. `DeviceActivityMonitor` extension kodi minimal (~6 MB xotira limiti): tashqi paket yo'q,
    tarmoq chaqiruvi yo'q, log yo'q.
13. Ta'lim / kitob / Qur'on / ish kategoriyalari `waste_scorer` da har doim `p = 0` beradi;
    bu birlik test bilan qulflanadi.
14. Ruxsat berilmagan holatda DW ekrani "ma'lumot yo'q" deb halol ko'rsatadi — soxta yoki
    o'ylab topilgan raqam ko'rsatilmaydi.

---

## Rejada aniqlanmagan — shu yerda hal qilindi

| Savol | Qaror |
|---|---|
| `app_key` hash algoritmi va salt qayerda saqlanadi | `HMAC-SHA256(salt, package_name)`; salt qurilmada `flutter_secure_storage` da generatsiya qilinadi va **serverga yuborilmaydi**. Natija: server `app_key` ni deanonimlashtira olmaydi; savdo — qurilma almashtirilganda tarixiy `app_key` lar mos kelmaydi (UI da yangi qurilmadan boshlab ko'rsatiladi). |
| Consent berilmagan holat | "App-level cloud stats" consent'i yo'q bo'lsa `app_key` umuman yuborilmaydi — faqat `category` darajasidagi agregat. |
| `dw_daily` upload chastotasi | Standart sync sikliga qo'shiladi (ADR-0002 trigger'lari); alohida jadval yo'q. |
| `dw_events.ts` aniqligi | Soatga yaxlitlanadi (§ "soatdan nozik timestamp yo'q" qoidasini bajarish uchun). |
| iOS'da `dw_daily` qayerdan keladi | `dw_ios_mode = full` da ham `dw_daily` **faqat** threshold eventlar va self-report'dan taxminlanadi (ilova haqiqiy daqiqalarni bilmaydi); `minutes` maydoni iOS'da `NULL` bo'lishi mumkin va Score birinchi hadi hisoblanmaydi. |
| Android'da limit "Bugun uzaytirish" qancha qo'shadi | +30 daqiqa, kuniga bir marta; keyingi uzaytirish "Ertaga qayta ko'rib chiqamiz" xabari bilan rad etiladi. |
| Entitlement rad etilsa qaror kim tomonidan qabul qilinadi | Avtomatik: `dw_ios_mode = selfreport` va reliz davom etadi; ADR yangilanadi, reliz bloklanmaydi. |

---

## Qachon qayta ko'riladi

1. Apple `DeviceActivity` da ilovaga raqam berishga ruxsat bersa — `dw_ios_mode` semantikasi
   qayta ko'riladi;
2. Family Controls entitlement 6-bosqich boshlanishigacha berilmasa yoki rad etilsa — iOS
   `selfreport` rejimida relizga chiqadi va bu ADR yangilanadi;
3. Play Usage Access deklaratsiyasi rad etilsa;
4. Smart Warning ≤ 15 daqiqa kechikishi beta foydalanuvchilarida asosiy shikoyatga aylansa
   (foreground service qayta ko'riladi);
5. 2-bosqichda "Qat'iy rejim" (shield / blocking) mahsulot qarori sifatida qabul qilinsa.
