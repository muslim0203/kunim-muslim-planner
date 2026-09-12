# KUNIM mobil ilova (Flutter)

**MUHIM: bu manba daraxti hech qachon kompilyatsiya qilinmagan va ishga
tushirilmagan.** Ushbu fayllarni yozgan mashinada Flutter, Dart SDK va
Android SDK o'rnatilmagan edi — hammasi qo'lda, `docs/plan.md` bo'lim 2 va
`CLAUDE.md` asosida yozilgan. `flutter analyze` / `flutter pub get` /
`flutter test` — birortasi ham bu yerda ishga tushirilmagan.

## Talab qilinadigan muhit

- Flutter 3.22+ (Dart SDK `>=3.4.0 <4.0.0`, `pubspec.yaml`da ko'rsatilgan)
- Android build uchun Android SDK (min SDK 26, ya'ni Android 8+)
- iOS build uchun Xcode + macOS (deployment target iOS 16.0)

## Ishga tushirish (Flutter o'rnatilgan mashinada)

```bash
cd apps/mobile

# 1) android/ va ios/ papkalari shu yerda faqat minimal holatda mavjud
#    (qarang: PLATFORM-SETUP.md) — to'liq host loyihasini generatsiya qiling:
flutter create --platforms=android,ios --org com.kunim --project-name kunim .

# 2) Paketlarni o'rnatish (shu bilan birga `flutter gen-l10n` ham avtomatik
#    ishga tushadi, chunki pubspec.yaml'da `flutter: generate: true`):
flutter pub get

# 3) Kod generatsiyasi (freezed / json_serializable / drift / riverpod):
dart run build_runner build --delete-conflicting-outputs

# 4) Ishga tushirish:
flutter run
```

## `make gen` nimani generatsiya qiladi

Repo ildizidagi `Makefile`ning `make gen` maqsadi (boshqa `apps/`lar bilan
birga) ushbu paket uchun quyidagilarni ishlab chiqaradi:

- `flutter gen-l10n` — `lib/app/l10n/*.arb` fayllaridan
  `lib/app/l10n/gen/app_localizations.dart` (`l10n.yaml`da sozlangan,
  `synthetic-package: false`, `output-class: AppLocalizations`).
- `build_runner` orqali:
  - `*.freezed.dart` — `freezed_annotation` bilan belgilangan immutable
    model/DTO klasslar uchun (hali Phase 0da modellar yo'q).
  - `*.g.dart` — `json_serializable` (DTO serializatsiya) va `drift_dev`
    (`lib/core/db/app_database.dart` uchun `app_database.g.dart`, jadval
    klasslari `lib/core/db/tables/`da) uchun.
  - `riverpod_generator` orqali `@riverpod` annotatsiyali provider'lar
    uchun kod (hozircha `Provider`/`StateProvider` qo'lda yozilgan, kelajakda
    generatsiyaga o'tkaziladi).

Bu fayllarning hech biri ushbu commit ichida yo'q — ular faqat Flutter
o'rnatilgan mashinada `dart run build_runner build` ishga tushgandan keyin
paydo bo'ladi. Ularni qo'lda tahrirlamang (`CLAUDE.md` qoidasi).

## Papka tuzilishi (qisqacha)

```
lib/
├── main.dart                  # bootstrap: WidgetsFlutterBinding, ProviderScope
├── app/                       # app.dart, router/, theme/, l10n/*.arb
├── core/db/                   # Drift: app_database.dart, tables/
├── core/network/              # dio client, xato xaritalash
├── shared/widgets/             # KunimCard, ProgressRing, EmptyState
└── features/<name>/presentation/  # Phase-0 uchun 5 ta placeholder ekran
```

## Tekshirilgan va tekshirilmagan narsalar

- **Tekshirilgan:** `pubspec.yaml`, `l10n.yaml`, `analysis_options.yaml` —
  YAML sifatida to'g'ri parslanishi (Node.js `js-yaml` bilan). ARB fayllar
  o'rtasidagi kalit muvofiqligi — `tool/check_l10n.mjs` (Node, `flutter`
  talab qilinmaydi) bilan ishga tushirilgan va **muvaffaqiyatli** o'tgan.
- **Tekshirilmagan (Flutter/Android SDK yo'qligi sababli):** `flutter pub
  get` paket versiyalarini yechishi, `flutter analyze`, `flutter test`,
  `flutter build apk`/`flutter build ios`, `dart run build_runner build`.
  `pubspec.yaml`dagi barcha versiya cheklovlari — konservativ taxminlar,
  Flutter o'rnatilgan mashinada `flutter pub get` / `flutter pub outdated`
  bilan tasdiqlanishi shart.

Android/iOS host loyihalari haqida — `PLATFORM-SETUP.md`ga qarang: u yerda
qaysi fayllar hozir mavjud va `flutter create --platforms=android,ios .`
qaysi qismlarni to'ldirishi kerakligi aniq yozilgan.
