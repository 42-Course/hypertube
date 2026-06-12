.PHONY: help init build up down restart bash console migrate rollback routes \
        test coverage logs seed generate db-reset db-create db-drop \
        setup-front front-install lint-api

COMPOSE      = docker compose
BACKEND_SVC  = backend
DC_RUN       = $(COMPOSE) run --rm $(BACKEND_SVC)
DC_EXEC      = $(COMPOSE) exec $(BACKEND_SVC)
RAILS        = $(DC_EXEC) bundle exec rails
RSPEC        = $(DC_EXEC) bundle exec rspec

# ─── Help ────────────────────────────────────────────────────────────────────
help:
	@printf "\n\033[1mHypertube – Available Make Targets\033[0m\n\n"
	@printf "  \033[36mSetup\033[0m\n"
	@printf "    make init           First-time project bootstrap (build + rails new + gems)\n"
	@printf "    make build          Rebuild Docker images\n"
	@printf "\n  \033[36mServices\033[0m\n"
	@printf "    make up             Start all services (background)\n"
	@printf "    make down           Stop all services\n"
	@printf "    make restart        Restart backend service\n"
	@printf "    make logs           Follow backend logs\n"
	@printf "\n  \033[36mRails\033[0m\n"
	@printf "    make bash           Open bash shell in backend container\n"
	@printf "    make console        Open Rails console\n"
	@printf "    make routes         List all routes\n"
	@printf "    make generate g=X   Run 'rails generate X'\n"
	@printf "\n  \033[36mDatabase\033[0m\n"
	@printf "    make migrate        Run pending migrations\n"
	@printf "    make rollback       Rollback last migration\n"
	@printf "    make seed           Run db/seeds.rb\n"
	@printf "    make db-create      Create the database\n"
	@printf "    make db-drop        Drop the database\n"
	@printf "    make db-reset       Drop + create + migrate + seed\n"
	@printf "\n  \033[36mTesting\033[0m\n"
	@printf "    make test           Run RSpec test suite\n"
	@printf "    make coverage       Run RSpec with SimpleCov HTML report\n"
	@printf "\n  \033[36mFrontend\033[0m\n"
	@printf "    make setup-front    Install frontend dependencies (bun)\n"
	@printf "\n"

# ─── Setup ───────────────────────────────────────────────────────────────────
init:
	@echo "\033[1m==> Building Docker image...\033[0m"
	$(COMPOSE) build
	@echo "\033[1m==> Running bootstrap script...\033[0m"
	$(DC_RUN) bash /app/init.sh
	@echo "\033[1m==> Done! Run 'make up' to start all services.\033[0m"

build:
	$(COMPOSE) build

# ─── Services ────────────────────────────────────────────────────────────────
up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart $(BACKEND_SVC)

logs:
	$(COMPOSE) logs -f $(BACKEND_SVC)

# ─── Rails ───────────────────────────────────────────────────────────────────
bash:
	$(DC_EXEC) bash

console:
	$(RAILS) console

routes:
	$(RAILS) routes

generate:
	$(RAILS) generate $(g)

# ─── Database ────────────────────────────────────────────────────────────────
migrate:
	$(RAILS) db:migrate

rollback:
	$(RAILS) db:rollback

seed:
	$(RAILS) db:seed

db-create:
	$(RAILS) db:create

db-drop:
	$(RAILS) db:drop

db-reset:
	$(RAILS) db:drop db:create db:migrate db:seed

# ─── Testing ─────────────────────────────────────────────────────────────────
test:
	$(RSPEC)

coverage:
	$(DC_EXEC) bash -c "COVERAGE=true bundle exec rspec --format documentation"
	@echo "\033[1mCoverage report generated at api/coverage/index.html\033[0m"

# ─── Frontend ────────────────────────────────────────────────────────────────
setup-front:
	cd web && bun install
