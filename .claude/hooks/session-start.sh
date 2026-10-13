#!/usr/bin/env bash
# SessionStart hook: give a Claude Code cloud session the toolchain that
# `tool/check.sh` and `backend/check.sh` need.
#
#   * Flutter 3.47.4 (the version pinned in pubspec.yaml and ci.yml) at
#     /opt/flutter, with the web artifacts pre-cached.
#   * The app's pub packages (`flutter pub get`).
#   * The backend's locked Python environment (`uv sync --frozen`).
#   * /opt/flutter/bin on PATH for every later shell, via $CLAUDE_ENV_FILE.
#
# It runs synchronously on purpose: a worker must be able to run its checks
# the moment the session opens. It is idempotent (a second run skips the
# clone and finds every package already fetched) and a no-op everywhere
# except a cloud session, so it never touches a developer's laptop.
set -euo pipefail

# 1. Cloud sessions only. CLAUDE_CODE_REMOTE is "true" there and unset on a
#    laptop, where the developer manages their own Flutter.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_VERSION="3.47.4"
FLUTTER_DIR="/opt/flutter"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 2. Flutter SDK. Skip the clone only when an existing install reports the
#    pinned version; a missing SDK is a fresh shallow clone of the tag. An
#    existing directory that is not the pinned version is an error, not
#    something to delete.
flutter_version_of_install() {
  "$FLUTTER_DIR/bin/flutter" --version 2>/dev/null \
    | sed -n 's/^Flutter \([0-9][0-9.]*\).*/\1/p' | head -n 1
}

installed=""
if [ -x "$FLUTTER_DIR/bin/flutter" ]; then
  installed="$(flutter_version_of_install || true)"
fi

if [ "$installed" = "$FLUTTER_VERSION" ]; then
  echo "session-start: Flutter $FLUTTER_VERSION already at $FLUTTER_DIR, skipping clone"
else
  echo "session-start: installing Flutter $FLUTTER_VERSION into $FLUTTER_DIR"
  # Never delete an SDK we did not verify: git cannot clone into a non-empty
  # directory, so say what is wrong and stop instead of guessing.
  if [ -n "$(ls -A "$FLUTTER_DIR" 2>/dev/null)" ]; then
    echo "session-start: $FLUTTER_DIR exists but is not Flutter $FLUTTER_VERSION" >&2
    echo "session-start: (found '${installed:-none}'); remove it and rerun." >&2
    exit 1
  fi
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

# Opt out of analytics (non-interactive; avoids the first-run banner), then
# fetch the web engine artifacts the flow tests and `flutter build web` need.
flutter config --no-analytics >/dev/null 2>&1 || true
flutter precache --web

# 3. The app's dependencies.
cd "$PROJECT_DIR"
flutter pub get
pub_status="pub get done"

# 4. The backend's dependencies. A missing `uv` must not fail the session:
#    the Flutter side is still usable, and the message says what is missing.
uv_status="uv sync skipped (uv not installed)"
if command -v uv >/dev/null 2>&1; then
  (cd "$PROJECT_DIR/backend" && uv sync --frozen)
  uv_status="uv sync done"
else
  echo "session-start: 'uv' is not installed; skipping the backend setup." >&2
  echo "session-start: install it from https://docs.astral.sh/uv/ and run" >&2
  echo "session-start: 'cd backend && uv sync --frozen' to run backend/check.sh." >&2
fi

# 5. Put Flutter on PATH for every shell the session opens later. Guarded so
#    a repeat run does not append a duplicate line.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  path_line="export PATH=$FLUTTER_DIR/bin:\$PATH"
  if ! grep -qxF "$path_line" "$CLAUDE_ENV_FILE" 2>/dev/null; then
    echo "$path_line" >> "$CLAUDE_ENV_FILE"
  fi
fi

# 6. One-line summary.
echo "session-start: Flutter $(flutter_version_of_install), $pub_status, $uv_status"
