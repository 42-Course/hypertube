#!/usr/bin/env python3
"""Compatibility entry point for the range-server container.

Docker still starts this file directly, so it prepares package imports,
keeps the legacy reexport surface available, and then hands off to the real
runtime wiring in ``range_server.main``.
"""

from pathlib import Path
import sys

SERVICE_ROOT = Path(__file__).resolve().parent
# Direct script execution does not put this service root on ``sys.path``.
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))

from range_server import *  # noqa: F401,F403 - legacy reexports
from range_server.main import main

if __name__ == "__main__":
    main()
