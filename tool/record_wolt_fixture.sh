#!/usr/bin/env bash
# Records a real Wolt consumer-assortment payload — the endpoint
# WoltMenuAdapter fetches (issue #168) — as a checked-in test fixture
# (issue #22; test/fixtures/README.md).
#
# `consumer-api.wolt.com` is unreachable from the build environment this
# script was written in — the egress proxy answers 403 to the CONNECT —
# so run it from any machine with normal internet access instead:
#
#   tool/record_wolt_fixture.sh <venue-slug>
#
# Example (the venue the checked-in fixture was recorded from):
#
#   tool/record_wolt_fixture.sh hamosad
#
# Writes test/fixtures/wolt_{slug}_menu.json, pretty-printed, prefixed
# with a `_fixture_note` object naming the venue, the recording time, the
# endpoint, the headers sent and what was redacted. WoltMenuMapper ignores
# unknown top-level keys by contract (see wolt_menu_mapper.dart's class
# doc comment and wolt_menu_mapper_test.dart), so `_fixture_note` sitting
# alongside the real payload never affects mapping.
#
# Then runs test/services/menu/wolt/wolt_fixture_shape_test.dart, which
# checks every field WoltMenuMapper reads is present and correctly
# typed — so a schema drift in the real payload shows up immediately,
# not the next time someone happens to run the suite.
#
# Wolt's older `restaurant-api.wolt.com/v4/venues/slug/{slug}/menu/data`
# endpoint answers every anonymous caller with HTTP 200 and a zero-byte
# body (measured 2026-09-25, issues #22 and #168), so it is not tried: a
# body from it would be the wrong shape for WoltMenuMapper anyway. An
# empty body from the assortment endpoint fails this script loudly for
# the same reason.

set -euo pipefail
cd "$(dirname "$0")/.."

# The header set lib/utils/wolt_headers.dart's `woltWebHeaders` sends,
# with the values lib/utils/constants.dart pins (`browserUserAgent`,
# `woltClientVersion`, `woltSessionIdNoConsent`) and wolt_headers.dart's
# `woltDefaultAppLanguage`. Keep them in sync if any changes. The
# recording checked in on 2026-09-25 needed only the first four.
readonly user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
readonly client_version='1.16.125'
readonly app_language='en'
readonly session_id='no-analytics-consent'

# Key names redacted wherever they appear in the payload, case-insensitive
# — a menu endpoint should carry none of these, but a platform can add a
# field this script has never seen.
readonly redact_key_pattern='token|secret|auth|session|apikey|api[_-]?key|password|passwd|email|phone|cookie|bearer|ssn'

usage() {
  echo "Usage: tool/record_wolt_fixture.sh <venue-slug>" >&2
  echo "Example: tool/record_wolt_fixture.sh hamosad" >&2
}

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  usage
  exit 1
fi

for cmd in curl jq uuidgen; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "record_wolt_fixture: '$cmd' is required but not on PATH." >&2
    exit 1
  fi
done

slug="$1"
url="https://consumer-api.wolt.com/consumer-api/consumer-assortment/v1/venues/slug/${slug}/assortment"
out_file="test/fixtures/wolt_${slug}_menu.json"
# A fresh id per run, the way wolt.com keeps one per browser. Never
# KetoClub's install id (D12).
web_client_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"

tmp_body="$(mktemp)"
trap 'rm -f "$tmp_body"' EXIT

echo "== fetching $url"
set +e
http_status="$(curl -sS -o "$tmp_body" -w '%{http_code}' \
  -H "User-Agent: $user_agent" \
  -H 'Accept: application/json' \
  -H 'platform: Web' \
  -H "app-language: $app_language" \
  -H "client-version: $client_version" \
  -H "clientversionnumber: $client_version" \
  -H "x-wolt-web-clientid: $web_client_id" \
  -H "w-wolt-session-id: $session_id" \
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

if [ ! -s "$tmp_body" ]; then
  echo "record_wolt_fixture: FAILED — $url returned HTTP 200 with an EMPTY body." >&2
  echo "This is how Wolt retired its previous menu endpoint (issues #22, #168):" >&2
  echo "the app now shows 'platform changed' for every Wolt menu. Find the" >&2
  echo "endpoint wolt.com's own web app reads a menu from (DevTools, Network)" >&2
  echo "and open an issue before re-recording." >&2
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

jq \
  --arg slug "$slug" \
  --arg endpoint "GET $url" \
  --arg recorded_at "$recorded_at" \
  --arg user_agent "$user_agent" \
  --arg app_language "$app_language" \
  --arg client_version "$client_version" \
  --arg session_id "$session_id" \
  --arg keys "$redact_key_pattern" \
  '{_fixture_note: {
      venue_slug: $slug,
      endpoint: $endpoint,
      recorded_at: $recorded_at,
      recorded_headers: {
        "User-Agent": $user_agent,
        "Accept": "application/json",
        "platform": "Web",
        "app-language": $app_language,
        "client-version": $client_version,
        "clientversionnumber": $client_version,
        "x-wolt-web-clientid": "<a fresh uuid4 per run>",
        "w-wolt-session-id": $session_id
      },
      redactions: ("any field whose key matched /" + $keys + "/i, and any bearer-token- or JWT-shaped string value, each replaced with the literal string \"[REDACTED]\""),
      purpose: "Real recording by tool/record_wolt_fixture.sh. NOT synthetic. Re-run the script to refresh; do not hand-edit the payload below without updating this note."
    }} + .' <<<"$redacted" > "$out_file"

echo "== endpoint that answered: $url"
echo "== wrote $out_file"

echo "== running the fixture-shape test"
export PATH="/opt/flutter/bin:$PATH"
flutter test test/services/menu/wolt/wolt_fixture_shape_test.dart

echo
echo "Done. Review $out_file for anything the redaction pass above missed"
echo "before committing it — it is about to become public in this repo's"
echo "git history."
