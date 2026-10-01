import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/classifier/menu_classifier.dart';
import 'package:ketoclub/services/classifier/scanned_menu_classifier.dart';
import 'package:ketoclub/services/platform/qr_scanner.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/venue/qr_payload_router.dart';
import 'package:ketoclub/state/scan_controller.dart';
import 'package:ketoclub/state/scanned_pages_registry.dart';
import 'package:ketoclub/utils/constants.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_qr_scanner.dart';
import '../fakes/fake_scanned_menu_classifier.dart';
import '../fakes/fake_settings_store.dart';

final DateTime _epoch = DateTime.utc(2026, 9, 29, 12);

void main() {
  group('ScanController', () {
    late FakeMenuRepository repository;
    late FakeClock clock;
    late FakeScannedMenuClassifier classifier;
    late FakeSettingsStore settings;
    late ScanController controller;

    setUp(() {
      repository = FakeMenuRepository();
      clock = FakeClock(_epoch);
      classifier = FakeScannedMenuClassifier();
      settings = FakeSettingsStore();
      controller = ScanController(
        classifier: classifier,
        repository: repository,
        clock: clock,
        settingsStore: settings,
      );
    });

    tearDown(() => controller.dispose());

    test('the paste flow never calls the scanned-menu classifier', () async {
      // Arrange
      controller.text = 'Steak';

      // Act
      await controller.submitPaste();

      // Assert
      expect(classifier.calls, isEmpty);
    });

    test('starts empty and cannot analyse', () {
      expect(controller.text, isEmpty);
      expect(controller.canAnalyse, isFalse);
      expect(controller.emptyPaste, isFalse);
      expect(controller.isSubmitting, isFalse);
    });

    test('canAnalyse needs text other than whitespace', () {
      // Act & Assert
      controller.text = '   \n  ';
      expect(controller.canAnalyse, isFalse);
      controller.text = 'Steak';
      expect(controller.canAnalyse, isTrue);
    });

    test('setting the text notifies listeners once per change', () {
      // Arrange
      var notified = 0;

      // Act
      controller
        ..addListener(() => notified++)
        ..text = 'Steak'
        ..text = 'Steak';

      // Assert
      expect(notified, 1);
    });

    test(
      'submitPaste stores the parsed menu and returns its scan ref',
      () async {
        // Arrange
        controller.text = 'Grilled salmon 68\nCaesar salad';

        // Act
        final ref = await controller.submitPaste();

        // Assert
        expect(ref, isNotNull);
        expect(ref!.source, MenuSource.scan);
        expect(repository.storedMenus, hasLength(1));
        expect(repository.storedMenus.single.venueRef, ref);
        expect(repository.storedMenus.single.fetchedAt, _epoch);
        expect(controller.emptyPaste, isFalse);
        expect(controller.isSubmitting, isFalse);
      },
    );

    test('submitPaste passes the uncategorised category name on', () async {
      // Arrange
      controller.text = 'Steak';

      // Act
      await controller.submitPaste(uncategorisedName: 'תפריט שהודבק');

      // Assert
      expect(
        repository.storedMenus.single.categories.single.name,
        'תפריט שהודבק',
      );
    });

    test('the same text pasted twice gives the same ref', () async {
      // Arrange
      controller.text = 'Steak\nSalmon';
      final first = await controller.submitPaste();
      clock.advance(const Duration(days: 1));

      // Act
      final second = await controller.submitPaste();

      // Assert
      expect(second, first);
    });

    test(
      'submitPaste of text with no dish stores nothing and flags it',
      () async {
        // Arrange
        controller.text = '45 ₪\n12';

        // Act
        final ref = await controller.submitPaste();

        // Assert
        expect(ref, isNull);
        expect(controller.emptyPaste, isTrue);
        expect(repository.storedMenus, isEmpty);
      },
    );

    test('editing the text clears the empty-paste flag', () async {
      // Arrange
      controller.text = '45 ₪';
      await controller.submitPaste();
      expect(controller.emptyPaste, isTrue);

      // Act
      controller.text = '45 ₪ x';

      // Assert
      expect(controller.emptyPaste, isFalse);
    });

    test('submitPaste with blank text does nothing', () async {
      // Act
      final ref = await controller.submitPaste();

      // Assert
      expect(ref, isNull);
      expect(controller.emptyPaste, isFalse);
      expect(repository.storedMenus, isEmpty);
    });

    test('does not notify after dispose when a store finishes late', () async {
      // Arrange
      final slow = ScanController(
        classifier: classifier,
        repository: repository,
        clock: clock,
        settingsStore: settings,
      )..text = 'Steak';

      // Act: dispose while the store is still in flight.
      final pending = slow.submitPaste();
      slow.dispose();

      // Assert: completing must not throw "used after dispose".
      expect(await pending, isNotNull);
    });
  });

  group('ScanController pages', () {
    late FakeMenuRepository repository;
    late FakeScannedMenuClassifier classifier;
    late FakeSettingsStore settings;
    late ScanController controller;

    ScannedPage page([int bytes = 4]) =>
        ScannedPage(mimeType: ScannedPage.jpeg, bytes: Uint8List(bytes));

    // [count] distinct pages, so equality does not collapse them.
    List<ScannedPage> distinct(int count) => [
      for (var i = 0; i < count; i++)
        ScannedPage(
          mimeType: ScannedPage.jpeg,
          bytes: Uint8List.fromList([i, 1, 2]),
        ),
    ];

    setUp(() {
      repository = FakeMenuRepository();
      classifier = FakeScannedMenuClassifier();
      settings = FakeSettingsStore();
      controller = ScanController(
        classifier: classifier,
        repository: repository,
        clock: FakeClock(_epoch),
        settingsStore: settings,
      );
    });

    tearDown(() => controller.dispose());

    test('starts with no pages and cannot analyse them', () {
      expect(controller.pages, isEmpty);
      expect(controller.atPageCap, isFalse);
      expect(controller.canAnalysePages, isFalse);
      expect(controller.analysing, isFalse);
      expect(controller.lastFailure, isNull);
    });

    test('addPages keeps the order and notifies once', () {
      // Arrange
      var notified = 0;
      controller.addListener(() => notified++);
      final first = distinct(3);

      // Act
      final rejection = controller.addPages(first);

      // Assert
      expect(rejection, isNull);
      expect(controller.pages, first);
      expect(controller.canAnalysePages, isTrue);
      expect(notified, 1);
    });

    test('the pages list cannot be modified from outside', () {
      controller.addPages(distinct(1));

      expect(() => controller.pages.add(page()), throwsUnsupportedError);
    });

    test('adding nothing does not notify', () {
      var notified = 0;
      controller
        ..addListener(() => notified++)
        ..addPages(const <ScannedPage>[]);

      expect(notified, 0);
    });

    test('a page of exactly maxScanPageBytes is accepted', () {
      final rejection = controller.addPages([page(maxScanPageBytes)]);

      expect(rejection, isNull);
      expect(controller.pages, hasLength(1));
    });

    test('a page over maxScanPageBytes is rejected with its own reason', () {
      // Act
      final rejection = controller.addPages([page(maxScanPageBytes + 1)]);

      // Assert
      expect(rejection, ScanPageRejection.pageTooLarge);
      expect(controller.pages, isEmpty);
    });

    test('an oversize page keeps the pages before it and drops the rest', () {
      // Arrange
      final ok = distinct(2);

      // Act
      final rejection = controller.addPages([
        ...ok,
        page(maxScanPageBytes + 1),
        ...distinct(1),
      ]);

      // Assert
      expect(rejection, ScanPageRejection.pageTooLarge);
      expect(controller.pages, ok);
    });

    test('maxScanPages pages fill the cap, one more is rejected', () {
      // Arrange
      final full = distinct(maxScanPages);

      // Act
      final fits = controller.addPages(full);
      final overflow = controller.addPages([page(9)]);

      // Assert
      expect(fits, isNull);
      expect(controller.atPageCap, isTrue);
      expect(overflow, ScanPageRejection.tooManyPages);
      expect(controller.pages, full);
    });

    test('a batch that crosses the cap keeps what fits', () {
      // Arrange
      controller.addPages(distinct(maxScanPages - 1));

      // Act
      final rejection = controller.addPages(distinct(3));

      // Assert
      expect(rejection, ScanPageRejection.tooManyPages);
      expect(controller.pages, hasLength(maxScanPages));
    });

    test('removePageAt removes that page and frees the cap', () {
      // Arrange
      final full = distinct(maxScanPages);
      controller
        ..addPages(full)
        // Act
        ..removePageAt(0);

      // Assert
      expect(controller.pages, full.sublist(1));
      expect(controller.atPageCap, isFalse);
    });

    test('removePageAt ignores an index out of range', () {
      var notified = 0;
      controller
        ..addPages(distinct(1))
        ..addListener(() => notified++)
        ..removePageAt(-1)
        ..removePageAt(1);

      expect(controller.pages, hasLength(1));
      expect(notified, 0);
    });

    test('movePage forward puts the page at the target index', () {
      // Arrange
      final p = distinct(3);
      controller
        ..addPages(p)
        // Act
        ..movePage(0, 2);

      // Assert
      expect(controller.pages, [p[1], p[2], p[0]]);
    });

    test('movePage backward puts the page at the target index', () {
      final p = distinct(3);
      controller
        ..addPages(p)
        ..movePage(2, 0);

      expect(controller.pages, [p[2], p[0], p[1]]);
    });

    test('movePage notifies and clears lastFailure', () async {
      // Arrange
      classifier.respondWith(
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.timeout),
      );
      controller.addPages(distinct(2));
      await controller.analysePages();
      expect(controller.lastFailure, isNotNull);
      var notified = 0;
      controller
        ..addListener(() => notified++)
        // Act
        ..movePage(0, 1);

      // Assert
      expect(controller.lastFailure, isNull);
      expect(notified, 1);
    });

    test('movePage ignores same, out-of-range and negative indexes', () {
      final p = distinct(2);
      var notified = 0;
      controller
        ..addPages(p)
        ..addListener(() => notified++)
        ..movePage(1, 1)
        ..movePage(-1, 0)
        ..movePage(0, -1)
        ..movePage(2, 0)
        ..movePage(0, 2);

      expect(controller.pages, p);
      expect(notified, 0);
    });

    test('analysePages sends the pages in the moved order', () async {
      // Arrange
      final p = distinct(3);
      controller
        ..addPages(p)
        ..movePage(2, 0);

      // Act
      await controller.analysePages();

      // Assert
      expect(classifier.calls.single.$1.pages, [p[2], p[0], p[1]]);
    });

    test('analysePages with no pages does nothing', () async {
      expect(await controller.analysePages(), isNull);
      expect(classifier.calls, isEmpty);
    });

    test('analysePages classifies all pages in one call, stores the menu '
        'and its analysis and returns the ref', () async {
      // Arrange
      final scanned = distinct(3);
      controller.addPages(scanned);

      // Act
      final ref = await controller.analysePages();

      // Assert
      expect(classifier.calls, hasLength(1));
      expect(classifier.calls.single.$1.pages, scanned);
      final stored = repository.storedMenus.single;
      expect(ref, stored.venueRef);
      expect(ref!.source, MenuSource.scan);
      expect(repository.savedAnalyses.single.ref, ref);
      expect(repository.savedAnalyses.single.analysis, isA<MenuAnalysed>());
      expect(controller.lastFailure, isNull);
      expect(controller.analysing, isFalse);
    });

    test('the pages survive a successful analysis', () async {
      controller.addPages(distinct(2));

      await controller.analysePages();

      expect(controller.pages, hasLength(2));
    });

    test('the options come from the settings', () async {
      // Arrange
      await settings.write(
        const AppSettings(
          estimationConsentGiven: false,
          netCarbLimitGrams: 12,
          dairyFree: true,
        ),
      );
      controller.addPages(distinct(1));

      // Act
      await controller.analysePages();

      // Assert
      final options = classifier.calls.single.$2;
      expect(options.estimationConsentGiven, isFalse);
      expect(options.netCarbLimitGrams, 12);
      expect(
        options.dietaryConstraints,
        ClassificationOptions.dietaryConstraintsFor(
          seedOilFree: false,
          dairyFree: true,
          carnivoreOnly: false,
        ),
      );
    });

    test('movePage during an analysis does nothing', () async {
      // Arrange
      final gate = Completer<void>();
      classifier.gate = gate.future;
      final p = distinct(2);
      controller.addPages(p);
      final pending = controller.analysePages();
      await pumpEventQueue();

      // Act
      controller.movePage(0, 1);

      // Assert
      expect(controller.pages, p);
      gate.complete();
      await pending;
    });

    test('analysing is true while the classifier is reading', () async {
      // Arrange
      final gate = Completer<void>();
      classifier.gate = gate.future;
      controller.addPages(distinct(1));

      // Act
      final pending = controller.analysePages();
      await pumpEventQueue();

      // Assert: mid-flight the pages are locked and a second call is a no-op.
      expect(controller.analysing, isTrue);
      expect(controller.canAnalysePages, isFalse);
      expect(controller.addPages(distinct(1)), isNull);
      expect(controller.pages, hasLength(1));
      controller.removePageAt(0);
      expect(controller.pages, hasLength(1));
      expect(await controller.analysePages(), isNull);
      gate.complete();
      expect(await pending, isNotNull);
      expect(controller.analysing, isFalse);
      expect(classifier.calls, hasLength(1));
    });

    test(
      'a failure sets lastFailure, stores nothing and keeps the pages',
      () async {
        // Arrange
        classifier.respondWith(
          const ScannedMenuFailed(reason: MenuAnalysisFailureReason.timeout),
        );
        final scanned = distinct(2);
        controller.addPages(scanned);

        // Act
        final ref = await controller.analysePages();

        // Assert
        expect(ref, isNull);
        expect(controller.lastFailure, MenuAnalysisFailureReason.timeout);
        expect(controller.pages, scanned);
        expect(repository.storedMenus, isEmpty);
        expect(repository.savedAnalyses, isEmpty);
        expect(controller.canAnalysePages, isTrue);
      },
    );

    group('with a pages registry', () {
      late ScannedPagesRegistry registry;
      late ScanController registered;

      setUp(() {
        registry = ScannedPagesRegistry();
        registered = ScanController(
          classifier: classifier,
          repository: repository,
          clock: FakeClock(_epoch),
          settingsStore: settings,
          pagesRegistry: registry,
        );
      });

      tearDown(() => registered.dispose());

      test('a successful read puts the pages under the returned ref', () async {
        // Arrange
        final scanned = distinct(3);
        registered.addPages(scanned);

        // Act
        final ref = await registered.analysePages();

        // Assert: exactly the pages the classifier read, so the menu
        // screen's "View pages" shows what the model saw.
        expect(ref, isNotNull);
        expect(registry.get(ref!), ScannedMenu(pages: scanned));
        expect(registry.get(ref), classifier.calls.single.$1);
      });

      test('editing the pages afterwards leaves the registered scan', () async {
        // Arrange
        final scanned = distinct(2);
        registered.addPages(scanned);
        final ref = await registered.analysePages();

        // Act
        registered
          ..removePageAt(0)
          ..addPages(distinct(4).sublist(3));

        // Assert
        expect(registry.get(ref!)!.pages, scanned);
      });

      test('a failure puts nothing in the registry', () async {
        // Arrange
        classifier.respondWith(
          const ScannedMenuFailed(reason: MenuAnalysisFailureReason.offline),
        );
        registered.addPages(distinct(2));

        // Act
        final ref = await registered.analysePages();

        // Assert: the ref the fake's first read would have used holds
        // nothing.
        expect(ref, isNull);
        expect(
          registry.get(
            const VenueRef(source: MenuSource.scan, platformId: 'fake-scan-1'),
          ),
          isNull,
        );
      });
    });

    test('retry calls the classifier again with the same pages and clears '
        'the failure on success', () async {
      // Arrange
      classifier.respondWith(
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.offline),
      );
      controller.addPages(distinct(2));
      await controller.analysePages();

      // Act: the network is back.
      classifier.respondWith(
        ScannedMenuRead(
          menu: Menu(
            venueRef: const VenueRef(
              source: MenuSource.scan,
              platformId: 'retry',
            ),
            currency: 'ILS',
            fetchedAt: _epoch,
            categories: const <MenuCategory>[],
          ),
          analysis: MenuAnalysed(
            dishes: const <AnalysedDish>[],
            unclassified: const <String>[],
            engine: const LlmEngine(model: 'fake/vision'),
            analysedAt: _epoch,
            options: const ClassificationOptions().snapshot,
          ),
        ),
      );
      final ref = await controller.analysePages();

      // Assert
      expect(classifier.calls, hasLength(2));
      expect(classifier.calls.last.$1, classifier.calls.first.$1);
      expect(ref?.platformId, 'retry');
      expect(controller.lastFailure, isNull);
    });

    test('changing the pages clears a stale failure', () async {
      // Arrange
      classifier.respondWith(
        const ScannedMenuFailed(reason: MenuAnalysisFailureReason.badResponse),
      );
      controller.addPages(distinct(2));
      await controller.analysePages();

      // Act
      controller.removePageAt(0);

      // Assert
      expect(controller.lastFailure, isNull);
    });

    test('does not notify after dispose when analysis finishes late', () async {
      // Arrange
      final gate = Completer<void>();
      classifier.gate = gate.future;
      final slow = ScanController(
        classifier: classifier,
        repository: repository,
        clock: FakeClock(_epoch),
        settingsStore: settings,
      )..addPages(distinct(1));

      // Act
      final pending = slow.analysePages();
      await pumpEventQueue();
      slow.dispose();
      gate.complete();

      // Assert
      expect(await pending, isNotNull);
    });
  });

  group('ScanController QR codes (issue #182)', () {
    late FakeQrScanner scanner;
    late ScanController controller;

    ScanController build(QrScanner qrScanner) => ScanController(
      classifier: FakeScannedMenuClassifier(),
      repository: FakeMenuRepository(),
      clock: FakeClock(_epoch),
      settingsStore: FakeSettingsStore(),
      qrScanner: qrScanner,
    );

    setUp(() {
      scanner = FakeQrScanner();
      controller = build(scanner);
    });

    tearDown(() => controller.dispose());

    test('is unavailable, and scans nothing, without a scanner', () async {
      // Arrange
      final bare = ScanController(
        classifier: FakeScannedMenuClassifier(),
        repository: FakeMenuRepository(),
        clock: FakeClock(_epoch),
        settingsStore: FakeSettingsStore(),
      );
      addTearDown(bare.dispose);

      // Assert
      expect(bare.qrAvailable, isFalse);
      expect(await bare.scanQr(), isNull);
      expect(bare.qrNotice, isNull);
    });

    test('reports the scanner availability', () {
      expect(controller.qrAvailable, isTrue);
      expect(build(FakeQrScanner(available: false)).qrAvailable, isFalse);
    });

    test('a cancelled scan answers null and leaves no notice', () async {
      // Arrange: nothing queued, so the scanner answers null.

      // Act
      final venue = await controller.scanQr();

      // Assert
      expect(venue, isNull);
      expect(controller.qrNotice, isNull);
      expect(controller.qrScanning, isFalse);
      expect(scanner.scanCallCount, 1);
    });

    test('a Wolt code answers the venue to open', () async {
      // Arrange
      scanner.queuePayload(
        'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina-lilinblum',
      );

      // Act
      final venue = await controller.scanQr();

      // Assert
      expect(
        venue?.ref,
        const VenueRef(
          source: MenuSource.wolt,
          platformId: 'vitrina-lilinblum',
        ),
      );
      expect(controller.qrNotice, isNull);
    });

    test('a website or PDF code answers a website venue', () async {
      // Arrange
      scanner.queuePayload('https://static.rest.co.il/1/29092026/menu.pdf');

      // Act
      final venue = await controller.scanQr();

      // Assert
      expect(venue?.ref.source, MenuSource.website);
    });

    test(
      'a Tabit code answers null and keeps the unsupported notice',
      () async {
        // Arrange
        scanner.queuePayload(
          'https://tabitisrael.co.il/tabit-order?siteName=x',
        );

        // Act
        final venue = await controller.scanQr();

        // Assert
        expect(venue, isNull);
        expect(controller.qrNotice, const QrUnsupportedSource('Tabit'));
      },
    );

    test('an Instagram code answers null and asks for a photograph', () async {
      // Arrange
      scanner.queuePayload('https://www.instagram.com/cafe.noa');

      // Act
      final venue = await controller.scanQr();

      // Assert
      expect(venue, isNull);
      expect(controller.qrNotice, const QrPhotographInstead());
    });

    test('a payload that is not a URL asks for a photograph', () async {
      // Arrange
      scanner.queuePayload('Table 12');

      // Act
      await controller.scanQr();

      // Assert
      expect(controller.qrNotice, const QrPhotographInstead());
    });

    test('the next scan clears the previous notice', () async {
      // Arrange
      scanner
        ..queuePayload('Table 12')
        ..queuePayload(null);
      await controller.scanQr();
      expect(controller.qrNotice, isNotNull);

      // Act
      await controller.scanQr();

      // Assert
      expect(controller.qrNotice, isNull);
    });

    test('editing the paste or adding pages clears the notice', () async {
      // Arrange
      scanner
        ..queuePayload('Table 12')
        ..queuePayload('Table 13');
      await controller.scanQr();

      // Act & Assert
      controller.text = 'Steak';
      expect(controller.qrNotice, isNull);

      await controller.scanQr();
      expect(controller.qrNotice, isNotNull);
      controller.addPages(<ScannedPage>[
        ScannedPage(
          mimeType: ScannedPage.jpeg,
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      ]);
      expect(controller.qrNotice, isNull);
    });

    test(
      'is scanning while the camera is open, and ignores a second',
      () async {
        // Arrange
        final gate = Completer<String?>();
        final slow = _GatedQrScanner(gate.future);
        final gated = build(slow);
        addTearDown(gated.dispose);

        // Act
        final first = gated.scanQr();
        final second = await gated.scanQr();

        // Assert
        expect(gated.qrScanning, isTrue);
        expect(second, isNull);
        expect(slow.scanCallCount, 1);

        gate.complete('https://wolt.com/en/isr/tel-aviv/restaurant/a-b');
        expect(await first, isNotNull);
        expect(gated.qrScanning, isFalse);
      },
    );

    test('does not notify after dispose when the camera closes late', () async {
      // Arrange
      final gate = Completer<String?>();
      final slow = build(_GatedQrScanner(gate.future));

      // Act
      final pending = slow.scanQr();
      slow.dispose();
      gate.complete(null);

      // Assert
      expect(await pending, isNull);
    });
  });
}

/// A [QrScanner] that answers when its [gate] completes.
final class _GatedQrScanner implements QrScanner {
  new(this.gate);

  final Future<String?> gate;
  int scanCallCount = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> scan() {
    scanCallCount++;
    return gate;
  }
}
