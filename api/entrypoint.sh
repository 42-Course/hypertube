#!/bin/bash
set -e

# Only enforce the "initialised" guard when we're actually starting the server.
# Commands like `bash /app/init.sh` or `rails console` pass through unconditionally.
if [[ "$*" == *"rails server"* ]]; then
  if [ ! -f "/app/config/application.rb" ]; then
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║  Rails app not initialised yet.  Run: make init          ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
  fi

  # Remove stale server pid left by an unclean shutdown
  rm -f /app/tmp/pids/server.pid

  # Ensure gems are current before starting
  bundle check || bundle install
fi

exec "$@"
