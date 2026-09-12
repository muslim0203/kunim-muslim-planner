# Bugungi balans, DW Score va "bekorchi skrolling" formulalari

Manba: `docs/plan.md` — 4-bo'lim ("Umumiy model va formulalar") va 8-bo'lim ("Statistika").
Implementatsiya: `apps/mobile/lib/features/statistics/domain/balance.dart`,
`apps/mobile/lib/features/wellbeing/domain/waste_scorer.dart`.
Server oylik varianti shu faylga mos bo'lishi shart.

---

## 1. Bugungi balans — 7 yo'nalish

| # | Yo'nalish | Manba modullar |
|---|---|---|
| 1 | Ma'naviyat | namoz, Qur'on, kun hikmati |
| 2 | Sog'liq | sport, suv, qadam, `health_logs` |
| 3 | Ish | ish vazifalari, fokus bloklari |
| 4 | Ta'lim | `education_items`, kurslar |
| 5 | Oila | oila kategoriyasidagi vazifa/voqealar |
| 6 | Dam olish | dam olish bloklari, kitob |
| 7 | Raqamli | Digital Wellbeing (DW Score) |

> **TODO: rejada aniqlanmagan.** Reja 7 yo'nalishni sanaydi va spetsifikatsiya shu faylda
> bo'lishini aytadi, lekin har yo'nalishning ball formulasi va o'zaro og'irliklari berilmagan.
> 5-bosqich boshlanishidan oldin hal qilinadi va shu yerga yoziladi. Talab: bir xil ma'lumotda
> online va offline hisob bir xil natija berishi (golden test).

---

## 2. "Bekorchi skrolling" ehtimoli (waste score)

Har sessiya uchun:

```
p = sigmoid( w_cat·cat + w_dur·f(dur) + w_night·night
           + w_reopen·reopen + w_focus·in_focus_block + w_self·self_report )
```

Og'irliklar (`w_*`) remote-config JSON da saqlanadi — kodga qattiq yozilmaydi.

**Kategoriya koeffitsienti `cat`:**

| Kategoriya | Qiymat |
|---|---|
| `social_shortform` | 1.0 |
| `video` | 0.8 |
| `social` | 0.7 |
| `games` | 0.6 |
| `news` | 0.4 |
| `messaging` | 0.2 |
| `productivity`, `education`, `quran` | 0 |

**Davomiylik `f(dur)`:**

| Sessiya davomiyligi | Qiymat |
|---|---|
| < 3 daqiqa | 0 |
| 3–10 daqiqa | 0.5 |
| 10–30 daqiqa | 1.0 |
| > 30 daqiqa | 1.2 |

**Boshqa signallar:**
- `night` — sessiya 23:00–05:00 oralig'ida.
- `reopen` — ilova yopilgandan keyin 5 daqiqa ichida qayta ochilgan.
- `in_focus_block` — rejalashtirilgan fokus bloki vaqtida.
- `self_report` — foydalanuvchining "Bu vaqt foydali bo'ldimi?" javobi.

**Yig'indi:**
```
waste_min = Σ dur · p     (faqat p > 0.5 bo'lgan sessiyalar)
```

**Qat'iy istisno:** ta'lim, kitob, Qur'on va ish hech qachon bekorchi deb hisoblanmaydi.

ML asosidagi scorer — 2-bosqich (self-report ma'lumotidan o'rgatiladi). MVP da faqat shu qoida.

---

## 3. DW Score

```
DW = 100
   − 30 · clamp(total/target − 1)
   − 30 · clamp(waste / 60)
   − 15 · clamp(night / 30)
   − 15 · clamp(breaches / 3)
   + 10 · (focus_respected / focus_planned)
```

- `total` — kunlik umumiy ekran vaqti, `target` — foydalanuvchi maqsadi.
- `waste` — 2-bo'limdagi `waste_min` (daqiqa).
- `night` — 23:00–05:00 oralig'idagi daqiqalar.
- `breaches` — oshirilgan limitlar soni.
- `focus_respected / focus_planned` — hurmat qilingan fokus bloklari ulushi.
- `clamp(x)` — [0, 1] oralig'iga qisish.

**iOS varianti:** birinchi had (`−30 · clamp(total/target − 1)`) yo'q — `DeviceActivityReport`
raqamlari extension sandbox'idan chiqmagani uchun umumiy ekran vaqti ilovaga ma'lum emas.
Shu sababli iOS'da Score foydalanuvchiga **"taxminiy"** deb belgilab ko'rsatiladi.

---

## 4. "Vaqtingizni qaytaring"

```
baseline        = median(waste, DW yoqilgandan keyingi 14 kun)      # oyiga qayta hisoblanadi
daily_recovered = max(0, baseline − today_waste)
                + warn80 dan keyin 5 daqiqa ichida yopilganda qolgan limit
```

Haftalik va oylik yig'indi ko'rsatiladi; qaytarilgan vaqtni kitob / sport / ta'lim / oila /
dam olishga taqsimlash taklif qilinadi.
