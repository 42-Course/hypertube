"""Runtime wiring for the range-server process.

This module builds the engine-backed application, installs it on the stdlib
HTTP handler, starts the threaded server, and coordinates shutdown so the
libtorrent owner thread can persist resume/session state.
"""

from __future__ import annotations

import signal
import threading
from http.server import ThreadingHTTPServer

from . import config
from .application import Application
from .engine import LibtorrentEngine
from .http_server import Handler
from .observability import backend_log
from .storage import ResumeStore

def build_application() -> Application:
    """Create the storage store, start the torrent engine, and return the app."""

    resume_store = ResumeStore(config.LIBTORRENT_DIR)
    engine = LibtorrentEngine(config.TORRENTS_DIR, resume_store)
    engine.start()
    return Application(engine, resume_store)


def main() -> None:
    """Run the HTTP server until SIGTERM/SIGINT or process shutdown."""

    port = config.PORT
    Handler.app = build_application()
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)

    def request_shutdown(_signum: int, _frame: object) -> None:
        """Ask ``serve_forever`` to stop from outside the signal handler frame."""

        threading.Thread(target=server.shutdown, name="http-shutdown", daemon=True).start()

    signal.signal(signal.SIGTERM, request_shutdown)
    signal.signal(signal.SIGINT, request_shutdown)

    backend_log("listening", port=port)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        Handler.app.engine.stop()
