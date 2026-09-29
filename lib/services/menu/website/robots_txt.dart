import 'package:flutter/foundation.dart';

/// The product token KetoClub answers to in `robots.txt`, matched without
/// regard to case against each `User-agent` line. The backend uses the
/// same token (`backend/app/services/website.py`).
const String robotsToken = 'ketoclubbot';

/// The `Allow`/`Disallow` rules that apply to KetoClub on one host
/// (RFC 9309, the subset restaurant sites use; architecture.md D19).
///
/// Pure and never throws. The backend carries a line-for-line Python
/// twin, because on web it is the backend that fetches.
@immutable
final class RobotsRules {
  /// Rules that allow everything: no `robots.txt`, or no group for
  /// KetoClub or `*`.
  const new() : _rules = const <(bool, String)>[];

  const new _(this._rules);

  /// Reads [text], keeping the groups that name [robotsToken], or the `*`
  /// groups when none does. Consecutive `User-agent` lines share a group;
  /// unknown keys and lines with no colon are ignored.
  factory parse(String text) {
    final ours = <(bool, String)>[];
    final anyone = <(bool, String)>[];
    var agents = <String>[];
    var inRules = false;
    var namesUs = false;
    var foundUs = false;
    for (final raw in text.split('\n')) {
      final line = raw.split('#').first.trim();
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final key = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      if (key == 'user-agent') {
        if (inRules) {
          agents = <String>[];
          inRules = false;
        }
        agents.add(value.toLowerCase());
        namesUs = agents.any((agent) => agent.contains(robotsToken));
        foundUs = foundUs || namesUs;
        continue;
      }
      if ((key != 'allow' && key != 'disallow') || agents.isEmpty) continue;
      inRules = true;
      if (value.isEmpty) continue;
      final rule = (key == 'allow', value);
      if (namesUs) {
        ours.add(rule);
      } else if (agents.contains('*')) {
        anyone.add(rule);
      }
    }
    return RobotsRules._(List.unmodifiable(foundUs ? ours : anyone));
  }

  final List<(bool, String)> _rules;

  /// Whether [url]'s path and query may be fetched: the longest matching
  /// pattern wins, a tie goes to `Allow`, and `/robots.txt` is always
  /// allowed.
  bool allows(Uri url) {
    final path = url.path.isEmpty ? '/' : url.path;
    final target = url.hasQuery ? '$path?${url.query}' : path;
    if (target == '/robots.txt') return true;
    (bool, String)? best;
    for (final rule in _rules) {
      if (!_matches(rule.$2, target)) continue;
      final current = best;
      if (current == null ||
          rule.$2.length > current.$2.length ||
          (rule.$2.length == current.$2.length && rule.$1)) {
        best = rule;
      }
    }
    return best?.$1 ?? true;
  }

  static bool _matches(String pattern, String path) {
    final anchored = pattern.endsWith(r'$');
    final body = anchored ? pattern.substring(0, pattern.length - 1) : pattern;
    final source = body.split('*').map(RegExp.escape).join('.*');
    return RegExp('^$source${anchored ? r'$' : ''}').hasMatch(path);
  }
}
