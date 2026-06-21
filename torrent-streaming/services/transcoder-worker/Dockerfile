# Runtime image for transcoder Sidekiq workers. Compose can run the same image with
# different queue sets/roles for interactive sessions, cleanup, and VOD packaging.
FROM ruby:3.3-slim

ARG APP_UID=10001
ARG APP_GID=10001

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential ffmpeg ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  if getent passwd "${APP_UID}" >/dev/null; then \
    echo "APP_UID ${APP_UID} already exists in the image; choose another UID" >&2; \
    exit 1; \
  fi; \
  if ! getent group "${APP_GID}" >/dev/null; then \
    groupadd --gid "${APP_GID}" appuser; \
  fi; \
  useradd --uid "${APP_UID}" --gid "${APP_GID}" --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

COPY shared/ruby/Gemfile shared/ruby/Gemfile.lock ./
RUN bundle install

ENV HOME=/nonexistent

COPY shared/ruby/lib ./shared/lib
COPY services/transcoder-worker/worker.rb ./worker.rb
COPY services/transcoder-worker/healthcheck.rb ./healthcheck.rb

RUN mkdir -p /app/storage/state /app/storage/torrents /app/storage/libtorrent /app/storage/hls /app/storage/logs \
  && chown -R appuser:${APP_GID} /app/storage/state /app/storage/hls /app/storage/logs

USER appuser:${APP_GID}

CMD ["bundle", "exec", "sidekiq", "-r", "./worker.rb", "-q", "interactive", "-q", "cleanup"]
