# Hypertube private tracker (opentracker)

A self-hosted [opentracker](https://erdgeist.org/arts/software/opentracker/)
instance for Hypertube, compiled **with whitelist support** so only torrents we
explicitly allow are tracked. Public trackers keep rejecting our info_hashes —
this gives us full control to test the app and run a small private swarm with
friends.

Runs on the same droplet (`167.71.57.19`) as the api, as its **own Kamal app**
sharing the existing kamal-proxy.

## Endpoints

Once deployed (and DNS + firewall are in place):

| Transport | Announce URL |
|-----------|--------------|
| HTTPS (via kamal-proxy) | `https://opentracker.fractalia.art/announce` |
| UDP (published directly) | `udp://opentracker.fractalia.art:6969/announce` |

Put both in your `.torrent` / magnet so peers can reach the tracker either way.
Stats (if you enable `access.stats`): `https://opentracker.fractalia.art/stats?mode=tpbs`.

## One-time prerequisites (outside this repo)

1. **DNS** — add an A record `opentracker.fractalia.art → 167.71.57.19`.
   Required *before* the first deploy so kamal-proxy can obtain its Let's Encrypt
   certificate.
2. **Firewall** — open **UDP 6969** on the droplet (e.g. `ufw allow 6969/udp`, plus
   the DigitalOcean cloud firewall if you use one). Ports 80/443 are already open
   for the api.

## The whitelist

Only info_hashes listed in [`whitelist.txt`](whitelist.txt) are tracked. It's a
plain list of **40-char hex info_hashes**, one per line (`#` comments allowed).

Get a torrent's info_hash (hex):

```sh
transmission-show -m my.torrent     # btih in the printed magnet
aria2c --show-files my.torrent
# from a magnet link: the xt=urn:btih:<HASH> value (convert base32 → hex if needed)
```

### Adding torrents

1. Add the hash(es) to `whitelist.txt`.
2. Commit the change (the image tag is the git SHA, so commit first).
3. `make tracker-deploy` — rebuilds (only the tiny whitelist layer, no C recompile),
   pushes, and redeploys.

For an urgent change made directly on the server, `make tracker-reload` sends
`SIGHUP` to re-read the file with zero downtime — but prefer the git-tracked flow
above so the whitelist stays auditable.

## Commands (run from the repo root)

```sh
make tracker-deploy     # build + push + deploy
make tracker-status     # container details + proxy/cert routing
make tracker-logs       # follow logs
make tracker-reload     # live whitelist reload (SIGHUP), no redeploy
make tracker-rollback   # roll back to the previous release
```

All of these run kamal inside the dev container (no local Ruby needed), the same
way the api targets do.

## How it's built

`make tracker-build` compiles opentracker from **vendored source** in
[`vendor/`](vendor/) (`libowfat.tar.gz`, `opentracker.tar.gz`). Vendoring keeps the
build hermetic and reproducible — it needs no access to fefe.de (which blocks
datacenters) or any git host at build time, only Alpine's package mirror. The
[`Dockerfile`](Dockerfile) uncomments `-DWANT_ACCESSLIST_WHITE` in opentracker's
Makefile and copies the whitelist as the **last** layer so hash edits rebuild
instantly.

### Re-vendoring (only when updating upstream)

```sh
# libowfat (gebi mirror of fefe's libowfat):
curl -sSL -o tracker/vendor/libowfat.tar.gz \
  https://codeload.github.com/gebi/libowfat/tar.gz/refs/heads/master

# opentracker (upstream, via git protocol):
docker run --rm -v "$PWD/tracker/vendor:/out" alpine:3.20 sh -c '
  apk add --no-cache git >/dev/null && cd /tmp &&
  git clone --depth 1 git://erdgeist.org/opentracker opentracker &&
  rm -rf opentracker/.git && tar czf /out/opentracker.tar.gz opentracker'
```

## Config

[`opentracker.conf`](opentracker.conf) listens TCP+UDP on `6969` (TCP is fronted by
the proxy → HTTPS; UDP is published directly). Edit it to tweak listen options or
restrict the stats page via `access.stats <ip>`.
