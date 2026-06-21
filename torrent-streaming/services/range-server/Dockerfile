# Container image for the internal range-server process.
# It installs the Debian libtorrent Python binding, copies only the service
# code, prepares writable runtime storage, and runs as a non-root user.
FROM debian:bookworm-slim

ARG APP_UID=10001
ARG APP_GID=10001

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl python3 python3-libtorrent \
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

ENV HOME=/nonexistent
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY services/range-server/app.py ./app.py
COPY services/range-server/range_server ./range_server

RUN mkdir -p /app/storage/state /app/storage/torrents /app/storage/libtorrent /app/storage/hls /app/storage/logs \
  && chown -R appuser:${APP_GID} /app/storage/torrents /app/storage/libtorrent /app/storage/logs

USER appuser:${APP_GID}

EXPOSE 7000
CMD ["python3", "app.py"]
