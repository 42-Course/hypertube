# Stable command surface for building, running, testing, and cleaning the POC.
# Targets wrap Docker Compose with consistent UID/GID build args, storage setup,
# and explicit safety gates for destructive or external-network operations.
.DEFAULT_GOAL := help

# Docker Compose command used by every target.
COMPOSE ?= docker compose
# Full Compose command for development mode with the override file.
COMPOSE_DEV ?= docker compose -f docker-compose.yml -f docker-compose.dev.yml
# Full Compose command for production mode (baked images, kamal-proxy ingress).
PROD_ENV_FILE ?= .env.production
COMPOSE_PROD ?= docker compose --env-file $(PROD_ENV_FILE) -f docker-compose.yml -f docker-compose.prod.yml
# UID/GID used to build the non-root application user inside images.
APP_UID ?= 10001
APP_GID ?= 10001
COMPOSE_ENV = APP_UID=$(APP_UID) APP_GID=$(APP_GID)
# Web port exposed on the host.
WEB_PORT ?= 4567
# Range-server port exposed on the host in development mode only.
RANGE_SERVER_PORT ?= 7001
# BitTorrent port exposed on the host in development mode only.
BITTORRENT_PORT ?= 6881
# Optional libtorrent listen interface, for example: 192.168.32.3:6881.
BITTORRENT_LISTEN_INTERFACES ?=
# Optional DHT routers, separated by commas.
BITTORRENT_DHT_ROUTERS ?=
# Development range-server discovery profile: standard or aggressive.
BITTORRENT_DISCOVERY_PROFILE ?= standard
# BITTORRENT_DISCOVERY_PROFILE ?= aggressive
# Development range-server cache mode: readwrite or off.
RANGE_SERVER_CACHE_MODE ?= readwrite
# Target service for logs and shell commands, for example: SERVICE=web.
SERVICE ?=
# Automatically discovered Ruby test files.
RUBY_TESTS := $(wildcard tests/ruby/test_*.rb)

.PHONY: help run up start build stop down restart ps logs logs-error logs-web logs-range logs-api logs-workers health shell dev dev-start dev-restart dev-logs dev-logs-error dev-ps dev-stop dev-down prod-deploy-remote prod-deploy prod-start prod-proxy prod-ps prod-logs prod-logs-error prod-down test test-smoke test-fast test-python test-ruby test-js test-compose test-syntax test-real clean clean-all storage-dirs storage-permissions

# Prints available commands and useful examples.
help:
	@printf "\n"
	@printf "Makefile du projet Real POC Torrent Streaming\n"
	@printf "================================================\n"
	@printf "\n"
	@printf "Usage rapide:\n"
	@printf "  make run                         Lance tout le projet avec build\n"
	@printf "  make start                       Lance tout sans rebuild\n"
	@printf "  make logs                        Suit tous les logs\n"
	@printf "  make logs-error                  Suit stderr uniquement, tous services\n"
	@printf "  make logs SERVICE=web            Suit les logs d'un service precis\n"
	@printf "  make ps                          Affiche l'etat des services\n"
	@printf "  make stop                        Arrete les containers\n"
	@printf "\n"
	@printf "Application:\n"
	@printf "  URL par defaut:                  http://localhost:$(WEB_PORT)\n"
	@printf "  Autre port:                      make run WEB_PORT=4570\n"
	@printf "  Range-server dev:                http://localhost:$(RANGE_SERVER_PORT)\n"
	@printf "  BitTorrent dev:                  tcp/udp localhost:$(BITTORRENT_PORT)\n"
	@printf "\n"
	@printf "Commandes principales:\n"
	@printf "  make build                       Construit les images Docker\n"
	@printf "  make run                         Build + demarrage + attente healthchecks\n"
	@printf "  make start                       Demarrage sans rebuild + attente healthchecks\n"
	@printf "  make restart                     Redemarre les services applicatifs\n"
	@printf "  make health                      Verifie les healthchecks internes\n"
	@printf "  make shell SERVICE=web           Ouvre un shell dans un service\n"
	@printf "\n"
	@printf "Mode dev avec code monte en volume:\n"
	@printf "  make dev                         Lance en dev avec rebuild si besoin\n"
	@printf "  make dev APP_UID=\"\$$(id -u)\" APP_GID=\"\$$(id -g)\"  Dev Linux avec bind mounts\n"
	@printf "  make dev RANGE_SERVER_PORT=7001  Lance en dev si le port 7000 est occupe\n"
	@printf "  make dev BITTORRENT_PORT=6882    Lance en dev si le port 6881 est occupe\n"
	@printf "  make dev BITTORRENT_LISTEN_INTERFACES=192.168.32.3:6881\n"
	@printf "  make dev RANGE_SERVER_CACHE_MODE=off  Lance avec cold start strict\n"
	@printf "  make dev-start                   Lance en dev sans rebuild\n"
	@printf "  make dev-restart                 Redemarre tous les services dev\n"
	@printf "  make dev-restart SERVICE=web     Redemarre seulement un service dev\n"
	@printf "  make dev-logs                    Suit les logs dev\n"
	@printf "  make dev-logs-error              Suit stderr dev uniquement\n"
	@printf "  make dev-logs SERVICE=web        Suit les logs dev d'un service\n"
	@printf "  make dev-down                    Arrete le mode dev avec compose down\n"
	@printf "  make dev-stop                    Alias de make dev-down\n"
	@printf "\n"
	@printf "Mode production (Compose-on-host + kamal-proxy):\n"
	@printf "  make prod-deploy-remote          Depuis le laptop: rsync + deploy via SSH\n"
	@printf "  make prod-deploy                 Sur le serveur: storage + build + up + proxy\n"
	@printf "  make prod-start                  Demarre sans rebuild\n"
	@printf "  make prod-proxy                  Re-enregistre la route stream.fractalia.art\n"
	@printf "  make prod-ps                     Etat des services prod\n"
	@printf "  make prod-logs SERVICE=web       Suit les logs prod\n"
	@printf "  make prod-down                   Arrete la stack prod (garde le storage)\n"
	@printf "\n"
	@printf "Tests et verification:\n"
	@printf "  make test                        Lance les tests rapides locaux\n"
	@printf "  make test-smoke                  Lance le smoke Docker complet\n"
	@printf "  make test-fast                   Alias des tests locaux rapides\n"
	@printf "  make test-python                 Tests Python range-server\n"
	@printf "  make test-ruby                   Tests Ruby\n"
	@printf "  make test-js                     Tests JavaScript du player\n"
	@printf "  make test-compose                Contrats docker-compose\n"
	@printf "  make test-syntax                 Checks syntaxe shell/ruby/js\n"
	@printf "  make test-real                   Scenario torrent reel opt-in\n"
	@printf "\n"
	@printf "Nettoyage:\n"
	@printf "  make clean                       Arrete Compose et retire les containers orphelins\n"
	@printf "  make clean-all CONFIRM=1         Supprime aussi videos, HLS, etat, logs locaux\n"
	@printf "  make storage-permissions         Affiche les commandes permissions Linux utiles\n"
	@printf "\n"
	@printf "Services utiles pour SERVICE=...:\n"
	@printf "  web, range-server, transcoder-api, transcoder-worker-interactive,\n"
	@printf "  transcoder-worker-vod, redis\n"
	@printf "\n"

# Creates the runtime directories expected by Docker Compose.
storage-dirs:
	@mkdir -p storage/state/media storage/state/sessions storage/state/locks storage/state/corrupt
	@mkdir -p storage/torrents storage/libtorrent storage/hls/sessions storage/hls/vod storage/logs

# Prints diagnostic permission commands for native Linux bind mounts.
storage-permissions:
	@printf "UID/GID container cible: $(APP_UID):$(APP_GID)\n"
	@printf "Commandes Linux optionnelles si les bind mounts existants bloquent l'ecriture:\n"
	@printf "  sudo chown -R $(APP_UID):$(APP_GID) storage/torrents storage/libtorrent storage/logs\n"
	@printf "  sudo chown -R $(APP_UID):$(APP_GID) storage/hls\n"
	@printf "  sudo chown -R $(APP_UID):$(APP_GID) storage/state\n"
	@printf "Aucun chown n'est lance par le Makefile.\n"

# Builds the project's Docker images.
build:
	$(COMPOSE_ENV) $(COMPOSE) build

# Starts the whole project with rebuilds and waits for healthchecks.
run: storage-dirs
	$(COMPOSE_ENV) WEB_PORT=$(WEB_PORT) $(COMPOSE) up -d --build
	@printf "\nProjet lance: http://localhost:$(WEB_PORT)\n"

# Convenience alias for make run.
up: run

# Starts the whole project without rebuilding and waits for healthchecks.
start: storage-dirs
	$(COMPOSE_ENV) WEB_PORT=$(WEB_PORT) $(COMPOSE) up -d
	@printf "\nProjet lance: http://localhost:$(WEB_PORT)\n"

# Stops Compose containers and removes orphans.
stop:
	$(COMPOSE) down --remove-orphans

# Convenience alias for make stop.
down: stop

# Restarts application services and then waits for readiness.
restart:
	$(COMPOSE) restart redis range-server transcoder-api transcoder-worker-interactive transcoder-worker-vod web
	$(COMPOSE_ENV) $(COMPOSE) up -d

# Shows Compose service status.
ps:
	$(COMPOSE) ps

# Follows all logs, or one service log with SERVICE=name.
logs:
	@if [ -n "$(SERVICE)" ]; then \
		$(COMPOSE) logs -f "$(SERVICE)"; \
	else \
		$(COMPOSE) logs -f; \
	fi

# Follows only stderr from all active Compose containers.
logs-error:
	@containers="$$($(COMPOSE) ps -q)"; \
	if [ -z "$$containers" ]; then \
		printf "Aucun container actif. Lance d'abord make run ou make start.\n"; \
		exit 1; \
	fi; \
	printf "%s\n" "$$containers" | xargs -n 1 -P 8 docker logs -f 1>/dev/null

# Follows web service logs.
logs-web:
	$(COMPOSE) logs -f web

# Follows range-server logs.
logs-range:
	$(COMPOSE) logs -f range-server

# Follows transcoder API logs.
logs-api:
	$(COMPOSE) logs -f transcoder-api

# Follows logs from both transcoder workers.
logs-workers:
	$(COMPOSE) logs -f transcoder-worker-interactive transcoder-worker-vod

# Checks internal readiness endpoints plus libtorrent importability.
health:
	$(COMPOSE) exec -T web curl -fsS http://localhost:4567/health/ready
	$(COMPOSE) exec -T transcoder-api curl -fsS http://localhost:4568/health/ready
	$(COMPOSE) exec -T range-server curl -fsS http://localhost:7000/health/ready
	$(COMPOSE) exec -T redis redis-cli ping
	$(COMPOSE) exec -T range-server python3 -c 'import libtorrent'

# Opens a shell in the service selected with SERVICE=name.
shell:
	@if [ -z "$(SERVICE)" ]; then \
		printf "Indique un service, exemple: make shell SERVICE=web\n"; \
		exit 1; \
	fi
	$(COMPOSE) exec "$(SERVICE)" sh

# Starts development mode with local source mounted and rebuilds if needed.
dev: storage-dirs
	$(COMPOSE_ENV) WEB_PORT=$(WEB_PORT) RANGE_SERVER_PORT=$(RANGE_SERVER_PORT) BITTORRENT_PORT=$(BITTORRENT_PORT) BITTORRENT_LISTEN_INTERFACES="$(BITTORRENT_LISTEN_INTERFACES)" BITTORRENT_DHT_ROUTERS="$(BITTORRENT_DHT_ROUTERS)" BITTORRENT_DISCOVERY_PROFILE="$(BITTORRENT_DISCOVERY_PROFILE)" RANGE_SERVER_CACHE_MODE="$(RANGE_SERVER_CACHE_MODE)" $(COMPOSE_DEV) up -d --build
	@printf "\nMode dev lance: http://localhost:$(WEB_PORT)\n"
	@printf "Range-server dev: http://localhost:$(RANGE_SERVER_PORT)\n"
	@printf "BitTorrent dev: tcp/udp localhost:$(BITTORRENT_PORT)\n"
	@printf "Range discovery: $(BITTORRENT_DISCOVERY_PROFILE), cache: $(RANGE_SERVER_CACHE_MODE)\n"

# Starts development mode without rebuilding, using existing images.
dev-start: storage-dirs
	$(COMPOSE_ENV) WEB_PORT=$(WEB_PORT) RANGE_SERVER_PORT=$(RANGE_SERVER_PORT) BITTORRENT_PORT=$(BITTORRENT_PORT) BITTORRENT_LISTEN_INTERFACES="$(BITTORRENT_LISTEN_INTERFACES)" BITTORRENT_DHT_ROUTERS="$(BITTORRENT_DHT_ROUTERS)" BITTORRENT_DISCOVERY_PROFILE="$(BITTORRENT_DISCOVERY_PROFILE)" RANGE_SERVER_CACHE_MODE="$(RANGE_SERVER_CACHE_MODE)" $(COMPOSE_DEV) up -d
	@printf "\nMode dev lance: http://localhost:$(WEB_PORT)\n"
	@printf "Range-server dev: http://localhost:$(RANGE_SERVER_PORT)\n"
	@printf "BitTorrent dev: tcp/udp localhost:$(BITTORRENT_PORT)\n"
	@printf "Range discovery: $(BITTORRENT_DISCOVERY_PROFILE), cache: $(RANGE_SERVER_CACHE_MODE)\n"

# Restarts one development service, or all services when SERVICE is empty.
dev-restart:
	@if [ -n "$(SERVICE)" ]; then \
		$(COMPOSE_DEV) restart "$(SERVICE)"; \
	else \
		$(COMPOSE_DEV) restart redis range-server transcoder-api transcoder-worker-interactive transcoder-worker-vod web; \
		$(COMPOSE_ENV) WEB_PORT=$(WEB_PORT) RANGE_SERVER_PORT=$(RANGE_SERVER_PORT) BITTORRENT_PORT=$(BITTORRENT_PORT) BITTORRENT_LISTEN_INTERFACES="$(BITTORRENT_LISTEN_INTERFACES)" BITTORRENT_DHT_ROUTERS="$(BITTORRENT_DHT_ROUTERS)" BITTORRENT_DISCOVERY_PROFILE="$(BITTORRENT_DISCOVERY_PROFILE)" RANGE_SERVER_CACHE_MODE="$(RANGE_SERVER_CACHE_MODE)" $(COMPOSE_DEV) up -d; \
	fi

# Follows development logs, or one service log with SERVICE=name.
dev-logs:
	@if [ -n "$(SERVICE)" ]; then \
		$(COMPOSE_DEV) logs -f "$(SERVICE)"; \
	else \
		$(COMPOSE_DEV) logs -f; \
	fi

# Follows only stderr from all active development containers.
dev-logs-error:
	@containers="$$($(COMPOSE_DEV) ps -q)"; \
	if [ -z "$$containers" ]; then \
		printf "Aucun container dev actif. Lance d'abord make dev ou make dev-start.\n"; \
		exit 1; \
	fi; \
	printf "%s\n" "$$containers" | xargs -n 1 -P 8 docker logs -f 1>/dev/null

# Shows development service status.
dev-ps:
	$(COMPOSE_DEV) ps

# Stops development mode with Compose down and removes orphans.
dev-down:
	$(COMPOSE_DEV) down --remove-orphans

# Convenience alias for make dev-down.
dev-stop: dev-down

# --- Production (Compose-on-host + kamal-proxy) -------------------------------
# From the laptop: push source + .env.production to the host and deploy there.
prod-deploy-remote:
	./scripts/deploy_remote.sh

# On the deploy host: prepares storage, builds, starts the stack, registers the
# proxy. Run from this directory after filling in .env.production.
prod-deploy:
	./scripts/deploy_prod.sh

# Starts the production stack without rebuilding and waits for healthchecks.
prod-start:
	$(COMPOSE_PROD) up -d

# (Re-)registers the stream.fractalia.art route with kamal-proxy. Re-run this
# after any `kamal proxy reboot`, which clears manual routes.
prod-proxy:
	./scripts/register_proxy.sh

# Shows production service status.
prod-ps:
	$(COMPOSE_PROD) ps

# Follows production logs, or one service log with SERVICE=name.
prod-logs:
	@if [ -n "$(SERVICE)" ]; then \
		$(COMPOSE_PROD) logs -f "$(SERVICE)"; \
	else \
		$(COMPOSE_PROD) logs -f; \
	fi

# Follows only stderr from all active production containers.
prod-logs-error:
	@containers="$$($(COMPOSE_PROD) ps -q)"; \
	if [ -z "$$containers" ]; then \
		printf "Aucun container prod actif. Lance d'abord make prod-deploy.\n"; \
		exit 1; \
	fi; \
	printf "%s\n" "$$containers" | xargs -n 1 -P 8 docker logs -f 1>/dev/null

# Stops the production stack (keeps runtime storage on the host).
prod-down:
	$(COMPOSE_PROD) down --remove-orphans

# Runs the fast local test set.
test: test-fast

# Runs all fast local tests except the Docker smoke test.
test-fast: test-syntax test-compose test-python test-ruby test-js

# Runs the full Docker smoke test with Compose startup.
test-smoke:
	$(COMPOSE_ENV) tests/smoke/compose_runtime_smoke.sh

# Checks Docker Compose contracts.
test-compose:
	python3 tests/smoke/test_compose_contracts.py

# Runs range-server Python tests.
test-python:
	python3 -m unittest discover -s tests/python -p 'test_*.py'

# Runs each Ruby test discovered in tests/ruby.
test-ruby:
	@for test_file in $(RUBY_TESTS); do \
		printf "\nRuby: %s\n" "$$test_file"; \
		ruby -Ishared/ruby/lib "$$test_file"; \
	done

# Checks and tests the player JavaScript.
test-js:
	node -c services/web/public/player.js
	node --test tests/js/test_player_ui.js

# Checks shell, Ruby, and JavaScript syntax.
test-syntax:
	bash -n tests/smoke/compose_runtime_smoke.sh
	bash -n tests/smoke/real_magnet_e2e.sh
	ruby -c services/web/app.rb
	ruby -c services/transcoder-api/app.rb
	ruby -c services/transcoder-worker/worker.rb
	node -c services/web/public/player.js

# Runs the real-torrent scenario only after explicit opt-in because it depends
# on external fixtures, tracker/DHT egress, peers, and local disk.
test-real:
	@if [ "$(ALLOW_EXTERNAL_TORRENT_TESTS)" != "1" ] || [ "$(CONFIRM_EXTERNAL_TORRENT_FIXTURES)" != "1" ]; then \
		printf "Scenario reel bloque par securite.\n"; \
		printf "Relance avec:\n"; \
		printf "  make test-real ALLOW_EXTERNAL_TORRENT_TESTS=1 CONFIRM_EXTERNAL_TORRENT_FIXTURES=1\n"; \
		exit 1; \
	fi
	ALLOW_EXTERNAL_TORRENT_TESTS=1 CONFIRM_EXTERNAL_TORRENT_FIXTURES=1 tests/smoke/real_magnet_e2e.sh

# Stops Compose without deleting runtime data.
clean:
	$(COMPOSE) down --remove-orphans

# Deletes generated runtime data only after a confirmation variable is set.
# The versioned storage directory shape and .gitkeep placeholders are preserved.
clean-all:
	@if [ "$(CONFIRM)" != "1" ]; then \
		printf "\nCette cible supprime les videos telechargees, HLS, etats et logs locaux.\n"; \
		printf "Relance volontairement avec: make clean-all CONFIRM=1\n\n"; \
		exit 1; \
	fi
	$(COMPOSE) down --remove-orphans
	find storage/state/media -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +
	find storage/state/sessions -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +
	find storage/state/locks -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +
	find storage/state/corrupt -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +
	find storage/torrents -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +
	find storage/libtorrent -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +
	find storage/hls/sessions -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +
	find storage/hls/vod -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +
	find storage/logs -mindepth 1 -maxdepth 1 ! -name .gitkeep -exec rm -rf {} +
	@printf "\nNettoyage complet termine. L'arborescence storage/ est conservee.\n"


range-server:
	$(COMPOSE_ENV) RANGE_SERVER_PORT=7001 $(COMPOSE_DEV) up range-server


range-server-reset:
	make clean-all CONFIRM=1
	make range-server
