#!/usr/bin/env bash
# Pushes the streaming service from this laptop to the deploy host and runs the
# production deploy there over SSH.
#
# It rsyncs the source (excluding the huge storage tree and .git) PLUS the local
# .env.production (which is gitignored and not on the host), then runs
# `make prod-deploy` on the host via SSH.
#
# Usage (from the torrent-streaming directory, with .env.production filled in):
#   ./scripts/deploy_remote.sh
#
# Overridable via env:
#   REMOTE_HOST (default 167.71.57.19)  REMOTE_USER (default root)
#   REMOTE_DIR  (default /opt/hypertube/torrent-streaming)
#   KAMAL_NETWORK (passed through to the host deploy if the Kamal network is not
#                  named "kamal")
set -euo pipefail

cd "$(dirname "$0")/.."

REMOTE_HOST="${REMOTE_HOST:-167.71.57.19}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_DIR="${REMOTE_DIR:-/opt/hypertube/torrent-streaming}"
SSH_DEST="${REMOTE_USER}@${REMOTE_HOST}"

if [[ ! -f .env.production ]]; then
  echo "ERROR: .env.production not found locally." >&2
  echo "Copy .env.production.example to .env.production and fill it in first." >&2
  exit 1
fi

echo "==> Ensuring remote directory $SSH_DEST:$REMOTE_DIR"
ssh "$SSH_DEST" "mkdir -p '$REMOTE_DIR'"

echo "==> Syncing source + .env.production to $SSH_DEST:$REMOTE_DIR"
# --delete keeps the host in sync with the laptop, but storage/ and .git are
# excluded so the host's runtime data and history are never touched/removed.
# .env.production is NOT excluded: it must reach the host.
rsync -az --delete \
  --exclude '.git' \
  --exclude 'storage' \
  ./ "$SSH_DEST:$REMOTE_DIR/"

echo "==> Running 'make prod-deploy' on $SSH_DEST"
# -t for a live TTY so build/healthcheck output streams back. KAMAL_NETWORK is
# forwarded only if set locally.
ssh -t "$SSH_DEST" \
  "cd '$REMOTE_DIR' && ${KAMAL_NETWORK:+KAMAL_NETWORK='$KAMAL_NETWORK' }make prod-deploy"

echo
echo "Done. Verify: curl -fsS https://stream.fractalia.art/health/ready"
