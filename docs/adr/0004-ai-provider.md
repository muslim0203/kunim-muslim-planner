# ADR-0004: Provider-independent AI layer, models and non-negotiable guardrails

**Holat:** Qabul qilingan
**Sana:** 2026-09-12

---

## Kontekst

KUNIM da AI — chat, planner, rescheduler, coach, tutor, analyst, wellbeing, recommender
agentlari, RAG (Qur'on/hadis/maqola korpusi), memory va klassifikatorlar. Ikki bosim bir vaqtda
mavjud:

1. **Provider riski.** Model narxi, mavjudligi va ID lari tez o'zgaradi; mintaqaviy cheklovlar
   bo'lishi mumkin. ТЗ 36 provider-mustaqillikni talab qiladi.
2. **Diniy kontent riski.** LLM hech qachon oyat/hadis manbai bo'la olmaydi (`CLAUDE.md`
   1-qoida). Bu texnik emas, mahsulot-hayotiy talab: bitta o'ylab topilgan hadis mahsulotni
   o'ldiradi.

Ushbu ADR `apps/api/app/ai/` qatlamining shartnomasini va buzilmaydigan cheklovlarini belgilaydi.
Bu yerda gap **KUNIM mahsuloti ish vaqtida chaqiradigan modellar** haqida (ishlab chiqish
vositalari haqida emas).

---

## Qaror

### 1. `ProviderAdapter` (Protocol)

Barcha LLM chaqiruvlari bitta Protocol orqali o'tadi (`apps/api/app/ai/providers/base.py`):

| Metod | Vazifa |
|---|---|
| `complete(...)` | Bir martalik matn javobi |
| `stream(...)` | SSE streaming (chat) |
| `complete_structured(schema, ...)` | Pydantic sxema bo'yicha strukturali chiqish (`PlanProposal`, `RescheduleProposal`, `Recommendation`, `WisdomAnswer`, `Insight`, `CoachMessage`, `WellbeingAdvice`) |
| `embed(...)` | Embedding vektorlari |

- Agent kodi (`ai/agents/*.py`) provider SDK sini **to'g'ridan-to'g'ri import qilmaydi**; faqat
  `ProviderAdapter` bilan ishlaydi. Buni statik test tekshiradi
  (`tests/ai/test_no_direct_sdk_import.py`).
- **Anthropic adapter — birinchi** (`anthropic_adapter.py`); **OpenAI-compatible — ikkinchi**
  (`openai_compat_adapter.py`: `openai` SDK + `base_url`).
- Ikkala adapter `tests/ai/test_adapter_contract.py` da **bir xil fixtures** bilan o'tadi
  (structured output, streaming, tool loop, refusal, cache hit).

**Anthropic adapter uchun aniq talablar:**

- Strukturali chiqish — `output_config.format` orqali (eskirgan `output_format` parametri
  **ishlatilmaydi**); tool argumentlari uchun tool ta'rifida `strict: true`.
- Streaming — `client.messages.stream(...)`, uzun javoblar uchun majburiy.
- **Assistant prefill ishlatilmaydi** — joriy modellarda u 400 xato qaytaradi; javob formatini
  boshqarish faqat structured output yoki system prompt bilan.
- `stop_reason == "refusal"` → `stop_details.category` loglanadi va foydalanuvchiga **xavfsiz
  shablon** javob beriladi. `stop_reason` `content` o'qishdan **oldin** tekshiriladi.
- Thinking: joriy Opus/Sonnet modellarida `thinking: {"type": "adaptive"}`;
  `budget_tokens` **ishlatilmaydi** (bu modellarda 400 qaytaradi). Haiku klassifikatorlarida
  thinking umuman yoqilmaydi (kechikish va narx uchun).
- `temperature` / `top_p` joriy Opus/Sonnet modellarida **yuborilmaydi** (400). Xatti-harakat
  `output_config.effort` bilan boshqariladi.
- **Prompt caching:** statik system prompt + safety siyosati + tool ta'riflari → birinchi
  cache breakpoint; RAG hujjatlari → ikkinchi breakpoint; **o'zgaruvchan** kontekst (sana,
  foydalanuvchi konteksti, savol) doim **oxirgi breakpoint'dan keyin**. Bitta so'rovda ≤ 4
  breakpoint. Cache prefiksiga `datetime.now()` kabi hech narsa kirmaydi.
- Tungi batch job'lar (`ai_batch`: memory dayjest, oylik insight) **Batches API** orqali —
  bu qatlam bo'yicha ~50% arzonroq.

### 2. Model tanlovi ma'lumotlar bazasida

Model tanlovi `ai_model_policy` jadvalida saqlanadi (admin tahrirlaydi) va agent kodida
**hech qachon hardcode qilinmaydi**. Kodda faqat agent nomi bo'yicha policy qidiruvi bo'ladi;
model ID o'zgarishi deploy talab qilmaydi.

```
ai_model_policy(
  id, agent TEXT UNIQUE, provider TEXT,            -- 'anthropic' | 'openai_compat'
  model TEXT, max_tokens INT, effort TEXT,         -- 'low'|'medium'|'high'|'xhigh'|'max'
  thinking_mode TEXT,                              -- 'adaptive' | 'off'
  params JSONB,                                    -- provider'ga xos qo'shimchalar
  price_in_per_mtok NUMERIC, price_out_per_mtok NUMERIC, price_cache_read_per_mtok NUMERIC,
  daily_quota INT, enabled BOOL,
  updated_by, updated_at
)
```

**Boshlang'ich policy (seed):**

| Agentlar | Model ID |
|---|---|
| planner, rescheduler, coach | `claude-opus-5` |
| chat, tutor, analyst, recommender, wellbeing | `claude-sonnet-5` |
| intent klassifikator, output klassifikator, memory extraction | `claude-haiku-4-5` |

Bu uchta ID `claude-api` skill'i orqali tekshirildi (2026-09-12) va joriy amaldagi to'liq
identifikatorlardir. **Model ID ga sana qo'shimchasi qo'shilmaydi** (`claude-opus-5-2026...`
kabi shakllar noto'g'ri). Narxlar (o'sha manba, kesh sanasi 2026-06-24, 1M token uchun
kirish/chiqish): `claude-opus-5` $5 / $25; `claude-sonnet-5` $2 / $10; `claude-haiku-4-5`
$1 / $5. Kontekst oynasi: Opus 5 va Sonnet 5 — 1M; Haiku 4.5 — 200K.

**Narxlar kodda hardcode qilinmaydi** — ular `ai_model_policy` ustunlarida saqlanadi va
`ai_requests.cost_usd` chaqiruv paytidagi policy qatoridan hisoblanadi. Narx o'zgarsa admin
bitta qatorni tahrirlaydi; eski `ai_requests` yozuvlari qayta hisoblanmaydi.

### 3. Embeddinglar

- **Prod:** Voyage **`voyage-multilingual-2`**, **1024 o'lcham**.
- **Dev:** lokal **`bge-m3`** (`providers/embeddings/local_bge_m3.py`), ham 1024 o'lcham —
  internetsiz ishlash uchun.
- `content_chunks.embedding` turi `vector(1024)`, pgvector **HNSW cosine** indeksi.
- `content_chunks` da `embedding_model TEXT NOT NULL` va `embedding_dim INT NOT NULL` ustunlari
  bo'ladi. **Bitta indeksda ikki xil model aralashmaydi.**
- **O'lcham o'zgarishi = reindex migratsiyasi.** Tartib qat'iy: (1) yangi jadval
  `content_chunks_v2` yangi `vector(N)` turi bilan; (2) barcha `published` kontentni qayta
  embedding qilish (arq job, progress bilan); (3) yangi HNSW indeks; (4) retriever'ni feature
  flag bilan yangi jadvalga o'tkazish; (5) eski jadvalni o'chirish. Joyida `ALTER TYPE`
  qilinmaydi.
- Faqat `status = published` bo'lgan `content` yozuvlari indekslanadi.
- Retriever: pgvector top-20 + `tsvector` top-20 → RRF → top-6.
- Anthropic embedding API taklif qilmaydi — shuning uchun embedding provideri LLM providerdan
  **mustaqil** almashtiriladi.

### 4. Buzilmaydigan qoidalar (non-negotiables)

Ular `ai/safety/` va `ai/rag/citation.py` da majburlanadi va `tests/ai/safety/*.yaml`
(~150 holat, 4 til) bilan qoplanadi.

1. **Diniy iqtibos faqat `content` jadvalidagi `published` yozuvdan.** Har
   `WisdomAnswer.citations[].quoted_text` tegishli `content_chunks.chunk_text` ichida
   **substring** sifatida tekshiriladi (normalizatsiya: whitespace va diakritika; qisman yoki
   "o'xshash" moslik qabul qilinmaydi). Tekshiruv o'tmasa — javob **refusal shabloniga**
   almashtiriladi. Oyat raqamlari Qur'on jadvaliga qarshi validatsiya qilinadi.
   **LLM hech qachon manba emas.**
2. **Fatvo-tipidagi intent doim rad etiladi.** Intent klassifikatori (haiku, keshlangan):
   `religious_ruling | religious_info | general | medical | psychological`.
   `religious_ruling` → **har doim** refusal + rasmiy muftiyatga yo'naltirish, hech qanday
   istisno va hech qanday "umumiy ma'lumot sifatida" javob yo'q. `religious_info` → RAG
   **majburiy** (manba topilmasa refusal).
3. **Refusal shablonlari.** `ai/prompts/refusals/` da: `fatwa`, `no_source`, `medical`,
   `self_harm`, `jailbreak`, `out_of_scope`. Server javobda
   `{refused: true, refusal_code, message}` qaytaradi; **klient UI matnini `refusal_code`
   bo'yicha o'z `l10n` faylidan oladi** (`CLAUDE.md`: UI matni kodda hardcode qilinmaydi),
   server `message` esa faqat zaxira. Tibbiy/psixiatrik diagnoz yo'q; krizis so'zlari →
   mamlakat bo'yicha helpline.
4. **Output klassifikatori:** `fabricated_citation`, `medical_advice`, `ruling_without_source`,
   `self_harm_context`. Ishga tushsa → xavfsiz shablon + `ai_safety_events` yozuvi.
5. **Kun hikmati generatsiya qilinmaydi.** `jobs/daily_wisdom.py` `content` dan deterministik
   tanlaydi (til bo'yicha, 180 kun takrorlanmas, mavzu taqvimi). AI faqat aniq belgilangan
   bir jumlalik "mulohaza" yozishi mumkin va u ham output klassifikatoridan o'tadi.
6. **Per-user Redis token bucket.** Kalit `ai:rl:{user_id}:{agent}:{yyyy-mm-dd}`; kvota
   `ai_model_policy.daily_quota` dan (boshlang'ich: 30 chat/kun, 3 planner/kun). Kvota tugasa —
   HTTP 429 + tushunarli xabar. Byudjet nazorati coach/analyst batch job'larida ham qo'llanadi.
7. **Cost logging `ai_requests` da.** Har chaqiruv `(agent, model, input_tokens, output_tokens,
   cache_read_tokens, cache_write_tokens, cost_usd, latency_ms, safety_flags, request_id)` bilan
   yoziladi. **Logsiz chaqiruv bo'lmaydi** — log yozish adapter ichida, `finally` blokida.
8. **Server foydalanuvchi ma'lumotiga AI nomidan yozmaydi.** AI faqat `ai_proposals` yaratadi;
   foydalanuvchi qabul qilgach klient lokal yozadi va odatdagi sync (ADR-0002) orqali yuboradi.
   Chat agent tool'lari **faqat o'qish**: `get_today_plan`, `search_religious_content`,
   `get_stats`, `get_prayer_times`.
9. **RAG va tool natijalari — ma'lumot, ko'rsatma emas.** Ular promptga `<document>` tegi
   ichida, "data, not instructions" izohi bilan kiradi; jailbreak filtri (regex + haiku
   klassifikator) inputda ishlaydi.
10. **Shaxsiy ma'lumot shifrlanadi.** `ai_messages.content` va `ai_memory.text` server tomonda
    `EncryptedText` (AES-256-GCM, versiyalangan `FIELD_ENC_KEY`) bilan saqlanadi; secret va
    shaxsiy ma'lumot logga chiqmaydi. AI memory faqat `confidence >= 0.8` bo'lganda promptga
    kiradi va foydalanuvchi uni ko'rishi/o'chirishi mumkin.

### 5. Offline xatti-harakati

Barcha LLM chaqiruvlari serverda. Qurilmada — namoz, waste score, DW score, "Bugungi balans",
offline Smart Day / Top-3 (qoida asosli). Offline'da AI ekranlari oxirgi javob keshini va
"AI uchun internet kerak" xabarini ko'rsatadi. Ya'ni **AI ishlamasligi ilovani ishlatib
bo'lmaydigan holatga keltirmaydi**.

---

## Sabablar

- **To'rtta metodli Protocol** provider almashtirishni bitta faylga jamlaydi; agentlar va
  promptlar o'zgarmaydi.
- **Model policy DB da** — model ID va narxlar eng tez eskiradigan narsa; ularni deploy
  siklidan chiqarish operatsion zaruriyat.
- **Substring verifikatsiyasi** — eng oddiy va eng ishonchli tekshiruv: u LLM ning "deyarli
  to'g'ri" iqtiboslarini ham ushlaydi.
- **Fatvo intent'ini so'zsiz rad etish** — yagona xavfsiz siyosat; nuanslangan qoida muqarrar
  ravishda buziladi.
- **Prompt caching + haiku klassifikatorlar + tungi Batches** — 7-bosqich DoD dagi "faol
  foydalanuvchi uchun kunlik xarajat < $0.05" maqsadiga erishishning yagona yo'li; bu uchtasi
  "optimizatsiya" emas, **arxitektura qismi**.
- **Embedding providerini LLM providerdan ajratish** — Anthropic embedding API taklif qilmaydi;
  ikkalasini bog'lash keraksiz cheklov bo'lardi.

---

## Ko'rib chiqilgan alternativalar (va nega rad etilgan)

| Variant | Nega rad etildi |
|---|---|
| **To'g'ridan-to'g'ri provider SDK agent kodida** | Provider almashtirish butun `ai/agents/` ni qayta yozishni talab qilardi; ТЗ 36 ga zid. |
| **LangChain / LlamaIndex** | Qo'shimcha abstraktsiya qatlami, versiya drift, debug qiyinligi va "sehrli" xatti-harakat; kerak bo'lgan narsa — to'rtta metodli Protocol. |
| **Model ID ni env/konfiguratsiya faylida saqlash** | Deploy talab qiladi; admin model policy'ni o'zgartira olmaydi va agent-bajadval siyosat qo'yish noqulay. |
| **OpenAI embeddings (`text-embedding-3-*`)** | O'zbek/rus/arab aralash korpus uchun `voyage-multilingual-2` tanlangan; dev'da lokal `bge-m3` internetsiz ishlaydi va bir xil o'lchamda. |
| **Alohida vektor baza (Qdrant/Weaviate)** | pgvector MVP miqyosida yetarli; ADR-0001. |
| **LLM ga to'g'ridan-to'g'ri yozish huquqi (tasks/calendar)** | Offline invariantlarni (ADR-0002) buzadi va foydalanuvchi nazoratini yo'qotadi; `ai_proposals` + sync yo'li majburiy. |
| **Generativ "kun hikmati"** | Manbasiz diniy matn xavfi — mahsulotning eng katta reputatsion riski. |
| **Fatvo savollariga "umumiy ma'lumot" sifatida javob berish** | Chegarani belgilash imkonsiz; foydalanuvchi uni hukm sifatida qabul qiladi. |
| **Semantik o'xshashlik bilan iqtibos tekshiruvi (substring o'rniga)** | Chegara qiymati sozlanishi kerak va "deyarli to'g'ri" o'ylab topilgan iqtibosni o'tkazib yuboradi. |
| **Avtomatik provider fallback** | Jimgina sifat/narx o'zgarishi; xatolik yashirin qoladi. MVP da qo'lda almashtirish (quyida). |
| **Fine-tuning / shaxsiy model** | MVP uchun qimmat va sekin; qoida asosli personalization + memory yetarli. |

---

## Oqibatlar

### Ijobiy

- Provider almashtirish adapter darajasida — agentlar va promptlar o'zgarmaydi.
- Model ID yoki narx eskirsa admin panelidan bir daqiqada almashtiriladi; yuqoridagi jadval
  "boshlang'ich qiymat", kod haqiqati emas.
- Xarajat har chaqiruv darajasida ko'rinadi (`AIRequestsAdmin` kunlik grafik) → byudjet
  nazorati real.
- Refusal xatti-harakati testlanadigan va takrorlanadigan.
- Embedding va LLM providerlari mustaqil evolyutsiya qiladi.

### Salbiy

- `complete_structured` ikkala providerda turlicha implementatsiya qilinadi (Anthropic
  `output_config.format`, OpenAI `response_format`) — kontrakt testi bu farqni yashiradi, lekin
  ikkita kod yo'li saqlanadi.
- **Substring verifikatsiyasi ba'zi to'g'ri javoblarni ham rad etadi** (LLM iqtibosni
  qisqartirsa) — bu **atayin**: noto'g'ri iqtibosdan ko'ra refusal afzal.
- 1024 o'lchamli vektorga bog'lanish kelajakdagi embedding modelini shu o'lcham bilan cheklaydi
  yoki to'liq reindex talab qiladi (yuqoridagi 5 qadamli migratsiya).
- Avtomatik fallback yo'qligi Anthropic uzilishida AI funksiyalarini vaqtincha o'chiradi
  (ilovaning qolgan qismi ishlaydi).
- Prompt caching prefiks barqarorligini talab qiladi — system prompt yoki tool ta'rifidagi
  kichik o'zgarish keshni butunlay bekor qiladi va xarajatni keskin oshiradi.

---

## Amalga oshirish uchun majburiy qoidalar

1. Barcha LLM chaqiruvlari `ProviderAdapter` orqali. `ai/agents/**` ichida `anthropic` yoki
   `openai` import qilinishi statik test bilan taqiqlanadi.
2. Model ID, `max_tokens`, `effort` va narxlar **faqat** `ai_model_policy` dan o'qiladi.
   Kodda literal model ID bo'lishi CI grep testi bilan taqiqlanadi (migratsiya seed'idan
   tashqari).
3. Har `WisdomAnswer` javobi `citation.py` dan o'tadi; substring tekshiruvi o'tmagan iqtibos
   **butun javobni** refusal shabloniga almashtiradi (iqtibosni olib tashlash yetarli emas).
4. `religious_ruling` intent'i uchun hech qanday model chaqirilmaydi — refusal darhol
   qaytariladi (token sarflanmaydi).
5. `religious_info` intent'ida RAG natijasi bo'sh bo'lsa → `no_source` refusal; LLM ga savol
   yuborilmaydi.
6. Har chaqiruv `ai_requests` ga yoziladi (`finally` blokida, xato holatida ham).
7. Redis token bucket har agent chaqiruvidan **oldin** tekshiriladi.
8. Prompt caching: statik system + safety + tool ta'riflari birinchi breakpoint'da; o'zgaruvchan
   kontekst oxirgi breakpoint'dan **keyin**. `usage.cache_read_input_tokens` monitoring qilinadi
   — u nolga tushsa alert.
9. `stop_reason` `content` o'qishdan oldin tekshiriladi; `refusal` bo'lsa xavfsiz shablon.
10. Foydalanuvchiga ko'rinadigan refusal matni klientda `refusal_code` bo'yicha `l10n` dan
    olinadi; serverda UI matni hardcode qilinmaydi.
11. `ai_messages.content` va `ai_memory.text` `EncryptedText` bilan saqlanadi; prompt va javob
    to'liq holda logga yozilmaydi (faqat token soni va safety flag'lar).
12. **AI sync jadvallariga yozmaydi** (ADR-0002 AI invarianti); statik test bilan tekshiriladi.
13. Embedding o'lchami o'zgarsa — yangi jadval + reindex migratsiyasi; joyida `ALTER TYPE`
    taqiqlanadi.
14. Faqat `status = published` kontent indekslanadi; `publish` amali embedding job'ini ishga
    tushiradi.
15. Yangi agent qo'shilganda `ai_model_policy` ga seed qator va `tests/ai/safety/` ga holatlar
    qo'shilishi shart — aks holda agent `enabled = false` holatida qoladi.

---

## Rejada aniqlanmagan — shu yerda hal qilindi

| Savol | Qaror |
|---|---|
| `ai_model_policy` ustunlari | §2 dagi to'liq shakl: `agent, provider, model, max_tokens, effort, thinking_mode, params, price_*, daily_quota, enabled, updated_by, updated_at`. |
| Narxlar qayerda saqlanadi | `ai_model_policy` da (kodda emas); `ai_requests.cost_usd` chaqiruv paytidagi policy qatoridan hisoblanadi. Boshlang'ich qiymatlar `claude-api` skill manbasidan (kesh 2026-06-24). |
| `wellbeing` agenti qaysi modelda | `claude-sonnet-5` (reja uni sanab o'tmagan). |
| Provider fallback siyosati | MVP da **avtomatik fallback yo'q**; `ai_model_policy` orqali qo'lda almashtiriladi. Jimgina sifat/narx o'zgarishi xatoni yashirardi. |
| Voyage embedding API nosozligi | Indekslash job'i retry bilan navbatda qoladi; foydalanuvchi oqimi RAG'siz `no_source` refusal'ga tushadi (soxta javob emas). |
| `temperature` / thinking parametrlari | Joriy Opus/Sonnet modellarida `temperature` yuborilmaydi; `thinking: adaptive` + `output_config.effort`. Haiku klassifikatorlarida thinking o'chiq. |
| Structured output mexanizmi | `output_config.format` (eskirgan `output_format` emas); tool argumentlari uchun `strict: true`. Assistant prefill ishlatilmaydi. |
| Refusal matnining tili | Server `refusal_code` qaytaradi, klient `l10n` dan matn oladi; server `message` — zaxira. |
| Substring tekshiruvining normalizatsiyasi | Whitespace va diakritika normalizatsiyasi; qisman/semantik moslik qabul qilinmaydi. |
| `content_chunks` da model kuzatuvi | `embedding_model` va `embedding_dim` ustunlari majburiy; bitta indeksda ikki model aralashmaydi. |
| Token bucket kaliti | `ai:rl:{user_id}:{agent}:{yyyy-mm-dd}`. |
| Batch API qayerda ishlatiladi | Faqat tungi `ai_batch` job'lari (memory dayjest, oylik insight) — foydalanuvchi kutadigan oqimlarda emas. |
| Yangi agent qo'shish tartibi | Policy seed + safety testlari bo'lmasa `enabled = false`. |

---

## Qachon qayta ko'riladi

1. `ai_model_policy` dagi model ID lari eskirsa yoki yangi narx/model qatlami chiqsa
   (7-bosqich oldidan `claude-api` skill orqali qayta tekshirish majburiy);
2. Kunlik AI xarajati faol foydalanuvchi uchun $0.05 dan oshsa, yoki cache hit nisbati 60% dan
   pastga tushsa;
3. RAG citation aniqligi golden Q&A to'plamida 95% dan pastga tushsa, yoki substring
   verifikatsiyasi tufayli false-refusal darajasi 10% dan oshsa;
4. Anthropic mavjudligi/mintaqaviy cheklovi OpenAI-compatible adapterga o'tishni talab qilsa
   (avtomatik fallback qarori qayta ko'riladi);
5. Embedding modeli almashtirilishi kerak bo'lsa (vektor o'lchami va to'liq reindex qarori).
