# Real POC Torrent Streaming

POC mono-utilisateur de streaming torrent seekable avec `libtorrent`, `ffmpeg`, HLS, Ruby/Sinatra, Sidekiq, Redis et Docker Compose.

L'objectif est de lire une video avant la fin du telechargement, puis de permettre un seek utilisateur vers une zone qui n'est pas encore disponible localement. Le `range-server` traduit les ranges HTTP demandees par `ffmpeg` en priorites de pieces torrent, et `ffmpeg` produit du HLS servi par l'application web.

## Sommaire

- [Prerequis](#prerequis)
- [Demarrage rapide](#demarrage-rapide)
- [Commandes Docker Compose](#commandes-docker-compose)
- [Permissions Docker non-root](#permissions-docker-non-root)
- [Commandes de verification](#commandes-de-verification)
- [Scenarios reels avec magnets externes](#scenarios-reels-avec-magnets-externes)
- [Architecture globale](#architecture-globale)
- [Flux fonctionnels](#flux-fonctionnels)
- [Stockage et etat durable](#stockage-et-etat-durable)
- [Variables d'environnement utiles](#variables-denvironnement-utiles)
- [Depannage rapide](#depannage-rapide)
- [Documentation projet](#documentation-projet)

## Prerequis

Pour lancer l'application :

- Docker Desktop ou un daemon Docker fonctionnel.
- Docker Compose v2 (`docker compose ...`).
- Acces reseau sortant depuis Docker pour les trackers, DHT et peers torrent.
- Espace disque suffisant dans `storage/`.

Pour lancer les tests locaux hors container :

- Ruby 3.x.
- Python 3.
- Node.js.
- `ffmpeg` pour les tests qui generent une fixture video locale.

Le binding Python `libtorrent` n'a pas besoin d'etre installe sur l'hote pour les tests unitaires : les tests Python utilisent des fakes. Le smoke Docker verifie en revanche `libtorrent` dans le container `range-server`.

## Demarrage rapide

Depuis la racine du depot :

```bash
docker compose up -d --build --wait
```

Ouvrir ensuite l'interface :

```text
http://localhost:4567
```

Arreter l'application :

```bash
docker compose down
```

Si le port `4567` est deja pris :

```bash
WEB_PORT=4570 docker compose up -d --build --wait
```

Puis ouvrir :

```text
http://localhost:4570
```

## Commandes Docker Compose

### Construire et lancer

```bash
docker compose up -d --build --wait
```

### Lancer sans rebuild

```bash
docker compose up -d --wait
```

### Voir les services

```bash
docker compose ps
```

### Suivre tous les logs

```bash
docker compose logs -f
```

### Suivre les logs d'un service

```bash
docker compose logs -f web
docker compose logs -f range-server
docker compose logs -f transcoder-api
docker compose logs -f transcoder-worker-interactive
docker compose logs -f transcoder-worker-vod
docker compose logs -f redis
```

### Tester les healthchecks depuis les containers

```bash
docker compose exec -T web curl -fsS http://localhost:4567/health/ready
docker compose exec -T transcoder-api curl -fsS http://localhost:4568/health/ready
docker compose exec -T range-server curl -fsS http://localhost:7000/health/ready
docker compose exec -T redis redis-cli ping
```

### Verifier `libtorrent` dans le container

```bash
docker compose exec -T range-server python3 -c 'import libtorrent'
```

### Redemarrer les services applicatifs

```bash
docker compose restart redis range-server transcoder-api transcoder-worker-interactive transcoder-worker-vod web
docker compose up -d --wait
```

### Arreter et nettoyer les containers Compose

```bash
docker compose down --remove-orphans
```

## Permissions Docker non-root

Les containers applicatifs tournent avec `appuser` au lieu de `root`. Par defaut, les images sont construites avec :

```text
APP_UID=10001
APP_GID=10001
```

Sur macOS Docker Desktop, le chemin standard ne demande pas de `chown` local :

```bash
make dev
make test-smoke
```

Sur Linux natif, les bind mounts gardent les UID/GID du host. Construire avec l'utilisateur local evite les erreurs d'ecriture sur `storage/` :

```bash
make dev APP_UID="$(id -u)" APP_GID="$(id -g)"
make test-smoke APP_UID="$(id -u)" APP_GID="$(id -g)"
```

Avec Compose direct :

```bash
APP_UID="$(id -u)" APP_GID="$(id -g)" docker compose up -d --build --wait
```

Changer `APP_UID` ou `APP_GID` change les build args des images et necessite un rebuild. Les cibles `make run`, `make dev` et `make test-smoke` utilisent `--build` ou un smoke avec rebuild.

Si des dossiers `storage/` existent deja avec un owner incompatible sur Linux, afficher les commandes de diagnostic :

```bash
make storage-permissions APP_UID="$(id -u)" APP_GID="$(id -g)"
```

Le Makefile n'execute pas de `sudo chown` automatiquement. Le `range-server` garde `storage/state` et `storage/hls` en lecture seule dans Compose; ses ecritures autorisees sont limitees a `storage/torrents`, `storage/libtorrent` et `storage/logs`.

## Commandes de verification

### Smoke runtime complet

Ce script demarre Compose, verifie les services, simule un recovery VOD apres Redis vide, puis nettoie Compose.

```bash
tests/smoke/compose_runtime_smoke.sh
```

### Syntaxe des scripts smoke

```bash
bash -n tests/smoke/compose_runtime_smoke.sh
bash -n tests/smoke/real_magnet_e2e.sh
```

### Contrats Docker Compose et harnais reel

```bash
python3 tests/smoke/test_compose_contracts.py
```

### Tests Python `range-server`

```bash
python3 -m unittest discover -s tests/python -p 'test_*.py'
```

Pour lancer uniquement la suite principale :

```bash
python3 -m unittest tests/python/test_range_server.py
```

### Tests Ruby

```bash
ruby -Ishared/ruby/lib tests/ruby/test_domain_state.rb
ruby -Ishared/ruby/lib tests/ruby/test_state_ownership.rb
ruby -Ishared/ruby/lib tests/ruby/test_service_routes.rb
ruby -Ishared/ruby/lib tests/ruby/test_web_ui_routes.rb
ruby -Ishared/ruby/lib tests/ruby/test_transcoder_lifecycle.rb
ruby -Ishared/ruby/lib tests/ruby/test_hls_interactive.rb
ruby -Ishared/ruby/lib tests/ruby/test_hls_vod.rb
```

### Syntaxe Ruby

```bash
ruby -c services/web/app.rb
ruby -c services/transcoder-api/app.rb
ruby -c services/transcoder-worker/worker.rb
```

### Tests JavaScript du player

```bash
node -c services/web/public/player.js
node --test tests/js/test_player_ui.js
```

### Check Git utile avant commit

```bash
git diff --check
git status --short
```

## Scenarios reels avec magnets externes

Les scenarios reels utilisent les fixtures :

- `docs/magnet_test.torrent`
- `docs/magnet_test2.torrent`

Ils sont volontairement opt-in, car ils dependent de la provenance acceptee, du reseau, des trackers, de la DHT, des peers, du temps d'execution et de l'espace disque.

Commande :

```bash
ALLOW_EXTERNAL_TORRENT_TESTS=1 \
CONFIRM_EXTERNAL_TORRENT_FIXTURES=1 \
tests/smoke/real_magnet_e2e.sh
```

Variables utiles :

```bash
REAL_MAGNET_METADATA_TIMEOUT_SECONDS=600
REAL_MAGNET_PLAYBACK_TIMEOUT_SECONDS=180
REAL_MAGNET_RESTART_TIMEOUT_SECONDS=120
REAL_MAGNET_VOD_TIMEOUT_SECONDS=300
REAL_MAGNET_FIXTURES="docs/magnet_test.torrent docs/magnet_test2.torrent"
REAL_MAGNET_LOG_DIR=storage/logs/real_magnet
REAL_MAGNET_KEEP_COMPOSE=1
```

Preuve de seek vers pieces non disponibles :

```bash
REAL_MAGNET_SEEK_PROOF_BYTE_START=<byte_start>
REAL_MAGNET_SEEK_PROOF_BYTE_END=<byte_end>
REAL_MAGNET_SEEK_EVIDENCE_SECONDS=15
```

Codes de sortie du harnais :

| Code | Sens |
| --- | --- |
| `0` | Scenario reussi avec preuves critiques obtenues. |
| `1` | Echec applicatif ou commande critique en erreur. |
| `2` | Resultat inconclusif lie aux preconditions externes. |

Les logs sont ecrits dans :

```text
storage/logs/real_magnet/<run_id>/
```

## Architecture globale

```text
Navigateur
  |
  | HTTP :4567
  v
web (Ruby/Sinatra)
  |                 \
  | API interne      \ HLS depuis storage/hls
  v                  \
transcoder-api        \
  |                    \
  | jobs Sidekiq        v
  v                  storage/state, storage/hls, storage/logs
redis <---- transcoder-worker-interactive
  ^       \ transcoder-worker-vod
  |        \
  |         \ ffmpeg lit une URL HTTP seekable
  |          v
range-server (Python/libtorrent)
  |
  | trackers / DHT / peers
  v
reseau BitTorrent
```

### `web`

Application Ruby/Sinatra exposee a l'utilisateur.

Responsabilites :

- servir l'UI ERB ;
- ajouter un magnet ;
- afficher metadata, fichiers, progression et erreurs ;
- selectionner le fichier video ;
- piloter play, seek et stop ;
- servir playlists et segments HLS au navigateur ;
- synchroniser l'etat utile depuis le `range-server`.

Seul `web` publie un port hote.

### `range-server`

Service Python avec `libtorrent`.

Responsabilites :

- ajouter les magnets ;
- recuperer les metadata torrent ;
- lister et classifier fichiers video, sous-titres et autres fichiers ;
- maintenir resume data et session state libtorrent ;
- exposer les fichiers selectionnes en HTTP seekable ;
- supporter `HEAD`, `GET` et `Range` ;
- traduire ranges d'octets en pieces torrent ;
- prioriser et attendre les pieces demandees par `ffmpeg`.

Le `range-server` n'ecrit pas dans `storage/state`. Il possede uniquement son etat libtorrent dans `storage/libtorrent`.

### `transcoder-api`

Service Ruby/Sinatra interne.

Responsabilites :

- creer les sessions de lecture ;
- recevoir play, seek, stop ;
- enqueue les jobs Sidekiq ;
- exposer l'etat des sessions ;
- demander l'annulation des sessions ou du packaging VOD.

### `transcoder-worker-interactive`

Worker Sidekiq Ruby dedie aux flux interactifs.

Responsabilites :

- lancer `ffmpeg` pour produire un HLS interactif ;
- gerer le seek en remplacant la session active ;
- arreter proprement les anciens process groups `ffmpeg` ;
- nettoyer les sessions HLS expirees.

Queues :

```text
interactive,cleanup
```

### `transcoder-worker-vod`

Worker Sidekiq Ruby dedie au packaging final.

Responsabilites :

- produire le HLS VOD final quand le fichier est complet ;
- conserver la source originale ;
- replanifier ou regenerer le VOD apres restart ;
- laisser la priorite a l'interactif via la queue `vod_control`.

Queues :

```text
vod_control,vod
```

### `redis`

Redis sert uniquement de broker Sidekiq. Il n'est pas une base de donnees applicative.

## Flux fonctionnels

### Ajout d'un magnet

1. L'utilisateur soumet un magnet dans l'UI.
2. `web` cree un `media_id` et ecrit l'etat initial.
3. `web` appelle `range-server`.
4. `range-server` ajoute le torrent a `libtorrent`.
5. L'UI poll le statut jusqu'a metadata disponible.

### Selection video

1. `range-server` expose la liste des fichiers.
2. `web` affiche les videos supportees.
3. L'utilisateur choisit un fichier video.
4. `range-server` priorise le fichier, les sous-titres lies et les pieces debut/fin.

### Lecture avant completion

1. L'utilisateur clique Play.
2. `web` demande une session a `transcoder-api`.
3. `transcoder-api` enqueue un job interactif.
4. `transcoder-worker-interactive` lance `ffmpeg`.
5. `ffmpeg` lit `http://range-server:7000/files/<media_id>/<file_index>`.
6. `range-server` priorise les pieces correspondant aux ranges demandees.
7. Des que la playlist HLS contient des segments valides, `web` expose la lecture au navigateur.

### Seek utilisateur

1. L'utilisateur deplace la timeline.
2. `web` demande un seek a `transcoder-api`.
3. L'ancienne session est marquee en arret.
4. Une nouvelle session `ffmpeg` demarre avec `-ss <target_seconds>`.
5. `range-server` priorise les pieces autour de la position cible.
6. L'UI bascule vers la nouvelle playlist quand elle est prete.

### HLS VOD final

1. Quand le fichier source est complet, un job VOD est planifie.
2. `transcoder-worker-vod` produit le HLS final sous `storage/hls/vod`.
3. La source originale reste conservee dans `storage/torrents`.
4. Apres restart avec Redis vide, l'etat durable permet de replanifier ou regenerer le VOD.

## Stockage et etat durable

Le projet n'utilise pas de base de donnees. Les donnees durables sont dans `storage/`.

| Chemin | Usage |
| --- | --- |
| `storage/state` | Etat JSON applicatif : medias, sessions, locks, fichiers corrompus. |
| `storage/torrents` | Fichiers telecharges par `libtorrent`. |
| `storage/libtorrent` | Resume data, manifest et session state `libtorrent`. |
| `storage/hls/sessions` | HLS temporaire pour les sessions interactives. |
| `storage/hls/vod` | HLS final apres completion. |
| `storage/logs` | Logs applicatifs, range-server, workers et `ffmpeg`. |

Regles importantes :

- Les services Ruby possedent `storage/state`.
- Le `range-server` ne modifie pas `storage/state`.
- Le `range-server` possede `storage/libtorrent`.
- Les ecritures JSON applicatives passent par locks et ecritures atomiques.
- Les JSON corrompus sont preserves sous `storage/state/corrupt`.

## Variables d'environnement utiles

### Ports

| Variable | Defaut | Description |
| --- | --- | --- |
| `WEB_PORT` | `4567` | Port hote expose par `web`. |

### Range server

| Variable | Defaut | Description |
| --- | --- | --- |
| `RANGE_SERVER_MIN_FREE_SPACE_BYTES` | `104857600` | Reserve disque minimale, 100 MiB par defaut. |
| `RANGE_SERVER_PIECE_TIMEOUT_SECONDS` | `30` | Timeout d'attente des pieces pour une range. |
| `RANGE_SERVER_PRELOAD_PIECES` | `4` | Nombre de pieces a precharger autour de la range active. |

### Metadata / transcoder

| Variable | Defaut | Description |
| --- | --- | --- |
| `FFPROBE_TIMEOUT_SECONDS` | `45` | Timeout global du probe metadata. Il doit rester superieur au timeout de range pour laisser arriver les pieces demandees. |
| `METADATA_PROBE_RETRY_SECONDS` | `15` | Backoff minimal avant de replanifier un probe metadata apres `ffprobe_timeout`, uniquement si le torrent a progresse. |

### Harnais reel externe

| Variable | Defaut | Description |
| --- | --- | --- |
| `ALLOW_EXTERNAL_TORRENT_TESTS` | unset | Doit valoir `1` pour lancer les scenarios reels. |
| `CONFIRM_EXTERNAL_TORRENT_FIXTURES` | unset | Doit valoir `1` apres confirmation de provenance/usage. |
| `REAL_MAGNET_FIXTURES` | fixtures PRD | Liste de fixtures a executer. |
| `REAL_MAGNET_LOG_DIR` | `storage/logs/real_magnet` | Dossier de logs du harnais. |
| `REAL_MAGNET_KEEP_COMPOSE` | unset | `1` garde Compose actif apres le harnais. |

## Depannage rapide

### Docker n'est pas joignable

Verifier que Docker Desktop ou le daemon Docker est lance :

```bash
docker ps
```

### Le port 4567 est occupe

Utiliser un autre port :

```bash
WEB_PORT=4570 docker compose up -d --build --wait
```

### Un service n'est pas healthy

Afficher l'etat :

```bash
docker compose ps
```

Afficher les logs du service :

```bash
docker compose logs -f <service>
```

### Nettoyer les containers

```bash
docker compose down --remove-orphans
```

### Nettoyer les donnees runtime

Attention : cette operation supprime les medias, HLS, etats et logs locaux. A faire seulement si tu veux repartir de zero.

Le plus sur est de supprimer uniquement les dossiers/fichiers generes en gardant les fichiers `.gitkeep` et l'arborescence `storage/` versionnee. Les emplacements runtime sont :

- `storage/state/media/*`
- `storage/state/sessions/*`
- `storage/state/locks/*.lock`
- `storage/state/corrupt/*`
- `storage/torrents/*`
- `storage/libtorrent/*`
- `storage/hls/sessions/*`
- `storage/hls/vod/*`
- `storage/logs/*`

## Documentation projet

Documents principaux :

- `docs/PRD.md` : specification produit et technique de depart.
- `docs/JALONS.md` : decoupage par jalons.
- `docs/TECHNICAL_CONTRACTS.md` : contrats transverses.
- `docs/TRACEABILITY.md` : matrice de tracabilite PRD.
- `docs/PROJECT_MEMORY.md` : decisions, erreurs, corrections et statut des jalons.
- `docs/REVIEW_LOG.md` : reviews par jalon et reviews finales.
- `docs/LIVRAISON_FINALE.md` : synthese finale, commandes verifiees et limites connues.

Les scenarios reels externes restent opt-in : ils ne doivent pas etre confondus avec les suites deterministes locales.
