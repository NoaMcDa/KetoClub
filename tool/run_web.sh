#!/usr/bin/env bash
# Runs the app in Chrome for local development with the browser's
# same-origin enforcement switched off (architecture.md §13).
#
# The restaurant platforms answer browser requests from foreign origins
# without CORS headers, so a plain `flutter run -d chrome` cannot read a
# Wolt menu: the browser refuses the response and the app reports the venue
# as unreadable in a browser. Chrome started this way skips that check, so
# a pasted Wolt link works exactly as it does on a phone.
#
# Development only. Never ship a build that relies on this flag; a deployed
# web build needs the CORS proxy architecture.md §13 describes.
#
# Usage: tool/run_web.sh [extra flutter run arguments]
set -euo pipefail
cd "$(dirname "$0")/.."

exec flutter run -d chrome \
  --web-browser-flag=--disable-web-security \
  "$@"
