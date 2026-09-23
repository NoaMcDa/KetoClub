// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.5, §18.4; issue
// #46): a pasted 10bis link or bare id now resolves to a classified menu —
// the adapter and its registration in di.dart are what changed since the
// honest `unsupportedSource` message this test used to assert (issue #33).
// A `notFound` ref still shows its own 10bis-specific copy, distinct from
// a Wolt not-found message (architecture.md §10, "collapsing reasons is a
// bug").

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_menu_mapper.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/verdict_counter_tiles.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// A real 10bis restaurant URL shape (architecture.md §6.5): a
/// `restaurants` path segment followed, somewhere later, by the numeric
/// restaurant id.
const String _tenBisUrl =
    'https://www.10bis.co.il/next/restaurants/menu/delivery/654321/some-slug';

/// The [VenueRef] [_tenBisUrl] resolves to, and the key the fakes below
/// are stubbed under.
const VenueRef _ref = VenueRef(source: MenuSource.tenbis, platformId: '654321');

/// A payload shaped like `test/fixtures/tenbis_synthetic_menu.json`
/// (issue #45), trimmed to the two dishes this test asserts on. Run
/// through the real [TenBisMenuMapper] below rather than built as a
/// `Menu` by hand, so this flow exercises the mapper too, not just the
/// screen.
const Map<String, Object?> _tenBisJson = <String, Object?>{
  'restaurantName': 'Vitrina Tel Aviv',
  'categoriesList': <Object?>[
    <String, Object?>{
      'categoryName': 'Steaks',
      'dishList': <Object?>[
        <String, Object?>{
          'dishId': 1001,
          'dishName': 'Entrecôte 300g',
          'dishDescription': 'Served with butter-infused potato purée',
          'price': 142.0,
          'dishOptionsList': <Object?>[
            <String, Object?>{
              'name': 'Choice of Side',
              'values': <Object?>[
                <String, Object?>{'name': 'Potato Purée'},
                <String, Object?>{'name': 'Green Salad'},
              ],
            },
          ],
        },
      ],
    },
    <String, Object?>{
      'categoryName': "Chef's Specials",
      'dishList': <Object?>[
        <String, Object?>{
          'dishId': '1002-shared',
          'dishName': 'Grilled Halloumi Salad',
          'price': 56.0,
        },
      ],
    },
  ],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('10bis paste flow', () {
    testWidgets('pasting a 10bis link resolves and shows the classified menu', (
      tester,
    ) async {
      // Setup: the repository answers the pasted link's venue with the
      // menu TenBisMenuMapper builds from the synthetic fixture's shape.
      final mapped = TenBisMenuMapper.toMenu(
        _tenBisJson,
        ref: _ref,
        fetchedAt: DateTime.utc(2026),
      );
      expect(mapped, isA<MenuFetched>(), reason: 'fixture shape drifted');
      final fakes = FakeAppDependencies();
      fakes.repository.stub(_ref, mapped);
      await pumpApp(tester, fakes);

      // Act: paste the 10bis URL and open it.
      await enterText(tester, _tenBisUrl);
      await tapAndSettle(tester, find.text(_en.venueSearchOpen));

      // Assert: a classified menu is shown, sourced from 10bis, with
      // both dishes from the mapped fixture visible.
      expect(find.byType(EngineChip), findsOneWidget);
      expect(find.byType(VerdictCounterTiles), findsOneWidget);
      expect(find.textContaining('10bis'), findsWidgets);
      expect(find.text('Entrecôte 300g'), findsOneWidget);
      expect(find.text('Grilled Halloumi Salad'), findsOneWidget);
    });

    testWidgets(
      'pasting a bare 10bis id behaves the same way as the full url',
      (tester) async {
        // Setup
        final mapped = TenBisMenuMapper.toMenu(
          _tenBisJson,
          ref: _ref,
          fetchedAt: DateTime.utc(2026),
        );
        final fakes = FakeAppDependencies();
        fakes.repository.stub(_ref, mapped);
        await pumpApp(tester, fakes);

        // Act: paste a bare numeric id and open it.
        await enterText(tester, '654321');
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert
        expect(find.byType(EngineChip), findsOneWidget);
        expect(find.text('Entrecôte 300g'), findsOneWidget);
      },
    );

    testWidgets(
      'a 10bis ref the repository cannot find shows the 10bis-specific '
      'not-found message',
      (tester) async {
        // Setup: distinct from a Wolt not-found message — both carry the
        // platform name into the same l10n key, and this asserts the
        // 10bis one specifically (architecture.md §10).
        final fakes = FakeAppDependencies();
        fakes.repository.stub(
          _ref,
          const MenuFetchFailed(
            reason: MenuFetchFailureReason.notFound,
            statusCode: 404,
          ),
        );
        await pumpApp(tester, fakes);

        // Act
        await enterText(tester, _tenBisUrl);
        await tapAndSettle(tester, find.text(_en.venueSearchOpen));

        // Assert
        expect(find.text(_en.fetchFailedNotFound('10bis')), findsOneWidget);
      },
    );
  });
}
