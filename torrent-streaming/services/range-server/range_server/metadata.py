"""Torrent metadata normalization and policy checks.

Torrent metadata is peer-supplied and therefore untrusted. This module turns it
into safe `FileSnapshot` values, enforces size/path/storage limits, links nearby
subtitles to selected videos, and resolves sanitized paths under the torrent
payload directory.
"""

from __future__ import annotations

import mimetypes
import re
import shutil
from http import HTTPStatus
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import unquote

from . import config
from .models import ApiError, FileSnapshot, HttpByteRange, RawTorrentFile

def sanitize_metadata_path(value: Any) -> str:
    """Return a display/storage-safe relative POSIX path from torrent metadata.

    Paths may be percent-encoded, Windows-shaped, empty, or hostile. Traversal
    is rejected, while harmless empty or device-like segments are dropped so all
    later file resolution starts from sanitized metadata.
    """
    raw = decode_metadata_path(str(value or "unnamed")).replace("\\", "/").replace("\x00", "?")
    raw_parts = PurePosixPath(raw).parts
    if any(part == ".." for part in raw_parts):
        raise ApiError(HTTPStatus.BAD_REQUEST, "unsafe_metadata_path", "torrent metadata path contains traversal")
    parts: list[str] = []
    for part in raw_parts:
        cleaned = part.strip().replace("\x00", "?")
        if not cleaned or cleaned in {".", "..", "/"}:
            continue
        if cleaned.endswith(":"):
            continue
        parts.append(cleaned)
    if not parts:
        return "unnamed"
    return "/".join(parts)


def decode_metadata_path(value: str) -> str:
    """Decode repeated percent-encoding without looping forever on crafted input."""
    decoded = value
    for _ in range(5):
        next_decoded = unquote(decoded)
        if next_decoded == decoded:
            return decoded
        decoded = next_decoded
    return decoded


def classify_path(path: str) -> tuple[str, bool]:
    extension = PurePosixPath(path).suffix.lower()
    if extension in config.VIDEO_EXTENSIONS:
        return "video", True
    if extension in config.TEXT_SUBTITLE_EXTENSIONS:
        return "subtitle", True
    if extension in config.IMAGE_SUBTITLE_EXTENSIONS:
        return "subtitle", False
    return "other", False


def build_file_snapshots(
    raw_files: list[RawTorrentFile],
    piece_length: int,
    file_progress: list[int] | None = None,
) -> tuple[FileSnapshot, ...]:
    """Validate raw libtorrent files and expose sanitized immutable file snapshots."""
    validate_torrent_metadata_policy(raw_files)
    if piece_length <= 0:
        piece_length = config.DEFAULT_PIECE_LENGTH

    snapshots: list[FileSnapshot] = []
    sanitized_paths: dict[str, int] = {}
    for raw_file in raw_files:
        safe_path = sanitize_metadata_path(raw_file.path)
        normalized_safe_path = safe_path
        if normalized_safe_path in sanitized_paths:
            # Different raw paths can collapse to the same safe path; reject the torrent.
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "duplicate_metadata_path",
                "torrent metadata paths collide after sanitizing",
            )
        sanitized_paths[normalized_safe_path] = raw_file.index
        kind, supported = classify_path(safe_path)
        if raw_file.size > 0:
            piece_start = max(0, raw_file.offset // piece_length)
            piece_end = max(piece_start, (raw_file.offset + raw_file.size - 1) // piece_length)
        else:
            piece_start = 0
            piece_end = -1
        downloaded = 0
        if file_progress and raw_file.index < len(file_progress):
            downloaded = max(0, min(int(file_progress[raw_file.index]), raw_file.size))
        snapshots.append(
            FileSnapshot(
                index=raw_file.index,
                path=safe_path,
                display_name=PurePosixPath(safe_path).name or safe_path,
                size=max(0, int(raw_file.size)),
                offset=max(0, int(raw_file.offset)),
                piece_start=piece_start,
                piece_end=piece_end,
                kind=kind,
                supported=supported,
                progress={"bytes_downloaded": downloaded, "bytes_total": max(0, int(raw_file.size))},
            )
        )
    return tuple(snapshots)


def validate_torrent_metadata_policy(raw_files: list[RawTorrentFile]) -> int:
    """Enforce metadata count, path length, per-file, and total-size limits."""
    if len(raw_files) > config.MAX_TORRENT_FILES:
        raise ApiError(HTTPStatus.BAD_REQUEST, "too_many_files", "torrent has too many files")

    total_size = 0
    for raw_file in raw_files:
        raw_path = unquote(str(raw_file.path or ""))
        if len(raw_path.encode("utf-8", errors="replace")) > config.MAX_METADATA_PATH_BYTES:
            raise ApiError(HTTPStatus.BAD_REQUEST, "path_too_long", "torrent metadata path is too long")
        file_size = max(0, int(raw_file.size))
        if file_size > config.MAX_FILE_BYTES:
            raise ApiError(HTTPStatus.BAD_REQUEST, "file_too_large", "torrent file exceeds configured limit")
        total_size += file_size

    if total_size > config.MAX_TOTAL_TORRENT_BYTES:
        raise ApiError(HTTPStatus.BAD_REQUEST, "torrent_too_large", "torrent exceeds configured size limit")
    return total_size


def ensure_storage_policy(raw_files: list[RawTorrentFile], torrents_dir: Path) -> None:
    """Reject torrents that exceed metadata limits or available payload storage."""
    total_size = validate_torrent_metadata_policy(raw_files)
    torrents_dir.mkdir(parents=True, exist_ok=True)
    free_bytes = shutil.disk_usage(torrents_dir).free
    required_free = total_size + max(0, config.MIN_FREE_SPACE_BYTES)
    if free_bytes < required_free:
        raise ApiError(HTTPStatus.INSUFFICIENT_STORAGE, "storage_free_space_low", "insufficient torrent storage space")


def linked_subtitle_indices(files: tuple[FileSnapshot, ...], video_index: int) -> tuple[int, ...]:
    """Find supported text subtitles next to a video with the same stem prefix."""
    video = next((file for file in files if file.index == video_index), None)
    if video is None:
        raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_file_index", "selected file does not exist")

    video_path = PurePosixPath(video.path)
    video_parent = str(video_path.parent).lower()
    video_stem = video_path.stem.lower()
    linked: list[int] = []
    for file in files:
        if file.kind != "subtitle" or not file.supported:
            continue
        subtitle_path = PurePosixPath(file.path)
        if str(subtitle_path.parent).lower() != video_parent:
            continue
        subtitle_stem = subtitle_path.stem.lower()
        if (
            subtitle_stem == video_stem
            or subtitle_stem.startswith(f"{video_stem}.")
            or subtitle_stem.startswith(f"{video_stem}-")
            or subtitle_stem.startswith(f"{video_stem}_")
        ):
            linked.append(file.index)
    return tuple(sorted(linked))


def selected_head_tail_pieces(file: FileSnapshot) -> tuple[int, ...]:
    """Return probe-friendly head and tail pieces to keep elevated after selection."""
    if file.piece_end < file.piece_start:
        return ()
    head = range(file.piece_start, min(file.piece_end + 1, file.piece_start + config.HEAD_TAIL_PIECES))
    tail_start = max(file.piece_start, file.piece_end - config.HEAD_TAIL_PIECES + 1)
    tail = range(tail_start, file.piece_end + 1)
    return tuple(sorted(set(head).union(tail)))

def range_content_type(file: FileSnapshot) -> str:
    extension = PurePosixPath(file.path).suffix.lower()
    explicit = {
        ".mkv": "video/x-matroska",
        ".mp4": "video/mp4",
        ".m4v": "video/mp4",
        ".mov": "video/quicktime",
        ".webm": "video/webm",
        ".avi": "video/x-msvideo",
        ".ts": "video/mp2t",
    }
    if extension in explicit:
        return explicit[extension]
    guessed, _encoding = mimetypes.guess_type(file.path)
    return guessed or "application/octet-stream"


def safe_torrent_file_path(torrents_dir: Path, media_id: str, file: FileSnapshot) -> Path:
    """Resolve a sanitized torrent file path and prove it stays under its media root."""
    base = (torrents_dir / media_id).resolve()
    parts = [part for part in PurePosixPath(file.path).parts if part not in {"", ".", "/"}]
    candidate = base.joinpath(*parts).resolve()
    try:
        # Defense in depth: sanitized metadata still must not escape the payload root.
        candidate.relative_to(base)
    except ValueError as exc:
        raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_file_path", "file path is outside torrent storage") from exc
    return candidate


def json_http_response(status: int, payload: dict[str, Any], headers: dict[str, str] | None = None) -> HttpResponse:
    body = json.dumps(payload, sort_keys=True).encode("utf-8")
    response_headers = {
        "Content-Type": "application/json",
        "Content-Length": str(len(body)),
    }
    if headers:
        response_headers.update(headers)
    return HttpResponse(status=status, headers=response_headers, body=body)


def torrent_error_code(status: Any) -> str | None:
    """Convert libtorrent error status into a stable API-safe diagnostic code."""
    errc = getattr(status, "errc", None)
    if errc is None:
        return None
    value = getattr(errc, "value", None)
    try:
        numeric_value = value() if callable(value) else value
    except Exception:
        numeric_value = None
    if numeric_value == 0:
        return None
    message_attr = getattr(errc, "message", None)
    try:
        message = message_attr() if callable(message_attr) else str(errc)
    except Exception:
        message = str(errc)
    if not message or message.lower() in {"success", "no error", "system:0"}:
        return None
    sanitized = re.sub(r"[^a-z0-9]+", "_", message.lower()).strip("_")
    return sanitized[:64] or "torrent_error"
