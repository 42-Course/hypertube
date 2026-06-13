.PHONY: help build up down restart bash console migrate rollback routes \
        test coverage logs seed generate db-reset db-create db-drop \
        setup-front front-install lint-api \
        prod-bundle prod-login prod-build prod-push \
        kamal-setup kamal-deploy kamal-rollback

COMPOSE      = docker compose
BACKEND_SVC  = backend
# DC_RUN spins up a throwaway container (use when the service may be down, e.g.
# bundle install). DC_EXEC reuses the already-running container (`make up`)
# instead of recreating one each time.
DC_RUN       = $(COMPOSE) run --rm $(BACKEND_SVC)
DC_EXEC      = $(COMPOSE) exec $(BACKEND_SVC)
# Runs *inside* the container, so it must not re-invoke docker compose.
BUNDLE_EXEC  = bundle exec
RAILS        = $(DC_EXEC) $(BUNDLE_EXEC) rails

# ── Production ────────────────────────────────────────────────────────────────
GHCR_USER   = 42-course
PROD_IMAGE  = ghcr.io/$(GHCR_USER)/hypertube-api
GIT_SHA     = $(shell git rev-parse HEAD)

# Kamal runs inside the dev container (no local Ruby needed).
# Build/push use Podman directly; deploy uses --skip-push so no local daemon.
KAMAL = $(COMPOSE) run --no-deps --rm \
          -v $(HOME)/.ssh:/root/.ssh:ro \
          $(BACKEND_SVC) bundle exec kamal
RSPEC        = $(DC_EXEC) $(BUNDLE_EXEC) rspec

# ─── Help ────────────────────────────────────────────────────────────────────
help:
	@printf "\n\033[1mHypertube – Available Make Targets\033[0m\n\n"
	@printf "  \033[36mSetup\033[0m\n"
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
	@printf "    make docs           Run Swagger and generate docs\n"
	@printf "    make test           Run RSpec test suite\n"
	@printf "    make coverage       Run RSpec with SimpleCov HTML report\n"
	@printf "\n  \033[36mFrontend\033[0m\n"
	@printf "    make setup-front    Install frontend dependencies (bun)\n"
	@printf "\n  \033[36mProduction (Kamal → fractalia.art)\033[0m\n"
	@printf "    make kamal-setup    First-time server provisioning (run once)\n"
	@printf "    make kamal-deploy   Deploy image built by CI for current commit\n"
	@printf "    make kamal-rollback Roll back to previous release\n"
	@printf "    make prod-push      Emergency: build + push image locally\n"
	@printf "\n"

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
docs:
	$(RAILS) rswag:specs:swaggerize

test:
	$(COMPOSE) exec -e RAILS_ENV=test $(BACKEND_SVC) bundle exec rspec

coverage:
	$(COMPOSE) exec -e RAILS_ENV=test $(BACKEND_SVC) bash -c "COVERAGE=true bundle exec rspec --format documentation"
	@echo "\033[1mCoverage report generated at api/coverage/index.html\033[0m"

# ─── Frontend ────────────────────────────────────────────────────────────────
setup-front:
	cd web && bun install

# ─── Production / Kamal ──────────────────────────────────────────────────────
# CI/CD (cd.yml) owns building and pushing the image on every push to main.
# These targets assume the image is already in the registry.

# Install kamal + thruster gems into the dev container's bundle cache.
# Run once after adding them to the Gemfile.
prod-bundle:
	$(DC_RUN) bundle install

# ── Emergency / local-only image management ───────────────────────────────────
# Use these only when you need to push an image outside of CI (e.g. hotfix).
prod-login:
	@sed -n 's/^KAMAL_REGISTRY_PASSWORD=//p' api/.kamal/secrets | \
	  docker login ghcr.io -u $(GHCR_USER) --password-stdin

prod-build:
	docker build -f api/Dockerfile \
	  -t $(PROD_IMAGE):$(GIT_SHA) \
	  -t $(PROD_IMAGE):latest \
	  api/

prod-push: prod-login prod-build
	docker push $(PROD_IMAGE):$(GIT_SHA)
	docker push $(PROD_IMAGE):latest

# ── Kamal deployment ──────────────────────────────────────────────────────────
# First-time server provisioning: installs Docker, starts proxy + accessories.
# Push to main first so CI builds the image, then run this.
kamal-setup:
	ssh-keyscan -H 167.71.57.19 >> $(HOME)/.ssh/known_hosts 2>/dev/null || true
	$(KAMAL) setup --skip-push

# Deploy the image that CI already built and pushed for the current commit.
kamal-deploy:
	$(KAMAL) deploy --skip-push

# Roll back to the previous release.
kamal-rollback:
	$(KAMAL) rollback
