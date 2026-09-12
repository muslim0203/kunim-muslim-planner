# Diniy kontent verifikatsiya jarayoni

Qur'on oyatlari, ahadis, va islomiy iqtiboslar `content` jadvalidagi tasdiqlangan yozuvlardan keladi. AI hech qachon manba sifatida ishlatilmaydi.

## Status oqimi

Barcha kontent uchun majburiy workflow:

```
draft → review → approved → published → archived
```

### Status qoidalari

- **`draft`**: Import qilinganda yoki yangi kontent qo'shilganda boshlang'ich holat.
- **`review`**: Kontent review uchun tayyor. Malakali reviewer tayin qilinadi.
- **`approved`**: Reviewer tasdiqladi. **Qat'iy qoida: `verified_by ≠ author`** — faqat boshqa shaxs tasdiqlaydi.
- **`published`**: Admin nashr qiladi. **Qat'iy qoida: `published` statusiga chiqish uchun litsenziyali manba shart.** Embedding job ishga tushiriladi.
- **`archived`**: Eskirgan yoki bekorqilgan kontent.
- **`edited`**: Tahrir (o'zgartirilgan `text_*` yoki `grade`) → avtomatik `review` qaytadi.

### Har o'tishning auditi

Har status o'tishi `audit_logs` ga yoziladi (actor, action, entity, before, after, ip, ua, request_id).

## Kontent sxemasi

```sql
content_sources(
  type TEXT,
  title TEXT,
  author TEXT,
  translator TEXT,
  edition TEXT,
  license TEXT,              -- Qat'iy: `published` uchun shartli
  verified_by UUID,
  verified_at TIMESTAMP
)

content(
  id UUID PRIMARY KEY,
  source_id UUID FOREIGN KEY,
  kind TEXT,                 -- ayah | hadith | quote | article
  ref TEXT,                  -- "2:255" yoki "Bukhari 6018"
  text_ar TEXT,              -- Arab
  text_by_lang JSONB,        -- {'uz': '...', 'ru': '...', 'en': '...'}
  grade TEXT,                -- oyat/hadith baholash (saheeh/daif/mawdu)
  topic_tags TEXT[],
  status TEXT,               -- draft|review|approved|published|archived
  checksum TEXT,             -- Oylik re-hash; integrity tekshiruv
  created_at TIMESTAMP,
  updated_at TIMESTAMP
)

content_chunks(
  id UUID PRIMARY KEY,
  content_id UUID FOREIGN KEY,
  lang TEXT,
  chunk_text TEXT,
  embedding VECTOR(1024),    -- pgvector; HNSW cosine
  metadata JSONB
)
```

## Qur'on ma'lumotlari

**Arab matni:** Tanzil Uthmani, CC BY-ND 3.0 (o'zgartirilmaydi; About'da attribution talab).

**Tarjimalar:**
- **O'zbek:** Alauddin Mansur — **litsenziya tekshiriladi** (UNRESOLVED)
- **Kirill (uz-Cyrl):** Faqat litsenziya ruxsat bersa; aks holda Latin variant
- **Rus:** Kuliev / Abu Adel
- **Ingliz:** Saheeh International

Har tarjima `content_sources` da litsenziya matni bilan qo'shiladi. Litsenziyasiz hech narsa chiqmaydi.

**Tafsir:** Qur'on tafsiri o'zbek tilida litsenziyasi bottleneck — 2-bosqich kontenti. Sxema tayyor, lekin reliz oldidan litsenziya ruxsati kerak.

## RAG va iqtibos verifikatsiya

### Retrieval

1. Foydalanuvchi savolini embed qilish (`voyage-multilingual-2`).
2. `content_chunks` da pgvector top-20 + tsvector top-20 yuklanadi.
3. RRF (Reciprocal Rank Fusion) → top-6 best matchlar.
4. Faqat `published` status'li kontent indekslanadi.

### Citation strukturasi

```
WisdomAnswer{
  answer: str,
  citations: [
    {
      content_id: UUID,
      ref: "2:255" yoki "Bukhari 6018",
      source_title: "Tanzil Qur'on" yoki "Riyozus-solihin",
      quoted_text: str
    },
    ...
  ],
  refused: bool
}
```

### Substring tekshiruv — MAJBURIY

Har `cited_text` quyidagini qondirishi kerak:

1. `content` jadvalidagi `text_by_lang[user_lang]` ichida substring ekanini tekshir.
2. Agar `quoted_text` chunk ichida topilmasa, **refusal bulon; "Manba topilmadi"**.
3. Ayah raqamlari Qur'on jadvaliga (`quran_progress`, sura/ayah bounds) qarshi validatsiya qilinadi.

AI hech qachon oyat raqamini o'ylab topmasligi kerak.

## AI Hech qachon manba emas

### Qat'iy qoidalar

- AI aslo hadis yoki oyat generatsiya qilmaydi.
- AI aslo "My interpretation is..." sifatida hukm bermasligi kerak.
- Har islomiy iqtibos faqat `published` `content` satridan.
- Agar AI `quoted_text` substring validatsiyasi muvaffaq bo'lmasa, refusal + standard teksti ("Manba tekshirildi; aniq iqtibos topilmadi").

### Kun hikmati

`jobs/daily_wisdom.py`: AI generatsiya qilmasligi; `content` dan **deterministik tanlash** (til bo'yicha, 180 kun takrorlanmas, Ramazon kabi mavzu taqvimi). AI faqat **bir jumlalik "mulohaza"** yozishi mumkin, aniq belgilangan prompt bilan (ТЗ 36).

## Kontent import va tekshiruv

1. Import CLI (`packages/content_tools/`) Qur'on + hadis to'plamlarini `draft` holat'iga kiritadi.
2. Malakali reviewer (content_editor/admin role):
   - Manba haqiqiyligini tekshir
   - Matn butunligini tasdiqla
   - Tarjima to'g'riligini tekshir
   - Grade/daraja (saheeh/daif) belgila
   - `verified_by` va `verified_at` ni to'ldirish
   - Statusini `approved` ga o'tgaz
3. Admin publish qiladi (`published` → embedding job)
4. Monthly checksum skripti: barcha `published` qatorlar har oylik re-hash qilinadi (integrity tekshiruvi).
5. Tahrir (`text_*` o'zgarishi) → avtomatik `review` qaytadi (malakali reviewer qayta tekshiradi).

## Litsenziya va attribution

| Manba | Litsenziya | Attribution | Holati |
|---|---|---|---|
| Tanzil Qur'on (Arab) | CC BY-ND 3.0 | "Tanzil.net" About'da | Qabul qilingan |
| QuranEnc (uz tarjima) | ? | Alauddin Mansur | UNRESOLVED — tekshirish talab |
| QuranEnc (ru tarjima) | ? | Kuliev/Abu Adel | UNRESOLVED — tekshirish talab |
| Saheeh International (en) | ? | Saheeh International | UNRESOLVED — tekshirish talab |

Litsenziya aniq bo'lmagan tarjimalar shu qadar kont'ent sifatida qo'shilmaydi. Relizdan oldin huquqiy aloqa qilish shart.
