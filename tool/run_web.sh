#!/usr/bin/env bash
# Runs the app in Chrome for local development with live Wolt menus working
# (architecture.md §13).
#
# The restaurant platforms answer browser requests from foreign origins
# without CORS headers, so a plain `flutter run -d chrome` cannot read a
# Wolt menu: the browser refuses the response and the app reports the venue
# as unreadable in a browser. This starts the local CORS-forwarding proxy
# (tool/cors_proxy.dart) and points the app at it, which is the clean fix
# the architecture names. The proxy stops when flutter run exits.
#
# Usage: tool/run_web.sh [extra flutter run arguments]
#   KETOCLUB_PROXY_PORT=9000 tool/run_web.sh   # use another port
set -euo pipefail
cd "$(dirname "$0")/.."

port="${KETOCLUB_PROXY_PORT:-8787}"

dart run tool/cors_proxy.dart --port "$port" &
proxy_pid=$!
trap 'kill "$proxy_pid" 2>/dev/null || true' EXIT

flutter run -d chrome \
  --dart-define="KETOCLUB_MENU_PROXY_URL=http://127.0.0.1:$port/" \
  "$@"
