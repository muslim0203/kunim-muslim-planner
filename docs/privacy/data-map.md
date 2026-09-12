# Ma'lumot xaritasi — Qurilma va server saqlash

Bu hujjat qaysi ma'lumot qayerda saqlanadi va xavfsizlik qarorlari bo'yicha tashkil etilgan.

## Sinxronizatsiya qoidalari (Bosqich 2, 3)

| Ma'lumot turi | Qurilmada | Serverda | Shifrlangan | Saqlash muddati |
|---|---|---|---|---|
| **Foydalanuvchi profili** | SQLite (offline) | PostgreSQL (sync) | Profil foto API orqali | To'liq avtorizatsiya |
| **Vazifalar** (tasks) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Kategoriyalar** (task_categories) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Kalendar event'lar** | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Odatlar** (habits) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Odat qaydlari** (habit_logs) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Maqsadlar** (goals) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Milestones** (milestones) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Namoz qaydlari** (prayer_logs) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Qur'on o'qish holati** (quran_progress) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Qur'on bookmark'lari** (quran_bookmarks) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Ruhiy holat qaydlari** (mood_logs) | Drift/SQLite | Sync | **AES-256-GCM** (note maydon) | Foydalanuvchi o'chguncha |
| **Uyqu ma'lumot** (sleep_logs) | Drift/SQLite | Sync | **AES-256-GCM** (note maydon) | Foydalanuvchi o'chguncha |
| **Sog'liq ma'lumot** (health_logs) | Drift/SQLite | Sync | **AES-256-GCM** (note maydon) | Foydalanuvchi o'chguncha |
| **Ta'lim element'lar** (education_items) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Kitoblar** (books) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **Sozlamalar** (preferences) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |
| **App limit'lari** (app_limits) | Drift/SQLite | Sync | Yo'q | Foydalanuvchi o'chguncha |

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
ai_messages.content
ai_memory.text
```

- **Kalii:** `FIELD_ENC_KEY` (versiya raqami bilan; kalii rotatsiyasi standart)
- **IV:** Har yozuvda random
- **Auth tag:** GCM

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
