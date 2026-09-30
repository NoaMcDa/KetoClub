/// Whether a restaurant-site URL points somewhere on the public internet
/// (architecture.md D19): the app's twin of the backend's `_checked_host`
/// and `is_public_address` (`backend/app/routers/website.py`,
/// `backend/app/services/website.py`), so a pasted or scanned link, or a
/// redirect, cannot make a phone fetch something on its own network.
///
/// Pure and never throws. Unlike the backend, the app cannot resolve a
/// name to its addresses without `dart:io`, so only a host that is itself
/// an IP address is judged by its range; a name is refused only when it
/// is local by its form (`localhost`, `*.local`, no dot at all).
library;

/// Whether [url] may be fetched as a restaurant's site: `http` or
/// `https`, no user info, the default port (80 or 443, as the backend
/// allows), and a public host by [isPublicHost].
bool isPublicWebUrl(Uri url) {
  final scheme = url.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return false;
  if (url.userInfo.isNotEmpty) return false;
  if (url.port != 80 && url.port != 443) return false;
  return isPublicHost(url.host);
}

/// Whether [host] names a public machine: not `localhost` or a
/// `*.localhost`/`*.local` name, not a dotless intranet name, and, when it
/// is an IP address, a globally routable one. A host that is a number in
/// any form but the plain dotted quad (`0x7f.1`, `2130706433`, `127.1`) is
/// refused: resolvers read those as addresses too.
bool isPublicHost(String host) {
  var name = host.toLowerCase();
  if (name.endsWith('.')) name = name.substring(0, name.length - 1);
  if (name.isEmpty) return false;
  if (name.contains(':')) return _isPublicIpv6(name);
  if (!name.contains('.')) return false;
  if (name.endsWith('.localhost') || name.endsWith('.local')) return false;
  final last = name.substring(name.lastIndexOf('.') + 1);
  if (_numericLabel.hasMatch(last)) return _isPublicIpv4(name);
  return true;
}

final RegExp _numericLabel = RegExp(r'^(?:\d+|0x[0-9a-f]*)$');
final RegExp _octet = RegExp(r'^(?:0|[1-9]\d{0,2})$');

/// The IPv4 ranges that are not globally routable, as `(network, prefix)`:
/// this network, private, shared (CGNAT), loopback, link-local, IETF,
/// documentation, benchmarking, multicast and reserved (with broadcast).
const List<(int, int)> _nonPublicIpv4 = <(int, int)>[
  (0x00000000, 8), // 0.0.0.0/8
  (0x0A000000, 8), // 10.0.0.0/8
  (0x64400000, 10), // 100.64.0.0/10
  (0x7F000000, 8), // 127.0.0.0/8
  (0xA9FE0000, 16), // 169.254.0.0/16
  (0xAC100000, 12), // 172.16.0.0/12
  (0xC0000000, 24), // 192.0.0.0/24
  (0xC0000200, 24), // 192.0.2.0/24
  (0xC0A80000, 16), // 192.168.0.0/16
  (0xC6120000, 15), // 198.18.0.0/15
  (0xC6336400, 24), // 198.51.100.0/24
  (0xCB007100, 24), // 203.0.113.0/24
  (0xE0000000, 4), // 224.0.0.0/4, multicast
  (0xF0000000, 4), // 240.0.0.0/4, reserved and broadcast
];

bool _isPublicIpv4(String name) {
  final parts = name.split('.');
  if (parts.length != 4 || !parts.every(_octet.hasMatch)) return false;
  var address = 0;
  for (final part in parts) {
    final octet = int.parse(part);
    if (octet > 255) return false;
    address = (address << 8) | octet;
  }
  return _isPublicIpv4Value(address);
}

bool _isPublicIpv4Value(int address) {
  for (final (network, prefix) in _nonPublicIpv4) {
    final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    if (address & mask == network) return false;
  }
  return true;
}

/// Only global unicast (`2000::/3`) is public, less the IETF protocol
/// block (`2001::/23`), documentation (`2001:db8::/32`) and 6to4
/// (`2002::/16`); so `::`, `::1`, `fc00::/7`, `fe80::/10` and `ff00::/8`
/// are refused. An IPv4-mapped address (`::ffff:a.b.c.d`) is judged as
/// the IPv4 address it carries.
bool _isPublicIpv6(String name) {
  final List<int> bytes;
  try {
    bytes = Uri.parseIPv6Address(name);
  } on FormatException {
    return false;
  }
  final mapped =
      bytes.sublist(0, 10).every((byte) => byte == 0) &&
      bytes[10] == 0xFF &&
      bytes[11] == 0xFF;
  if (mapped) {
    return _isPublicIpv4Value(
      (bytes[12] << 24) | (bytes[13] << 16) | (bytes[14] << 8) | bytes[15],
    );
  }
  if (bytes[0] & 0xE0 != 0x20) return false;
  if (bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] < 0x02) return false;
  if (bytes[0] == 0x20 &&
      bytes[1] == 0x01 &&
      bytes[2] == 0x0D &&
      bytes[3] == 0xB8) {
    return false;
  }
  if (bytes[0] == 0x20 && bytes[1] == 0x02) return false;
  return true;
}
