/// The request headers Wolt's own web client sends
/// (`phase2_discovery_research.md` §2.2), shared by every direct call to
/// Wolt: the venue search (issue #39) and the menu fetch (issue #168).
///
/// Pure: no I/O and no state. Callers own the per-instance web client id
/// ([woltWebClientId]) and decide whether a `User-Agent` may be sent.
library;

import 'dart:math';

import 'package:ketoclub/utils/constants.dart';

/// The `app-language` sent when a caller has no language of its own to
/// send — the menu fetch, whose `VenueRef`-only interface carries none.
///
/// It is also what the real recording of the assortment endpoint sent
/// (`test/fixtures/wolt_hamosad_menu.json`'s `_fixture_note`); the menu
/// still came back in the venue's own language (`selected_language: he`),
/// which is the language a waiter script must be written in anyway
/// (architecture.md §12).
const String woltDefaultAppLanguage = 'en';

/// The header set wolt.com sends, for a direct request to Wolt.
///
/// [language] becomes `app-language`; [webClientId] becomes
/// `x-wolt-web-clientid` and must never be KetoClub's install id, which is
/// sent to KetoClub's backend and nowhere else (D12). A browser forbids a
/// page from setting `User-Agent`, so pass [includeUserAgent] false there.
Map<String, String> woltWebHeaders({
  required String language,
  required String webClientId,
  bool includeUserAgent = true,
}) => <String, String>{
  'Accept': 'application/json',
  'platform': 'Web',
  'client-version': woltClientVersion,
  'clientversionnumber': woltClientVersion,
  'app-language': language,
  'x-wolt-web-clientid': webClientId,
  'w-wolt-session-id': woltSessionIdNoConsent,
  if (includeUserAgent) 'User-Agent': browserUserAgent,
};

/// A random (version 4) UUID drawn from [random], in the canonical
/// lowercase 8-4-4-4-12 form: the `x-wolt-web-clientid` value, generated
/// once per service instance the way wolt.com keeps one per browser.
String woltWebClientId(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
