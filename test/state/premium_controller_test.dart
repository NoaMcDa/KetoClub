import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/platform/entitlement.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/premium_controller.dart';
import 'package:ketoclub/state/scan_controller.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_entitlement.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_scanned_menu_classifier.dart';
import '../fakes/fake_settings_store.dart';

/// One distinct JPEG page.
ScannedPage _page(int n) => ScannedPage(
  mimeType: ScannedPage.jpeg,
  bytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, n]),
);

void main() {
  group('PremiumController', () {
    test('sells Premium only in a Banto build over a store', () {
      final store = FakeEntitlement();
      expect(PremiumController(store, bantoMode: true).sellsPremium, isTrue);
      expect(PremiumController(store).sellsPremium, isFalse);
      expect(
        PremiumController(
          const NullEntitlement(),
          bantoMode: true,
        ).sellsPremium,
        isFalse,
      );
    });

    test('its access is limited for a free Banto phone only', () {
      final store = FakeEntitlement();
      expect(PremiumController(store, bantoMode: true).access.limited, isTrue);
      expect(PremiumController(store).access.limited, isFalse);
      expect(
        PremiumController(
          FakeEntitlement(premium: true),
          bantoMode: true,
        ).access.limited,
        isFalse,
      );
    });

    test('reads the store once per session, and not at all when nothing is '
        'sold', () async {
      final store = FakeEntitlement(premium: true)
        ..queueRefresh(const PremiumInactive());
      final premium = PremiumController(store, bantoMode: true);
      expect(store.calls, isEmpty, reason: 'no I/O at construction');

      await premium.ensureChecked();
      await premium.ensureChecked();

      expect(store.calls, <EntitlementCall>[EntitlementCall.refresh]);
      expect(premium.isPremium, isFalse, reason: 'the lapse was read');

      final keto = FakeEntitlement();
      await PremiumController(keto).ensureChecked();
      await PremiumController(keto).loadPrice();
      expect(keto.calls, isEmpty);
    });

    test("loads the store's price", () async {
      final premium = PremiumController(
        FakeEntitlement(price: r'$5.99'),
        bantoMode: true,
      );
      expect(premium.price, isNull);
      await premium.loadPrice();
      expect(premium.price, r'$5.99');
    });

    test('a purchase activates Premium, notifies and keeps the '
        'result', () async {
      final premium = PremiumController(FakeEntitlement(), bantoMode: true);
      var notified = 0;
      premium.addListener(() => notified++);

      final result = await premium.purchase();
      await pumpEventQueue();

      expect(result, const PremiumActive());
      expect(premium.isPremium, isTrue);
      expect(premium.lastResult, const PremiumActive());
      expect(premium.busy, isFalse);
      expect(notified, greaterThan(1));

      premium.clearResult();
      expect(premium.lastResult, isNull);
    });

    test('a double tap opens the store once', () async {
      final store = FakeEntitlement();
      final premium = PremiumController(store, bantoMode: true);
      await Future.wait(<Future<EntitlementResult>>[
        premium.purchase(),
        premium.purchase(),
      ]);
      expect(store.calls, <EntitlementCall>[EntitlementCall.purchase]);
    });

    test('a restore answers what the store holds', () async {
      final store = FakeEntitlement()..queueRestore(const PremiumInactive());
      final premium = PremiumController(store, bantoMode: true);
      expect(await premium.restore(), const PremiumInactive());
      expect(premium.lastResult, const PremiumInactive());
    });

    test('in a build that sells nothing, a purchase is notSold without the '
        'store', () async {
      final store = FakeEntitlement();
      final premium = PremiumController(store);
      expect(
        await premium.purchase(),
        const EntitlementFailed(EntitlementFailureReason.notSold),
      );
      expect(store.calls, isEmpty);
    });

    test('a change the store reports later notifies, and dispose stops '
        'it', () async {
      final store = FakeEntitlement();
      final premium = PremiumController(store, bantoMode: true);
      var notified = 0;
      premium.addListener(() => notified++);

      store.setPremium(active: true);
      await pumpEventQueue();
      expect(notified, 1);
      expect(premium.isPremium, isTrue);

      premium.dispose();
      store.setPremium(active: false);
      await pumpEventQueue();
      expect(notified, 1);
    });
  });

  group('ScanController monthly count (ALG-18)', () {
    late FakeSettingsStore settings;
    late FakeClock clock;
    late FakeScannedMenuClassifier classifier;

    ScanController build({required bool bantoMode}) {
      final controller = ScanController(
        classifier: classifier,
        repository: FakeMenuRepository(),
        clock: clock,
        settingsStore: settings,
        bantoMode: bantoMode,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    setUp(() {
      settings = FakeSettingsStore();
      clock = FakeClock(DateTime.utc(2026, 10, 30, 12));
      classifier = FakeScannedMenuClassifier();
    });

    test('a Banto build counts every read scan and pasted menu in its '
        'month', () async {
      final controller = build(bantoMode: true)
        ..addPages(<ScannedPage>[_page(1)]);
      await controller.analysePages();
      controller.text = 'Steak\nSalad';
      await controller.submitPaste();

      expect(controller.scansThisMonth, 2);
      final stored = await settings.read();
      expect(stored.scanMonth, '2026-10');
      expect(stored.scanCount, 2);
      expect(await controller.loadScanCount(), 2);
    });

    test('a new month starts from nothing', () async {
      await settings.write(
        const AppSettings(scanMonth: '2026-10', scanCount: 5),
      );
      final controller = build(bantoMode: true);
      expect(await controller.loadScanCount(), 5);

      clock.advance(const Duration(days: 3));
      expect(await controller.loadScanCount(), 0);

      controller.text = 'Steak';
      await controller.submitPaste();
      final stored = await settings.read();
      expect(stored.scanMonth, '2026-11');
      expect(stored.scanCount, 1);
    });

    test('a failed read is not counted', () async {
      classifier.respondWith(
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.offline),
      );
      final controller = build(bantoMode: true)
        ..addPages(<ScannedPage>[_page(1)]);
      await controller.analysePages();
      expect(controller.scansThisMonth, 0);
      expect(settings.writeCallCount, 0);
    });

    test('a KetoClub build counts nothing, so its settings never '
        'change', () async {
      final controller = build(bantoMode: false)
        ..addPages(<ScannedPage>[_page(1)]);
      await controller.analysePages();
      controller.text = 'Steak';
      await controller.submitPaste();
      expect(settings.writeCallCount, 0);
      expect(await settings.read(), const AppSettings());
    });
  });
}
