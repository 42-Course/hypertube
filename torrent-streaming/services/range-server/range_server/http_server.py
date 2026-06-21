"""Stdlib HTTP adapter for the range-server application.

The handler owns protocol details such as bounded request reads, JSON response
encoding, HEAD suppression, and streaming chunk writes. Application code stays
framework-free and returns plain response objects.
"""

from __future__ import annotations

import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler
from urllib.parse import urlparse

from . import config
from .application import Application
from .models import HttpResponse
from .observability import backend_error, backend_log

class Handler(BaseHTTPRequestHandler):
    """Route HTTP requests into ``Application`` and write protocol responses."""

    server_version = "RangeServer/0.4"
    app: Application

    def do_HEAD(self) -> None:
        self.dispatch()

    def do_GET(self) -> None:
        self.dispatch()

    def do_POST(self) -> None:
        self.dispatch()

    def dispatch(self) -> None:
        """Dispatch file streaming separately from the bounded JSON API."""

        parsed = urlparse(self.path)
        if self.command in {"GET", "HEAD"} and parsed.path.startswith("/files/"):
            # The streaming layer owns Range parsing and HEAD semantics; the
            # adapter only suppresses body bytes for HEAD after headers are set.
            headers = {key: value for key, value in self.headers.items()}
            response = self.app.handle_file(self.command, self.path, headers)
            self.respond_http(response, suppress_body=self.command == "HEAD")
            return

        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            self.respond(HTTPStatus.BAD_REQUEST, {"error": "invalid_content_length"})
            return
        if length < 0:
            self.respond(HTTPStatus.BAD_REQUEST, {"error": "invalid_content_length"})
            return
        # JSON endpoints are read fully into memory, so enforce the shared body
        # limit before touching ``rfile``.
        if length > config.MAX_JSON_BODY_BYTES:
            self.respond(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "body_too_large"})
            return
        body = self.rfile.read(length) if length else b""
        status, payload = self.app.handle(self.command, self.path, body)
        self.respond(status, payload)

    def log_message(self, fmt: str, *args: object) -> None:
        """Send BaseHTTPRequestHandler access logs through structured logging."""

        backend_log("http_request_log", remote_addr=self.address_string(), message=fmt % args)

    def respond(self, status: int, payload: dict[str, object]) -> None:
        """Write the stable JSON response envelope used by API endpoints."""

        body = json.dumps(payload, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def respond_http(self, response: HttpResponse, suppress_body: bool = False) -> None:
        """Write a prepared file response and stream body chunks when allowed."""

        self.send_response(response.status)
        for key, value in response.headers.items():
            self.send_header(key, value)
        self.end_headers()
        if suppress_body:
            return
        try:
            for chunk in response.chunks():
                self.wfile.write(chunk)
        except Exception as exc:
            # Once headers have been sent, streaming failures can only be logged.
            backend_error("stream_error", error_class=exc.__class__.__name__, message=str(exc))
