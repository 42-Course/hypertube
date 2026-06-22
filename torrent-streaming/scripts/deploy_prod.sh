#!/usr/bin/env bash
# Deploys the torrent streaming stack in production ("Compose-on-host" model).
#
# Runs the whole mesh as a Compose project on the deploy host and attaches the
# public `web` service to the Kamal-managed `kamal` network so kamal-proxy can
# terminate TLS for stream.fractalia.art (see register_proxy.sh). This is NOT a
# Kamal app — the API must already be deployed (it creates the `kamal` network).
#
# Usage (on the deploy host, from the torrent-streaming directory):
#   cp .env.production.example .env.production   # then fill it in
#   ./scripts/deploy_prod.sh
#
# Re-run any time to roll out rebuilt images.
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE=".env.production"
KAMAL_NETWORK="${KAMAL_NETWORK:-kamal}"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f docker-compose.yml -f docker-compose.prod.yml)

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.production.example and fill it in." >&2
  exit 1
fi

# Load env so we can resolve STREAMING_STORAGE_ROOT / APP_UID / APP_GID here.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${STREAM_TICKET_SECRET:?STREAM_TICKET_SECRET must be set in $ENV_FILE}"
STORAGE_ROOT="${STREAMING_STORAGE_ROOT:?STREAMING_STORAGE_ROOT must be set in $ENV_FILE}"
APP_UID="${APP_UID:-10001}"
APP_GID="${APP_GID:-10001}"

# The shared network is created by the API's Kamal deploy. Fail early with a
# clear message rather than a confusing Compose error if it is missing.
if ! docker network inspect "$KAMAL_NETWORK" >/dev/null 2>&1; then
  echo "ERROR: Docker network '$KAMAL_NETWORK' does not exist." >&2
  echo "Deploy the Hypertube API with Kamal first (it creates this network)," >&2
  echo "or set KAMAL_NETWORK to the correct name." >&2
  exit 1
fi

echo "==> Ensuring storage tree under $STORAGE_ROOT (owner $APP_UID:$APP_GID)"
sudo mkdir -p \
  "$STORAGE_ROOT"/state/media \
  "$STORAGE_ROOT"/state/sessions \
  "$STORAGE_ROOT"/state/locks \
  "$STORAGE_ROOT"/state/corrupt \
  "$STORAGE_ROOT"/torrents \
  "$STORAGE_ROOT"/libtorrent \
  "$STORAGE_ROOT"/hls/sessions \
  "$STORAGE_ROOT"/hls/vod \
  "$STORAGE_ROOT"/logs
sudo chown -R "$APP_UID:$APP_GID" "$STORAGE_ROOT"

echo "==> Building images"
APP_UID="$APP_UID" APP_GID="$APP_GID" "${COMPOSE[@]}" build

echo "==> Starting stack and waiting for healthchecks"
APP_UID="$APP_UID" APP_GID="$APP_GID" "${COMPOSE[@]}" up -d --wait

echo "==> Registering kamal-proxy route for stream.fractalia.art"
./scripts/register_proxy.sh

echo
echo "Done. Streaming stack is up. Public URL: https://stream.fractalia.art"
"${COMPOSE[@]}" ps
