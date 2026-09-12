# Qabul tekshiruv ro'yxati (acceptance-checklist)

Har bosqich DoD (Definition of Done) quyida tekshiruv ro'yxati sifatida taqsimlanadi. Hamma `- [ ]` bo'lish kerak.

---

## Bosqich 0: Skelet va CI

- [ ] CI pipelines o'rnatilgan va GitHub'da yashil
- [ ] Android emulator ishlab ochildi va Flutter demo'si ishlaydi
- [ ] iOS simulator ishlab ochildi va Flutter demo'si ishlaydi
- [ ] `make gen` command barcha code generators'ni ishlantiradi (freezed, drift, riverpod, pigeon, openapi client)
- [ ] ADR-001 (stack) tayyar va approved
- [ ] ADR-002 (sync) tayyar va approved
- [ ] ADR-003 (dw-platforms) tayyar va approved
- [ ] ADR-004 (ai-provider) tayyar va approved
- [ ] iOS Family Controls entitlement so'rovi Apple'ga yuborilgan

---

## Bosqich 1: Auth, profil, onboarding, Home shell, tema, i18n

- [ ] Fresh install → onboarding oqimi boshlanadi
- [ ] Onboarding qadam 1: til tanlash (uz-Latn, uz-Cyrl, ru, en)
- [ ] Onboarding qadam 2: ism va avatar kiriting/yuklang
- [ ] Onboarding qadam 3: joylashuv va namoz usuli tanlang
- [ ] Onboarding qadam 4: hayotiy maqsadlarni tanlang/kiriting
- [ ] Onboarding qadam 5: ruxsatlar (notifikatsiya, joylashuv, healthkit/health connect) + maxfiylik siyosati
- [ ] Onboarding oxirida: login ekraniga o'tish
- [ ] Login email + parol bilan ishlaydi
- [ ] Login Google Sign-In bilan ishlaydi
- [ ] Login Apple Sign-In bilan ishlaydi
- [ ] Login undan keyin Home shell ochildi
- [ ] App restart → session saqlandi, qayta login yo'q (offline'da ham)
- [ ] Logout → session tozalandi, login ekraniga qaytdi
- [ ] Light tema o'chir; barcha shimlar Material 3 ColorScheme asosida
- [ ] Dark tema o'chir; barcha shimlar Material 3 ColorScheme asosida
- [ ] System theme izlashni o'rnatilgan OS sozlamasi qayta qo'llaniladi
- [ ] 4 til arning hammasida 100% string qoplash (l10n_check CI)
- [ ] Home navigation: Bosh sahifa | Kun tartibi | Statistika | AI | Sozlamalar

---

## Bosqich 2: Vazifalar, kalendar, odatlar, maqsadlar — offline-first + sync

- [ ] Yangi vazifa qo'shish (sarlavha, tavsif, dedlayn, kategoriya)
- [ ] Vazifani tahrir ishlaydi
- [ ] Vazifani bajarilgan deb belgilash (`completed_at` yangilandi)
- [ ] Vazifani o'chirish (soft delete)
- [ ] Vazifalar Home'da "Top-3" blokda ko'rinadi
- [ ] Vazifa "bugungi bloklar" (bugungi tayyorlangan vazifalar saatlari bo'yicha)
- [ ] Kalendar ko'rinishi haftalar va kuni orqali ko'rish
- [ ] Kalendar RRULE subset: kunlik, haftalik (kunlar tanlash)
- [ ] Yangi odat qo'shish (sarlavha, kategoriya, ma'qul/taqs)
- [ ] Odat streak counter: 7-kunlik, 30-kunlik, 100-kunlik badge'lar
- [ ] Yangi maqsad qo'shish
- [ ] Maqsad bosqichlariga (milestones) qo'shish
- [ ] Qurilma 1 — offline'da vazifa qo'shing; qayta onlayn; Qurilma 2 — yangi vazifani ko'radi
- [ ] Qurilma 1 — offline'da vazifa qo'shing; Qurilma 2 — offline'da ehtiyoj qayta qo'shing (bir xil id); qayta onlayn → merge conflict avtomatik hal qilinadi
- [ ] Offline'da qo'shilgan o'zgarishlar sync_outbox'da saqlanadi; qayta online → sync push ishlaydi
- [ ] Konflikt matritsasi test: ikki Dart in-memory Drift + test API server qarama-qarshi

---

## Bosqich 3: Namoz, Qur'on, kun hikmati

- [ ] Namoz vaqtlari Toshkent'da 12 test sanasi uchun rasmiy jadval bilan mos
- [ ] Namoz bildirishnomasi reboot'dan keyin ishlab ochildi
- [ ] Qur'on matniga (Tanzil Uthmani) offline kirish
- [ ] Qur'on tarjimasi (mavjud litsenziyaga ko'ra): o'zbek / rus / ingliz
- [ ] Har kun hikmatida manba qayd qilingan
- [ ] `content_tools` CLI — Qur'on import qiladi va embedding'larni generatsiya qiladi
- [ ] `content_tools` CLI — birinchi hadis to'plami import qiladi (litsenziya tekshirilgan)
- [ ] `content` jadvalida checksum har record'da
- [ ] Hikmat status: draft → review → approved → published

---

## Bosqich 4: Mood, uyqu, sog'liq, ta'lim, kitoblar (+ ish, oila, dam olish)

- [ ] Mood yozuvini qo'shish (emoji/rang + ixtiyori eslatma)
- [ ] Uyqu jurnal (vaqt, davomiyligi, sifati)
- [ ] Sog'liq metrika (suv, qadam, ish harakati, vb.)
- [ ] Ta'lim sessiyasi (mavzu, davomiylik, qayta ko'rish)
- [ ] Kitob qo'shish (sarlavha, muallif, page counter, vb.)
- [ ] Ish kategoriyasi foydalanish (project/assignment qo'shish)
- [ ] Oila kategoriyasi foydalanish (event/reminder qo'shish)
- [ ] Dam olish kategoriyasi foydalanish (hobby/activity qo'shish)
- [ ] Har modul: add/edit/delete/history
- [ ] Offline va sync (mood, uyqu, sog'liq, ta'lim, kitoblar hammasida)
- [ ] Home "Smart Day" bloki hamma kategoriyani ko'rinadi

---

## Bosqich 5: Statistika, review'lar, Bugungi balans, gamifikatsiya

- [ ] Statistika (kunlik/haftalik) offline Drift'da hisoblandi
- [ ] Statistika online va offline ma'lumot bir xil (golden test)
- [ ] Review: "Haftalik review" tunda generatsiya qilinadi (qoida-asosli matn)
- [ ] Review: "Oylik review" tunda generatsiya qilinadi
- [ ] Review'lar Notification Center'da ko'rinadi
- [ ] Bugungi balans: 7 yo'nalish ko'rinadi (Ma'naviyat, Sog'liq, Ish, Ta'lim, Oila, Dam olish, Raqamli)
- [ ] Bugungi balans formula doc/balance-formula.md bilan mos
- [ ] Streak badge'lar Home'da ko'rinadi (7/30/100 kunlik odata)
- [ ] Gamifikatsiya milestone'lar

---

## Bosqich 6: Digital Wellbeing: Android va iOS

- [ ] Android: PACKAGE_USAGE_STATS ruxsati so'raladi
- [ ] Android: in-app disclosure ekrani ko'rinadi (Play talabi)
- [ ] Android: 24 soatlik real foydalanish ma'lumoti tizim DW bilan ±5% to'g'riligi
- [ ] Android: AppCategoryResolver (foydalanuvchi qayta belgilashi mumkin)
- [ ] Android: UsageWorker har 15 daqiqada ishlaydi + app ochilganda
- [ ] Android: Session qo'shilgan dw_sessions, dw_daily, dw_events
- [ ] Android: limit 80% / 100% notifikatsiyasi
- [ ] Android: limit snoozli ("15 daqiqa kechiktirish" / "Bugun uzaytirish")
- [ ] iOS: Family Controls entitlement maqbul qabul qilinsa (yoki entitlement rad etilsa selfreport bilan)
- [ ] iOS: DeviceActivityReport extension sandbox'da ishlaydi (raqamlar ilovaga chiqmaydi)
- [ ] iOS: DeviceActivityMonitor extension 80%/100% event → lokal notifikatsiya + App Group flag
- [ ] iOS: Threshold notification qurilmada ko'rinadi
- [ ] iOS: "Qat'iy rejim" (ManagedSettings.shield) MVP'da o'chiq
- [ ] Ruxsat rad etilsa: iOS va Android ikkalasi ham to'liq ishlaydi
- [ ] Play Data Safety + Usage Access deklaratsiya hujjati tayyor

---

## Bosqich 7: AI: chat, planner, reschedule, recs, memory, RAG

- [ ] AI chat agent ishlaydi va javoblarni qaytaradi
- [ ] AI planner agent kunlik reja taklifi beradi
- [ ] AI rescheduler agent vazifalarni qayta jadvallash taklifi beradi
- [ ] AI recommender agent tafsiyalarni beradi
- [ ] AI memory service foydalanuvchi xotira saqlab turadi va prompts'ga qo'shadi
- [ ] RAG: kontent taraftar qidiruvi (pgvector + tsvector)
- [ ] RAG: citation.py har quoted_text'ni content_chunks ichida substring sifatida tekshiradi
- [ ] RAG refusal: manba yo'q → AI refused javob beradi
- [ ] Safety suite: refusal holatlarda 100% catch (fatvo, tibbiy maslahat, sohta iqtibos, vb.)
- [ ] Planner proposal sync orqali qo'llanadi
- [ ] Faol foydalanuvchi kunlik AI xarajati < $0.05
- [ ] Offline fallback: Smart Day + Top-3
- [ ] Intent klassifikator "fatvo-tipi" → muftiyatga yo'naltirish
- [ ] Personalizatsiya (MVP): qoida asosli feature + memory + haftalik profil dayjest

---

## Bosqich 8: Smart notifications va personalizatsiya

- [ ] Smart Interruption backoff: simulyatsiya qilingan engagement ma'lumoti bilan
- [ ] Push notifikatsiyalari qurilmalar orasida dublikat yo'q
- [ ] Home'da shaxsiy insight (≥14 kun ma'lumot bo'lganda)
- [ ] Notification backoff: engagement ratio ≥0.4 → normal; 0.15–0.4 → 2x fewer; 0.05–0.15 → daily digest; <0.05 → weekly digest
- [ ] Smart Interruption qoidalari `notification_policy.dart` va `jobs/notif_scheduler.py` da bir xil
- [ ] Interaksiya (tap/action) → backoff reset

---

## Bosqich 9: Xavfsizlik, QA, beta, reliz

- [ ] OWASP MASVS-L1 checklist 100% qoplanadi
- [ ] TalkBack (Android) accessibility tekshiruvi
- [ ] VoiceOver (iOS) accessibility tekshiruvi
- [ ] Text scale 200% da sajlanadi
- [ ] Kontrast (WCAG) checker'da yashil
- [ ] RTL (Arabic pseudo-locale) smoke test
- [ ] Cold start < 2 sekund
- [ ] Store asset'lar: 4 tilga tarjima (uz-Latn, uz-Cyrl, ru, en)
- [ ] Privacy policy har til'da
- [ ] Play Data Safety form to'liq to'ldirilgan
- [ ] Play Usage Access deklaratsiya
- [ ] App Store nutrition label
- [ ] TestFlight build 20–50 tester'ga jo'natilgan
- [ ] Internal testing build 20–50 tester'ga jo'natilgan
- [ ] Crash-free rate ≥ 99.5% testing davomida
- [ ] Android do'koniga (Google Play) yuborilgan
- [ ] iOS do'koniga (App Store) yuborilgan

---

## Reliz: Keyingi marhala

- [ ] `docs/acceptance-checklist.md` 100% tugallangan
- [ ] Bosqich 0–9 hammasida DoD 100%
- [ ] Real Android qurilmada (API 26+) test qilingan
- [ ] Real iOS qurilmada (iOS 16+) test qilingan
- [ ] Ikkala do'koniga yuborilgan hammasida tugallangan
