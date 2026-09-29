import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/state/scan_controller.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';

final DateTime _epoch = DateTime.utc(2026, 9, 29, 12);

void main() {
  group('ScanController', () {
    late FakeMenuRepository repository;
    late FakeClock clock;
    late ScanController controller;

    setUp(() {
      repository = FakeMenuRepository();
      clock = FakeClock(_epoch);
      controller = ScanController(repository: repository, clock: clock);
    });

    tearDown(() => controller.dispose());

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
      final slow = ScanController(repository: repository, clock: clock)
        ..text = 'Steak';

      // Act: dispose while the store is still in flight.
      final pending = slow.submitPaste();
      slow.dispose();

      // Assert: completing must not throw "used after dispose".
      expect(await pending, isNotNull);
    });
  });
}
