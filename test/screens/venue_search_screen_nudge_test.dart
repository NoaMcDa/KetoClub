// The empty-profile notice above the Discovery list (Banto, issue #421).
// Plain `flutter test` compiles the flag off, so each test passes
// `bantoMode` explicitly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/screens/venue_search_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/venue_search_controller.dart';
import 'package:ketoclub/widgets/helper_tool_sheet.dart';
import 'package:ketoclub/widgets/profile_nudge.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_connectivity.dart';
import '../fakes/fake_location_service.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_venue_search_service.dart';
import '../fakes/fake_visit_history_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

final Finder _nudge = find.byKey(
  profileNudgeKey(ProfileNudgeSurface.discovery),
);

/// A store the disclosure banner treats as already answered, so only the
/// notice under test is on the screen.
FakeSettingsStore _store({
  DietaryProfile profile = DietaryProfile.empty,
  bool dismissed = false,
  bool menuDismissed = false,
}) => FakeSettingsStore(
  initial: AppSettings(
    profile: profile,
    disclosureSeen: true,
    discoveryNudgeDismissed: dismissed,
    menuNudgeDismissed: menuDismissed,
  ),
);

Future<void> _pump(
  WidgetTester tester,
  FakeSettingsStore store, {
  required bool bantoMode,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = VenueSearchController(
    store,
    FakeMenuRepository(),
    locationService: FakeLocationService(),
    venueSearchService: FakeVenueSearchService(),
    estimateClassifier: FakeMenuClassifier(),
    autoEstimateLimit: 0,
    visitHistory: FakeVisitHistoryStore(FakeClock(DateTime.utc(2026))),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<VenueSearchController>.value(
      value: controller,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: VenueSearchScreen(
          bantoMode: bantoMode,
          autofocusSearch: false,
          connectivity: FakeConnectivity(),
          locationService: FakeLocationService(),
          settingsStore: store,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the Discovery empty-profile notice', () {
    testWidgets('shows once above the list for a keto-only profile', (
      tester,
    ) async {
      await _pump(tester, _store(), bantoMode: true);

      expect(_nudge, findsOneWidget);
      expect(find.text(_en.profileNudgeMessage), findsOneWidget);
      expect(find.text(_en.profileNudgeChoose), findsOneWidget);
      expect(find.text(_en.profileNudgeDismiss), findsOneWidget);
    });

    testWidgets('shows in Hebrew, laid out right to left', (tester) async {
      await _pump(
        tester,
        _store(),
        bantoMode: true,
        locale: const Locale('he'),
      );

      expect(find.text(_he.profileNudgeMessage), findsOneWidget);
      expect(Directionality.of(tester.element(_nudge)), TextDirection.rtl);
    });

    testWidgets('is absent without the flag', (tester) async {
      await _pump(tester, _store(), bantoMode: false);

      expect(_nudge, findsNothing);
    });

    testWidgets('is absent once the profile holds a restriction', (
      tester,
    ) async {
      final store = _store(
        profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
      );

      await _pump(tester, store, bantoMode: true);

      expect(_nudge, findsNothing);
    });

    testWidgets('is absent when it was dismissed on Discovery', (tester) async {
      await _pump(tester, _store(dismissed: true), bantoMode: true);

      expect(_nudge, findsNothing);
    });

    testWidgets('a dismissal on the menu does not hide it here', (
      tester,
    ) async {
      await _pump(tester, _store(menuDismissed: true), bantoMode: true);

      expect(_nudge, findsOneWidget);
    });

    testWidgets('"Not now" hides it and remembers it for Discovery only', (
      tester,
    ) async {
      final store = _store();
      await _pump(tester, store, bantoMode: true);

      await tester.tap(find.text(_en.profileNudgeDismiss));
      await tester.pumpAndSettle();

      expect(_nudge, findsNothing);
      final stored = await store.read();
      expect(stored.discoveryNudgeDismissed, isTrue);
      expect(stored.menuNudgeDismissed, isFalse);
    });

    testWidgets('the action opens the picker; choosing adds it, shows the '
        'helper-tool sheet and removes the notice', (tester) async {
      final store = _store();
      await _pump(tester, store, bantoMode: true);

      await tester.tap(find.text(_en.profileNudgeChoose));
      await tester.pumpAndSettle();
      final option = find.byKey(restrictionOptionKey(RestrictionId.sesame));
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(find.byKey(helperToolSheetKey), findsOneWidget);
      await tester.tap(find.byKey(helperToolOkKey));
      await tester.pumpAndSettle();
      expect(_nudge, findsNothing);
      final stored = await store.read();
      expect(stored.profile.contains(RestrictionId.sesame), isTrue);
    });
  });
}
