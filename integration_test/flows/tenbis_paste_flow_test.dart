// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.5, §18.4; issue
// #46): a pasted 10bis link or bare id now resolves to a classified menu —
// the adapter and its registration in di.dart are what changed since the
// honest `unsupportedSource` message this test used to assert (issue #33).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/tenbis/tenbis_menu_mapper.dart';
import 'package:ketoclub/widgets/rules_reason_banner.dart';
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

/// A payload in the live `NextApi/GetRestaurantMenu` envelope, shaped
/// like `test/fixtures/tenbis_19156_menu.json` (#468) and trimmed to the
/// two dishes this test asserts on. Run through the real
/// [TenBisMenuMapper] below rather than built as a `Menu` by hand, so
/// this flow exercises the mapper too, not just the screen.
const Map<String, Object?> _tenBisJson = <String, Object?>{
  'Errors': null,
  'Success': true,
  'Data': <String, Object?>{
    'resId': 654321,
    'categoriesList': <Object?>[
      <String, Object?>{
        'categoryID': 1,
        'categoryName': 'Steaks',
        'dishList': <Object?>[
          <String, Object?>{
            'dishId': 1001,
            'dishName': 'Entrecôte 300g',
            'dishDescription': 'Served with butter-infused potato purée',
            'dishPrice': 142,
            'dishImageUrl': '',
            'choices': <Object?>[
              <String, Object?>{
                'textBeforeChoosing': 'Choice of Side',
                'subs': <Object?>[
                  <String, Object?>{'name': 'Potato Purée', 'price': 0},
                  <String, Object?>{'name': 'Green Salad', 'price': 0},
                ],
              },
            ],
          },
        ],
      },
      <String, Object?>{
        'categoryID': 2,
        'categoryName': "Chef's Specials",
        'dishList': <Object?>[
          <String, Object?>{
            'dishId': 1002,
            'dishName': 'Grilled Halloumi Salad',
            'dishDescription': '',
            'dishPrice': 56,
            'dishImageUrl': '',
            'choices': <Object?>[],
          },
        ],
      },
    ],
  },
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('10bis paste flow', () {
    testWidgets('pasting a 10bis link resolves and shows the classified menu', (
      tester,
    ) async {
      // Setup: the repository answers the pasted link's venue with the
      // menu TenBisMenuMapper builds from the recorded fixture's shape.
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
      await tapAndSettle(tester, find.byTooltip(_en.venueSearchOpenLink));

      // Assert: a classified menu is shown, sourced from 10bis, with
      // both dishes from the mapped fixture visible.
      expect(find.byType(RulesReasonBanner), findsOneWidget);
      expect(find.byType(VerdictCounterTiles), findsOneWidget);
      expect(find.textContaining('10bis'), findsWidgets);
      expect(find.text('Entrecôte 300g'), findsOneWidget);
      expect(find.text('Grilled Halloumi Salad'), findsOneWidget);
    });
  });
}
