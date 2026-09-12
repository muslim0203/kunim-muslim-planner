# Agent vazifalari ledgeri

**Qoida:** har faylning bir vaqtda **bitta yozuvchi egasi** bo'ladi. Ziddiyatni orkestrator hal qiladi.

**Xarajat/token:** bu muhitda agent usage ko'rsatkichi orkestratorga ko'rinmaydi → **mavjud emas**.
Taxminiy foizlar yozilmaydi.

---

## 0-bosqich: Skelet va CI

| ID | Vazifa | Model | Holat | Fayl egaligi | Tekshiruv (haqiqiy natija) |
|---|---|---|---|---|---|
| T-001 | Monorepo skeleti, `git init`, `.gitignore`, `.editorconfig`, `CLAUDE.md` | Opus 5 (orkestrator) | ✅ | root fayllar, `docs/plan.md` | Papka daraxti va git repo yaratildi |
| T-002 | FastAPI skeleti: `/health`, `/health/ready`, config, db mixinlar, Alembic, SQLAdmin | Sonnet | ✅ | `apps/api/**` | `pytest -q` → **4 passed**; `ruff check` → **passed**; `ruff format --check` → **passed** |
| T-003 | Flutter shell: router, tema, 4 til ARB, Drift, dio, shared widgetlar | Sonnet | ⚠️ qisman | `apps/mobile/**` | `check_l10n.mjs` → **4 locale × 20 kalit, passed**. Flutter toolchain yo'q → `pub get`/`analyze`/`test` **bajarilmadi** |
| T-004 | Hujjatlar: status, checklist, backlog, content-policy, privacy/data-map, iOS entitlement | Haiku | ✅ | `docs/*.md` (adr'dan tashqari) | Fayllar mavjud; litsenziya holati UNRESOLVED deb halol qoldirilgan |
| T-005 | ADR-0001..0004 + index | Opus | ✅ | `docs/adr/**` | 5 fayl, 705 satr; sarlavha strukturasi va model ID'lari tekshirildi |
| T-006 | Infra: docker-compose (dev/prod), api.Dockerfile, Caddyfile, init-db, `Makefile`, `.env.example` | Sonnet | ⚠️ qisman | `infra/**`, `Makefile`, `.env.example` | YAML parse → **OK**; Docker va `make` o'rnatilmagan → **ishga tushirilmadi** |
| T-007 | CI: `api.yml`, `mobile.yml`, `content.yml`, PR shabloni | Haiku | ✅ | `.github/**` | YAML parse → **OK**; runner yo'q → workflow **ishga tushirilmadi** |

### Orkestrator tuzatgan xatolar

| # | Nima topildi | Tuzatish |
|---|---|---|
| 1 | `setup-python`ning `cache: pip` sozlamasi `requirements.txt` qidiradi, bizda `pyproject.toml` — CI birinchi qadamda yiqilardi | `cache-dependency-path: apps/api/pyproject.toml` qo'shildi |
| 2 | API `SECRET_KEY` deb nomlagan, CI va `.env.example` esa `JWT_SECRET` — kontrakt buzilgan | `JWT_SECRET` ga o'zgartirildi; rejaning 11-bo'limi talab qiladigan `FIELD_ENC_KEY` qo'shildi |
| 3 | `apps/mobile/tool/check_l10n.mjs` yozilmagan, lekin `mobile.yml` va `make l10n` unga murojaat qiladi | Yozildi va ishlatildi — parity o'tdi |
| 4 | `docs/balance-formula.md` yozilmay qolgan | Yozildi (formulalar rejadan aynan ko'chirildi) |
| 5 | Ikki agent iOS entitlement matnini ikki faylga yozgan | To'liqrog'i qoldirildi, dublikat o'chirildi |
| 6 | `worker` konteyneri `app.jobs.worker.WorkerSettings` ni chaqiradi, modul mavjud emas — crash-loop bo'lardi | `apps/api/app/jobs/worker.py` stub yozildi, `arq` dependency qo'shildi, import tekshirildi |
| 7 | `ruff format --check` 4 faylda yiqilardi → CI qizil | `ruff format` ishlatildi, qayta tekshirildi |
| 8 | Bo'sh papkalarni git saqlamaydi | `.gitkeep` qo'shildi |

---

## Holat belgilari

- ✅ **Tugallangan va tekshirilgan** — dalil yuqoridagi ustunda
- ⚠️ **Qisman** — kod yozilgan, lekin kerakli tool yo'qligi sababli tekshirilmagan
- 🟡 **Jarayonda**
- ⬜ **Boshlanmagan**

## Model marshrutlash qoidasi

| Vazifa turi | Model |
|---|---|
| Taqsimlash, qabul, integratsiya, umumiy nazorat | Orkestrator (bu sessiya: **Opus 5**) |
| Murakkab/noaniq/xato narxi yuqori (sync, auth, native, AI safety) | Opus |
| Odatdagi implementatsiya va integratsiya | Sonnet |
| Andoza asosidagi sodda, aniq chegaralangan ish | Haiku |
