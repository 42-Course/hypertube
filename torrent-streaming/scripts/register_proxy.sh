#!/usr/bin/env bash
# Registers (or refreshes) the kamal-proxy route that exposes the streaming
# `web` service at https://stream.fractalia.art with Let's Encrypt TLS.
#
# kamal-proxy is the reverse proxy the API's Kamal deploy runs on the host. We
# add a route for our own (non-Kamal) container by pointing the proxy at the
# `streaming-web` network alias on the shared `kamal` network. The web container
# must already be running and attached to that network (deploy_prod.sh does this).
#
# Idempotent: safe to re-run. MUST be re-run if kamal-proxy is ever rebooted
# (`kamal proxy reboot`), which clears manually-registered routes.
#
# Usage:
#   ./scripts/register_proxy.sh
# Overridable via env: PROXY_CONTAINER, STREAM_HOST, TARGET, HEALTH_CHECK_PATH.
set -euo pipefail

PROXY_CONTAINER="${PROXY_CONTAINER:-kamal-proxy}"
SERVICE_NAME="${SERVICE_NAME:-streaming-web}"
STREAM_HOST="${STREAM_HOST:-stream.fractalia.art}"
TARGET="${TARGET:-streaming-web:4567}"
HEALTH_CHECK_PATH="${HEALTH_CHECK_PATH:-/health/ready}"

if ! docker ps --format '{{.Names}}' | grep -qx "$PROXY_CONTAINER"; then
  echo "ERROR: kamal-proxy container '$PROXY_CONTAINER' is not running." >&2
  echo "Deploy the Hypertube API with Kamal first, or set PROXY_CONTAINER." >&2
  exit 1
fi

echo "==> kamal-proxy deploy $SERVICE_NAME -> $TARGET (host $STREAM_HOST, TLS)"
docker exec "$PROXY_CONTAINER" kamal-proxy deploy "$SERVICE_NAME" \
  --target "$TARGET" \
  --host "$STREAM_HOST" \
  --tls \
  --health-check-path "$HEALTH_CHECK_PATH"

echo "==> Route registered. Verify: curl -fsS https://$STREAM_HOST/health/ready"
