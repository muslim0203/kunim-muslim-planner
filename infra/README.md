# Verification update — 2026-09-12

Development stack now runs on Docker Desktop with healthy PostgreSQL, Redis, MinIO, API and worker. Migrations and live auth/queue smoke checks passed. See docs/implementation-status.md. Historical untested notes below describe the original authoring state. Production deployment has not been run. Development ports are localhost-only; MinIO images now use quay.io/minio. Use the documented --env-file command. Restart terminals opened before Docker installation to refresh PATH.

# KUNIM — infratuzilma (`infra/`)

> **Diqqat:** ushbu fayllarning hech biri ular yozilgan mashinada ishga
> tushirilmagan/tekshirilmagan, chunki bu mashinada **Docker o'rnatilmagan**
> (PostgreSQL va Redis ham alohida o'rnatilmagan). Faqat quyidagilar
> bajarildi: YAML fayllar Node.js orqali sintaktik jihatdan tekshirildi;
> qolgan barcha narsa (haqiqiy `docker build`, `docker compose up`,
> konteynerlar ichidagi ulanishlar, healthcheck'lar, Caddy'ning TLS olishi)
> faqat ko'zdan kechirish orqali yozilgan, lekin **hech qachon ishga
> tushirilmagan**. Docker (va, prod uchun, real domen) mavjud mashinada albatta qayta
> tekshiring.

## Tarkib

| Fayl | Vazifasi |
|---|---|
| `docker-compose.yml` | Dev stack: postgres, redis, minio (+ minio-init), api, worker |
| `docker-compose.prod.yml` | Prod uchun **to'liq mustaqil** stack (yuqoridagi + caddy); dev fayl bilan `-f`/`-f` orqali birlashtirilmaydi — sabab fayl ichidagi izohda |
| `api.Dockerfile` | `apps/api` uchun ko'p bosqichli (multi-stage) image, build context = repo tuguni |
| `Caddyfile` | Prod uchun reverse proxy + avtomatik TLS + xavfsizlik sarlavhalari |
| `init-db/01-extensions.sql` | Postgres kengaytmalari (`vector`, `pg_trgm`), faqat bo'sh volume'da birinchi marta ishga tushganda avtomatik bajariladi |

## Stack'ni ishga tushirish (dev, Docker o'rnatilgan mashinada)

```sh
cp .env.example .env      # repo tugunida, keyin haqiqiy qiymatlar bilan to'ldiring
make up                   # yoki: docker compose --env-file .env -f infra/docker-compose.yml up -d
make logs                 # loglarni kuzatish
make ps                   # holatni ko'rish
make down                 # to'xtatish
```

`docker compose` buyrug'iga `--env-file .env` **majburiy qo'shiladi** (Makefile
buni avtomatik qiladi): Compose fayl ichidagi `${VAR}` o'zgaruvchilarni odatda
compose faylining o'zi joylashgan papkadan (`infra/`) emas, balki
`--env-file` ko'rsatilgan joydan o'qiydi — bu farqni chalkashtirmaslik uchun
har doim aniq ko'rsatiladi.

## Xizmatlar va portlar (dev)

| Xizmat | Image | Port (host) | Vazifasi |
|---|---|---|---|
| `postgres` | `pgvector/pgvector:pg16` | `5432` | Asosiy baza (pgvector bilan) |
| `redis` | `redis:7-alpine` | `6379` | Cache + `arq` navbat backend |
| `minio` | `minio/minio` | `9000` (S3 API), `9001` (konsol) | Eksport fayllar uchun S3-mos ombor |
| `minio-init` | `minio/mc` | — | Bir martalik: `kunim-exports` bucket'ini yaratadi, keyin chiqadi (`exited (0)` — normal holat) |
| `api` | shu repo (`api.Dockerfile`) | `8000` | FastAPI (dev: `--reload`, `apps/api` host'dan mount qilingan) |
| `worker` | shu repo (`api.Dockerfile`) | — | `arq` fon vazifalari worker'i |

Prod'da (`docker-compose.prod.yml`): `postgres`/`redis`/`minio` portlari **host'ga
chiqarilmaydi** (faqat konteynerlar ichidagi tarmoqdan, xizmat nomi orqali:
`postgres:5432`, `redis:6379`), `api`/`worker` esa manba kodi mount qilinmagan
image'dan ishlaydi va faqat `caddy` (`80`/`443`) tashqariga ochiladi.

## Volume'larni tozalash / qayta boshlash

```sh
make down
docker volume rm kunim_pgdata kunim_redisdata kunim_miniodata   # nom prefiksi papka nomiga qarab farq qilishi mumkin
docker volume ls | grep kunim   # aniq nomlarni shu buyruq bilan tekshiring
make up
```

`init-db/01-extensions.sql` faqat **bo'sh** `pgdata` volume'da birinchi marta
ishga tushishda bajariladi — volume o'chirilmasa, uni qayta ishga tushirish
kifoya emas.

## Muhit o'zgaruvchilari

Barcha o'zgaruvchilar va ularning izohlari repo tugunidagi `.env.example`
faylida (o'zbekcha izohlar bilan). Hech qachon haqiqiy qiymatlarni
`.env.example`ga yozmang — u commit qilinadi, `.env` esa `.gitignore`da.

## Nima tekshirilmadi (va nega)

- `docker build` / `docker compose up` — Docker bu mashinada yo'q.
- Postgres/Redis/MinIO healthcheck'larining haqiqatda ishlashi — mos
  dastur(lar) o'rnatilmagan.
- Caddy'ning haqiqiy domen uchun TLS sertifikat olishi — domen va prod
  server yo'q.
- `Makefile` ning haqiqiy bajarilishi (`make help`, `make up`, ...) — GNU
  Make bu mashinada topilmadi (`command -v make` — natija yo'q).

Tekshirilgani: barcha YAML fayllar (`docker-compose.yml`,
`docker-compose.prod.yml`) Node.js `yaml` orqali muvaffaqiyatli parse
qilindi (sintaktik xato yo'q); `Makefile` va `Dockerfile`/`Caddyfile` faqat
ko'zdan kechirish orqali tekshirildi.
