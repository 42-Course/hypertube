"""Shared data models for range-server API and streaming contracts.

The dataclasses in this module are the boundary objects passed between the
application, engine, validation, and HTTP adapter layers. Their ``to_*`` helpers
define JSON payload shapes consumed by other services and tests.
"""

from __future__ import annotations

import queue
from dataclasses import dataclass, field
from typing import Any, Callable

from . import config

class ApiError(Exception):
    """Domain error with a stable HTTP status, code, message, and headers."""

    def __init__(
        self,
        status: int,
        code: str,
        message: str | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message or code)
        self.status = status
        self.code = code
        self.message = message or code
        self.headers = headers or {}


@dataclass(frozen=True)
class Magnet:
    """Normalized magnet input plus the canonical BTIH info hash."""

    raw: str
    normalized: str
    info_hash: str


@dataclass(frozen=True)
class RawTorrentFile:
    """File entry as reported by torrent metadata before API sanitization."""

    index: int
    path: str
    size: int
    offset: int


@dataclass(frozen=True)
class FileSnapshot:
    """Sanitized file metadata exposed through status and file-list APIs."""

    index: int
    path: str
    display_name: str
    size: int
    offset: int
    piece_start: int
    piece_end: int
    kind: str
    supported: bool
    progress: dict[str, int] = field(default_factory=dict)

    def to_api(self) -> dict[str, Any]:
        """Return the public file payload with progress defaults filled in."""

        return {
            "index": self.index,
            "path": self.path,
            "display_name": self.display_name,
            "size": self.size,
            "offset": self.offset,
            "piece_start": self.piece_start,
            "piece_end": self.piece_end,
            "kind": self.kind,
            "supported": self.supported,
            "progress": {
                "bytes_downloaded": self.progress.get("bytes_downloaded", 0),
                "bytes_total": self.progress.get("bytes_total", self.size),
            },
        }


@dataclass(frozen=True)
class TorrentSnapshot:
    """Immutable view of a torrent at one engine refresh point."""

    media_id: str
    magnet: str
    info_hash: str | None = None
    name: str | None = None
    status: str = "metadata"
    metadata_ready: bool = False
    selected_file_index: int | None = None
    progress: dict[str, int] = field(default_factory=dict)
    error: str | None = None
    files: tuple[FileSnapshot, ...] = ()
    piece_length: int = config.DEFAULT_PIECE_LENGTH
    diagnostics: dict[str, Any] = field(default_factory=dict)

    def to_status_api(self) -> dict[str, Any]:
        """Return the stable torrent status payload for ``GET /torrents/:id``."""

        selected_file = next((file for file in self.files if file.index == self.selected_file_index), None)
        return {
            "media_id": self.media_id,
            "info_hash": self.info_hash,
            "name": self.name,
            "status": self.status,
            "metadata_ready": self.metadata_ready,
            "selected_file_index": self.selected_file_index,
            "progress": {
                "bytes_downloaded": self.progress.get("bytes_downloaded", 0),
                "bytes_total": self.progress.get("bytes_total", 0),
                "pieces_have": self.progress.get("pieces_have", 0),
                "pieces_total": self.progress.get("pieces_total", 0),
            },
            "selected_file_progress": (
                {
                    "bytes_downloaded": selected_file.progress.get("bytes_downloaded", 0),
                    "bytes_total": selected_file.progress.get("bytes_total", selected_file.size),
                }
                if selected_file is not None
                else None
            ),
            "error": self.error,
            "diagnostics": self.diagnostics,
        }

    def to_files_api(self) -> dict[str, Any]:
        """Return the file-list payload, hiding files until metadata is ready."""

        return {
            "media_id": self.media_id,
            "metadata_ready": self.metadata_ready,
            "files": [file.to_api() for file in self.files] if self.metadata_ready else [],
        }


@dataclass(frozen=True)
class SelectionResult:
    """Result of choosing the video file that should be prioritized and served."""

    media_id: str
    selected_file_index: int
    linked_subtitles: tuple[int, ...]

    def to_api(self) -> dict[str, Any]:
        """Return the selection response consumed by the web service."""

        return {
            "media_id": self.media_id,
            "selected_file_index": self.selected_file_index,
            "prioritized": {
                "video": True,
                "linked_subtitles": list(self.linked_subtitles),
                "head_tail": True,
            },
        }


@dataclass
class Command:
    """Synchronous command envelope sent to the libtorrent owner thread."""

    name: str
    args: tuple[Any, ...]
    result: queue.Queue


@dataclass(frozen=True)
class HttpByteRange:
    """Inclusive byte range used for HTTP Range parsing and piece waits."""

    start: int
    end: int

    @property
    def length(self) -> int:
        """Return the number of bytes covered by the inclusive range."""

        return self.end - self.start + 1


@dataclass(frozen=True)
class HttpResponse:
    """Prepared HTTP response for either buffered JSON or streamed file bytes."""

    status: int
    headers: dict[str, str]
    body: bytes = b""
    body_iter: Callable[[], Any] | None = None

    def chunks(self) -> Any:
        """Yield response bytes without forcing streamed bodies into memory."""

        if self.body_iter is not None:
            return self.body_iter()
        if self.body:
            return iter((self.body,))
        return iter(())


class PieceTimeout(Exception):
    """Raised when required torrent pieces are unavailable before timeout."""

    def __init__(
        self,
        media_id: str,
        file_index: int,
        byte_range: HttpByteRange,
        pieces: tuple[int, ...],
        timeout_seconds: float,
    ) -> None:
        super().__init__("piece_timeout")
        self.media_id = media_id
        self.file_index = file_index
        self.byte_range = byte_range
        self.pieces = pieces
        self.timeout_seconds = timeout_seconds


class SourceReadError(Exception):
    """Raised when the local source file produces fewer bytes than promised."""

    def __init__(
        self,
        media_id: str,
        file_index: int,
        byte_range: HttpByteRange,
        expected_bytes: int,
        actual_bytes: int,
    ) -> None:
        super().__init__("source_read_short")
        self.media_id = media_id
        self.file_index = file_index
        self.byte_range = byte_range
        self.expected_bytes = expected_bytes
        self.actual_bytes = actual_bytes
