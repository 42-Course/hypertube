"""Seekable HTTP file streaming for selected torrent files.

This module validates `/files/...` requests, parses HTTP Range headers, maps
byte ranges to torrent pieces, asks the engine to prioritize those pieces, and
streams only bytes that are both downloaded and visible in the local payload
file.
"""

from __future__ import annotations

import json
import time
from http import HTTPStatus
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from . import config
from .metadata import range_content_type, safe_torrent_file_path
from .models import ApiError, FileSnapshot, HttpByteRange, HttpResponse, PieceTimeout, SourceReadError
from .observability import backend_error, backend_exception, backend_log
from .validation import header_value, parse_file_index, validate_media_id

def parse_http_range_header(header_value: str | None, total_size: int) -> HttpByteRange | None:
    """Parse the single-range forms supported by the service.

    Invalid, unsatisfiable, and multi-range requests become 416 responses with
    the required `Content-Range: bytes */size` header attached to the ApiError.
    """
    if header_value is None or str(header_value).strip() == "":
        return None
    header = str(header_value).strip()
    if not header.lower().startswith("bytes="):
        raise_range_not_satisfiable(total_size, "invalid_range")
    spec = header[6:].strip()
    if "," in spec:
        raise_range_not_satisfiable(total_size, "multi_range_unsupported")
    if "-" not in spec:
        raise_range_not_satisfiable(total_size, "invalid_range")
    start_text, end_text = [part.strip() for part in spec.split("-", 1)]
    if total_size < 0:
        total_size = 0
    if total_size == 0:
        raise_range_not_satisfiable(total_size, "range_not_satisfiable")

    if start_text == "":
        if not end_text.isdigit():
            raise_range_not_satisfiable(total_size, "invalid_range")
        suffix_length = int(end_text)
        if suffix_length <= 0:
            raise_range_not_satisfiable(total_size, "range_not_satisfiable")
        start = max(0, total_size - suffix_length)
        return HttpByteRange(start=start, end=total_size - 1)

    if not start_text.isdigit() or (end_text and not end_text.isdigit()):
        raise_range_not_satisfiable(total_size, "invalid_range")
    start = int(start_text)
    if start >= total_size:
        raise_range_not_satisfiable(total_size, "range_not_satisfiable")
    end = total_size - 1 if end_text == "" else min(int(end_text), total_size - 1)
    if end < start:
        raise_range_not_satisfiable(total_size, "range_not_satisfiable")
    return HttpByteRange(start=start, end=end)


def is_open_ended_http_range(header_value: str | None) -> bool:
    if header_value is None:
        return False
    header = str(header_value).strip()
    if not header.lower().startswith("bytes="):
        return False
    spec = header[6:].strip()
    if "," in spec or "-" not in spec:
        return False
    start_text, end_text = [part.strip() for part in spec.split("-", 1)]
    return bool(start_text) and end_text == ""


def raise_range_not_satisfiable(total_size: int, code: str) -> None:
    raise ApiError(
        HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE,
        code,
        code,
        headers={
            "Accept-Ranges": "bytes",
            "Content-Range": f"bytes */{max(0, total_size)}",
        },
    )


def pieces_for_file_range(file: FileSnapshot, piece_length: int, byte_range: HttpByteRange) -> tuple[int, ...]:
    """Translate a file-relative byte range into absolute torrent piece indexes."""
    if byte_range.length <= 0:
        return ()
    if piece_length <= 0:
        piece_length = config.DEFAULT_PIECE_LENGTH
    absolute_start = file.offset + byte_range.start
    absolute_end = file.offset + byte_range.end
    piece_start = absolute_start // piece_length
    piece_end = absolute_end // piece_length
    return tuple(range(piece_start, piece_end + 1))


def preload_pieces_after(file: FileSnapshot, active_pieces: tuple[int, ...]) -> tuple[int, ...]:
    if not active_pieces or config.RANGE_PRELOAD_PIECES <= 0:
        return ()
    first = max(active_pieces) + 1
    last = min(file.piece_end, first + config.RANGE_PRELOAD_PIECES - 1)
    if first > last:
        return ()
    return tuple(range(first, last + 1))


def chunk_range_for(byte_range: HttpByteRange, offset: int) -> HttpByteRange:
    chunk_size = min(max(1, config.RANGE_CHUNK_BYTES), byte_range.end - offset + 1)
    return HttpByteRange(offset, offset + chunk_size - 1)


def iter_chunk_ranges(byte_range: HttpByteRange) -> Any:
    offset = byte_range.start
    while offset <= byte_range.end:
        chunk_range = chunk_range_for(byte_range, offset)
        yield chunk_range
        offset = chunk_range.end + 1


def json_http_response(status: int, payload: dict[str, Any], headers: dict[str, str] | None = None) -> HttpResponse:
    body = json.dumps(payload, sort_keys=True).encode("utf-8")
    response_headers = {
        "Content-Type": "application/json",
        "Content-Length": str(len(body)),
    }
    if headers:
        response_headers.update(headers)
    return HttpResponse(status=status, headers=response_headers, body=body)



class RangeStreamer:
    """HTTP-facing coordinator for selected-file range streaming."""

    def __init__(self, engine: Any, torrents_dir: Path) -> None:
        self.engine = engine
        self.torrents_dir = torrents_dir

    def handle_file(self, method: str, raw_path: str, headers: dict[str, str] | None = None) -> HttpResponse:
        try:
            return self._handle_file(method, raw_path, headers or {})
        except PieceTimeout as exc:
            backend_error(
                "range_piece_timeout_response",
                method=method,
                path=raw_path,
                media_id=exc.media_id,
                file_index=exc.file_index,
                start=exc.byte_range.start,
                end=exc.byte_range.end,
                pieces=list(exc.pieces),
                timeout_seconds=exc.timeout_seconds,
            )
            payload = {
                "error": "piece_timeout",
                "media_id": exc.media_id,
                "file_index": exc.file_index,
                "range": {"start": exc.byte_range.start, "end": exc.byte_range.end},
                "pieces": list(exc.pieces),
                "timeout_seconds": exc.timeout_seconds,
            }
            return json_http_response(
                HTTPStatus.SERVICE_UNAVAILABLE,
                payload,
                {
                    "Retry-After": "5",
                    "X-Range-Error": "piece_timeout",
                },
            )
        except ApiError as exc:
            if exc.code == "multi_range_unsupported":
                self._log_range("multi_range_unsupported", path=raw_path)
            backend_error(
                "range_api_error_response",
                method=method,
                path=raw_path,
                status=exc.status,
                code=exc.code,
                message=exc.message,
            )
            return json_http_response(exc.status, {"error": exc.code, "message": exc.message}, exc.headers)
        except SourceReadError as exc:
            backend_error(
                "range_source_read_short_response",
                method=method,
                path=raw_path,
                media_id=exc.media_id,
                file_index=exc.file_index,
                start=exc.byte_range.start,
                end=exc.byte_range.end,
                expected_bytes=exc.expected_bytes,
                actual_bytes=exc.actual_bytes,
            )
            payload = {
                "error": "source_read_short",
                "media_id": exc.media_id,
                "file_index": exc.file_index,
                "range": {"start": exc.byte_range.start, "end": exc.byte_range.end},
                "expected_bytes": exc.expected_bytes,
                "actual_bytes": exc.actual_bytes,
            }
            return json_http_response(
                HTTPStatus.SERVICE_UNAVAILABLE,
                payload,
                {
                    "X-Range-Error": "source_read_short",
                },
            )
        except Exception as exc:
            backend_exception("range_internal_error", exc, method=method, path=raw_path)
            return json_http_response(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "internal_error"})

    def _handle_file(self, method: str, raw_path: str, headers: dict[str, str]) -> HttpResponse:
        """Validate a file request and prepare a streamable response.

        The first chunk is prioritized and checked before returning the response
        object, so early piece or sparse-file failures can still become a
        structured 503. Once the body iterator starts, HTTP status and headers
        have already been sent by the server.
        """
        parsed = urlparse(raw_path)
        path_parts = [part for part in parsed.path.split("/") if part]
        if len(path_parts) != 3 or path_parts[0] != "files":
            raise ApiError(HTTPStatus.NOT_FOUND, "not_found", "file endpoint is unknown")
        if method not in {"GET", "HEAD"}:
            raise ApiError(HTTPStatus.METHOD_NOT_ALLOWED, "method_not_allowed", "method is not allowed")

        media_id = validate_media_id(path_parts[1])
        file_index = parse_file_index(path_parts[2])
        snapshot = self.engine.get_snapshot(media_id)
        if snapshot is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "not_found", "torrent is unknown")
        if not snapshot.metadata_ready:
            raise ApiError(HTTPStatus.CONFLICT, "metadata_not_ready", "metadata is not ready")
        if snapshot.selected_file_index != file_index:
            raise ApiError(HTTPStatus.CONFLICT, "file_not_selected", "requested file is not selected")
        file = next((candidate for candidate in snapshot.files if candidate.index == file_index), None)
        if file is None or file.kind != "video" or not file.supported:
            raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_file_index", "file_index must select a supported video")

        range_header = header_value(headers, "Range")
        parsed_range = parse_http_range_header(range_header, file.size)
        open_ended_range = is_open_ended_http_range(range_header)
        is_range_request = parsed_range is not None
        if parsed_range is None:
            byte_range = HttpByteRange(0, max(0, file.size - 1))
            status = HTTPStatus.OK
        else:
            byte_range = parsed_range
            status = HTTPStatus.PARTIAL_CONTENT

        response_range = byte_range

        content_type = range_content_type(file)
        backend_log(
            "range_file_request",
            method=method,
            media_id=media_id,
            file_index=file_index,
            range_header=range_header,
            response_status=status,
            start=response_range.start,
            end=response_range.end,
            file_size=file.size,
            open_ended_range=open_ended_range,
            content_type=content_type,
        )
        response_headers = {
            "Accept-Ranges": "bytes",
            "Content-Type": content_type,
        }
        if parsed_range is None:
            if method == "HEAD" or file.size == 0:
                response_headers["Content-Length"] = str(file.size)
            else:
                # Full-file GET streams until close so growth/wait behavior stays chunk-driven.
                response_headers["Connection"] = "close"
        else:
            response_headers["Content-Length"] = str(response_range.length if file.size > 0 else 0)
            response_headers["Content-Range"] = f"bytes {response_range.start}-{response_range.end}/{file.size}"

        if method == "HEAD" or file.size == 0:
            # HEAD reports metadata only; it must not prioritize pieces or open payload files.
            return HttpResponse(status=status, headers=response_headers)

        file_path = safe_torrent_file_path(self.torrents_dir, media_id, file)
        request_token: str | None = None
        try:
            prepare_range = (
                chunk_range_for(byte_range, byte_range.start)
                if open_ended_range or not is_range_request
                else response_range
            )
            for chunk_range in iter_chunk_ranges(prepare_range):
                request_token = self._prioritize_and_wait_chunk(
                    media_id,
                    file_index,
                    file,
                    snapshot.piece_length,
                    request_token,
                    chunk_range,
                    release_on_error=True,
                )
                self._wait_for_source_contains_chunk(media_id, file_index, file_path, chunk_range, config.RANGE_PIECE_TIMEOUT_SECONDS)
        except Exception:
            if request_token is not None:
                self.engine.release_range(media_id, request_token)
            raise

        return HttpResponse(
            status=status,
            headers=response_headers,
            body_iter=lambda: self._iter_file_chunks(
                media_id,
                file_index,
                file,
                snapshot.piece_length,
                file_path,
                response_range,
                request_token,
                first_chunk=chunk_range_for(response_range, response_range.start),
            ),
        )

    def _wait_for_source_contains_chunk(
        self,
        media_id: str,
        file_index: int,
        file_path: Path,
        chunk_range: HttpByteRange,
        timeout_seconds: float,
    ) -> None:
        """Wait until libtorrent's sparse payload file covers the requested chunk.

        Having the torrent pieces is necessary but not sufficient: the payload
        file may appear or grow slightly later. This guard prevents returning a
        short read as valid media bytes.
        """
        deadline = time.monotonic() + max(0, timeout_seconds)
        last_size = 0
        expected_end = chunk_range.end + 1
        while True:
            try:
                last_size = file_path.stat().st_size
                if last_size >= expected_end:
                    return
            except FileNotFoundError:
                last_size = 0
            except OSError:
                last_size = 0
            if time.monotonic() >= deadline:
                actual = max(0, last_size - chunk_range.start)
                self._log_range(
                    "source_read_short",
                    media_id=media_id,
                    file_index=file_index,
                    start=chunk_range.start,
                    end=chunk_range.end,
                    expected_bytes=chunk_range.length,
                    actual_bytes=actual,
                )
                raise SourceReadError(media_id, file_index, chunk_range, chunk_range.length, actual)
            time.sleep(min(config.RANGE_WAIT_POLL_SECONDS, max(0.0, deadline - time.monotonic())))

    def _prioritize_and_wait_chunk(
        self,
        media_id: str,
        file_index: int,
        file: FileSnapshot,
        piece_length: int,
        request_token: str | None,
        chunk_range: HttpByteRange,
        release_on_error: bool = False,
    ) -> str:
        """Prioritize the chunk's pieces, preload the next window, and wait for availability."""
        pieces = pieces_for_file_range(file, piece_length, chunk_range)
        preload = preload_pieces_after(file, pieces)
        token = self.engine.prioritize_range(media_id, request_token, pieces, preload)
        wait_started = time.monotonic()
        try:
            self._wait_for_pieces(media_id, file_index, chunk_range, pieces, config.RANGE_PIECE_TIMEOUT_SECONDS)
        except Exception:
            if release_on_error:
                self.engine.release_range(media_id, token)
            raise
        waited_seconds = time.monotonic() - wait_started
        self._log_range(
            "range_ready",
            media_id=media_id,
            file_index=file_index,
            start=chunk_range.start,
            end=chunk_range.end,
            pieces=pieces,
            waited_seconds=round(waited_seconds, 3),
        )
        return token

    def _wait_for_pieces(
        self,
        media_id: str,
        file_index: int,
        byte_range: HttpByteRange,
        pieces: tuple[int, ...],
        timeout_seconds: float,
    ) -> None:
        if not pieces:
            return
        deadline = time.monotonic() + max(0, timeout_seconds)
        while True:
            if self.engine.have_pieces(media_id, pieces):
                return
            if time.monotonic() >= deadline:
                self._log_range(
                    "piece_timeout",
                    media_id=media_id,
                    file_index=file_index,
                    start=byte_range.start,
                    end=byte_range.end,
                    pieces=pieces,
                    timeout_seconds=timeout_seconds,
                )
                raise PieceTimeout(media_id, file_index, byte_range, pieces, timeout_seconds)
            time.sleep(min(config.RANGE_WAIT_POLL_SECONDS, max(0.0, deadline - time.monotonic())))

    def _iter_file_chunks(
        self,
        media_id: str,
        file_index: int,
        file: FileSnapshot,
        piece_length: int,
        file_path: Path,
        byte_range: HttpByteRange,
        request_token: str,
        first_chunk: HttpByteRange,
    ) -> Any:
        """Yield file bytes after headers have been committed.

        Later piece or disk-read failures can no longer change the HTTP status,
        so they are logged and the iterator stops cleanly. The range priority
        token is always released in `finally`.
        """
        remaining = byte_range.length
        offset = byte_range.start
        try:
            with file_path.open("rb") as handle:
                handle.seek(offset)
                while remaining > 0:
                    chunk_size = min(max(1, config.RANGE_CHUNK_BYTES), remaining)
                    chunk_range = HttpByteRange(offset, offset + chunk_size - 1)
                    if chunk_range != first_chunk:
                        request_token = self._prioritize_and_wait_chunk(
                            media_id,
                            file_index,
                            file,
                            piece_length,
                            request_token,
                            chunk_range,
                        )
                        self._wait_for_source_contains_chunk(
                            media_id,
                            file_index,
                            file_path,
                            chunk_range,
                            config.RANGE_PIECE_TIMEOUT_SECONDS,
                        )
                    else:
                        pieces = pieces_for_file_range(file, piece_length, chunk_range)
                        try:
                            self._wait_for_pieces(media_id, file_index, chunk_range, pieces, config.RANGE_PIECE_TIMEOUT_SECONDS)
                        except PieceTimeout:
                            # First-chunk timeouts here happen after headers, so stop the body.
                            return
                    data = handle.read(chunk_size)
                    if len(data) != chunk_size:
                        self._log_range(
                            "source_read_short",
                            media_id=media_id,
                            file_index=file_index,
                            start=chunk_range.start,
                            end=chunk_range.end,
                            expected_bytes=chunk_size,
                            actual_bytes=len(data),
                        )
                        return
                    yield data
                    offset += chunk_size
                    remaining -= chunk_size
        except (PieceTimeout, SourceReadError):
            return
        finally:
            # Streaming priorities are transient and must not leak after disconnects.
            self.engine.release_range(media_id, request_token)

    def _log_range(self, event: str, **payload: Any) -> None:
        backend_log(event, **payload)
