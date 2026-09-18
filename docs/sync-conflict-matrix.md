# Sinxronizatsiya konflikt matritsasi

Bu fayl ADR-0002 (Offline-first sync protokoli va konflikt qoidalari) dan olingan normallashtirilgan qoida o'rniga o'tkazuvchi. Fayl ADR-0002 o'zgarganda yangilanadi. **Istisna yoxdilari yoki aniqliksizliklar uchun manbani ADR-0002 da tekshiring.**

---

## Konflikt qoidalari jadvali

Har bir qator ADR-0002 ning "Konflikt matritsasi (normativ)" bo'limidagi qoidani ifodalaydi Raqamlash — ADR ning o'z raqamlanishi (1–25). Ikkita qoida birlashtirilmagan, hech bir qoida bo'laklarga bo'linmagan.

| # | Entity / maydon | Vaziyat | Kutilgan natija |
|---|---|---|---|
| 1 | Barcha sync jadvallari (default) | Kelayotgan `updated_at` > mavjud | `applied` — klient holati qabul qilinadi |
| 2 | Barcha sync jadvallari (default) | Kelayotgan `updated_at` < mavjud | `conflict` — server holati qaytariladi `server_row` ichida |
| 3 | Barcha sync jadvallari (default) | Teng `updated_at`, payload aynan bir xil | `applied` — no-op |
| 4 | Barcha sync jadvallari (default) | Teng `updated_at`, payload farqli | `conflict` — serverda saqlangan holat g'olib (deterministic tie-break) |
| 5 | Soft delete (barcha jadvallardagi `deleted_at`) | Merge natijasida `deleted_at > updated_at` | `applied` yoki `conflict` — o'chirish g'olib, LWW dan qat'i nazar. Tiriltirish faqat `updated_at > deleted_at` bo'lgan keyingi `upsert` bilan |
| 6 | Har qanday qator | `updated_at > server_time + 24h` | `rejected`, `reason: "updated_at_in_future"` |
| 7 | Har qanday qator | `created_at > updated_at` | `applied` — server `created_at = min(mavjud, kelayotgan)` qilib normallashtiradi, rad etmaydi |
| 8 | `tasks.completed_at` | Natural kalit yoxdiligi, max-wins strategiyasi | `applied` yoki `conflict` — `completed_at` max-wins (`NULL` eng kichik); Sync hech qachon vazifani bajarilmagan holatga qaytarmaydi. `completed` bayrog'i sinxronlanmaydi — `completed_at IS NOT NULL` dan hosil qilinadi. Qolgan maydonlar LWW |
| 9 | `habit_logs` | Natural kalit `(user_id, habit_id, date)`. Additiv maydonlar `count`, `value` | `conflict` — `count` va `value` max-wins; `note` LWW |
| 26 | `daily_scores` | Natural kalit `(user_id, date)`. `points`, `done`, `planned` | `conflict` — barchasi max-wins; ball qurilmada hisoblanadi, server qo'shadi |
| 10 | `prayer_logs` | Natural kalit `(user_id, prayer_key, date)`. Tartiblangan enum `status` | `conflict` — `status` tartiblangan enum max-wins: `none(0) < qaza(1) < alone(2) < jamaah(3)`; `note` LWW |
| 11 | `mood_logs` | Natural kalit `(user_id, coalesce(ref_id,''), date)`. Set merge `tags` | `conflict` — `score` LWW, `note` LWW, `tags` ikki to'plamning birlashmasi, ko'pi bilan 32 element. Limitdan oshsa qaysilari qolishi: g'olib elementlari o'z tartibida, keyin yutqazganning qolganlari saralangan tartibda, so'ng 32 tagacha kesiladi; qolganlar saralangan holda qaytadi (limit ichida — oddiy saralangan birlashma) |
| 12 | `sleep_logs` | Natural kalit `(user_id, coalesce(ref_id,''), date)`. Pair merge `bed_time`/`wake_time` | `conflict` — `bed_time` va `wake_time` LWW juftlik sifatida (ikkalasi bitta yutuvchidan); `duration_min` hosil qiluvchi, max-wins **emas**; `quality` LWW, `note` LWW |
| 13 | `health_logs` | Natural kalit `(user_id, coalesce(ref_id,''), date)`. Additiv maydonlar | `conflict` — Additiv: `water_ml`, `steps`, `workout_min`, `calories` max-wins. Additiv emas: `weight_kg` LWW, `note` LWW |
| 14 | `habit_logs`, `prayer_logs`, `mood_logs`, `sleep_logs`, `health_logs`, `family_logs` (NK to'qnashuvi) | Ikki qurilma bir xil natural kalit uchun turli `id` yaratsa | `conflict` — `created_at` kichikrog'i omon qoladi (teng bo'lsa leksikografik kichik `id`). Maydonlar 9–13 va 25 bo'yicha birlashtiriladi. Yutqazgan `id` tombstone qilinadi va payload'iga `{"merged_into": "<omon qolgan id>"}` qo'shiladi. Klient ikkala qatorni ham qabul qiladi va `merged_into` tombstone'ini UI da ko'rsatmaydi |
| 15 | `quran_progress` | Bitta qator foydalanuvchi uchun (NK `(user_id)`). `last_ayah_key` | `conflict` — `last_ayah_key` LWW |
| 16 | `quran_progress.pages_read_total`, `ayahs_read_total`, `khatm_count` | Additiv maydonlar umumiy hisob | `conflict` — max-wins (umumiy hisob kamaymaydi) |
| 17 | `quran_bookmarks` | LWW + soft delete | `applied` yoki `conflict` — Qoidalar #1–5 qo'llaniladi |
| 18 | `goals`, `milestones` | LWW merge, `progress_percent` | `applied` yoki `conflict` — LWW; `progress_percent` max-wins **emas** (maqsad orqaga ham qaytishi mumkin) |
| 19 | `preferences` | Bitta qator foydalanuvchi uchun. Butun qator merge | `applied` yoki `conflict` — Butun qator LWW (maydonli merge yo'q) |
| 20 | `task_categories`, `calendar_events`, `habits`, `education_items`, `books`, `app_limits` | LWW + soft delete | `applied` yoki `conflict` — Qoidalar #1–5 qo'llaniladi |
| 21 | `dw_daily`, `dw_score` | Upload-only. NK `(user_id, date, app_key)` / `(user_id, date)`. Additiv maydonlar | `applied` — NK va `minutes`, `sessions`, `waste_minutes_est`, `score` max-wins. Pull bu qatorlarni hech qachon qaytarmaydi |
| 22 | `dw_events` | Upload-only, append-only. Idempotent by `id` | `applied` — Hech qachon `conflict` bermaydi |
| 23 | Noma'lum `entity` yoki JWT `user_id` ga mos kelmagan qator | Pull yoki push uchun ruxsatsiz ma'lumot | `rejected` (`unknown_entity` / `foreign_user`) — Klient yozuvni outbox'dan olib tashlaydi va loglaydi |
| 24 | `content` (hikmatlar), Qur'on matni (bundled), namoz preset'lari | Push qilinsa (pull-only kesh) | `rejected` (`readonly_entity`) — Klient yozuvni outbox'dan olib tashlaydi |
| 25 | `family_logs` | Natural kalit `(user_id, coalesce(ref_id,''), date)`. Additiv `minutes`, set merge `activities` | `conflict` — `minutes` max-wins, `activities` ikki to'plamning birlashmasi (ko'pi bilan 32, #11 dagi kesish qoidasi), `note` LWW. NK to'qnashuvi #14 bo'yicha |

---

## `rejected` sabablari (yopiq enum)

| Sabab (kod) | Qachon yuzaga keladi | Klient nima qilishi kerak |
|---|---|---|
| `updated_at_in_future` | `updated_at > server_time + 24 soat` | Qatorni `updated_at = now()` bilan qayta muhrlaydi, `attempts++`, outbox'ga qaytadan qo'yadi |
| `schema_invalid` | Payload sxemaga mos emas | Outbox'da `last_error` bilan qoldiradi, diagnostikaga chiqaradi, qayta yubormaydi |
| `unknown_entity` | `entity` `SYNC_ENTITIES` da yo'q | Outbox yozuvini o'chiradi (eski klient qoldig'i), loglaydi |
| `readonly_entity` | Entity faqat-onlayn yoki pull-only (`content`, Qur'on, preset) | Outbox yozuvini o'chiradi; bu klient bug'i → Sentry |
| `foreign_user` | `payload.user_id` JWT subjektiga mos emas | Outbox yozuvini o'chiradi, sessiyani qayta tekshiradi |
| `payload_too_large` | Bitta `payload` > 64 KB | Diagnostikaga chiqaradi |

---

## Jadval tasnifi

**Kataloq:**

| Offline (ikki tomonlama sync) | Upload-only | Pull-only | Faqat onlayn | Faqat lokal |
|---|---|---|---|---|
| `tasks` | `dw_daily` | `content` (hikmatlar) | `auth`, `refresh_tokens` | xom `dw_sessions` |
| `task_categories` | `dw_events` | Qur'on matni | avatar yuklash | `usage_sessions_raw` |
| `calendar_events` | `dw_score` | namoz preset'lari | AI chat / planner / reschedule / recommendations / memory (`ai_proposals`, `ai_messages`, `ai_memory`) | `scrolling_events` |
| `habits` | | | server statistikasi | xom `notification_events` |
| `habit_logs` | | | `/admin` | AI javob keshi |
| `goals` | | | | |
| `milestones` | | | | |
| `prayer_logs` | | | | |
| `quran_progress` | | | | |
| `quran_bookmarks` | | | | |
| `mood_logs` | | | | |
| `sleep_logs` | | | | |
| `health_logs` | | | | |
| `family_logs` | | | | |
| `education_items` | | | | |
| `books` | | | | |
| `preferences` | | | | |
| `app_limits` | | | | |

**Qoidalar:**
- `SYNC_ENTITIES` — serverdagi yagona manba (`app/modules/sync/registry.py`). Ro'yxatda yo'q entity → `rejected` / `unknown_entity`.
- Upload-only entity pull javobida umuman chiqmaydi; pull-only entity'ga push → `rejected` / `readonly_entity`.
- Qurilmalar aro ephemer holat (UI state) sync qilinmaydi.

---

## Saqlash muddatlari va tiklash strategiyasi

### Tombstone va tiklash oynasi
- **Tombstone: 90 kun** (`jobs/cleanup.py` tomonidan tozalanadi).
- O'sha paytdagi eng katta `server_version` `sync_user_state.purged_up_to_version` ga yoziladi.
- Agar kursor `cursor < purged_up_to_version` bo'lsa, server javobda **`full_resync_required: true`** qaytaradi va `rows` bo'sh bo'ladi.

### To'liq resync (full_resync_required: true)

Klient majburiy to'liq resync qiladi:
1. `sync_outbox` **saqlanadi** (yuborilmagan lokal o'zgarishlar yo'qolmaydi).
2. Sync jadvallaridagi `dirty = 0` qatorlar o'chiriladi (`dirty = 1` qatorlar qoladi — ular hali serverga yetmagan).
3. `cursor = 0` qilinadi.
4. To'liq pull bajariladi.
5. Pull tugagach outbox odatdagidek push qilinadi.

**Qisman tiklash taqiqlanadi** — u ma'lumot yo'qotishga olib keladi.

### Tarixiy ma'lumotlar va support tiklashi
- **`row_history`: 30 kun.** Har qabul qilingan o'zgarishning oldingi va yangi holati saqlanadi (`row_history` jadvalida). Faqat support orqali qo'lda tiklash uchun; klient endpoint'i uni o'qimaydi, MVP da avtomatik rollback yo'q. Kirish `/admin` orqali va `audit_logs` bilan yozib boriladi. `EncryptedText` ustunlari bu yerda ham shifrlangan saqlanadi.
- **Idempotentlik: `sync_batches`: 7 kun.** Bir xil `batch_id` + bir xil request → saqlangan javob qaytariladi. `server_row` ichidagi `EncryptedText` ustunlari keshda shifrlangan saqlanadi va replay'da ochiladi (javob asl javob bilan bir xil). Saqlash muddati 7 kun; undan eski qaytadan kelsa yangi batch sifatida qabul qilinadi.

---

## Test nomlash konventsiyasi (ADR-0002 orqali)

**Talab:** `apps/api/tests/sync/test_merge_matrix.py` yuqoridagi har bir qator uchun kamida bitta test saqlaydi. Test nomi qator raqamini o'z ichiga oladi:

```
test_rule_NN_<qisqa_tavsif>
```

Masalan, qoida #9 (`habit_logs` natural key) uchun:
```
test_rule_09_habit_logs_natural_key_max_wins
```

`merge.py` dagi har bir qoida kod izohida mos qator raqamini ko'rsatadi. 

**Flutter** (`apps/mobile/test/sync/`): ikki in-memory Drift baza + test API bilan uchidan-uchiga ssenariylarni tekshiradi (2-bosqich DoD).

**Manba:** ADR-0002, "Test majburiyati" bo'limi.

---

## Izoh

- **25 qoida**, raqamlangan 1–25 (ADR orikinal raqamlanishi; 25-qator `family_logs` uchun 2026-09-14 da qo'shilgan, 1–24 o'zgarmagan).
- Barcha raqam va maydon nomlari ADR-0002 dan verbatim olingan.
- `(user_id, server_version)` unikal va pull `ORDER BY server_version ASC`.
- Butun tranzaksiya ichida har change alohida SAVEPOINT; bitta `rejected` boshqalarni bekor qilmaydi.
- Klient merge mantiqi **yoxdiligi** — faqat server javobini qo'llaydi.
