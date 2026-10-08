import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/community/menu_store_client.dart';

import '../../fakes/fake_menu_store_client.dart';

/// The venue every upload in this file belongs to.
const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'hamosad');

/// A one-dish menu for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026, 10, 8),
  venueName: 'HaMosad',
  categories: const <MenuCategory>[
    MenuCategory(
      id: 'mains',
      name: 'Mains',
      dishes: <Dish>[
        Dish(
          id: 'd1',
          name: 'Steak',
          description: 'With fries',
          price: 9800,
          options: <DishOption>[],
        ),
      ],
    ),
  ],
);

/// An analysis of [_menu] carrying the user's own diet settings.
final MenuAnalysed _analysis = MenuAnalysed(
  dishes: const <AnalysedDish>[
    AnalysedDish(
      dishId: 'd1',
      name: 'Steak',
      verdict: DishVerdict.orderAsIs,
      why: 'Protein.',
    ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'test-model'),
  analysedAt: DateTime.utc(2026, 10, 8),
  options: const AnalysisOptionsSnapshot(
    netCarbLimitGrams: 20,
    dietaryConstraints: <String>['noPork'],
  ),
);

void main() {
  group('MenuUpload.toJson', () {
    test('writes the venue reference, names and menu', () {
      // Arrange
      final upload = MenuUpload(
        ref: _ref,
        venueName: 'HaMosad',
        city: 'Tel Aviv',
        menu: _menu,
        analysis: _analysis,
      );

      // Act
      final json = upload.toJson();

      // Assert
      expect(json['source'], equals('wolt'));
      expect(json['platform_id'], equals('hamosad'));
      expect(json['venue_name'], equals('HaMosad'));
      expect(json['city'], equals('Tel Aviv'));
      expect(json['menu'], equals(_menu.toJson()));
    });

    test('drops the analysis options and keeps everything else', () {
      // Arrange
      final upload = MenuUpload(ref: _ref, menu: _menu, analysis: _analysis);
      final expected = _analysis.toJson()..remove('options');

      // Act
      final analysis = upload.toJson()['analysis']! as Map<String, Object?>;

      // Assert
      expect(analysis.containsKey('options'), isFalse);
      expect(analysis, equals(expected));
      expect(jsonEncode(upload.toJson()), isNot(contains('noPork')));
    });

    test('round-trips through JSON with a null analysis', () {
      // Arrange
      final upload = MenuUpload(ref: _ref, menu: _menu);

      // Act
      final decoded =
          jsonDecode(jsonEncode(upload.toJson())) as Map<String, Object?>;

      // Assert
      expect(decoded.containsKey('analysis'), isTrue);
      expect(decoded['analysis'], isNull);
      expect(decoded['venue_name'], isNull);
      expect(decoded['city'], isNull);
      expect(
        Menu.tryFrom(decoded['menu']! as Map<String, Object?>),
        equals(_menu),
      );
    });

    test('round-trips an analysis that MenuAnalysed reads back', () {
      // Arrange
      final upload = MenuUpload(ref: _ref, menu: _menu, analysis: _analysis);

      // Act
      final decoded =
          jsonDecode(jsonEncode(upload.toJson())) as Map<String, Object?>;
      final analysis = MenuAnalysed.tryFrom(
        decoded['analysis']! as Map<String, Object?>,
      );

      // Assert
      expect(analysis, isNotNull);
      expect(analysis!.options, isNull);
      expect(analysis.dishes, equals(_analysis.dishes));
    });
  });

  group('MenuStoreResult', () {
    test('values compare by their fields', () {
      // Assert
      expect(
        const MenuStored(created: true),
        equals(const MenuStored(created: true)),
      );
      expect(
        const MenuStored(created: true),
        isNot(equals(const MenuStored(created: false))),
      );
      expect(
        const MenuStoreFailed(reason: MenuStoreFailureReason.timeout),
        isNot(
          equals(
            const MenuStoreFailed(reason: MenuStoreFailureReason.rejected),
          ),
        ),
      );
      expect(
        const MenuStoreFailed(reason: MenuStoreFailureReason.timeout).hashCode,
        equals(
          const MenuStoreFailed(reason: MenuStoreFailureReason.timeout)
              .hashCode,
        ),
      );
      expect(
        const MenuStoreFailed(reason: MenuStoreFailureReason.timeout)
            .toString(),
        contains('timeout'),
      );
      expect(const MenuStored(created: false).toString(), contains('false'));
    });
  });

  group('NoMenuStoreClient', () {
    test('is not configured and answers notConfigured', () async {
      // Arrange
      const client = NoMenuStoreClient();

      // Act
      final result = await client.upload(MenuUpload(ref: _ref, menu: _menu));

      // Assert
      expect(client.isConfigured, isFalse);
      expect(
        result,
        equals(
          const MenuStoreFailed(reason: MenuStoreFailureReason.notConfigured),
        ),
      );
    });
  });

  group('FakeMenuStoreClient', () {
    test('records every upload and stores it by default', () async {
      // Arrange
      final fake = FakeMenuStoreClient();
      final first = MenuUpload(ref: _ref, menu: _menu);
      final second = MenuUpload(ref: _ref, menu: _menu, analysis: _analysis);

      // Act
      final result = await fake.upload(first);
      await fake.upload(second);

      // Assert
      expect(fake.isConfigured, isTrue);
      expect(result, equals(const MenuStored(created: true)));
      expect(fake.uploads, equals(<MenuUpload>[first, second]));
    });

    test('answers notConfigured once unconfigured', () async {
      // Arrange
      final fake = FakeMenuStoreClient()..isConfigured = false;

      // Act
      final result = await fake.upload(MenuUpload(ref: _ref, menu: _menu));

      // Assert
      expect(fake.isConfigured, isFalse);
      expect(
        result,
        equals(
          const MenuStoreFailed(reason: MenuStoreFailureReason.notConfigured),
        ),
      );
      expect(fake.uploads, hasLength(1));
    });

    test('answers with the scripted result', () async {
      // Arrange
      final fake = FakeMenuStoreClient()
        ..respondWith(
          const MenuStoreFailed(reason: MenuStoreFailureReason.rateLimited),
        );

      // Act
      final result = await fake.upload(MenuUpload(ref: _ref, menu: _menu));

      // Assert
      expect(
        result,
        equals(
          const MenuStoreFailed(reason: MenuStoreFailureReason.rateLimited),
        ),
      );
    });

    test('holds an upload until the gate completes', () async {
      // Arrange
      final gate = Completer<void>();
      final fake = FakeMenuStoreClient()..gate = gate;
      MenuStoreResult? result;

      // Act
      unawaited(
        fake
            .upload(MenuUpload(ref: _ref, menu: _menu))
            .then((value) => result = value),
      );
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(fake.uploads, hasLength(1));
      expect(result, isNull);

      // Act
      gate.complete();
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(result, equals(const MenuStored(created: true)));
    });
  });
}
