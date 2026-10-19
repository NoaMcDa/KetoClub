// The monthly scan counter in the settings (Banto, ALG-18, issue #360):
// written only while it counts a scan, so a keto install's stored record
// stays byte-identical; read tolerantly; a new month starts from nothing.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/services/storage/settings_store.dart';

void main() {
  group('AppSettings scan counter', () {
    test('defaults to nothing counted, and the default record writes no '
        'counter key', () {
      const settings = AppSettings();
      expect(settings.scanMonth, isEmpty);
      expect(settings.scanCount, 0);
      expect(settings.scansIn('2026-10'), 0);
      expect(settings.toJson().containsKey('monthlyScans'), isFalse);
    });

    test('round-trips through JSON as one month and count', () {
      const settings = AppSettings(scanMonth: '2026-10', scanCount: 3);
      final json = settings.toJson();
      expect(json['monthlyScans'], <String, Object?>{
        'month': '2026-10',
        'count': 3,
      });
      final decoded = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      final read = AppSettings.tryFrom(decoded);
      expect(read, settings);
      expect(read!.scansIn('2026-10'), 3);
    });

    test('a new month reads as nothing counted, with no write', () {
      const settings = AppSettings(scanMonth: '2026-10', scanCount: 5);
      expect(settings.scansIn('2026-11'), 0);
      expect(settings.scansIn('2027-10'), 0);
      expect(settings.scansIn('2026-10'), 5);
    });

    test('a zero count is not written, so it reads back as the '
        'default', () {
      const settings = AppSettings(scanMonth: '2026-10');
      expect(settings.toJson().containsKey('monthlyScans'), isFalse);
      expect(AppSettings.tryFrom(settings.toJson()), const AppSettings());
    });

    test('a malformed counter reads as nothing counted, keeping the rest '
        'of the record', () {
      for (final raw in <Object?>[
        3,
        'many',
        <Object?>[1, 2],
        <String, Object?>{'month': 7, 'count': 2},
        <String, Object?>{'month': '', 'count': 2},
        <String, Object?>{'month': '2026-10', 'count': '2'},
        <String, Object?>{'month': '2026-10', 'count': -1},
        <String, Object?>{'month': '2026-10'},
      ]) {
        final json = const AppSettings(seedOilFree: true).toJson()
          ..['monthlyScans'] = raw;
        final read = AppSettings.tryFrom(json);
        expect(read, isNotNull, reason: '$raw');
        expect(read!.scanCount, 0, reason: '$raw');
        expect(read.scanMonth, isEmpty, reason: '$raw');
        expect(read.seedOilFree, isTrue, reason: '$raw');
      }
    });

    test('copyWith keeps or replaces the counter, and equality and the hash '
        'follow it', () {
      const base = AppSettings(scanMonth: '2026-10', scanCount: 2);
      expect(base.copyWith(), base);
      expect(base.copyWith().hashCode, base.hashCode);
      final next = base.copyWith(scanCount: 3);
      expect(next.scanCount, 3);
      expect(next.scanMonth, '2026-10');
      expect(next, isNot(base));
      expect(
        base.copyWith(scanMonth: '2026-11', scanCount: 1).scansIn('2026-11'),
        1,
      );
    });

    test('toString names the count and month only', () {
      expect(
        '${const AppSettings(scanMonth: '2026-10', scanCount: 2)}',
        contains('scans: 2 in 2026-10'),
      );
    });
  });
}
