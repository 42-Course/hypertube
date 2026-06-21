"""Environment-backed configuration for range-server.

The service keeps constants here so Docker defaults, tests, and runtime code
share one contract for storage locations, request limits, torrent discovery,
and range streaming behavior. Callers should read values from this module at
use time when tests may patch them dynamically.
"""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

SERVICE = "range-server"
STORAGE_ROOT = Path(os.environ.get("STORAGE_ROOT", "/app/storage"))
TORRENTS_DIR = Path(os.environ.get("TORRENTS_DIR", str(STORAGE_ROOT / "torrents")))
LIBTORRENT_DIR = Path(os.environ.get("LIBTORRENT_DIR", str(STORAGE_ROOT / "libtorrent")))
LOGS_DIR = Path(os.environ.get("LOGS_DIR", str(STORAGE_ROOT / "logs")))

MEDIA_ID_PATTERN = re.compile(r"^[0-9a-f]{32}$")
BTIH_HEX_PATTERN = re.compile(r"^[0-9a-f]{40}$")
BTIH_BASE32_PATTERN = re.compile(r"^[a-z2-7]{32}$")
MAX_MAGNET_BYTES = int(os.environ.get("RANGE_SERVER_MAX_MAGNET_BYTES", "8192"))
MAX_JSON_BODY_BYTES = int(os.environ.get("RANGE_SERVER_MAX_JSON_BODY_BYTES", "65536"))
MAX_TORRENT_FILES = int(os.environ.get("RANGE_SERVER_MAX_FILES", "10000"))
MAX_TOTAL_TORRENT_BYTES = int(os.environ.get("RANGE_SERVER_MAX_TOTAL_BYTES", str(1024 * 1024 * 1024 * 1024)))
MAX_FILE_BYTES = int(os.environ.get("RANGE_SERVER_MAX_FILE_BYTES", str(512 * 1024 * 1024 * 1024)))
MAX_METADATA_PATH_BYTES = int(os.environ.get("RANGE_SERVER_MAX_METADATA_PATH_BYTES", "4096"))
MIN_FREE_SPACE_BYTES = int(os.environ.get("RANGE_SERVER_MIN_FREE_SPACE_BYTES", str(100 * 1024 * 1024)))
DEFAULT_PIECE_LENGTH = 256 * 1024
HEAD_TAIL_PIECES = int(os.environ.get("RANGE_SERVER_HEAD_TAIL_PIECES", "2"))
RANGE_CHUNK_BYTES = int(os.environ.get("RANGE_SERVER_CHUNK_BYTES", str(256 * 1024)))
RANGE_PIECE_TIMEOUT_SECONDS = float(os.environ.get("RANGE_SERVER_PIECE_TIMEOUT_SECONDS", "30"))
RANGE_WAIT_POLL_SECONDS = float(os.environ.get("RANGE_SERVER_WAIT_POLL_SECONDS", "0.05"))
RANGE_PRELOAD_PIECES = int(os.environ.get("RANGE_SERVER_PRELOAD_PIECES", "4"))
RESUME_SAVE_INTERVAL_SECONDS = int(os.environ.get("RANGE_SERVER_RESUME_SAVE_INTERVAL", "60"))
SESSION_STATE_SAVE_INTERVAL_SECONDS = int(os.environ.get("RANGE_SERVER_SESSION_STATE_SAVE_INTERVAL", "60"))
BITTORRENT_PORT = int(os.environ.get("BITTORRENT_PORT", "6881"))
BITTORRENT_LISTEN_INTERFACES = os.environ.get("BITTORRENT_LISTEN_INTERFACES")
DEFAULT_DHT_ROUTERS = (
    "router.bittorrent.com:6881",
    "router.utorrent.com:6881",
    "dht.transmissionbt.com:6881",
)
BITTORRENT_DHT_ROUTERS = os.environ.get("BITTORRENT_DHT_ROUTERS", ",".join(DEFAULT_DHT_ROUTERS))
BITTORRENT_PARALLEL_TRACKER_ANNOUNCES = os.environ.get("BITTORRENT_PARALLEL_TRACKER_ANNOUNCES")
BITTORRENT_ANNOUNCE_TO_ALL_TRACKERS = os.environ.get("BITTORRENT_ANNOUNCE_TO_ALL_TRACKERS")
BITTORRENT_ANNOUNCE_TO_ALL_TIERS = os.environ.get("BITTORRENT_ANNOUNCE_TO_ALL_TIERS")
BITTORRENT_DISCOVERY_PROFILE = os.environ.get("BITTORRENT_DISCOVERY_PROFILE", "standard")
RANGE_SERVER_CACHE_MODE = os.environ.get("RANGE_SERVER_CACHE_MODE", "readwrite")
MAX_RECENT_ALERTS = int(os.environ.get("RANGE_SERVER_MAX_RECENT_ALERTS", "20"))

AGGRESSIVE_DISCOVERY_SETTINGS = {
    "use_dht_as_fallback": True,
    "tracker_completion_timeout": 10,
    "tracker_receive_timeout": 5,
    "min_reconnect_time": 10,
    "tracker_backoff": 20,
    "connection_speed": 120,
    "connections_limit": 500,
    "torrent_connect_boost": 100,
    "active_dht_limit": 256,
    "active_tracker_limit": 3200,
    "dht_search_branching": 16,
}

VIDEO_EXTENSIONS = {".mkv", ".mp4", ".mov", ".avi", ".webm", ".m4v", ".ts"}
TEXT_SUBTITLE_EXTENSIONS = {".srt", ".vtt", ".ass", ".ssa"}
IMAGE_SUBTITLE_EXTENSIONS = {".sup", ".idx", ".sub", ".pgs"}
PORT = int(os.environ.get("PORT", "7000"))
BACKEND_DEBUG_STDERR = os.environ.get("BACKEND_DEBUG_STDERR", "1")

def normalize_cache_mode(value: str | None) -> str:
    """Collapse cache mode input to the two modes the engine understands."""

    return "off" if str(value or "").strip().lower() == "off" else "readwrite"


def normalize_discovery_profile(value: str | None) -> str:
    """Return the supported discovery profile name for user input."""

    return "aggressive" if str(value or "").strip().lower() == "aggressive" else "standard"


def parse_optional_bool(value: str | bool | None) -> bool | None:
    """Parse optional environment-style booleans while preserving unset values."""

    if value is None:
        return None
    if isinstance(value, bool):
        return value
    normalized = str(value).strip().lower()
    if not normalized:
        return None
    return normalized not in {"0", "false", "no", "off"}


def profile_default_bool(profile: str, configured: str | bool | None) -> bool:
    """Use explicit booleans first, then aggressive-profile defaults."""

    parsed = parse_optional_bool(configured)
    if parsed is not None:
        return parsed
    return normalize_discovery_profile(profile) == "aggressive"


def discovery_settings_for(profile: str) -> dict[str, Any]:
    """Return libtorrent setting overrides for the selected discovery profile."""

    return dict(AGGRESSIVE_DISCOVERY_SETTINGS) if normalize_discovery_profile(profile) == "aggressive" else {}

def configured_dht_routers(configured: str | None = None) -> tuple[tuple[str, int], ...]:
    """Parse configured DHT routers into libtorrent ``(host, port)`` pairs."""

    if configured is None:
        # Read the module value at call time so tests can patch the environment
        # result without reloading every caller.
        configured = BITTORRENT_DHT_ROUTERS
    if configured is None:
        configured = ",".join(DEFAULT_DHT_ROUTERS)
    routers = []
    for raw_router in configured.split(","):
        router = raw_router.strip()
        if not router:
            continue
        host, separator, port_text = router.rpartition(":")
        if not separator or not host:
            continue
        try:
            port = int(port_text)
        except ValueError:
            continue
        routers.append((host, port))
    return tuple(routers)


def configured_dht_bootstrap_nodes(configured: str | None = None) -> str:
    """Return the comma-separated bootstrap string expected by libtorrent."""

    return ",".join(f"{host}:{port}" for host, port in configured_dht_routers(configured))
