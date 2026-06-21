"""JSON API routing and readiness checks for the range-server service.

This module translates HTTP methods and paths into engine/storage operations
without touching libtorrent directly. It also owns the stable JSON error shape
used by the web service and operational health checks.
"""

from __future__ import annotations

from http import HTTPStatus
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from . import config
from .engine import TorrentEngine
from .models import ApiError, HttpResponse
from .observability import backend_error, backend_exception
from .range_streaming import RangeStreamer
from .storage import ResumeStore, check_writable_dir
from .validation import parse_json_object, parse_magnet, validate_media_id

class Application:
    """Small application layer behind the stdlib HTTP adapter."""

    def __init__(
        self,
        engine: TorrentEngine,
        resume_store: ResumeStore,
        torrents_dir: Path | None = None,
        logs_dir: Path | None = None,
        range_streamer: RangeStreamer | None = None,
    ) -> None:
        self.engine = engine
        self.resume_store = resume_store
        self.torrents_dir = config.TORRENTS_DIR if torrents_dir is None else torrents_dir
        self.logs_dir = config.LOGS_DIR if logs_dir is None else logs_dir
        self.range_streamer = range_streamer or RangeStreamer(engine, self.torrents_dir)

    def handle(self, method: str, raw_path: str, body: bytes = b"") -> tuple[int, dict[str, Any]]:
        """Route JSON API requests and map domain failures to stable payloads."""

        try:
            parsed = urlparse(raw_path)
            path_parts = [part for part in parsed.path.split("/") if part]
            if method == "GET" and parsed.path == "/health":
                return HTTPStatus.OK, {"service": config.SERVICE, "status": "ok"}
            if method == "GET" and parsed.path == "/health/live":
                return HTTPStatus.OK, {"service": config.SERVICE, "status": "live"}
            if method == "GET" and parsed.path == "/health/ready":
                return self._ready()
            if method == "POST" and path_parts == ["torrents"]:
                return self._post_torrents(body)
            if len(path_parts) == 2 and path_parts[0] == "torrents" and method == "GET":
                return self._get_torrent(path_parts[1])
            if len(path_parts) == 3 and path_parts[0] == "torrents" and path_parts[2] == "files" and method == "GET":
                return self._get_files(path_parts[1])
            if (
                len(path_parts) == 3
                and path_parts[0] == "torrents"
                and path_parts[2] == "select-file"
                and method == "POST"
            ):
                return self._select_file(path_parts[1], body)
            return HTTPStatus.NOT_FOUND, {"error": "not_found"}
        except ApiError as exc:
            backend_error(
                "api_error",
                method=method,
                path=raw_path,
                status=exc.status,
                code=exc.code,
                message=exc.message,
            )
            return exc.status, {"error": exc.code, "message": exc.message}
        except Exception as exc:
            backend_exception("application_internal_error", exc, method=method, path=raw_path)
            return HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "internal_error"}

    def handle_file(self, method: str, raw_path: str, headers: dict[str, str] | None = None) -> HttpResponse:
        """Delegate seekable file responses to the streaming layer."""

        return self.range_streamer.handle_file(method, raw_path, headers or {})

    def _ready(self) -> tuple[int, dict[str, Any]]:
        """Report whether libtorrent and all writable runtime directories are usable."""

        engine_ready, engine_error = self.engine.ready()
        # Directory and store checks remain dynamic because tests and containers
        # can patch or mount these paths after the module is imported.
        checks = {
            "libtorrent": {"ok": engine_ready, "error": engine_error},
            "torrents_writable": {"ok": check_writable_dir(self.torrents_dir)["ok"]},
            "libtorrent_writable": {"ok": self.resume_store.is_writable()},
            "logs_writable": {"ok": check_writable_dir(self.logs_dir)["ok"]},
        }
        ready = all(result["ok"] for result in checks.values())
        return (
            HTTPStatus.OK if ready else HTTPStatus.SERVICE_UNAVAILABLE,
            {"service": config.SERVICE, "status": "ready" if ready else "not_ready", "checks": checks},
        )

    def _post_torrents(self, body: bytes) -> tuple[int, dict[str, Any]]:
        """Validate and register a magnet for a media ID."""

        payload = parse_json_object(body)
        media_id = validate_media_id(payload.get("media_id"))
        magnet = parse_magnet(payload.get("magnet"))
        # Reject early when payload or resume storage cannot be written; the web
        # caller treats this as a capacity/configuration problem, not bad input.
        if not check_writable_dir(self.torrents_dir)["ok"] or not self.resume_store.is_writable():
            raise ApiError(HTTPStatus.INSUFFICIENT_STORAGE, "storage_unavailable", "torrent storage is not writable")
        existing = self.engine.get_snapshot(media_id)
        # A media ID may be retried for the same torrent, but must not be
        # silently rebound to a different info hash.
        if existing and existing.info_hash and existing.info_hash != magnet.info_hash:
            raise ApiError(
                HTTPStatus.CONFLICT,
                "duplicate_media_conflict",
                "media_id already points to another info hash",
            )
        snapshot = self.engine.add_torrent(media_id, magnet)
        return HTTPStatus.ACCEPTED, {
            "media_id": snapshot.media_id,
            "info_hash": snapshot.info_hash,
            "status": snapshot.status,
            "metadata_ready": snapshot.metadata_ready,
            "duplicate": existing is not None,
        }

    def _get_torrent(self, media_id_value: str) -> tuple[int, dict[str, Any]]:
        """Return the public status payload for one known torrent."""

        media_id = validate_media_id(media_id_value)
        snapshot = self.engine.get_snapshot(media_id)
        if snapshot is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "not_found", "torrent is unknown")
        return HTTPStatus.OK, snapshot.to_status_api()

    def _get_files(self, media_id_value: str) -> tuple[int, dict[str, Any]]:
        """Return files only after torrent metadata has been discovered."""

        media_id = validate_media_id(media_id_value)
        snapshot = self.engine.get_snapshot(media_id)
        if snapshot is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "not_found", "torrent is unknown")
        return HTTPStatus.OK, snapshot.to_files_api()

    def _select_file(self, media_id_value: str, body: bytes) -> tuple[int, dict[str, Any]]:
        """Select the supported video file that range streaming will expose."""

        media_id = validate_media_id(media_id_value)
        payload = parse_json_object(body)
        file_index = payload.get("file_index")
        if isinstance(file_index, bool) or not isinstance(file_index, int) or file_index < 0:
            raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_file_index", "file_index must be a non-negative integer")
        result = self.engine.select_file(media_id, file_index)
        return HTTPStatus.OK, result.to_api()
