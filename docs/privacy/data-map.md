# Maxfiylik va ma'lumot xaritalanishi (Data Map)

Quyidagi jadval qaysi ma'lumotlar qayerda saqlanadi, serverga yuklaniladi yoki yo'q, va qanday shifrlanganligi ko'rsatadi.

| Ma'lumot turi | Qayerda saqlanadi | Serverga yuklanadimi | Shifrlash | Saqlash muddati |
|---|---|---|---|---|
| **DW xom sessiyalari** (`dw_sessions` lokal) | Qurilmada Drift + SQLCipher | **YO'Q — hech qachon** | SQLCipher (lokal) | Kunlik agregat keyin o'chiriladi |
| **Scrolling hodisalari** (`scrolling_events` lokal) | Qurilmada Drift + SQLCipher | **YO'Q — hech qachon** | SQLCipher (lokal) | Kunlik agregat keyin o'chiriladi |
| **Notification engagement log** (lokal) | Qurilmada Drift + SQLCipher | Kunlik agregat faqat | SQLCipher + server AES-256-GCM | 180 kun keyin o'chiriladi |
| **DW kunlik agregat** (`dw_daily`) | Qurilmada + server | **HA, app_key hash bilan** | SQLCipher (lokal) + AES-256-GCM (server) | Lokal 14 kun, server 180 kun |
| **DW hodisalari** (`dw_events`) | Qurilmada + server | **HA** | SQLCipher (lokal) + AES-256-GCM (server) | Lokal 14 kun, server 180 kun |
| **DW Score kunlik** (`dw_score`) | Server | **HA** | AES-256-GCM | 180 kun |
| **Mood jurnal** (`mood_logs.note`) | Qurilmada + server | **HA** | SQLCipher (lokal) + AES-256-GCM (server) | 90 kun keyin tombstone, 30 kun `row_history` |
| **Uyqu jurnal** (`sleep_logs.note`) | Qurilmada + server | **HA** | SQLCipher (lokal) + AES-256-GCM (server) | 90 kun keyin tombstone, 30 kun `row_history` |
| **Sog'liq jurnal** (`health_logs.note`) | Qurilmada + server | **HA** | SQLCipher (lokal) + AES-256-GCM (server) | 90 kun keyin tombstone, 30 kun `row_history` |
| **Oila jurnali** (`family_logs.note`) | Qurilmada + server | **HA** | SQLCipher (lokal) + AES-256-GCM (server) | 90 kun keyin tombstone, 30 kun `row_history` |
| **AI chat xabarlari** (`ai_messages.content`) | Qurilmada lokal kesh + server | **HA** | SQLCipher (lokal) + AES-256-GCM (server) | 180 kun keyin o'chiriladi |
| **AI xotira** (`ai_memory.text`) | Server | **HA** | AES-256-GCM | 180 kun keyin o'chiriladi |
| **Vazifalar** (`tasks`) | Qurilmada + server | **HA (sync)** | SQLCipher (lokal) + TLS (tranzit) | Sync orqali, soft delete 90 kun |
| **Kalendar hodisalari** (`calendar_events`) | Qurilmada + server | **HA (sync)** | SQLCipher (lokal) + TLS (tranzit) | Sync orqali, soft delete 90 kun |
| **Odatlar** (`habits`) | Qurilmada + server | **HA (sync)** | SQLCipher (lokal) + TLS (tranzit) | Sync orqali, soft delete 90 kun |
| **Odatlar loglari** (`habit_logs`) | Qurilmada + server | **HA (sync)** | SQLCipher (lokal) + TLS (tranzit) | Sync orqali, soft delete 90 kun |
| **Namoz loglari** (`prayer_logs`) | Qurilmada + server | **HA (sync)** | SQLCipher (lokal) + TLS (tranzit) | Sync orqali, soft delete 90 kun |
| **Qur'on o'qish holati** (`quran_progress`) | Qurilmada + server | **HA (sync)** | SQLCipher (lokal) + TLS (tranzit) | Sync orqali |
| **Qur'on xatchiqlari** (`quran_bookmarks`) | Qurilmada + server | **HA (sync)** | SQLCipher (lokal) + TLS (tranzit) | Sync orqali |
| **Maqsadlar** (`goals`) | Qurilmada + server | **HA (sync)** | SQLCipher (lokal) + TLS (tranzit) | Sync orqali, soft delete 90 kun |
| **Ta'lim elementlari** (`education_items`) | Qurilmada + server | **HA (sync)** | SQLCipher (lokal) + TLS (tranzit) | Sync orqali, soft delete 90 kun |
| **Kitoblar** (`books`) | Qurilmada + server | **HA (sync)** | SQLCipher (lokal) + TLS (tranzit) | Sync orqali, soft delete 90 kun |
| **Foydalanuvchi profili** | Server | **HA** | TLS (tranzit) + server database | Pincode/username teslim so'ralguncha |
| **Google/Apple OIDC tokenlar** | Secure storage (lokal) | **YO'Q** | Flutter Secure Storage | Logout'da o'chiriladi |
| **JWT access token** | Xotira (lokal) | **YO'Q** | RAM xotirasi (15 daq TTL) | Session buyumada |
| **JWT refresh token** | Secure storage (lokal) | Server hash sifatida | Flutter Secure Storage + server hash | 30 kun yoki rotation qilingunga |
| **Qur'on matnlari** (`content` + `quran_progress`) | Qurilmada bundled | **YO'Q** | SQLCipher (lokal) | Doimiy (public domain) |
| **Kontent (hadis, iqtibos)** | Qurilmada kesh + server | **HA (read-only pull)** | SQLCipher (lokal) + AES-256-GCM (server) | Lokal kesh 30 kun, server doimiy |
| **Foydalanuvchi eksport** (JSON) | MinIO/S3 (vaqtincha) | **HA** | AES-256-GCM | 24 soat + signed URL |
| **O'chirish tavoaf** | Server soft-delete | Cascade 7 kun grace | AES-256-GCM | 7 kun grace, keyin hard-delete |
| **Audit log** | Server | **HA** | AES-256-GCM | 90 kun |
| **`row_history`** (point-in-time recovery) | Server | **HA** | AES-256-GCM | 30 kun keyin o'chiriladi |

---

## Digital Wellbeing ma'lumot (Bosqich 6)

| Ma'lumot turi | Qurilmada | Serverda | Shifrlangan | Saqlash muddati | Qoidalar |
|---|---|---|---|---|---|
| **Xom sessiyalar** (dw_sessions: app, start, end, duration) | ✓ SQLite | **❌ HECH QACHON** | N/A | 30 kun (local) | Raw session hech qachon serverga chiqmaydi |
| **Xom scrolling'lar** (scrolling_events: app, ts, scroll_depth) | ✓ SQLite | **❌ HECH QACHON** | N/A | 30 kun (local) | Xom event hech qachon serverga chiqmaydi |
| **Kunlik agregat** (dw_daily: app_key hashed, category, minutes, sessions, waste_minutes_est) | ✓ SQLite | ✓ PostgreSQL | Yo'q; app_key per-user salt bilan hash | 90 kun | Faqat yuklanish: qurilmadan serverga (pull yo'q) |
| **Event'lar** (dw_events: type warn80/warn100/snoozed/extended, ts) | ✓ SQLite | ✓ PostgreSQL | Yo'q | 90 kun | Bildirishnoma harakati |
| **DW Score** (daily_score: score, waste_minutes, night_minutes, breaches) | ✓ SQLite | ✓ PostgreSQL | Yo'q | 90 kun | Kalkulyatsiya qurilmada va serverda bir xil |

### DW ma'lumot hashing

- **app_key** qurilmada nominal nomi bilan saqlanadi (birinchi 8 ta belgisi + app category ID).
- **Serverga yuborilganda:** app_key + per-user salt = SHA-256 hash → server'da faqat hash saqlaydi.
- Foydalanuvchi "cloud stats" ruxsatini rad qilsa → hash o'chirilib yuborilmaydi; local `dw_daily` saqlanib turadi.

---

## AI va chat ma'lumot (Bosqich 7)

| Ma'lumot turi | Qurilmada | Serverda | Shifrlangan | Saqlash muddati |
|---|---|---|---|---|
| **Chat tarix** (ai_messages) | Qoida asosida local cache | PostgreSQL | **AES-256-GCM** (content maydon) | 180 kun (logs), keyin soft-delete |
| **Memory qaydlari** (ai_memory: fact/preference/goal) | Yo'q | PostgreSQL | **AES-256-GCM** (text maydon) | 180 kun (logs), keyin soft-delete |
| **AI proposal'lar** (ai_proposals: planner/reschedule) | Yo'q | PostgreSQL | Yo'q (strukturali) | Foydalanuvchi o'chguncha |
| **AI request log'lari** (ai_requests: model, tokens, cost) | Yo'q | PostgreSQL | Yo'q | 180 kun |

---

## Ruxsat va autentifikatsiya (Bosqich 1, 11)

| Ma'lumot turi | Qurilmada | Serverda | Shifrlangan | Saqlash muddati |
|---|---|---|---|---|
| **Refresh token** | ✓ secure_storage (KeyChain/Keystore) | ✓ PostgreSQL (token_hash) | ✓ Argon2id hash | 30 kun |
| **Access token** | ✓ RAM xotirada (faqat) | **❌ HECH QACHON** | N/A | 15 daq (xotirda) |
| **Database kalii** | ✓ secure_storage (SQLCipher uchun) | **❌ HECH QACHON** | N/A | O'rnatish davomida |
| **Device ID** | ✓ SQLite | ✓ PostgreSQL (firebase_messaging) | Yo'q | To'liq avtorizatsiya |

---

## Qur'on va kontent (Bosqich 3)

| Ma'lumot turi | Qurilmada | Serverda | Shifrlangan | Saqlash muddati |
|---|---|---|---|---|
| **Qur'on matn (Arab)** | ✓ bundled SQLite read-only | ✓ PostgreSQL (content jadvali) | Yo'q (public) | Doimiy |
| **Qur'on tarjimalari** | ✓ bundled SQLite or content_pack | ✓ PostgreSQL (content jadvali) | Yo'q (public) | Doimiy |
| **Hadis matn'lari** | ✓ content_pack (download) | ✓ PostgreSQL (content jadvali) | Yo'q (public) | Doimiy |
| **Kun hikmati** | ✓ cache (eng oxirgi 30 kun) | ✓ PostgreSQL (content jadvali) | Yo'q (public) | Doimiy |
| **Namoz preset'lari** | ✓ bundled (read-only) | ✓ PostgreSQL | Yo'q (public) | Doimiy |

---

## Statistika va analitika (Bosqich 5)

| Ma'lumot turi | Qurilmada | Serverda | Shifrlangan | Saqlash muddati |
|---|---|---|---|---|
| **Kunlik statistika** | ✓ Drift; hisoblangan lokal | ✓ PostgreSQL (user_statistics) | Yo'q | 1 yil |
| **Xavfsizlik event'lar** (ai_safety_events) | Yo'q | ✓ PostgreSQL | Yo'q | 180 kun |
| **Audit log'lari** (audit_logs) | Yo'q | ✓ PostgreSQL | Yo'q | 1 yil yoki GDPR talabi |
| **Analytics** (PostHog, Sentry) | ✓ qoida asosida local buffer | ✓ PostHog/Sentry | N/A (third-party) | PostHog/Sentry siyosati |

---

## Export va o'chirish (Bosqich 9, 11)

### Export (`POST /users/me/export`)

- **Jarayon:** Foydalanuvchi export so'radi → arq job shaklida JSON export → MinIO/S3 signed URL.
- **Signiture:** HMAC-SHA256 + 24 soatlik muddati.
- **Mazmun:** Barcha jadvallar JSON sifatida (bar sensitive field'lar; shifrlangan maydonlar bali qiymati bilan).
- **Saqlash muddati:** Signed URL 24 soat; keyin faylni o'chirish.

### O'chirish (`DELETE /users/me`)

1. **Soft delete:** `users.deleted_at = now()` + token revocation.
2. **Grace period:** 7 kun.
3. **Hard delete:** 7 kundan keyin cascade o'chirish:
   - Barcha jadval qatorlar (foydalanuvchi ID's)
   - Embedding'lar tozalash
   - AI memory'ni tozalash
   - Audit log'da hash ID'si qoladi

---

## Tombstone va cache cleanup (Bosqich 2, 11)

| Vazifa | Muddati | Jarayon |
|---|---|---|
| **Tombstone tozalash** | 90 kun | Soft-delete qatorlar 90 kundan keyin hard-delete; eski cursor = to'liq resync |
| **AI logs tozalash** | 180 kun | `ai_requests`, `ai_messages`, `ai_memory` 180 kundan keyin hard-delete |
| **Row history** (support'uchun) | 30 kun | `row_history` jadvalidagi qo'shni 30 kundan keyin tozalash |
| **Export URL's** | 24 soat | MinIO/S3 URL faqat 24 soat; keyin o'chirish |
| **Notification log's** (kunlik agregat) | 30 kun | Local notification event'lar 30 kundan keyin o'chirish |

---

## Server ustun shifrlash (AES-256-GCM)

Quyidagi maydonlar `EncryptedText` TypeDecorator bilan shifrlangan:

```python
mood_logs.note
health_logs.note
sleep_logs.note
family_logs.note
ai_messages.content
ai_memory.text
```

- **Kalii:** `FIELD_ENC_KEY` (versiya raqami bilan; kalii rotatsiyasi standart)
- **IV:** Har yozuvda random
- **Auth tag:** GCM (16 bayt)
- **Saqlash formati:** `v<versiya>:<base64url(nonce ‖ ciphertext ‖ tag)>`, nonce 12 bayt; versiya GCM associated data sifatida ham tekshiriladi (boshqa versiyaga "qayta yorliqlash" ishlamaydi)
- **Kalit formati:** 32 tasodifiy baytning base64 ko'rinishi; `FIELD_ENC_KEY_VERSION` (default 1) har shifrmatnga yoziladi
- **Dev/test:** `ENV=dev` da placeholder yoki bo'sh kalit bo'lsa ochiq, deterministik dev kaliti ishlatiladi (faqat dev/test uchun). **staging/prod** da placeholder yoki bo'sh kalit bilan server ishga tushmaydi — ochiq matnga jimgina qaytish yo'q
- **`row_history`:** `before`/`after` JSON ichidagi shu maydonlar ham shifrlangan holda yoziladi
- **`sync_batches.response`:** idempotentlik keshidagi `server_row` ichida ham shifrlangan; replay'da ochiladi (7 kun)
- **Loglar:** rad etilgan / muvaffaqiyatsiz sync change uchun faqat entity, row id, maydon nomlari va xato kodlari — qiymatlar, exception matni, SQL parametrlari loglanmaydi; 422 javobi yuborilgan `input` ni qaytarmaydi
- **Implementatsiya:** `apps/api/app/db/types.py` (`EncryptedText`)

---

## Minimal DW ma'lumot filosofiyasi (Bosqich 4, 11)

- **Sarlavha:** Faqat kunlik kategoriya daqiqalari + event'lar (warn/snooze/extend).
- **Soatdan nozik timestamp:** Yo'q; server'da faqat kun granularity (privacy).
- **App nomlari:** Hesh qilingan; ishlatuvchi ruxsatisiz server'ga jo'natilmaydi.
- **Foydalanuvchi harakati:** Server'da tahliliy faqat agregat (ochiladigan); individual session yo'q.

---

## Privacy consent (Bosqich 1)

Onboarding'da 4-qadam alohida consent'lar:

1. **Analytics** (PostHog)
2. **AI personalization** (memory)
3. **DW cloud stats** (dw_daily upload)
4. **Privacy policy** + maxfiylik ehtiyoji

Foydalanuvchi rad etsa → ayni ma'lumot saqlanib turadi, serverga o'tmaydi.

---

## Compliance cheklist

- [ ] GDPR: Export + delete ishlaydi
- [ ] CCPA: Foydalanuvchi ma'lumoti export qilinadi
- [ ] iOS App Privacy: Privacy label qiymat bilan to'ldirilgan
- [ ] Android: Data Safety Form to'ldirilgan
- [ ] Audit log: 1 yil saqlanadi
