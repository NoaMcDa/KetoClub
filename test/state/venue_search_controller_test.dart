import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/venue_search_controller.dart';

import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

void main() {
  group('VenueSearchController', () {
    late FakeSettingsStore settings;
    late FakeMenuRepository repository;
    late VenueSearchController controller;

    setUp(() {
      settings = FakeSettingsStore();
      repository = FakeMenuRepository();
      controller = VenueSearchController(settings, repository);
    });

    test('setInput with a Wolt url resolves to a wolt VenueRef', () {
      // Arrange
      const url = 'https://wolt.com/en/isr/tel-aviv/restaurant/vitrina';

      // Act
      controller.setInput(url);

      // Assert
      expect(
        controller.resolved,
        const VenueRef(source: MenuSource.wolt, platformId: 'vitrina'),
      );
      expect(controller.isInvalid, isFalse);
    });

    test('setInput with a bare slug resolves to MenuSource.wolt', () {
      // Arrange
      const slug = 'vitrina-lilinblum';

      // Act
      controller.setInput(slug);

      // Assert
      expect(controller.resolved?.source, MenuSource.wolt);
      expect(controller.resolved?.platformId, slug);
    });

    test('setInput with a numeric id resolves to MenuSource.tenbis', () {
      // Arrange
      const id = '123456';

      // Act
      controller.setInput(id);

      // Assert
      expect(controller.resolved?.source, MenuSource.tenbis);
      expect(controller.resolved?.platformId, id);
    });

    test('setInput with nonsense sets isInvalid true', () {
      // Arrange
      const nonsense = 'https://example.com/not/a/venue';

      // Act
      controller.setInput(nonsense);

      // Assert
      expect(controller.resolved, isNull);
      expect(controller.isInvalid, isTrue);
    });

    test('setInput with empty input is neither resolved nor invalid', () {
      // Act
      controller.setInput('');

      // Assert
      expect(controller.resolved, isNull);
      expect(controller.isInvalid, isFalse);
      expect(controller.input, '');
    });

    test('setInput notifies listeners exactly once per call', () {
      // Arrange
      var notifyCount = 0;

      // Act
      controller
        ..addListener(() => notifyCount++)
        ..setInput('vitrina-lilinblum')
        ..setInput('123456')
        ..setInput('');

      // Assert
      expect(notifyCount, 3);
    });

    test('load leaves lastVenue null when nothing has been opened '
        '(issue #55)', () async {
      // Act
      await controller.load();

      // Assert
      expect(controller.lastVenue, isNull);
      expect(controller.lastVenueName, isNull);
    });

    test('load exposes AppSettings.lastVenue and its cached name '
        '(issue #55)', () async {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');
      await settings.write(const AppSettings(lastVenue: ref));
      repository.seedCache(
        CachedMenu(
          menu: Menu(
            venueRef: ref,
            venueName: 'Vitrina',
            currency: 'ILS',
            fetchedAt: DateTime.utc(2026),
            categories: const <MenuCategory>[],
          ),
        ),
      );

      // Act
      await controller.load();

      // Assert
      expect(controller.lastVenue, equals(ref));
      expect(controller.lastVenueName, equals('Vitrina'));
    });

    test('load falls back to the platform id when the cached menu names '
        'no venue, or nothing is cached for it (issue #55)', () async {
      // Arrange
      const ref = VenueRef(source: MenuSource.wolt, platformId: 'vitrina');
      await settings.write(const AppSettings(lastVenue: ref));

      // Act: nothing seeded in the repository at all.
      await controller.load();

      // Assert
      expect(controller.lastVenueName, equals('vitrina'));
    });

    test('load notifies listeners exactly once', () async {
      // Arrange
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // Act
      await controller.load();

      // Assert
      expect(notifyCount, 1);
    });
  });
}
