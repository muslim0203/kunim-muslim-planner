# ADR-0003: Digital Wellbeing — Android and iOS are two different products

## Status

Accepted — 2026-09-12

## Context

Digital Wellbeing (DW) — KUNIM ning asosiy farqlovchi funksiyasi: ekran vaqti, "bekorchi
skrolling" bahosi, limitlar, Smart Warning va "Vaqtingizni qaytaring". Lekin ikki platforma
texnik jihatdan tubdan farq qiladi:

- Android'da ilova `UsageStatsManager` orqali **haqiqiy raqamlarni** (qaysi ilova, qancha
  daqiqa, qachon) o'qiy oladi.
- iOS'da Screen Time API (`FamilyControls` / `DeviceActivity` / `ManagedSettings`) raqamlarni
  ilovaga **umuman bermaydi**: tanlangan ilovalar opaque token sifatida keladi va statistika
  faqat sandbox'langan `DeviceActivityReport` extension ichida ko'rinadi.

Buni MVP oxirida "tekislashga" urinish loyihani buzadi. Shuning uchun reja birinchi kundan
(`docs/plan.md`, Kontekst 3; `CLAUDE.md`, 5-qoida) buni qabul qiladi.

## Decision

**Android DW va iOS DW — bitta UI ostidagi ikki xil mahsulot.** Umumiy narsa — ekranlar,
terminologiya va `dw_score` formulasi tuzilishi; ma'lumot manbalari va aniqlik darajasi umumiy
EMAS. iOS Score UI da **"taxminiy"** deb belgilanishi **MUST**.

### Android (full)

- Ruxsat: **`PACKAGE_USAGE_STATS`**, `Settings.ACTION_USAGE_ACCESS_SETTINGS` intent orqali.
  Intent'dan **oldin in-app disclosure ekrani MUST ko'rsatilsin** (nima yig'iladi, nima uchun,
  qayerda saqlanadi) — Play Permissions Declaration Form talabi. DW store listing'da asosiy
  funksiya sifatida deklaratsiya qilinadi.
- **`AccessibilityService` ishlatilMAYDI.** Sabab: Play siyosati bu API ni faqat nogironlik
  ehtiyojlari uchun ruxsat etadi; boshqa ilova kontentini o'qish ТЗ 46 bo'yicha ham taqiqlangan.
  Natija: **scroll darajasidagi aniqlash yo'q** — "bekorchi skrolling" faqat sessiya shaklidan
  (kategoriya, davomiylik, vaqt, qayta ochish) baholanadi.
- **`QUERY_ALL_PACKAGES` so'ralMAYDI.** Sabab: Play uni "sensitive" deb hisoblaydi va alohida
  asos talab qiladi; manifest `<queries><intent MAIN/LAUNCHER>` filtri kerakli ilovalarni ko'rish
  uchun yetarli.
- **Overlay bloklash yo'q — `SYSTEM_ALERT_WINDOW` so'ralMAYDI.** Sabab: boshqa ilova ustiga
  majburlovchi ekran chiqarish Play siyosati xavfi va rad etilish sababi. Limit = **faqat
  bildirishnoma** (80% / 100%; amallar: Ochish / 15 daq kechiktirish / Bugun uzaytirish).
- Native modul: `android/.../wellbeing/` — `UsageCollector.kt` (`queryEvents`,
  `ACTIVITY_RESUMED/PAUSED`, API 26–28 uchun `MOVE_TO_*`; 3 soniyadan kichik bo'shliqlar
  birlashtiriladi; `SCREEN_INTERACTIVE` → pickups), `AppCategoryResolver.kt`
  (`ApplicationInfo.category` + `assets/app_categories.json` override; foydalanuvchi qayta
  belgilay oladi), `UsageWorker.kt` (WorkManager 15 daq + app ochilganda + `BOOT_COMPLETED`).
- **MVP da foreground service yo'q** (Android 14 friction, batareya). Shuning uchun
  **Smart Warning kechikishi ≤ 15 daqiqa** deb qabul qilinadi va bu UI da halol ko'rsatiladi.
  Opt-in "Focus session" foreground service — 2-bosqich.
- OEM battery killer (Xiaomi/Huawei) → in-app whitelisting yo'riqnomasi; ma'lumot bo'shlig'i
  ("14:00 dan beri ma'lumot yo'q") yashirilMAYDI.

### iOS (limited)

- Stack: **`FamilyControls` + `DeviceActivity` + `ManagedSettings`**, iOS 16+ individual
  avtorizatsiya. `com.apple.developer.family-controls` entitlement **so'rovi 0-bosqichda**
  yuboriladi.
- `FamilyActivityPicker` **opaque token** qaytaradi — **ilova bundle ID yoki ilova nomini hech
  qachon bilmaydi** va bilishga urinMAYDI.
- `DeviceActivityReport` extension (`ios/KunimReport/`): statistika **faqat sandbox'langan
  SwiftUI view ichida** ko'rsatiladi. Bu raqamlar **MUST NOT** ilovaga yoki serverga uzatilsin —
  na App Group orqali, na boshqa yo'l bilan.
- `DeviceActivityMonitor` extension (`ios/KunimMonitor/`): kunlik schedule; har limit uchun
  80% / 100% threshold event → lokal notification + App Group bayrog'i `{limitId, level, ts}`.
  **Faqat shu threshold eventlar App Group orqali ilovaga o'tadi**; ilova resume'da ularni
  `dw_events` ga yozadi. Extension xotira limiti ~6 MB — kod minimal bo'lishi shart.
- `ManagedSettingsStore.shield` **MVP da o'chiq** (Android bilan paritet uchun); "Qat'iy rejim" —
  2-bosqich.
- iOS "bekorchi vaqt" = threshold eventlar + self-report ("Bu vaqt foydali bo'ldimi?") →
  natijadagi Score **"taxminiy"** deb belgilanadi.
- **Feature flag `dw_ios_mode = full | selfreport`.** `full` — entitlement berilgan va
  `DeviceActivity` ishlayapti; `selfreport` — entitlement yo'q yoki foydalanuvchi avtorizatsiya
  bermagan, DW faqat qo'lda self-report bilan ishlaydi.
- **iOS relizi entitlement berilishiga bog'lanMAYDI.** `dw_ios_mode=selfreport` bilan ilova
  to'liq ishlaydigan holatda do'konga chiqishi mumkin bo'lishi shart; bu CI da va QA da alohida
  ssenariy sifatida tekshiriladi.

### Data that leaves the device

Ikkala platformada ham qurilmadan **faqat** quyidagilar chiqadi:

| Chiqadi | Izoh |
|---|---|
| `dw_daily(date, app_key, category, minutes, sessions, waste_minutes_est)` | `app_key` **per-user salt bilan hash** qilinadi (foydalanuvchi "app-level cloud stats" ni yoqmagan bo'lsa); soatdan nozik timestamp yo'q |
| `dw_events(type, ts)` | type ∈ `warn80`, `warn100`, `snoozed`, `extended`, `closed_after_warn`, `selfreport_*` |
| `dw_score` | Kunlik hisoblangan ball |

**Xom `dw_sessions` hech qachon serverga yuklanMAYDI** (`CLAUDE.md`, 7-qoida). `scrolling_events`
va notification engagement log ham faqat lokal qoladi (ulardan faqat kunlik agregat chiqadi).
`dw_daily` yuklash yo'nalishi **upload-only** — server bu jadvalni klientga qaytarmaydi.

### Shared model

- DW Score formulasi ikkala platformada bir xil kod yo'lida hisoblanadi, lekin **iOS variantida
  birinchi had (total/target) yo'q**, chunki umumiy ekran vaqti iOS'da mavjud emas.
- Bekorchi skrolling ehtimoli (`wellbeing/domain/waste_scorer.dart`) og'irliklari remote-config
  JSON da; Ta'lim / kitob / Qur'on / ish kategoriyalari **hech qachon bekorchi deb
  belgilanMAYDI**.
- DW kontekstli ogohlantirish chastotasi: bir ilova uchun soatiga ≤ 1, kuniga ≤ 6.

## Consequences

- Ikki platforma uchun ikki xil DW ekran holati va ikki xil QA ssenariysi kerak; 6-bosqich
  Android (2 hafta) va iOS (1.5 hafta) sifatida alohida rejalashtirilgan.
- Ruxsat rad etilganda (Android Usage Access yoki iOS FamilyControls) ilova **buzilMAYDI** — DW
  ekrani tushuntirish va self-report bilan ishlaydi. Bu 6-bosqich DoD talabi.
- AccessibilityService yo'qligi "bekorchi skrolling" aniqligini pasaytiradi; buning o'rniga
  sessiya shakli + self-report ishlatiladi va ML 2-bosqichga qoldiriladi.
- Foreground service yo'qligi Smart Warning ni real vaqtli emas, ≤ 15 daqiqa kechikishli qiladi —
  bu mahsulot va'dasida shunday aytiladi.
- Server DW ma'lumotining minimal qismini ko'radi, shuning uchun Play Data Safety va App Store
  nutrition label deklaratsiyalari sodda bo'ladi.
- iOS raqamlari sandbox'dan chiqmagani uchun cross-device DW statistikasi iOS'da to'liq bo'lmaydi.
- **Open question:** reja `app_key` hash uchun salt qayerda saqlanishini aytmaydi. Bu yerda
  tanlangan yechim: salt qurilmada `flutter_secure_storage` da generatsiya qilinadi va serverga
  yuborilMAYDI — natijada server `app_key` ni deanonimlashtira olmaydi, lekin foydalanuvchi
  qurilma almashtirsa server tomondagi tarixiy `app_key` lar mos kelmaydi.
- **Open question:** reja `dw_daily` upload chastotasini aniq aytmaydi; standart sync sikliga
  qo'shilishi (ADR-0002) nazarda tutiladi.

## Alternatives considered

| Variant | Nega rad etildi |
|---|---|
| **Android `AccessibilityService` bilan scroll aniqlash** | Play siyosati (faqat nogironlik uchun) va ТЗ 46 taqiqi; ilova butunlay rad etilishi mumkin. |
| **`QUERY_ALL_PACKAGES`** | Play "sensitive permission" deb alohida asos talab qiladi; `<queries>` filtri bilan ehtiyoj qoplanadi. |
| **`SYSTEM_ALERT_WINDOW` bilan overlay bloklash** | Siyosat xavfi va foydalanuvchi uchun agressiv UX; bildirishnoma bilan bir xil maqsadga yetiladi. |
| **MVP da foreground service** | Android 14 da doimiy bildirishnoma va batareya narxi; "Focus session" sifatida opt-in 2-bosqichga ko'chirildi. |
| **iOS `ManagedSettings.shield` ni MVP da yoqish** | Android'da ekvivalenti yo'q (overlay rad etilgan) → paritet buziladi; shuningdek App Store review xavfi. |
| **iOS raqamlarini extension'dan App Group orqali chiqarish** | Apple Screen Time maxfiylik modelini buzadi, review'da rad etiladi va KUNIM ning maxfiylik va'dasiga zid. |
| **Bitta umumiy DW mahsulot (platformalarni tenglashtirish)** | Yoki Android imkoniyati behuda ketadi, yoki iOS da amalga oshmaydigan va'da beriladi. |

## Revisit when

1. Apple `DeviceActivity` da ilovaga raqam berishga ruxsat bersa (yoki entitlement rad etilsa) —
   `dw_ios_mode` semantikasi qayta ko'riladi;
2. Family Controls entitlement 6-bosqich boshlanishigacha berilmasa — iOS `selfreport` rejimida
   relizga chiqadi va bu ADR tasdiqlanadi/yangilanadi;
3. Play Usage Access deklaratsiyasi rad etilsa;
4. Smart Warning ≤ 15 daqiqa kechikishi beta foydalanuvchilarida asosiy shikoyatga aylansa
   (foreground service qayta ko'riladi);
5. 2-bosqichda "Qat'iy rejim" (shield / blocking) mahsulot qarori sifatida qabul qilinsa.
