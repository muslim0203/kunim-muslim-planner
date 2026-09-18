# Android relizi: imzolash va do'konga chiqarish

Bu hujjat KUNIM Android ilovasini imzolash tartibini yozadi. iOS imzolash
bu yerda yo'q: u Apple Developer hisobi va macOS talab qiladi
(`docs/ios-family-controls-request.md` ga qarang).

## Tamoyil

- **Kalit repozitoriyga hech qachon tushmaydi.** `.gitignore` `*.jks`,
  `*.keystore` va `android/key.properties` ni bloklaydi.
- **Play App Signing ishlatiladi.** Ya'ni bizdagi kalit — *upload key*.
  Foydalanuvchiga yetadigan APK'ni Google o'z kaliti bilan qayta imzolaydi.
  Upload key yo'qolsa, Google'dan uni almashtirishni so'rash mumkin;
  app signing key yo'qolsa ilovani yangilab bo'lmaydi.
- **Kalit yo'q bo'lsa** release build debug kaliti bilan imzolanadi, shunda
  `flutter run --release` va test telefoni uchun tezkor APK ishlayveradi.
  Play debug sertifikatini qabul qilmaydi, shuning uchun bunday build
  bexosdan foydalanuvchiga chiqib keta olmaydi.

## 1. Upload key yaratish (bir marta)

Parolni **faqat o'zingiz** kiritasiz — buyruq uni interaktiv so'raydi.
Repozitoriydan tashqarida papka tanlang:

```bash
mkdir -p /d/Dasturlarim/keys && keytool -genkeypair -v -keystore /d/Dasturlarim/keys/kunim-upload.jks -keyalg RSA -keysize 4096 -validity 10000 -alias kunim-upload
```

Fayl PKCS12 formatida yaratiladi (Java 9+ dagi standart).
`keytool` Java 17 bilan keladi (`/d/Dasturlarim/jdk*/bin` yoki
Android Studio ichidagi JBR). So'raladigan maydonlar (CN, O, ...) ixtiyoriy,
lekin bir marta yoziladi va o'zgarmaydi.

**Zaxira:** `.jks` fayl va parollarni parol menejeriga qo'ying. Faylni
yo'qotish = ilovani yangilay olmaslik (Play App Signing bilan — tiklash
so'rovi orqali hal bo'ladi, lekin kunlar ketadi).

## 2. Loyihaga ulash

`apps/mobile/android/key.properties.example` dan nusxa oling:

```bash
cp apps/mobile/android/key.properties.example apps/mobile/android/key.properties
```

va to'ldiring (`storeFile` — absolyut yo'l, `\` emas `/` bilan):

```
storeFile=D:/Dasturlarim/keys/kunim-upload.jks
storePassword=...
keyAlias=kunim-upload
keyPassword=...
```

Fayl gitignore qilingan. `app/build.gradle.kts` uni o'qiydi; fayl bo'lmasa
`KUNIM_ANDROID_KEYSTORE`, `KUNIM_ANDROID_STORE_PASSWORD`,
`KUNIM_ANDROID_KEY_ALIAS`, `KUNIM_ANDROID_KEY_PASSWORD` muhit
o'zgaruvchilaridan oladi (CI shu yo'ldan yuradi).

## 3. Yig'ish

```bash
make aab    # Play uchun (app bundle)
make apk    # test telefoni uchun
```

Natija:
`apps/mobile/build/app/outputs/bundle/release/app-release.aab` va
`apps/mobile/build/app/outputs/flutter-apk/app-release.apk`.

## 4. Imzoni tekshirish

Debug kaliti bilan imzolanib qolmaganiga ishonch hosil qiling:

```bash
keytool -printcert -jarfile apps/mobile/build/app/outputs/flutter-apk/app-release.apk
```

Egasi `CN=Android Debug` bo'lsa — kalit ulanmagan (2-qadam).

## 5. Versiya

`apps/mobile/pubspec.yaml` dagi `version: 0.1.0+1` — `+` dan keyingi son
`versionCode`. Play'ga har yuklashda u **oshishi shart**.

## CI (ixtiyoriy)

`.github/workflows/release-mobile.yml` — qo'lda (`workflow_dispatch`) yoki
`v*` tegi bilan ishga tushadi va imzolangan AAB'ni artefakt qilib qo'yadi.
GitHub → Settings → Secrets da 4 ta secret kerak:

| Secret | Qiymat |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 kunim-upload.jks` natijasi |
| `ANDROID_STORE_PASSWORD` | keystore paroli |
| `ANDROID_KEY_ALIAS` | `kunim-upload` |
| `ANDROID_KEY_PASSWORD` | kalit paroli |

Secret'lar qo'yilmagan bo'lsa workflow tushunarli xato bilan to'xtaydi;
oddiy `Mobile` CI unga bog'liq emas.

## Relizdan oldin qoladigan ishlar

Imzolash tayyor, lekin do'konga chiqarish uchun bular ham kerak (reja
9-bosqich): Play Data Safety va Usage Access deklaratsiyasi, maxfiylik
siyosati havolasi, do'kon matnlari 4 tilda, skrinshotlar, yosh reytingi.
