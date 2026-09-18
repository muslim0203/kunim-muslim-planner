# KUNIM (Muslim Planner) — monorepo developer entrypoint.
#
# Melos/Nx ishlatilmaydi — shu Makefile yetarli (see CLAUDE.md).
#
# Assumes a POSIX-compatible shell for recipe lines (e.g. Git Bash's sh.exe
# on Windows — the shell GNU Make normally uses when installed via Git for
# Windows/MSYS2/Chocolatey). Every recipe below uses only `sh`-portable
# constructs ([ ], &&, command -v) for that reason.
#
# NOT executed on the machine that authored this file: GNU Make itself is
# not installed here (`command -v make` found nothing), so nothing below
# has actually been run — only reviewed by eye and checked with a Node
# `.mk`-agnostic sanity pass (see infra/README.md and the T-006 report for
# what was and wasn't verified).

.DEFAULT_GOAL := help

# --- OS detection for the API venv's interpreter path -----------------------
ifeq ($(OS),Windows_NT)
	VENV_PY := .venv/Scripts/python.exe
else
	VENV_PY := .venv/bin/python
endif

.PHONY: help up down logs ps api api-install migrate revision mobile gen \
	apk aab test test-api test-mobile lint format l10n clean

help: ## Shu yordam matnini ko'rsatish (default)
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# --- Docker (infra/) ---------------------------------------------------------
# All targets pass --env-file explicitly: `docker compose` resolves a bare
# `.env` relative to the Compose file's own directory (infra/), not the
# cwd, when `-f` points outside it — so without this flag the root
# `.env` (see .env.example) would silently NOT be picked up.

up: ## Docker stack'ni fon rejimida ishga tushirish (dev)
	@command -v docker >/dev/null 2>&1 || { echo "Docker o'rnatilmagan"; exit 1; }
	docker compose --env-file .env -f infra/docker-compose.yml up -d

down: ## Docker stack'ni to'xtatish
	@command -v docker >/dev/null 2>&1 || { echo "Docker o'rnatilmagan"; exit 1; }
	docker compose --env-file .env -f infra/docker-compose.yml down

logs: ## Docker konteyner loglarini kuzatish (follow)
	@command -v docker >/dev/null 2>&1 || { echo "Docker o'rnatilmagan"; exit 1; }
	docker compose --env-file .env -f infra/docker-compose.yml logs -f

ps: ## Docker konteynerlar holatini ko'rsatish
	@command -v docker >/dev/null 2>&1 || { echo "Docker o'rnatilmagan"; exit 1; }
	docker compose --env-file .env -f infra/docker-compose.yml ps

# --- API (apps/api) ----------------------------------------------------------

api-install: ## apps/api uchun venv yaratish va dependency'larni o'rnatish
	@[ -d apps/api/.venv ] || (cd apps/api && python -m venv .venv)
	cd apps/api && ./$(VENV_PY) -m pip install --upgrade pip
	cd apps/api && ./$(VENV_PY) -m pip install -e ".[dev]"

api: ## FastAPI dev serverni ishga tushirish (uvicorn --reload)
	@[ -f apps/api/$(VENV_PY) ] || { echo "apps/api/.venv topilmadi — avval ishga tushiring: make api-install"; exit 1; }
	cd apps/api && ./$(VENV_PY) -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

migrate: ## Alembic migratsiyalarini bazaga qo'llash (upgrade head)
	@[ -f apps/api/$(VENV_PY) ] || { echo "apps/api/.venv topilmadi — avval ishga tushiring: make api-install"; exit 1; }
	cd apps/api && ./$(VENV_PY) -m alembic upgrade head

revision: ## Yangi Alembic revision yaratish (majburiy: m="xabar")
	@[ -n "$(m)" ] || { echo 'Xato: m="xabar" argumenti kerak. Masalan: make revision m="add users table"'; exit 1; }
	@[ -f apps/api/$(VENV_PY) ] || { echo "apps/api/.venv topilmadi — avval ishga tushiring: make api-install"; exit 1; }
	cd apps/api && ./$(VENV_PY) -m alembic revision --autogenerate -m "$(m)"

# --- Mobile (apps/mobile) ----------------------------------------------------

mobile: ## Flutter ilovasini ishga tushirish
	@command -v flutter >/dev/null 2>&1 || { echo "Flutter o'rnatilmagan"; exit 1; }
	cd apps/mobile && flutter run

gen: ## Kod generatsiyasi: freezed/drift/riverpod (build_runner)
	@command -v flutter >/dev/null 2>&1 || { echo "Flutter o'rnatilmagan"; exit 1; }
	cd apps/mobile && dart run build_runner build --delete-conflicting-outputs
	# TODO (phase 2): pigeon platform-channel kod generatsiyasi shu yerga qo'shiladi
	# TODO (phase 6): OpenAPI client generatsiyasi (apps/api sxemasidan apps/mobile uchun) shu yerga qo'shiladi

apk: ## Release APK yig'ish (test telefoni uchun; docs/release-android.md)
	@command -v flutter >/dev/null 2>&1 || { echo "Flutter o'rnatilmagan"; exit 1; }
	cd apps/mobile && flutter build apk --release

aab: ## Play uchun imzolangan app bundle yig'ish (docs/release-android.md)
	@command -v flutter >/dev/null 2>&1 || { echo "Flutter o'rnatilmagan"; exit 1; }
	@[ -f apps/mobile/android/key.properties ] || [ -n "$$KUNIM_ANDROID_KEYSTORE" ] || \
		{ echo "Imzo kaliti sozlanmagan — docs/release-android.md"; exit 1; }
	cd apps/mobile && flutter build appbundle --release

# --- Tests --------------------------------------------------------------------

test: test-api test-mobile ## Barcha testlarni ishga tushirish (api + mobile)

test-api: ## apps/api testlarini ishga tushirish (pytest)
	@[ -f apps/api/$(VENV_PY) ] || { echo "apps/api/.venv topilmadi — avval ishga tushiring: make api-install"; exit 1; }
	cd apps/api && ./$(VENV_PY) -m pytest

test-mobile: ## apps/mobile testlarini ishga tushirish (flutter test)
	@command -v flutter >/dev/null 2>&1 || { echo "Flutter o'rnatilmagan"; exit 1; }
	cd apps/mobile && flutter test

# --- Lint / format / l10n -----------------------------------------------------

lint: ## Statik tekshiruv: ruff check + dart analyze
	@[ -f apps/api/$(VENV_PY) ] || { echo "apps/api/.venv topilmadi — avval ishga tushiring: make api-install"; exit 1; }
	cd apps/api && ./$(VENV_PY) -m ruff check .
	@command -v flutter >/dev/null 2>&1 || { echo "Flutter o'rnatilmagan"; exit 1; }
	cd apps/mobile && dart analyze

format: ## Kodni avtomatik formatlash: ruff format + dart format
	@[ -f apps/api/$(VENV_PY) ] || { echo "apps/api/.venv topilmadi — avval ishga tushiring: make api-install"; exit 1; }
	cd apps/api && ./$(VENV_PY) -m ruff format .
	@command -v flutter >/dev/null 2>&1 || { echo "Flutter o'rnatilmagan"; exit 1; }
	cd apps/mobile && dart format .

l10n: ## Tarjima (.arb) fayllarini tekshirish (uz/uz_Cyrl/ru/en to'liqligi)
	node apps/mobile/tool/check_l10n.mjs

# --- Housekeeping --------------------------------------------------------------

clean: ## Kesh va vaqtinchalik fayllarni tozalash (.venv'ga tegilmaydi)
	rm -rf apps/api/.pytest_cache apps/api/.ruff_cache apps/api/.mypy_cache
	find apps/api -type d -name __pycache__ -prune -exec rm -rf {} +
	rm -rf apps/mobile/.dart_tool apps/mobile/build
	@echo "Tozalandi."
