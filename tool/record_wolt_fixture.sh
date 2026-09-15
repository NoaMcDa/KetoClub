#!/usr/bin/env bash
# Records a real Wolt `menu/data` payload as a checked-in test fixture
# (issue #22; see test/fixtures/README.md for why the checked-in
# wolt_vitrina_lilinblum_menu.json is synthetic instead).
#
# `restaurant-api.wolt.com` is unreachable from the build environment this
# script was written in — the egress proxy answers 403 to the CONNECT —
# so it could not be run there. Run it from any machine with normal
# internet access instead:
#
#   tool/record_wolt_fixture.sh <venue-slug>
#
# Example (the canonical slug used across this repo's docs and fixtures):
#
#   tool/record_wolt_fixture.sh vitrina-lilinblum
#
# Writes test/fixtures/wolt_{slug}_menu.json, pretty-printed, prefixed
# with a `_fixture_note` key naming the venue, the recording date, the
# endpoint, and what was redacted. WoltMenuMapper ignores unknown
# top-level keys by contract (see wolt_menu_mapper.dart's class doc
# comment and wolt_menu_mapper_test.dart), so `_fixture_note` sitting
# alongside the real payload never affects mapping.
#
# Then runs test/services/menu/wolt/wolt_fixture_shape_test.dart, which
# checks every field WoltMenuMapper reads is present and correctly
# typed — so a schema drift in the real payload shows up immediately,
# not the next time someone happens to run the suite.

set -euo pipefail
cd "$(dirname "$0")/.."

# The same header lib/utils/constants.dart's `browserUserAgent` sends —
# several platform APIs reject a request with no browser-shaped UA. Keep
# the two in sync if it ever changes (test/fixtures/README.md carries the
# same note for the curl command this script replaces).
readonly user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

# Key names redacted wherever they appear in the payload, case-insensitive
# — a menu endpoint should carry none of these, but a platform can add a
# field this script has never seen.
readonly redact_key_pattern='token|secret|auth|session|apikey|api[_-]?key|password|passwd|email|phone|cookie|bearer|ssn'

usage() {
  echo "Usage: tool/record_wolt_fixture.sh <venue-slug>" >&2
  echo "Example: tool/record_wolt_fixture.sh vitrina-lilinblum" >&2
}

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  usage
  exit 1
fi

for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "record_wolt_fixture: '$cmd' is required but not on PATH." >&2
    exit 1
  fi
done

slug="$1"
url="https://restaurant-api.wolt.com/v4/venues/slug/${slug}/menu/data"
out_file="test/fixtures/wolt_${slug}_menu.json"

tmp_body="$(mktemp)"
trap 'rm -f "$tmp_body"' EXIT

echo "== fetching $url"
set +e
http_status="$(curl -sS -o "$tmp_body" -w '%{http_code}' \
  -H "User-Agent: $user_agent" \
  -H 'Accept: application/json' \
  "$url")"
curl_exit=$?
set -e

if [ "$curl_exit" -ne 0 ]; then
  echo "record_wolt_fixture: FAILED — curl could not reach $url (exit $curl_exit)." >&2
  echo "Check your network connection; this host is unreachable from some build environments by design." >&2
  exit 1
fi

if [ "$http_status" != "200" ]; then
  echo "record_wolt_fixture: FAILED — $url returned HTTP $http_status, not 200." >&2
  echo "Response body was:" >&2
  cat "$tmp_body" >&2
  echo >&2
  exit 1
fi

if ! jq -e . "$tmp_body" >/dev/null 2>&1; then
  echo "record_wolt_fixture: FAILED — the response body is not valid JSON." >&2
  echo "Response body was:" >&2
  cat "$tmp_body" >&2
  echo >&2
  exit 1
fi

echo "== redacting personal data and tokens"
# Two passes: redact any value whose *key* looks sensitive (token, auth,
# email, ...), then, everywhere else, redact any *string value* shaped
# like a bearer token or a JWT, regardless of its key — belt and braces,
# since a platform can name a field anything.
redacted="$(jq --arg keys "$redact_key_pattern" '
  def redact_by_key:
    if type == "object" then
      with_entries(
        if (.key | test($keys; "i")) then .value = "[REDACTED]"
        else .value |= redact_by_key
        end
      )
    elif type == "array" then map(redact_by_key)
    else . end;
  def looks_like_a_token:
    test("^[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}$")
    or test("^(?i:bearer )")
    or test("^[A-Za-z0-9_-]{40,}$");
  def redact_token_shaped:
    if type == "string" and looks_like_a_token then "[REDACTED]"
    elif type == "object" then map_values(redact_token_shaped)
    elif type == "array" then map(redact_token_shaped)
    else . end;
  redact_by_key | redact_token_shaped
' "$tmp_body")"

recorded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
note="Recorded ${recorded_at} from ${url} for venue slug \"${slug}\" by tool/record_wolt_fixture.sh. NOT synthetic. Redacted: any field whose key matched /${redact_key_pattern}/i, and any bearer-token- or JWT-shaped string value found anywhere in the payload, each replaced with the literal string \"[REDACTED]\". Re-run this script to refresh; do not hand-edit the payload below without updating this note."

jq --arg note "$note" '{_fixture_note: $note} + .' <<<"$redacted" > "$out_file"

echo "== wrote $out_file"

echo "== running the fixture-shape test"
export PATH="/opt/flutter/bin:$PATH"
flutter test test/services/menu/wolt/wolt_fixture_shape_test.dart

echo
echo "Done. Review $out_file for anything the redaction pass above missed"
echo "before committing it — it is about to become public in this repo's"
echo "git history."
