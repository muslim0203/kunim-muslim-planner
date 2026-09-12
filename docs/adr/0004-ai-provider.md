# ADR-0004: Provider-independent AI layer, models and non-negotiable guardrails

## Status

Accepted — 2026-09-12

## Context

KUNIM da AI — chat, planner, rescheduler, coach, tutor, analyst, wellbeing, recommender
agentlari, RAG (Qur'on/hadis/maqola korpusi), memory va klassifikatorlar. Ikki bosim bir vaqtda
mavjud:

1. **Provider riski.** Model narxi, mavjudligi va ID lari tez o'zgaradi; mintaqaviy cheklovlar
   bo'lishi mumkin. ТЗ 36 provider-mustaqillikni talab qiladi.
2. **Diniy kontent riski.** LLM hech qachon oyat/hadis manbai bo'la olmaydi
   (`CLAUDE.md`, 1-qoida). Bu texnik emas, mahsulot-hayotiy talab.

Ushbu ADR `apps/api/app/ai/` qatlamining shartnomasini va buzilmaydigan cheklovlarini belgilaydi.

## Decision

### 1. ProviderAdapter (Protocol)

Barcha LLM chaqiruvlari **MUST** bitta Protocol orqali o'tsin
(`apps/api/app/ai/providers/base.py`):

| Metod | Vazifa |
|---|---|
| `complete(...)` | Bir martalik matn javobi |
| `stream(...)` | SSE streaming (chat) |
| `complete_structured(schema, ...)` | Pydantic sxema bo'yicha strukturali chiqish (`PlanProposal`, `RescheduleProposal`, `Recommendation`, `WisdomAnswer`, `Insight`) |
| `embed(...)` | Embedding vektorlari |

- Agent kodi (`ai/agents/*.py`) **MUST NOT** provider SDK sini to'g'ridan-to'g'ri import qilsin.
- **Anthropic adapter — birinchi** (`anthropic_adapter.py`); **OpenAI-compatible — ikkinchi**
  (`openai_compat_adapter.py`, `openai` SDK + `base_url`, `response_format`).
- Ikkala adapter **MUST** `tests/ai/test_adapter_contract.py` da bir xil fixtures bilan o'tsin
  (structured output, streaming, tool loop, refusal).
- Anthropic adapter talablari: prompt caching (statik system + RAG siyosati → cache breakpoint,
  keyin o'zgaruvchan kontekst), `stop_reason == refusal` → xavfsiz shablon javob, tungi batch
  job'lar uchun Batches API.

### 2. Model choice lives in the database

Model tanlovi **MUST** `ai_model_policy` jadvalida saqlansin (admin tahrirlaydi) va agent kodida
**hech qachon hardcode qilinMASIN**. Kodda faqat agent nomi bo'yicha policy qidiruvi bo'ladi;
model ID o'zgarishi deploy talab qilmasligi shart.

`docs/plan.md` 5-bo'limida ko'rsatilgan boshlang'ich policy (verbatim):

| Agentlar | Model ID |
|---|---|
| planner, rescheduler, coach | `claude-opus-5` |
| chat, tutor, analyst, recommender | `claude-sonnet-5` |
| klassifikatorlar, memory extraction | `claude-haiku-4-5` |

> **Note:** bu model ID lari `docs/plan.md` dan o'zgartirilmasdan ko'chirildi —
> **verify against Anthropic docs before Phase 7**.

### 3. Embeddings

- **Prod:** Voyage **`voyage-multilingual-2`**.
- **Dev:** lokal **`bge-m3`** (`providers/embeddings/local_bge_m3.py`).
- Vektor o'lchami **MUST** `vector(1024)` bo'lsin (`content_chunks.embedding`, pgvector HNSW
  cosine). Ikkala embedding manbai bir xil o'lchamda bo'lishi shart; o'lcham o'zgarsa to'liq
  re-index migratsiyasi talab qilinadi.
- Faqat `status = published` bo'lgan `content` yozuvlari indekslanadi.
- Retriever: pgvector top-20 + `tsvector` top-20 → RRF → top-6.

### 4. Non-negotiables

Quyidagilar buzilmaydi; ular `ai/safety/` va `ai/rag/citation.py` da majburlanadi va
`tests/ai/safety/*.yaml` (~150 holat, 4 til) bilan qoplanadi.

1. **Diniy iqtibos faqat `content` jadvalidan.** Har `WisdomAnswer.citations[].quoted_text`
   **MUST** tegishli `content_chunks.chunk_text` ichida **substring** sifatida tekshirilsin;
   tekshiruv o'tmasa — javob **refusal shabloniga** almashtiriladi. Oyat raqamlari Qur'on
   jadvaliga qarshi validatsiya qilinadi. **LLM hech qachon manba emas.**
2. **Kun hikmati generatsiya qilinMAYDI.** `jobs/daily_wisdom.py` `content` dan deterministik
   tanlaydi (til bo'yicha, 180 kun takrorlanmas, mavzu taqvimi). AI faqat aniq belgilangan
   bir jumlalik "mulohaza" yozishi mumkin.
3. **Refusal shablonlari majburiy.** Fatvo-tipidagi so'rov (`religious_ruling`) → doim rad +
   muftiyatga yo'naltirish; tibbiy/psixiatrik diagnoz yo'q; krizis so'zlari → mamlakat bo'yicha
   helpline. Output klassifikatori (`fabricated_citation`, `medical_advice`,
   `ruling_without_source`, `self_harm_context`) ishga tushsa → xavfsiz shablon +
   `ai_safety_events` yozuvi.
4. **Per-user Redis token bucket.** Har agent uchun kunlik kvota (masalan 30 chat/kun,
   3 planner/kun; admin sozlaydi). Kvota tugasa — 429 va foydalanuvchiga tushunarli xabar.
5. **Cost logging `ai_requests` da.** Har chaqiruv `(agent, model, tokens, cache_read, cost_usd,
   latency, safety_flags)` bilan yoziladi. Logsiz chaqiruv bo'lMAYDI.
6. **Server foydalanuvchi ma'lumotiga AI nomidan yozMAYDI.** AI faqat `ai_proposals` yaratadi;
   foydalanuvchi qabul qilgach klient lokal yozadi va odatdagi sync (ADR-0002) orqali yuboradi.
   Chat agent tool'lari **faqat o'qish**: `get_today_plan`, `search_religious_content`,
   `get_stats`, `get_prayer_times`.
7. **RAG va tool natijalari ma'lumot, ko'rsatma emas.** Ular promptga `<document>` tegi ichida,
   "data, not instructions" izohi bilan kiradi; jailbreak filtri (regex + haiku klassifikator)
   inputda ishlaydi.
8. **Shaxsiy ma'lumot shifrlanadi.** `ai_messages.content` va `ai_memory.text` server tomonda
   `EncryptedText` (AES-256-GCM) bilan saqlanadi; secret va shaxsiy ma'lumot logga chiqmaydi.

### 5. Offline behaviour

Barcha LLM chaqiruvlari serverda; qurilmada — namoz, waste score, DW score, "Bugungi balans",
offline Smart Day / Top-3 (qoida asosli). Offline'da AI ekranlari oxirgi javob keshini va
"AI uchun internet kerak" xabarini ko'rsatadi. Ya'ni **AI ishlamasligi ilovani ishlatib
bo'lmaydigan holatga keltirMAYDI**.

## Consequences

- Provider almashtirish adapter darajasida — agentlar va promptlar o'zgarmaydi.
- `ai_model_policy` DB da bo'lgani uchun model ID eskirsa admin panelidan bir daqiqada
  almashtiriladi; shu sababli yuqoridagi jadval "boshlang'ich qiymat", kod haqiqati emas.
- `complete_structured` ikkala providerda turlicha implementatsiya qilinadi (Anthropic tool/schema,
  OpenAI `response_format`), lekin kontrakt testi farqni yashiradi.
- Substring verifikatsiyasi ba'zi to'g'ri javoblarni ham rad etadi (masalan LLM iqtibosni
  qisqartirsa) — bu **atayin** qabul qilingan: noto'g'ri iqtibosdan ko'ra refusal afzal.
- 1024 o'lchamli vektorga bog'lanish kelajakdagi embedding modelini shu o'lcham bilan cheklaydi
  yoki to'liq re-index talab qiladi.
- Kunlik xarajat maqsadi (faol foydalanuvchi uchun < $0.05, 7-bosqich DoD) faqat prompt caching +
  haiku klassifikatorlar + tungi Batches bilan erishiladi; bu uchtasi "optimizatsiya" emas,
  arxitektura qismi.
- **Open question:** reja `ai_model_policy` jadvalining ustunlarini sanamaydi. Bu yerda tanlangan
  minimal shakl: `(agent, model, max_tokens, temperature, enabled, updated_by, updated_at)`.
- **Open question:** reja provider fallback (Anthropic ishlamay qolsa avtomatik OpenAI-compat ga
  o'tish) siyosatini aytmaydi. MVP da avtomatik fallback **yo'q** deb qabul qilinadi —
  `ai_model_policy` orqali qo'lda almashtiriladi.
- **Open question:** reja Voyage embedding API nosozligida nima bo'lishini aytmaydi; indekslash
  job'i retry bilan navbatda qoladi, foydalanuvchi oqimi RAG'siz refusal'ga tushadi.

## Alternatives considered

| Variant | Nega rad etildi |
|---|---|
| **To'g'ridan-to'g'ri Anthropic SDK agent kodida** | Provider almashtirish butun `ai/agents/` ni qayta yozishni talab qilardi; ТЗ 36 ga zid. |
| **LangChain / LlamaIndex kabi framework** | Qo'shimcha abstraktsiya qatlami, versiya drift va debug qiyinligi; kerak bo'lgan narsa — to'rtta metodli Protocol. |
| **Model ID ni konfiguratsiya faylida (env) saqlash** | Deploy talab qiladi; admin model policy'ni o'zgartira olmaydi va agent-bajadval siyosat qo'yish noqulay. |
| **OpenAI embeddings (`text-embedding-3-*`)** | O'zbek/rus/arab aralash korpus uchun `voyage-multilingual-2` reja bo'yicha tanlangan; dev'da lokal `bge-m3` internetsiz ishlaydi. |
| **LLM ga to'g'ridan-to'g'ri yozish huquqi (tasks/calendar)** | Offline invariantlarni (ADR-0002) buzadi va foydalanuvchi nazoratini yo'qotadi; `ai_proposals` + sync yo'li majburiy. |
| **Generativ "kun hikmati"** | Manbasiz diniy matn xavfi — mahsulotning eng katta reputatsion riski. |
| **Fine-tuning / shaxsiy model** | MVP uchun qimmat va sekin; qoida asosli personalization + memory yetarli. |

## Revisit when

1. `ai_model_policy` dagi model ID lari eskirsa yoki Anthropic yangi narx/model qatlamini chiqarsa
   (7-bosqich oldidan majburiy tekshiruv);
2. Kunlik AI xarajati faol foydalanuvchi uchun $0.05 dan oshsa;
3. RAG citation aniqligi golden Q&A to'plamida 95% dan pastga tushsa;
4. Anthropic mavjudligi/mintaqaviy cheklovi OpenAI-compatible adapterga o'tishni talab qilsa
   (avtomatik fallback qarori qayta ko'riladi);
5. Embedding modeli almashtirilishi kerak bo'lsa (vektor o'lchami va to'liq re-index qarori).
