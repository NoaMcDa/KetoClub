// The kitchen notice and the strict-entry demotion on the menu screen
// (Banto; ALG-07, issue #349), over the recorded Wolt menu with a sesame
// profile. Plain `flutter test` compiles the flag off, so each test passes
// `bantoMode` explicitly.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/screens/menu_screen.dart';
import 'package:ketoclub/services/menu/platform_menu_adapter.dart';
import 'package:ketoclub/services/menu/wolt/wolt_menu_mapper.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/carb_budget_controller.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/widgets/kitchen_notice.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_connectivity.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_classifier.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_menu_sharer.dart';
import '../fakes/fake_notes_store.dart';
import '../fakes/fake_screen_brightness.dart';
import '../fakes/fake_settings_store.dart';

const VenueRef _ref = VenueRef(source: MenuSource.wolt, platformId: 'hamosad');

/// The recorded Wolt menu (wolt_hamosad_menu.json).
final Menu _menu = (WoltMenuMapper.toMenu(
  jsonDecode(File('test/fixtures/wolt_hamosad_menu.json').readAsStringSync())
      as Map<String, Object?>,
  ref: _ref,
  fetchedAt: DateTime.utc(2026),
) as MenuFetched).menu;

/// The fixture's plain chips ("צ'יפס") and a cola.
const String _chipsId = '61ecfdac853cef6ba4d5e3f6';
const String _colaId = '61ecfdac853cef6ba4d5e3f3';

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);

final DietaryProfile _celiac = DietaryProfile.empty.withEntry(
  RestrictionId.gluten,
);

/// A controller whose model answers every dish of the fixture "order as
/// is", over settings holding [profile].
MenuController _controller(DietaryProfile profile) {
  final repository = FakeMenuRepository()..stub(_ref, MenuFetched(menu: _menu));
  final classifier = FakeMenuClassifier()
    ..respondWith(
      MenuAnalysed(
        dishes: <AnalysedDish>[
          for (final dish in _menu.allDishes)
            AnalysedDish(
              dishId: dish.id,
              name: dish.name,
              verdict: DishVerdict.orderAsIs,
              why: 'why',
            ),
        ],
        unclassified: const <String>[],
        engine: const LlmEngine(model: 'm'),
        analysedAt: DateTime.utc(2026),
      ),
    );
  return MenuController(
    repository,
    classifier,
    FakeSettingsStore(initial: AppSettings(profile: profile)),
    FakeNotesStore(),
    CarbBudgetController(),
  );
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  MenuController controller, {
  required bool bantoMode,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<CarbBudgetController>.value(
      value: CarbBudgetController(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: ChangeNotifierProvider<MenuController>.value(
          value: controller,
          child: MenuScreen(
            ref: _ref,
            screenBrightness: FakeScreenBrightness(),
            connectivity: FakeConnectivity(),
            externalLinkOpener: FakeExternalLinkOpener(),
            menuSharer: FakeMenuSharer(),
            bantoMode: bantoMode,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return lookupAppLocalizations(locale);
}

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('a sesame profile sees the sesame kitchen and its question '
        '(${locale.languageCode})', (tester) async {
      // Arrange
      final l10n = await _pump(
        tester,
        _controller(_sesame),
        bantoMode: true,
        locale: locale,
      );

      // Assert: collapsed, naming only the kitchen sesame cares about.
      expect(find.byKey(kitchenNoticeKey), findsOneWidget);
      expect(
        find.text(l10n.kitchenNoticeSummary(l10n.kitchenKindSesame)),
        findsOneWidget,
      );

      // Act
      await tester.tap(find.text(l10n.kitchenNoticeShow));
      await tester.pumpAndSettle();

      // Assert: one row, its question in the menu's language (Hebrew).
      final sesame = KitchenSignals.of(_menu)
          .firstWhere((signal) => signal.kind == KitchenSignalKind.sesame);
      expect(
        find.byKey(kitchenNoticeRowKey(KitchenSignalKind.sesame)),
        findsOneWidget,
      );
      expect(
        find.byKey(kitchenNoticeRowKey(KitchenSignalKind.fryer)),
        findsNothing,
      );
      expect(find.text(sesame.questionHe), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sesame demotes nothing: the chips still fit', (tester) async {
    // Arrange
    final controller = _controller(_sesame);

    // Act
    await _pump(tester, controller, bantoMode: true);

    // Assert: the sesame signal is named in the notice only.
    final chips = controller.evaluationFor(_chipsId)!;
    expect(chips.state, DishState.fits);
    expect(chips.concerns, isEmpty);
  });

  testWidgets('celiac: fried dishes share the fryer, the cola is untouched', (
    tester,
  ) async {
    // Arrange
    final controller = _controller(_celiac);

    // Act
    await _pump(tester, controller, bantoMode: true);

    // Assert: every kitchen concern is the fryer's, on a dish now "ask"
    // whose wire verdict did not move. (The plain chips carry a hidden
    // gluten concern of their own, so they were "ask" already.)
    final demoted = <EvaluatedDish>[
      for (final evaluated in controller.evaluations.values)
        if (evaluated.concerns.any(
          (concern) => concern.source == ConcernSource.kitchen,
        ))
          evaluated,
    ];
    expect(demoted, isNotEmpty);
    for (final evaluated in demoted) {
      expect(evaluated.state, DishState.ask);
      expect(evaluated.dish.verdict, DishVerdict.orderAsIs);
      final kitchen = evaluated.concerns.singleWhere(
        (concern) => concern.source == ConcernSource.kitchen,
      );
      expect(kitchen.restrictionId, RestrictionId.gluten);
      expect(kitchen.matchedText, KitchenSignalKind.fryer.name);
    }
    expect(controller.evaluationFor(_colaId)!.state, DishState.fits);
  });

  testWidgets('the fryer row never names the placeholder entry', (
    tester,
  ) async {
    // Arrange
    final l10n = await _pump(tester, _controller(_celiac), bantoMode: true);

    // Act
    await tester.tap(find.text(l10n.kitchenNoticeShow));
    await tester.pumpAndSettle();

    // Assert: the recorded menu's "💙" notice line shows a fryer to the
    // pure pass, but is not a dish.
    final seenIn = find.descendant(
      of: find.byKey(kitchenNoticeRowKey(KitchenSignalKind.fryer)),
      matching: find.textContaining('Seen in:'),
    );
    expect(seenIn, findsOneWidget);
    expect(tester.widget<Text>(seenIn).data, isNot(contains('💙')));
  });

  testWidgets('a keto-only profile sees no notice and no demotion', (
    tester,
  ) async {
    // Arrange
    final controller = _controller(DietaryProfile.empty);

    // Act
    await _pump(tester, controller, bantoMode: true);

    // Assert
    expect(find.byKey(kitchenNoticeKey), findsNothing);
    expect(controller.evaluations, isEmpty);
    expect(controller.kitchen.signals, isNotEmpty);
  });

  testWidgets('bantoMode off: no notice, keto verdicts only', (tester) async {
    // Arrange
    final controller = _controller(_sesame);

    // Act
    await _pump(tester, controller, bantoMode: false);

    // Assert
    expect(find.byType(KitchenNotice), findsNothing);
    expect(controller.evaluations, isEmpty);
    expect(
      controller.evaluatedRows.every(
        (entry) => entry.evaluated.concerns.every(
          (concern) => concern.source != ConcernSource.kitchen,
        ),
      ),
      isTrue,
    );
  });
}
