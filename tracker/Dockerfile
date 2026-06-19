# opentracker — Hypertube private BitTorrent tracker.
#
# Built from VENDORED source (tracker/vendor/*.tar.gz) so the build is hermetic
# and reproducible: it needs no access to fefe.de (which blocks datacenters) or
# any git host at build time — only the Alpine package mirror. Sources:
#   - libowfat : github.com/gebi/libowfat mirror of fefe's libowfat
#   - opentracker : git://erdgeist.org/opentracker (upstream)
# Re-vendor with the helper if you ever need to update them (see tracker/README.md).
#
# Whitelist enforcement (-DWANT_ACCESSLIST_WHITE) is enabled by uncommenting the
# feature in opentracker's Makefile below — this is the whole reason we build our own.

# ─── build stage ──────────────────────────────────────────────────────────────
FROM alpine:3.20 AS build

RUN apk add --no-cache build-base zlib-dev zlib-static

WORKDIR /build
COPY vendor/libowfat.tar.gz vendor/opentracker.tar.gz ./

# libowfat (static lib + headers). The mirror's top dir is libowfat-master/;
# opentracker's Makefile expects it at ../libowfat, so normalise the name.
# -fcommon is injected via CC (not CFLAGS) so libowfat's own -I. include path is
# preserved; modern gcc defaults to -fno-common which breaks libowfat's globals.
RUN tar xzf libowfat.tar.gz && mv libowfat-* libowfat && \
    make -C libowfat CC="gcc -fcommon"

# opentracker, with whitelist support compiled in.
RUN tar xzf opentracker.tar.gz && \
    sed -i 's|^#FEATURES+=-DWANT_ACCESSLIST_WHITE|FEATURES+=-DWANT_ACCESSLIST_WHITE|' opentracker/Makefile && \
    make -C opentracker && \
    strip opentracker/opentracker

# ─── runtime stage ──────────────────────────────────────────────────────────────
FROM alpine:3.20

# Kamal requires this label on images it didn't build itself (we build via plain
# `docker build`); it must match `service:` in config/deploy.yml.
LABEL service="hypertube-tracker"

# zlib for gzip-compressed scrape responses (compiled into opentracker by default).
RUN apk add --no-cache zlib && \
    addgroup -S tracker && adduser -S -G tracker -H -s /sbin/nologin tracker

COPY --from=build /build/opentracker/opentracker /usr/local/bin/opentracker

# Config + whitelist. whitelist.txt is COPYed LAST so editing hashes only
# invalidates this tiny layer — rebuilds stay near-instant (no C recompile).
WORKDIR /etc/opentracker
COPY opentracker.conf /etc/opentracker/opentracker.conf
COPY whitelist.txt    /etc/opentracker/whitelist.txt

USER tracker
EXPOSE 6969/tcp 6969/udp

# Foreground (opentracker does not daemonize) so it stays PID 1 and receives
# SIGHUP (whitelist reload) / SIGTERM (clean shutdown) from the container runtime.
ENTRYPOINT ["opentracker", "-f", "/etc/opentracker/opentracker.conf"]
