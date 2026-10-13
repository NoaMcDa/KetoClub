#!/usr/bin/env bash
# Builds the web app into build/web.
#
# Usage:
#   tool/build_web.sh            # the KetoClub web build
#   tool/build_web.sh --banto    # the Banto web build
#
# --banto adds --dart-define=BANTO_MODE=true (lib/utils/banto_mode.dart) and
# copies web/manifest.banto.json over build/web/manifest.json, so the installed
# app's name is Banto. Without it the build is exactly `flutter build web
# --release`. Extra arguments after the flag are not accepted.
set -euo pipefail

cd "$(dirname "$0")/.."

banto=false
case "${1:-}" in
  "") ;;
  --banto) banto=true ;;
  *)
    echo "usage: tool/build_web.sh [--banto]" >&2
    exit 2
    ;;
esac
if [ "$#" -gt 1 ]; then
  echo "usage: tool/build_web.sh [--banto]" >&2
  exit 2
fi

if [ "$banto" = true ]; then
  flutter build web --release --dart-define=BANTO_MODE=true
  cp web/manifest.banto.json build/web/manifest.json
else
  flutter build web --release
fi
