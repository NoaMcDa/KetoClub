#!/usr/bin/env bash
# Runs locally exactly what the `quality` and `test` CI jobs run
# (architecture.md §18.5). Use it before pushing, or link it as a git hook:
#   ln -s ../../tool/check.sh .git/hooks/pre-push
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== flutter pub get"
flutter pub get

echo "== dart format"
dart format --output=none --set-exit-if-changed lib test integration_test test_driver

echo "== flutter analyze"
flutter analyze --fatal-infos --fatal-warnings

echo "== coverage helper"
tool/gen_coverage_helper.sh

echo "== flutter test (unit + flow + architecture)"
flutter test --coverage

echo "== coverage gate"
tool/coverage_gate.sh coverage/lcov.info

echo "All checks passed."
