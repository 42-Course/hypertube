"""Libtorrent ownership and torrent state for the range server.

This module is the only place that talks directly to libtorrent. It keeps all
session and handle access on one background owner thread, publishes immutable
snapshots for HTTP code, and translates file/range selections into libtorrent
file and piece priorities.
"""

from __future__ import annotations

import importlib
import queue
import socket
import threading
import time
from dataclasses import replace
from http import HTTPStatus
from pathlib import Path
from typing import Any, Callable

from . import config
from .metadata import (
    build_file_snapshots,
    ensure_storage_policy,
    linked_subtitle_indices,
    selected_head_tail_pieces,
    torrent_error_code,
)
from .models import ApiError, Command, FileSnapshot, Magnet, RawTorrentFile, SelectionResult, TorrentSnapshot
from .observability import backend_error, backend_exception, backend_log
from .storage import ResumeStore, write_bytes_atomic
from .validation import parse_magnet

STOP_COMMAND = object()



def default_libtorrent_listen_interfaces(port: int, configured: str | None = None) -> str:
    """Return the libtorrent listen interface string for configured or detected networking."""
    if configured is None:
        configured = config.BITTORRENT_LISTEN_INTERFACES
    if configured and configured.strip():
        return configured.strip()
    detected_ip = detect_default_ipv4()
    return f"{detected_ip}:{port}" if detected_ip else f"0.0.0.0:{port}"


def detect_default_ipv4() -> str | None:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("1.1.1.1", 80))
            address = sock.getsockname()[0]
    except OSError:
        return None
    if not address or address.startswith("127."):
        return None
    return address

def enable_parallel_tracker_announces(params: Any, profile: str | None = None) -> None:
    """Flatten tracker tiers when the discovery profile wants simultaneous announces."""
    if profile is None:
        profile = config.BITTORRENT_DISCOVERY_PROFILE
    if not config.profile_default_bool(profile, config.BITTORRENT_PARALLEL_TRACKER_ANNOUNCES):
        return
    trackers = getattr(params, "trackers", None)
    if trackers is None or not hasattr(params, "tracker_tiers"):
        return
    try:
        tracker_count = len(trackers)
    except TypeError:
        tracker_count = len(list(trackers))
    if tracker_count <= 1:
        return
    params.tracker_tiers = [0] * tracker_count


class TorrentEngine:
    """Small interface consumed by the HTTP layer without exposing libtorrent handles."""

    def start(self) -> None:
        raise NotImplementedError

    def stop(self) -> None:
        raise NotImplementedError

    def ready(self) -> tuple[bool, str | None]:
        raise NotImplementedError

    def add_torrent(self, media_id: str, magnet: Magnet) -> TorrentSnapshot:
        raise NotImplementedError

    def get_snapshot(self, media_id: str) -> TorrentSnapshot | None:
        raise NotImplementedError

    def select_file(self, media_id: str, file_index: int) -> SelectionResult:
        raise NotImplementedError

    def prioritize_range(
        self,
        media_id: str,
        request_token: str | None,
        active_pieces: tuple[int, ...],
        preload_pieces: tuple[int, ...],
    ) -> str:
        raise NotImplementedError

    def release_range(self, media_id: str, request_token: str) -> None:
        raise NotImplementedError

    def have_pieces(self, media_id: str, pieces: tuple[int, ...]) -> bool:
        raise NotImplementedError


class LibtorrentEngine(TorrentEngine):
    """Thread-owned libtorrent adapter with snapshot and priority bookkeeping.

    Public methods enqueue commands and wait for the owner thread to run them.
    Direct handle/session access must stay inside this class because the Python
    libtorrent binding is not treated as safe to call concurrently from request
    threads.
    """

    def __init__(
        self,
        torrents_dir: Path,
        resume_store: ResumeStore | None = None,
        import_libtorrent: Callable[[], Any] | None = None,
    ) -> None:
        self.torrents_dir = torrents_dir
        self.resume_store = resume_store or ResumeStore(torrents_dir.parent / "libtorrent")
        self.import_libtorrent = import_libtorrent or (lambda: importlib.import_module("libtorrent"))
        self.commands: queue.Queue[Command | object] = queue.Queue()
        self.snapshots: dict[str, TorrentSnapshot] = {}
        self.handles: dict[str, Any] = {}
        self.lock = threading.Lock()
        self.thread: threading.Thread | None = None
        self.startup_error: str | None = None
        self.initialized = False
        self.lt: Any = None
        self.session: Any = None
        self.cache_mode = self.resume_store.cache_mode
        self.discovery_profile = config.normalize_discovery_profile(config.BITTORRENT_DISCOVERY_PROFILE)
        self.discovery_settings = config.discovery_settings_for(self.discovery_profile)
        self.last_resume_save = time.monotonic()
        self.last_session_state_save = 0.0
        # media_id -> request token -> (active pieces, preload pieces)
        self.range_requests: dict[str, dict[str, tuple[set[int], set[int]]]] = {}
        self.range_request_counter = 0
        self.recent_alerts: dict[str, list[dict[str, Any]]] = {}
        self.session_alerts: list[dict[str, Any]] = []

    def start(self) -> None:
        if self.thread is not None:
            return
        # This is the sole owner of libtorrent session and torrent handles.
        self.thread = threading.Thread(target=self._run, name="libtorrent-owner", daemon=True)
        self.thread.start()

    def stop(self) -> None:
        self.commands.put(STOP_COMMAND)
        if self.thread is not None:
            self.thread.join(timeout=5)

    def ready(self) -> tuple[bool, str | None]:
        if self.startup_error:
            return False, self.startup_error
        if self.thread is None or not self.thread.is_alive():
            return False, "libtorrent thread is not running"
        if not self.initialized:
            return False, "libtorrent initializing"
        return True, None

    def add_torrent(self, media_id: str, magnet: Magnet) -> TorrentSnapshot:
        return self._call("add_torrent", media_id, magnet)

    def get_snapshot(self, media_id: str) -> TorrentSnapshot | None:
        with self.lock:
            return self.snapshots.get(media_id)

    def select_file(self, media_id: str, file_index: int) -> SelectionResult:
        return self._call("select_file", media_id, file_index)

    def prioritize_range(
        self,
        media_id: str,
        request_token: str | None,
        active_pieces: tuple[int, ...],
        preload_pieces: tuple[int, ...],
    ) -> str:
        return str(self._call("prioritize_range", media_id, request_token, tuple(active_pieces), tuple(preload_pieces)))

    def release_range(self, media_id: str, request_token: str) -> None:
        self._call("release_range", media_id, request_token)

    def have_pieces(self, media_id: str, pieces: tuple[int, ...]) -> bool:
        return bool(self._call("have_pieces", media_id, tuple(pieces)))

    def _call(self, name: str, *args: Any) -> Any:
        """Run a command on the libtorrent owner thread and return its result."""
        ready, error = self.ready()
        if not ready:
            raise ApiError(HTTPStatus.SERVICE_UNAVAILABLE, "libtorrent_unavailable", error or "libtorrent is unavailable")
        result: queue.Queue = queue.Queue(maxsize=1)
        self.commands.put(Command(name=name, args=args, result=result))
        ok, value = result.get(timeout=30)
        if ok:
            return value
        raise value

    def _run(self) -> None:
        """Owner-thread loop for libtorrent.

        Initialization, command execution, alert polling, snapshot refreshes,
        and persistence all happen here. Keeping that work serialized preserves
        the libtorrent owner-thread rule while request threads only see stable
        snapshots and command results.
        """
        try:
            self.lt = self.import_libtorrent()
            self._create_session()
            self._restore_from_manifest()
            self.initialized = True
        except Exception as exc:
            self.startup_error = "libtorrent startup failed"
            backend_error("libtorrent_startup_failed", error_class=exc.__class__.__name__, message=str(exc))
            return

        while True:
            try:
                try:
                    command = self.commands.get(timeout=0.25)
                except queue.Empty:
                    self._poll_alerts()
                    self._refresh_snapshots()
                    self._periodic_resume_save()
                    continue
                if command is STOP_COMMAND:
                    self._shutdown_save()
                    return
                self._handle_command(command)
            except Exception:
                backend_exception("engine_loop_exception")

    def _create_session(self) -> None:
        listen_interfaces = default_libtorrent_listen_interfaces(config.BITTORRENT_PORT)
        dht_bootstrap_nodes = config.configured_dht_bootstrap_nodes()
        settings = {
            "listen_interfaces": listen_interfaces,
            "enable_dht": True,
            "dht_bootstrap_nodes": dht_bootstrap_nodes,
            "enable_lsd": True,
            "enable_upnp": False,
            "enable_natpmp": False,
            "announce_to_all_trackers": config.profile_default_bool(
                self.discovery_profile,
                config.BITTORRENT_ANNOUNCE_TO_ALL_TRACKERS,
            ),
            "announce_to_all_tiers": config.profile_default_bool(
                self.discovery_profile,
                config.BITTORRENT_ANNOUNCE_TO_ALL_TIERS,
            ),
        }
        settings.update(self.discovery_settings)
        alert_mask = self._diagnostic_alert_mask()
        if alert_mask is not None:
            settings["alert_mask"] = alert_mask
        try:
            self.session = self.lt.session(settings)
        except TypeError:
            self.session = self.lt.session()
            if hasattr(self.session, "apply_settings"):
                try:
                    self.session.apply_settings(settings)
                except Exception as exc:
                    backend_exception("libtorrent_apply_settings_failed", exc)
        self._restore_session_state()
        extensions = self._enable_discovery_extensions()
        backend_log(
            "libtorrent_session_created",
            listen_interfaces=listen_interfaces,
            dht_bootstrap_nodes=dht_bootstrap_nodes,
            cache_mode=self.cache_mode,
            discovery_profile=self.discovery_profile,
            discovery_settings=self.discovery_settings,
            discovery_extensions=extensions,
            announce_to_all_trackers=settings["announce_to_all_trackers"],
            announce_to_all_tiers=settings["announce_to_all_tiers"],
        )

    def _enable_discovery_extensions(self) -> list[str]:
        if self.session is None or not hasattr(self.session, "add_extension"):
            return []
        enabled = []
        for creator_name, extension_name in (
            ("create_ut_metadata_plugin", "ut_metadata"),
            ("create_ut_pex_plugin", "ut_pex"),
        ):
            creator = getattr(self.lt, creator_name, None)
            if creator is None:
                continue
            try:
                self.session.add_extension(creator)
                enabled.append(extension_name)
            except Exception:
                try:
                    self.session.add_extension(creator())
                    enabled.append(extension_name)
                except Exception as exc:
                    backend_exception("libtorrent_extension_enable_failed", exc, extension=extension_name)
        return enabled

    def _restore_session_state(self) -> None:
        if self.session is None or not hasattr(self.session, "load_state"):
            return
        state = self.resume_store.load_session_state(self.lt)
        if not state:
            return
        try:
            self.session.load_state(state)
            backend_log("libtorrent_session_state_loaded")
        except Exception as exc:
            backend_exception("session_state_load_failed", exc)
            self.resume_store.quarantine(self.resume_store.session_state_path)

    def _diagnostic_alert_mask(self) -> int | None:
        categories = getattr(getattr(self.lt, "alert", None), "category_t", None)
        if categories is None:
            return None
        mask = 0
        for name in (
            "error_notification",
            "tracker_notification",
            "dht_notification",
            "port_mapping_notification",
            "status_notification",
            "torrent_log_notification",
            "session_log_notification",
        ):
            value = getattr(categories, name, None)
            if value is None:
                continue
            try:
                mask |= int(value)
            except Exception:
                raw_value = getattr(value, "value", None)
                try:
                    mask |= int(raw_value() if callable(raw_value) else raw_value)
                except Exception:
                    continue
        return mask or None

    def _restore_from_manifest(self) -> None:
        """Recreate remembered magnets from the range-server manifest."""
        records = self.resume_store.load()
        for media_id, record in records.items():
            try:
                magnet = parse_magnet(record["magnet"])
                handle = self._add_handle(media_id, magnet)
                snapshot = TorrentSnapshot(
                    media_id=media_id,
                    magnet=magnet.normalized,
                    info_hash=magnet.info_hash,
                    selected_file_index=record.get("selected_file_index"),
                )
                with self.lock:
                    self.snapshots[media_id] = snapshot
                self.handles[media_id] = handle
            except Exception:
                backend_exception("restore_from_manifest_failed", media_id=media_id)

    def _handle_command(self, command: Command) -> None:
        """Dispatch one queued public API command inside the owner thread."""
        try:
            if command.name == "add_torrent":
                value = self._add_torrent(*command.args)
            elif command.name == "select_file":
                value = self._select_file(*command.args)
            elif command.name == "prioritize_range":
                value = self._prioritize_range(*command.args)
            elif command.name == "release_range":
                value = self._release_range(*command.args)
            elif command.name == "have_pieces":
                value = self._have_pieces(*command.args)
            else:
                raise RuntimeError(f"unknown command {command.name}")
            command.result.put((True, value))
        except Exception as exc:
            backend_error(
                "engine_command_failed",
                command=command.name,
                error_class=exc.__class__.__name__,
                message=str(exc),
            )
            command.result.put((False, exc))

    def _add_torrent(self, media_id: str, magnet: Magnet) -> TorrentSnapshot:
        with self.lock:
            current = self.snapshots.get(media_id)
            if current:
                if current.info_hash and current.info_hash != magnet.info_hash:
                    raise ApiError(
                        HTTPStatus.CONFLICT,
                        "duplicate_media_conflict",
                        "media_id already points to another info hash",
                    )
                return current

        handle = self._add_handle(media_id, magnet)
        snapshot = TorrentSnapshot(media_id=media_id, magnet=magnet.normalized, info_hash=magnet.info_hash)
        with self.lock:
            self.snapshots[media_id] = snapshot
        self.handles[media_id] = handle
        self._save_manifest()
        self._request_resume_save(media_id)
        return snapshot

    def _add_handle(self, media_id: str, magnet: Magnet) -> Any:
        params = self._read_resume_params(media_id, magnet)
        if params is None:
            params = self.lt.parse_magnet_uri(magnet.raw)
        params.save_path = str(self.torrents_dir / media_id)
        enable_parallel_tracker_announces(params, self.discovery_profile)
        handle = self.session.add_torrent(params)
        self._kickstart_torrent_discovery(handle, magnet, params)
        return handle

    def _read_resume_params(self, media_id: str, magnet: Magnet) -> Any | None:
        """Load fastresume data, preferring files that still contain metadata.

        Libtorrent may produce resume data before metadata is available. That
        data is useful as a fallback, but it must not replace a metadata-rich
        backup because metadata is what makes file listing and selection work
        after restart.
        """
        if not self.resume_store.cache_enabled():
            return None
        primary_path = self.resume_store.resume_path(media_id)
        metadata_path = self.resume_store.metadata_resume_path(media_id)
        fallback_params = None

        for path in (primary_path, metadata_path):
            if not path.exists():
                continue
            try:
                params = self.lt.read_resume_data(path.read_bytes())
                resume_info_hash = self._params_info_hash(params)
                if resume_info_hash != magnet.info_hash:
                    raise ValueError("fastresume info_hash does not match magnet")
                if self._params_have_metadata(params):
                    return params
                if fallback_params is None:
                    fallback_params = params
            except Exception:
                self.resume_store.quarantine(path)

        return fallback_params

    def _kickstart_torrent_discovery(self, handle: Any, magnet: Magnet, params: Any) -> None:
        for method_name in ("force_reannounce", "force_dht_announce"):
            method = getattr(handle, method_name, None)
            if not method:
                continue
            try:
                method()
            except Exception:
                backend_exception("torrent_discovery_kickstart_failed", method=method_name)
        self._dht_get_peers(magnet, params)

    def _dht_get_peers(self, magnet: Magnet, params: Any) -> None:
        if self.session is None or not hasattr(self.session, "dht_get_peers"):
            return
        info_hash = self._params_best_info_hash(params) or self._make_sha1_hash(magnet.info_hash)
        if info_hash is None:
            return
        try:
            self.session.dht_get_peers(info_hash)
            backend_log("torrent_dht_get_peers_requested", info_hash=magnet.info_hash)
        except Exception as exc:
            backend_exception("torrent_dht_get_peers_failed", exc, info_hash=magnet.info_hash)

    def _params_best_info_hash(self, params: Any) -> Any | None:
        info_hashes = getattr(params, "info_hashes", None)
        if info_hashes is not None and hasattr(info_hashes, "get_best"):
            try:
                return info_hashes.get_best()
            except Exception:
                return None
        return getattr(params, "info_hash", None)

    def _make_sha1_hash(self, info_hash: str) -> Any | None:
        sha1_hash = getattr(self.lt, "sha1_hash", None)
        if sha1_hash is None:
            return None
        try:
            return sha1_hash(bytes.fromhex(info_hash))
        except Exception:
            try:
                return sha1_hash(info_hash)
            except Exception:
                return None

    def _params_info_hash(self, params: Any) -> str | None:
        info_hashes = getattr(params, "info_hashes", None)
        if info_hashes is not None and hasattr(info_hashes, "get_best"):
            return str(info_hashes.get_best()).lower()
        info_hash = getattr(params, "info_hash", None)
        if info_hash is not None:
            return str(info_hash).lower()
        return None

    def _params_have_metadata(self, params: Any) -> bool:
        return getattr(params, "ti", None) is not None

    def _select_file(self, media_id: str, file_index: int) -> SelectionResult:
        """Select the playable video and seed initial file/piece priorities."""
        snapshot = self.snapshots.get(media_id)
        if snapshot is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "not_found", "torrent is unknown")
        if not snapshot.metadata_ready:
            raise ApiError(HTTPStatus.CONFLICT, "metadata_not_ready", "metadata is not ready")
        selected = next((file for file in snapshot.files if file.index == file_index), None)
        if selected is None or selected.kind != "video" or not selected.supported:
            raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_file_index", "file_index must select a supported video")

        linked = linked_subtitle_indices(snapshot.files, file_index)
        handle = self.handles.get(media_id)
        if handle is not None:
            priorities = [0] * len(snapshot.files)
            priorities[file_index] = 2
            for subtitle_index in linked:
                if subtitle_index < len(priorities):
                    priorities[subtitle_index] = 4
            if hasattr(handle, "prioritize_files"):
                handle.prioritize_files(priorities)
            # Keep container headers and trailers warm so ffmpeg can probe and seek.
            for piece in selected_head_tail_pieces(selected):
                if hasattr(handle, "piece_priority"):
                    handle.piece_priority(piece, 5)

        updated = replace(snapshot, selected_file_index=file_index)
        with self.lock:
            self.snapshots[media_id] = updated
        self._save_manifest()
        self._request_resume_save(media_id)
        return SelectionResult(media_id=media_id, selected_file_index=file_index, linked_subtitles=linked)

    def _prioritize_range(
        self,
        media_id: str,
        request_token: str | None,
        active_pieces: tuple[int, ...],
        preload_pieces: tuple[int, ...],
    ) -> str:
        """Raise piece priorities for one active streaming request.

        Each HTTP stream keeps a token so overlapping reads can share priority.
        Active pieces are highest, preload pieces are next, and pieces leave the
        boosted set only when no live request still needs them.
        """
        snapshot = self.snapshots.get(media_id)
        if snapshot is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "not_found", "torrent is unknown")
        if snapshot.selected_file_index is None:
            raise ApiError(HTTPStatus.CONFLICT, "file_not_selected", "no selected file is available")
        selected = next((file for file in snapshot.files if file.index == snapshot.selected_file_index), None)
        if selected is None:
            raise ApiError(HTTPStatus.CONFLICT, "file_not_selected", "selected file is not available")
        handle = self.handles.get(media_id)
        if handle is None or not hasattr(handle, "piece_priority"):
            return request_token or self._new_range_token()

        active = {int(piece) for piece in active_pieces if int(piece) >= 0}
        preload = {int(piece) for piece in preload_pieces if int(piece) >= 0} - active
        if request_token is None:
            request_token = self._new_range_token()
        requests = self.range_requests.setdefault(media_id, {})
        old_active, old_preload = self._range_union(media_id)
        requests[request_token] = (active, preload)
        new_active, new_preload = self._range_union(media_id)
        head_tail = set(selected_head_tail_pieces(selected))

        old = old_active.union(old_preload)
        new = new_active.union(new_preload)
        # Releasing a range must restore only pieces no other request still owns.
        for piece in sorted(old - new - head_tail):
            priority = 2 if selected.piece_start <= piece <= selected.piece_end else 0
            handle.piece_priority(piece, priority)
        for piece in sorted(head_tail - new):
            handle.piece_priority(piece, 5)
        for piece in sorted(new_preload - new_active):
            handle.piece_priority(piece, 6)
        for piece in sorted(new_active):
            handle.piece_priority(piece, 7)

        return request_token

    def _release_range(self, media_id: str, request_token: str) -> None:
        """Drop one stream's range token and lower pieces that are no longer needed."""
        snapshot = self.snapshots.get(media_id)
        if snapshot is None or snapshot.selected_file_index is None:
            return None
        selected = next((file for file in snapshot.files if file.index == snapshot.selected_file_index), None)
        if selected is None:
            return None
        requests = self.range_requests.get(media_id)
        if not requests or request_token not in requests:
            return None
        handle = self.handles.get(media_id)
        old_active, old_preload = self._range_union(media_id)
        del requests[request_token]
        if not requests:
            self.range_requests.pop(media_id, None)
        new_active, new_preload = self._range_union(media_id)
        if handle is None or not hasattr(handle, "piece_priority"):
            return None

        head_tail = set(selected_head_tail_pieces(selected))
        old = old_active.union(old_preload)
        new = new_active.union(new_preload)
        # Head/tail pieces stay elevated after transient range priorities end.
        for piece in sorted(old - new - head_tail):
            priority = 2 if selected.piece_start <= piece <= selected.piece_end else 0
            handle.piece_priority(piece, priority)
        for piece in sorted(head_tail - new):
            handle.piece_priority(piece, 5)
        for piece in sorted(new_preload - new_active):
            handle.piece_priority(piece, 6)
        for piece in sorted(new_active):
            handle.piece_priority(piece, 7)
        return None

    def _range_union(self, media_id: str) -> tuple[set[int], set[int]]:
        """Return the combined active and preload pieces for all live range tokens."""
        active: set[int] = set()
        preload: set[int] = set()
        for request_active, request_preload in self.range_requests.get(media_id, {}).values():
            active.update(request_active)
            preload.update(request_preload)
        preload.difference_update(active)
        return active, preload

    def _new_range_token(self) -> str:
        self.range_request_counter += 1
        return f"range-{self.range_request_counter}"

    def _have_pieces(self, media_id: str, pieces: tuple[int, ...]) -> bool:
        if not pieces:
            return True
        handle = self.handles.get(media_id)
        if handle is None:
            return False
        try:
            status = handle.status() if hasattr(handle, "status") else None
            if status is not None and bool(getattr(status, "is_seeding", False)):
                return True
        except Exception:
            pass
        if not hasattr(handle, "have_piece"):
            return False
        for piece in pieces:
            try:
                if not bool(handle.have_piece(int(piece))):
                    return False
            except Exception:
                return False
        return True

    def _poll_alerts(self) -> None:
        if self.session is None or not hasattr(self.session, "pop_alerts"):
            return
        for alert in self.session.pop_alerts():
            name = alert.__class__.__name__
            media_id = self._media_id_for_handle(getattr(alert, "handle", None))
            if self._is_diagnostic_alert(name):
                self._record_alert(media_id, name, str(alert))
            if name == "metadata_received_alert":
                self._refresh_snapshots()
                self._save_manifest()
                if media_id:
                    self._request_resume_save(media_id)
            elif name == "save_resume_data_alert":
                if media_id:
                    try:
                        self._write_resume_data(media_id, alert.params)
                    except Exception as exc:
                        backend_exception("resume_data_write_failed", exc, media_id=media_id)
            elif name == "save_resume_data_failed_alert":
                backend_error("resume_save_failed", alert=str(alert))
            elif name == "dht_bootstrap_alert":
                self._save_session_state(force=True)
            elif name == "dht_reply_alert":
                self._save_session_state()

    def _is_diagnostic_alert(self, name: str) -> bool:
        return (
            name == "metadata_received_alert"
            or name.startswith("tracker_")
            or name.startswith("dht_")
            or name.startswith("listen_")
            or name.startswith("portmap_")
            or name.startswith("external_ip")
            or name in {"torrent_error_alert", "torrent_finished_alert"}
        )

    def _record_alert(self, media_id: str | None, alert_type: str, message: str) -> None:
        record = {
            "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "type": alert_type,
            "message": message[:500],
        }
        if media_id:
            alerts = self.recent_alerts.setdefault(media_id, [])
        else:
            alerts = self.session_alerts
        alerts.append(record)
        del alerts[:-config.MAX_RECENT_ALERTS]
        backend_log("libtorrent_alert", media_id=media_id, alert_type=alert_type, message=message[:500])

    def _refresh_snapshots(self) -> None:
        for media_id, handle in list(self.handles.items()):
            try:
                with self.lock:
                    previous = self.snapshots[media_id]
                snapshot = self._snapshot_from_handle(media_id, previous, handle)
                with self.lock:
                    self.snapshots[media_id] = snapshot
            except ApiError as exc:
                self._disable_handle(handle)
                with self.lock:
                    previous = self.snapshots.get(media_id)
                    if previous:
                        self.snapshots[media_id] = replace(previous, status="failed", error=exc.code)
                backend_error("snapshot_refresh_api_error", media_id=media_id, code=exc.code, message=exc.message)
            except Exception as exc:
                backend_exception("snapshot_refresh_failed", exc, media_id=media_id)

    def _snapshot_from_handle(self, media_id: str, previous: TorrentSnapshot, handle: Any) -> TorrentSnapshot:
        """Build the immutable snapshot published to API and range handlers."""
        status = handle.status()
        status_has_metadata = getattr(status, "has_metadata", None)
        if status_has_metadata is not None:
            has_metadata = bool(status_has_metadata() if callable(status_has_metadata) else status_has_metadata)
        else:
            has_metadata = bool(handle.has_metadata()) if hasattr(handle, "has_metadata") else False
        pieces_total = 0
        files: tuple[FileSnapshot, ...] = ()
        name = previous.name
        bytes_total = int(getattr(status, "total_wanted", 0) or 0)
        if has_metadata:
            torrent_info = handle.torrent_file()
            name = str(torrent_info.name())
            piece_length = int(torrent_info.piece_length())
            pieces_total = int(torrent_info.num_pieces())
            storage = torrent_info.files()
            raw_files: list[RawTorrentFile] = []
            for index in range(int(storage.num_files())):
                raw_files.append(
                    RawTorrentFile(
                        index=index,
                        path=str(storage.file_path(index)),
                        size=int(storage.file_size(index)),
                        offset=int(storage.file_offset(index)),
                    )
                )
            # Torrent metadata is untrusted, so policy and path checks run before exposure.
            ensure_storage_policy(raw_files, self.torrents_dir)
            file_progress = self._file_progress(handle)
            files = build_file_snapshots(raw_files, piece_length, file_progress)
            bytes_total = sum(file.size for file in files)
        else:
            piece_length = previous.piece_length

        error = torrent_error_code(status)
        diagnostics = self._status_diagnostics(media_id, status)
        state = "metadata"
        if has_metadata:
            state = "downloaded" if bool(getattr(status, "is_seeding", False)) else "downloading"
        if error:
            state = "failed"
        return TorrentSnapshot(
            media_id=media_id,
            magnet=previous.magnet,
            info_hash=previous.info_hash,
            name=name,
            status=state,
            metadata_ready=has_metadata,
            selected_file_index=previous.selected_file_index,
            progress={
                "bytes_downloaded": int(getattr(status, "total_done", 0) or 0),
                "bytes_total": bytes_total,
                "pieces_have": int(getattr(status, "num_pieces", 0) or 0),
                "pieces_total": pieces_total,
            },
            error=error,
            files=files,
            piece_length=piece_length,
            diagnostics=diagnostics,
        )

    def _status_diagnostics(self, media_id: str, status: Any) -> dict[str, Any]:
        recent_alerts = list(self.recent_alerts.get(media_id, ())[-config.MAX_RECENT_ALERTS:])
        session_alerts = list(self.session_alerts[-config.MAX_RECENT_ALERTS:])
        return {
            "cache_mode": self.cache_mode,
            "discovery_profile": self.discovery_profile,
            "discovery_settings": dict(self.discovery_settings),
            "libtorrent_state": str(getattr(status, "state", "unknown")),
            "num_peers": int(getattr(status, "num_peers", 0) or 0),
            "num_seeds": int(getattr(status, "num_seeds", 0) or 0),
            "list_peers": int(getattr(status, "list_peers", 0) or 0),
            "connect_candidates": int(getattr(status, "connect_candidates", 0) or 0),
            "download_rate": int(getattr(status, "download_rate", 0) or 0),
            "upload_rate": int(getattr(status, "upload_rate", 0) or 0),
            "total_download": int(getattr(status, "total_download", 0) or 0),
            "total_payload_download": int(getattr(status, "total_payload_download", 0) or 0),
            "alert_summary": self._alert_summary(recent_alerts, session_alerts),
            "recent_alerts": recent_alerts,
            "session_alerts": session_alerts,
        }

    def _alert_summary(self, recent_alerts: list[dict[str, Any]], session_alerts: list[dict[str, Any]]) -> dict[str, Any]:
        alerts = recent_alerts + session_alerts
        tracker_alerts = [alert for alert in alerts if str(alert.get("type", "")).startswith("tracker_")]
        dht_alerts = [alert for alert in alerts if str(alert.get("type", "")).startswith("dht_")]
        return {
            "tracker_alerts": len(tracker_alerts),
            "tracker_errors": sum(1 for alert in tracker_alerts if alert.get("type") == "tracker_error_alert"),
            "dht_alerts": len(dht_alerts),
            "last_tracker_alert_at": tracker_alerts[-1].get("at") if tracker_alerts else None,
            "last_dht_alert_at": dht_alerts[-1].get("at") if dht_alerts else None,
        }

    def _file_progress(self, handle: Any) -> list[int] | None:
        if not hasattr(handle, "file_progress"):
            return None
        try:
            return [int(value) for value in handle.file_progress()]
        except TypeError:
            return [int(value) for value in handle.file_progress(0)]
        except Exception:
            return None

    def _periodic_resume_save(self) -> None:
        now = time.monotonic()
        if now - self.last_resume_save < config.RESUME_SAVE_INTERVAL_SECONDS:
            return
        self.last_resume_save = now
        for media_id in list(self.handles):
            self._request_resume_save(media_id)
        self._save_manifest()
        self._save_session_state()

    def _request_resume_save(self, media_id: str) -> None:
        if not self.resume_store.cache_enabled():
            return
        handle = self.handles.get(media_id)
        if handle is not None and hasattr(handle, "save_resume_data"):
            try:
                flags = self._resume_save_flags()
                if flags is None:
                    handle.save_resume_data()
                else:
                    handle.save_resume_data(flags)
            except Exception as exc:
                backend_exception("resume_save_request_failed", exc, media_id=media_id)

    def _resume_save_flags(self) -> Any:
        flag_type = getattr(self.lt, "save_resume_flags_t", None)
        return getattr(flag_type, "save_info_dict", None)

    def _write_resume_data(self, media_id: str, params: Any) -> None:
        """Persist fastresume data without losing a metadata-rich backup.

        Metadata-bearing resume files are kept both as the primary file and as a
        separate backup. If libtorrent later emits metadata-less resume data,
        the backup is restored or preserved so a restart can still list files.
        """
        if not self.resume_store.cache_enabled():
            return
        data = bytes(self.lt.write_resume_data_buf(params))
        primary_path = self.resume_store.resume_path(media_id)
        metadata_path = self.resume_store.metadata_resume_path(media_id)
        incoming_has_metadata = self._params_have_metadata(params)

        if not incoming_has_metadata:
            # Metadata-less resume data should never overwrite known metadata.
            if self._resume_file_has_metadata(primary_path):
                backend_log("skip_resume_without_metadata", media_id=media_id, reason="primary_has_metadata")
                return
            if self._resume_file_has_metadata(metadata_path):
                write_bytes_atomic(primary_path, metadata_path.read_bytes())
                backend_log("restored_metadata_resume_backup", media_id=media_id)
                return

        write_bytes_atomic(primary_path, data)
        if incoming_has_metadata:
            write_bytes_atomic(metadata_path, data)

    def _resume_file_has_metadata(self, path: Path) -> bool:
        if not path.exists():
            return False
        try:
            return self._params_have_metadata(self.lt.read_resume_data(path.read_bytes()))
        except Exception:
            return False

    def _save_session_state(self, force: bool = False) -> None:
        if self.session is None:
            return
        now = time.monotonic()
        if not force and now - self.last_session_state_save < config.SESSION_STATE_SAVE_INTERVAL_SECONDS:
            return
        self.last_session_state_save = now
        try:
            self.resume_store.save_session_state(self.lt, self.session, self._session_state_save_flags())
        except Exception as exc:
            backend_exception("session_state_save_failed", exc)

    def _session_state_save_flags(self) -> Any:
        flag_type = getattr(self.lt, "save_state_flags_t", None)
        return getattr(flag_type, "save_dht_state", None)

    def _save_manifest(self) -> None:
        with self.lock:
            snapshots = dict(self.snapshots)
        self.resume_store.save(snapshots)

    def _shutdown_save(self) -> None:
        for media_id in list(self.handles):
            self._request_resume_save(media_id)
        deadline = time.monotonic() + 1.0
        while time.monotonic() < deadline:
            self._poll_alerts()
            time.sleep(0.05)
        self._save_manifest()
        self._save_session_state(force=True)

    def _disable_handle(self, handle: Any) -> None:
        try:
            has_metadata = handle.has_metadata() if hasattr(handle, "has_metadata") else False
            if hasattr(handle, "prioritize_files") and hasattr(handle, "torrent_file") and has_metadata:
                storage = handle.torrent_file().files()
                handle.prioritize_files([0] * int(storage.num_files()))
        except Exception as exc:
            backend_exception("disable_handle_prioritize_failed", exc)
        try:
            if hasattr(handle, "pause"):
                handle.pause()
        except Exception as exc:
            backend_exception("disable_handle_pause_failed", exc)

    def _media_id_for_handle(self, alert_handle: Any) -> str | None:
        if alert_handle is None:
            return None
        for media_id, handle in self.handles.items():
            try:
                if handle == alert_handle:
                    return media_id
            except Exception:
                continue
        return None
