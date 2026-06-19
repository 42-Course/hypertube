.PHONY: help build up down restart bash console migrate rollback routes \
        test coverage logs seed generate db-reset db-create db-drop \
        setup-front front-install lint-api \
        prod-bundle prod-login prod-build prod-push \
        kamal-setup kamal-deploy kamal-rollback \
        tracker-build tracker-push tracker-deploy tracker-status \
        tracker-logs tracker-reload tracker-rollback

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
TRACKER_IMAGE = ghcr.io/$(GHCR_USER)/opentracker
GIT_SHA     = $(shell git rev-parse HEAD)

# Kamal runs inside the dev container (no local Ruby needed).
# Build/push use Podman directly; deploy uses --skip-push so no local daemon.
KAMAL = $(COMPOSE) run --no-deps --rm \
          -v $(HOME)/.ssh:/root/.ssh:ro \
          $(BACKEND_SVC) bundle exec kamal

# Same idea for the tracker, which is a SEPARATE Kamal project under tracker/.
# We mount the whole repo (kamal derives the image tag from the git SHA) and reuse
# the api's installed kamal gem via BUNDLE_GEMFILE. GIT_CONFIG_* marks the mounted
# repo as safe since the container runs as root over a host-owned checkout.
KAMAL_TRACKER = $(COMPOSE) run --no-deps --rm \
          -v $(HOME)/.ssh:/root/.ssh:ro \
          -v $(CURDIR):/workspace -w /workspace/tracker \
          -e BUNDLE_GEMFILE=/app/Gemfile \
          -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
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
	@printf "\n  \033[36mTracker (opentracker → opentracker.fractalia.art)\033[0m\n"
	@printf "    make tracker-deploy   Build + push + deploy the tracker\n"
	@printf "    make tracker-status   Show container + proxy/cert status\n"
	@printf "    make tracker-logs     Follow tracker logs\n"
	@printf "    make tracker-reload   Live-reload whitelist (SIGHUP)\n"
	@printf "    make tracker-rollback Roll back the tracker\n"
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

# ── opentracker (private BitTorrent tracker → opentracker.fractalia.art) ───────
# Separate Kamal app sharing the same droplet + kamal-proxy as the api.
# HTTPS announce via the proxy; UDP announce published directly on 6969.
# Source is vendored in tracker/vendor/ so the image build needs no internet
# beyond the Alpine package mirror. See tracker/README.md for the full workflow.

# Build the opentracker image on host docker, tagged with the current git SHA
# (kamal deploys that exact tag) and latest.
tracker-build:
	docker build -f tracker/Dockerfile \
	  -t $(TRACKER_IMAGE):$(GIT_SHA) \
	  -t $(TRACKER_IMAGE):latest \
	  tracker/

# Build + push the image to GHCR (reuses the api's registry login).
tracker-push: prod-login tracker-build
	docker push $(TRACKER_IMAGE):$(GIT_SHA)
	docker push $(TRACKER_IMAGE):latest

# Build, push, then deploy the tracker (kamal pulls the SHA tag on the server).
# First run also registers opentracker.fractalia.art with the shared proxy and
# triggers its Let's Encrypt cert (DNS + UDP firewall must be in place first).
#
# We remove the old container BEFORE booting the new one: opentracker publishes
# UDP 6969 directly on the host (an exclusive port), so kamal's default
# new-alongside-old rollout can't bind it ("port already allocated"). The swap
# costs a few seconds of downtime — fine for a tracker, clients just re-announce.
# The `-` lets the first deploy (nothing to remove) proceed.
tracker-deploy: tracker-push
	-$(KAMAL_TRACKER) app remove
	$(KAMAL_TRACKER) deploy --skip-push

# Show the running container + proxy/cert routing for the tracker.
tracker-status:
	$(KAMAL_TRACKER) app details
	$(KAMAL_TRACKER) proxy details

# Follow tracker logs.
tracker-logs:
	$(KAMAL_TRACKER) app logs -f

# Live-reload the whitelist (SIGHUP) without a redeploy — use after editing the
# whitelist on the server; for git-tracked changes prefer `make tracker-deploy`.
tracker-reload:
	$(KAMAL_TRACKER) app exec --reuse "kill -HUP 1"

# Roll the tracker back to its previous release.
tracker-rollback:
	$(KAMAL_TRACKER) rollback
