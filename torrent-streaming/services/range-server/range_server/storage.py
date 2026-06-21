"""Range-server runtime storage helpers.

This module owns only libtorrent/runtime artifacts under the range-server
storage area: the manifest, fastresume files, metadata backups, session state,
and corrupt-file quarantine. Application state belongs to other services and is
intentionally outside this module's responsibilities.
"""

from __future__ import annotations

import json
import os
import shutil
import time
from pathlib import Path
from typing import Any

from . import config
from .models import TorrentSnapshot
from .validation import validate_media_id

def now_token() -> str:
    return time.strftime("%Y%m%d%H%M%S", time.gmtime())


class ResumeStore:
    """Small range-server-owned store used to restore magnets and libtorrent state."""

    MANIFEST_NAME = "range_server_manifest.json"
    SESSION_STATE_NAME = "session_state.bencoded"

    def __init__(self, root: Path, cache_mode: str | None = None) -> None:
        self.root = root
        self.manifest_path = root / self.MANIFEST_NAME
        self.session_state_path = root / self.SESSION_STATE_NAME
        self.corrupt_dir = root / "corrupt"
        self.cache_mode = config.normalize_cache_mode(config.RANGE_SERVER_CACHE_MODE if cache_mode is None else cache_mode)

    def cache_enabled(self) -> bool:
        return self.cache_mode != "off"

    def is_writable(self) -> bool:
        if not self.cache_enabled():
            return True
        try:
            self.root.mkdir(parents=True, exist_ok=True)
            probe = self.root / f".probe-{os.getpid()}"
            probe.write_text("ok", encoding="utf-8")
            probe.unlink()
            return True
        except Exception:
            return False

    def load(self) -> dict[str, dict[str, Any]]:
        """Load the manifest, quarantining it if the schema or records are unsafe."""
        if not self.cache_enabled():
            return {}
        if not self.manifest_path.exists():
            return {}
        try:
            payload = json.loads(self.manifest_path.read_text(encoding="utf-8"))
            if not isinstance(payload, dict) or payload.get("schema_version") != 1:
                raise ValueError("unsupported manifest schema")
            torrents = payload.get("torrents", {})
            if not isinstance(torrents, dict):
                raise ValueError("manifest torrents must be an object")
            return {
                validate_media_id(media_id): record
                for media_id, record in torrents.items()
                if isinstance(record, dict) and isinstance(record.get("magnet"), str)
            }
        except Exception:
            self.quarantine(self.manifest_path)
            return {}

    def save(self, torrents: dict[str, TorrentSnapshot]) -> None:
        """Persist the restart manifest without storing mutable application state."""
        if not self.cache_enabled():
            return
        self.root.mkdir(parents=True, exist_ok=True)
        payload = {
            "schema_version": 1,
            "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "torrents": {
                media_id: {
                    "magnet": snapshot.magnet,
                    "info_hash": snapshot.info_hash,
                    "selected_file_index": snapshot.selected_file_index,
                }
                for media_id, snapshot in sorted(torrents.items())
            },
        }
        write_json_atomic(self.manifest_path, payload)

    def load_session_state(self, lt: Any) -> Any | None:
        if not self.cache_enabled():
            return None
        if not self.session_state_path.exists():
            return None
        try:
            return lt.bdecode(self.session_state_path.read_bytes())
        except Exception:
            self.quarantine(self.session_state_path)
            return None

    def save_session_state(self, lt: Any, session: Any, flags: Any | None = None) -> None:
        if not self.cache_enabled():
            return
        if not hasattr(session, "save_state") or not hasattr(lt, "bencode"):
            return
        state = session.save_state() if flags is None else session.save_state(flags)
        write_bytes_atomic(self.session_state_path, bytes(lt.bencode(state)))

    def resume_path(self, media_id: str) -> Path:
        return self.root / f"{media_id}.fastresume"

    def metadata_resume_path(self, media_id: str) -> Path:
        return self.root / f"{media_id}.metadata.fastresume"

    def quarantine(self, path: Path) -> None:
        """Move corrupt runtime files aside so startup can continue safely."""
        if not self.cache_enabled():
            return
        if not path.exists():
            return
        self.corrupt_dir.mkdir(parents=True, exist_ok=True)
        destination = self.corrupt_dir / f"{path.name}.{now_token()}.{os.getpid()}.corrupt"
        shutil.move(str(path), str(destination))


def write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    data = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8") + b"\n"
    write_bytes_atomic(path, data)


def write_bytes_atomic(path: Path, data: bytes) -> None:
    """Atomically replace a runtime file and fsync the containing directory."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.parent / f".{path.name}.{os.getpid()}.tmp"
    with tmp.open("wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)
    try:
        # Directory fsync makes the replacement durable on filesystems that require it.
        dir_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError:
        pass


def check_writable_dir(path: Path) -> dict[str, object]:
    try:
        path.mkdir(parents=True, exist_ok=True)
        probe = path / f".healthcheck-{os.getpid()}"
        probe.write_text("ok", encoding="utf-8")
        probe.unlink()
        return {"ok": True}
    except Exception as exc:  # pragma: no cover - exercised in container smoke
        return {"ok": False, "error": f"{exc.__class__.__name__}: {exc}"}
