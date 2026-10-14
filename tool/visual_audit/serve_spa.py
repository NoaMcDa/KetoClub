"""Serves a Flutter web build with the single-page-app fallback its path
URLs need (docs/RUNNING.md, "Web shell"; issue #226): a file that exists is
served as is, and every other path gets `index.html`, so a deep link such as
`/venue/wolt/hamosad` loads the app instead of a 404 — which
`python3 -m http.server` cannot do (docs/VISUAL_AUDIT.md).

    python3 tool/visual_audit/serve_spa.py build/web [port]   # default 8080

Standard library only; binds 127.0.0.1.
"""

import functools
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class Handler(SimpleHTTPRequestHandler):
    """Falls back to `index.html` for any path that names no file."""

    def send_head(self):  # noqa: D102 - SimpleHTTPRequestHandler's hook
        path = self.translate_path(self.path)
        if not os.path.exists(path):
            self.path = "/index.html"
        return super().send_head()


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "build/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
    handler = functools.partial(Handler, directory=root)
    print(f"serving {root} on http://127.0.0.1:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
