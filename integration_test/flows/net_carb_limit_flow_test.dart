// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §18.4; issue #57):
// the net-carb limit chosen in Settings reaches the classifier on the next
// menu opened, and an analysis cached under a different limit is not
// reused for it. An unchanged limit reuses the cached analysis, spending
// no classifier call. The effect spans three screens — the menu, Settings
// and the menu again — which is why this is a flow and not a widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/storage/menu_cache.dart';
import 'package:ketoclub/services/storage/settings_store.dart';

import 'flow_support.dart';

/// The Wolt venue page the user pastes.
const String _woltUrl =
    'https://wolt.com/en/isr/tel-aviv/restaurant/net-carb-limit-venue';

/// The [VenueRef] [_woltUrl] resolves to.
const VenueRef _ref = VenueRef(
  source: MenuSource.wolt,
  platformId: 'net-carb-limit-venue',
);

/// The one dish on the menu.
const Dish _steak = Dish(
  id: 'steak',
  name: 'Herb Butter Steak',
  description: '',
  price: 42,
  options: <DishOption>[],
);

/// The English strings this test reads expected copy from.
final AppLocalizations _en = AppLocalizationsEn();

/// The menu the repository serves for [_ref].
final Menu _menu = Menu(
  venueRef: _ref,
  currency: 'ILS',
  fetchedAt: DateTime.utc(2026),
  categories: const [
    MenuCategory(id: 'c1', name: 'Mains', dishes: [_steak]),
  ],
);

/// An AI analysis of [_menu] made under the default 6 g limit, as a
/// previous visit would have cached it.
final MenuAnalysed _cachedAt6g = MenuAnalysed(
  dishes: const [
    AnalysedDish(
      dishId: 'steak',
      name: 'Herb Butter Steak',
      verdict: DishVerdict.orderAsIs,
      why: 'Protein and butter, no starch.',
      netCarbsEstimate: 1,
    ),
  ],
  unclassified: const <String>[],
  engine: const LlmEngine(model: 'served-model'),
  analysedAt: DateTime.utc(2026),
  options: const AnalysisOptionsSnapshot(netCarbLimitGrams: 6),
);

/// Fakes with consent given, [_menu] served for [_ref], and [_cachedAt6g]
/// already cached beside it.
Future<FakeAppDependencies> _fakes() async {
  final fakes = FakeAppDependencies();
  await fakes.settingsStore.write(
    const AppSettings(estimationConsentGiven: true),
  );
  fakes.repository
    ..stub(_ref, MenuFetched(menu: _menu))
    ..seedCache(CachedMenu(menu: _menu, analysis: _cachedAt6g));
  return fakes;
}

/// Pastes [_woltUrl] on the Explore screen and opens the venue.
Future<void> _openVenue(WidgetTester tester) async {
  await enterText(tester, _woltUrl);
  await tapAndSettle(tester, find.text(_en.venueSearchOpen));
}

/// Goes back one screen through the app bar's back button.
Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Net carb limit flow', () {
    testWidgets(
      'raising the limit in Settings re-analyses the next menu opened, '
      'under the new limit',
      (tester) async {
        // Setup
        final fakes = await _fakes();
        await pumpApp(tester, fakes);

        // Act: open the venue once.
        await _openVenue(tester);

        // Assert: the menu shows, answered from the analysis cached under
        // the same (default) limit, so the classifier was never asked.
        expect(find.text(_steak.name), findsOneWidget);
        expect(fakes.classifier.optionCalls, isEmpty);

        // Act: from the menu, open Settings and raise the limit by 1 g.
        await tapAndSettle(tester, find.byIcon(Icons.settings));
        final plus = find.byKey(netCarbLimitIncreaseKey);
        await tester.ensureVisible(plus);
        await tapAndSettle(tester, plus);

        // Assert: the stepper shows the new limit.
        expect(find.text(_en.settingsNetCarbLimitValue(7)), findsOneWidget);

        // Act: back to the menu, back to Explore, and open it again.
        await _back(tester);
        await _back(tester);
        await _openVenue(tester);

        // Assert: this open re-analysed, and the classifier was given 7 g.
        expect(find.text(_steak.name), findsOneWidget);
        expect(fakes.classifier.optionCalls, hasLength(1));
        expect(
          fakes.classifier.optionCalls.single.netCarbLimitGrams,
          equals(7),
        );
      },
    );

    testWidgets('reopening a venue with the limit unchanged reuses its '
        'cached analysis', (tester) async {
      // Setup
      final fakes = await _fakes();
      await pumpApp(tester, fakes);

      // Act: open, go back, open again.
      await _openVenue(tester);
      await _back(tester);
      await _openVenue(tester);

      // Assert
      expect(find.text(_steak.name), findsOneWidget);
      expect(fakes.classifier.optionCalls, isEmpty);
    });
  });
}
