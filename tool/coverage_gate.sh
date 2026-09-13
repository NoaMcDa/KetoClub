#!/usr/bin/env bash
# Fails when line coverage across lib/ is below the threshold
# (architecture.md §18.4). Generated files are excluded.
#
# Usage: tool/coverage_gate.sh [path/to/lcov.info]
# Env:   COVERAGE_MIN  minimum percentage, default 80
set -euo pipefail

lcov_file="${1:-coverage/lcov.info}"
min="${COVERAGE_MIN:-80}"

if [ ! -s "$lcov_file" ]; then
  echo "coverage gate: $lcov_file is missing or empty. Run 'flutter test --coverage' first." >&2
  exit 1
fi

awk -v min="$min" '
  /^SF:/ {
    path = substr($0, 4)
    skip = (path ~ /\.g\.dart$/ || path ~ /\.freezed\.dart$/ || path ~ /\/l10n\//)
  }
  /^LF:/ { if (!skip) lf += substr($0, 4) }
  /^LH:/ { if (!skip) lh += substr($0, 4) }
  END {
    if (lf == 0) { print "coverage gate: no instrumented lines found." > "/dev/stderr"; exit 1 }
    pct = 100 * lh / lf
    printf "coverage gate: %.1f%% of %d lines covered (minimum %s%%)\n", pct, lf, min
    if (pct + 0 < min + 0) { print "coverage gate: FAILED" > "/dev/stderr"; exit 1 }
  }
' "$lcov_file"
