import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ketoclub/models/venue.dart';

/// The longest key, in UTF-8 bytes, a Hive box can store (issue #280).
///
/// Hive writes a string key's UTF-8 length in a single byte and checks the
/// limit only inside an `assert`, against the key's UTF-16 length. In a
/// release build a longer key is recorded with its length mod 256, so the
/// next launch reads the entry from the wrong offset and recovery truncates
/// the box there, losing every entry written after it; in a debug build the
/// write throws and is dropped. Every key built here therefore stays within
/// this bound, measured in bytes rather than characters, since a non-ASCII
/// id is longer in bytes than the `assert` counts.
const int maxStorageKeyBytes = 255;

/// The marker between a hashed key's source and its digest. No short key
/// can carry it: a website id is an `http(s)` URL, a Wolt slug, a 10bis id
/// and a scan's hex fingerprint never start with `#`.
const String _hashedMarker = '#sha256:';

/// The key [ref] is stored under in every Hive box keyed by a venue: the
/// menu cache, its pins and the visit history (issue #280; D23).
///
/// [VenueRef.cacheKey] itself (`source/platformId`) whenever it fits in
/// [maxStorageKeyBytes], so every key already on a device is unchanged.
/// A longer one, in practice a website URL carrying a long query, is
/// `source/#sha256:<hex digest of platformId>`: 80 bytes for a website,
/// stable across runs and platforms, and still unique per platform.
String storageKeyFor(VenueRef ref) {
  final key = ref.cacheKey;
  if (utf8.encode(key).length <= maxStorageKeyBytes) return key;
  final digest = sha256.convert(utf8.encode(ref.platformId));
  return '${ref.source.name}/$_hashedMarker$digest';
}
