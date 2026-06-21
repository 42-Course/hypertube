"""Request validation helpers for range-server HTTP inputs.

These functions normalize public identifiers, magnets, JSON bodies, file
indexes, and headers before requests reach the engine or streaming layer.
They raise ``ApiError`` so callers can preserve stable HTTP error mappings.
"""

from __future__ import annotations

import base64
import json
from http import HTTPStatus
from typing import Any
from urllib.parse import parse_qsl, quote, urlparse

from . import config
from .models import ApiError, Magnet

def validate_media_id(value: Any) -> str:
    """Require media IDs to be the 32-character lowercase hex contract."""

    media_id = str(value or "")
    if not config.MEDIA_ID_PATTERN.match(media_id):
        raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_media_id", "media_id must be 32 lowercase hex characters")
    return media_id


def parse_magnet(value: Any) -> Magnet:
    """Validate a magnet URI and produce a stable normalized form."""

    raw = str(value or "").strip()
    if not raw or len(raw.encode("utf-8")) > config.MAX_MAGNET_BYTES:
        raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_magnet", "magnet is empty or too large")

    parsed = urlparse(raw)
    if parsed.scheme.lower() != "magnet" or not parsed.query:
        raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_magnet", "magnet query is required")

    pairs = parse_qsl(parsed.query, keep_blank_values=True)
    normalized_pairs: list[tuple[str, str]] = []
    info_hash: str | None = None
    for key, param_value in pairs:
        normalized_key = key.lower()
        normalized_value = param_value.strip()
        if normalized_key == "xt":
            normalized_value = normalized_value.lower()
            if normalized_value.startswith("urn:btih:"):
                info_hash = normalize_btih(normalized_value.removeprefix("urn:btih:"))
        normalized_pairs.append((normalized_key, normalized_value))

    if info_hash is None:
        raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_magnet", "magnet xt=urn:btih is required")

    # Sorting and percent-encoding make duplicate submissions comparable even
    # when clients send magnet parameters in a different order or case.
    normalized_query = "&".join(
        f"{quote(key, safe='')}={quote(param_value, safe='')}"
        for key, param_value in sorted(normalized_pairs)
    )
    return Magnet(raw=raw, normalized=f"magnet:?{normalized_query}", info_hash=info_hash)


def normalize_btih(value: str) -> str:
    """Return a lowercase hexadecimal info hash from hex or base32 BTIH input."""

    lowered = value.lower()
    if config.BTIH_HEX_PATTERN.match(lowered):
        return lowered
    if config.BTIH_BASE32_PATTERN.match(lowered):
        try:
            return base64.b32decode(lowered.upper()).hex()
        except Exception as exc:
            raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_magnet", "invalid btih base32") from exc
    raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_magnet", "invalid btih")


def parse_json_object(body: bytes) -> dict[str, Any]:
    """Decode a request body that must be a JSON object."""

    try:
        payload = json.loads(body.decode("utf-8") if body else "{}")
    except Exception as exc:
        raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_json", "request body must be JSON") from exc
    if not isinstance(payload, dict):
        raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_body", "request body must be a JSON object")
    return payload


def parse_file_index(value: Any) -> int:
    """Parse a URL path file index as a non-negative integer."""

    text = str(value or "")
    if not text.isdigit():
        raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_file_index", "file_index must be a non-negative integer")
    return int(text)


def header_value(headers: dict[str, str], name: str) -> str | None:
    """Look up a header case-insensitively without changing caller storage."""

    target = name.lower()
    for key, value in headers.items():
        if str(key).lower() == target:
            return value
    return None
