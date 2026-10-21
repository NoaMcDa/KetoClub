// The full-screen order card (Banto, issue #418): a section per dish in
// the dish's language, the allergy note once, brightness raised while it
// is open, Remove, Copy, Share and Clear order; at 390px, in Hebrew (RTL)
// and English, with a screen-reader label on every control.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/screens/order_card_screen.dart';
import 'package:ketoclub/utils/allergens/order_card_text.dart';
import 'package:ketoclub/utils/allergens/profile_evaluator.dart';
import 'package:ketoclub/widgets/verdict_copy.dart';

import '../fakes/fake_menu_sharer.dart';
import '../fakes/fake_screen_brightness.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);

/// [name] with [id], evaluated for [_sesame] as the menu screen hands it
/// over.
OrderDish _item(String id, String name) {
  final dish = Dish(
    id: id,
    name: name,
    description: '',
    price: 10,
    options: const <DishOption>[],
  );
  final evaluated = ProfileEvaluator.evaluate(
    AnalysedDish(
      dishId: id,
      name: name,
      verdict: DishVerdict.orderAsIs,
      why: 'Nothing starchy.',
    ),
    dish,
    _sesame,
  );
  return (
    dish: dish,
    evaluated: evaluated,
    questions: VerdictCopy.waiterQuestions(
      evaluated,
      hebrew: VerdictCopy.dishIsHebrew(dish),
    ),
  );
}

final List<OrderDish> _hebrewOrder = <OrderDish>[
  _item('tahini', 'סלט עם טחינה'),
  _item('eggplant', 'סלט חצילים'),
];

/// What the screen reported back to the menu.
final class _Calls {
  final List<String> removed = <String>[];
  int cleared = 0;
}

Future<_Calls> _pump(
  WidgetTester tester, {
  List<OrderDish>? dishes,
  bool hebrew = true,
  Locale locale = const Locale('he'),
  FakeScreenBrightness? brightness,
  FakeMenuSharer? sharer,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => OrderCardScreen(
                    dishes: dishes ?? _hebrewOrder,
                    profile: _sesame,
                    hebrew: hebrew,
                    onRemove: calls.removed.add,
                    onClear: () => calls.cleared++,
                    menuSharer: sharer,
                    screenBrightness: brightness ?? FakeScreenBrightness(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  final copied = <String>[];

  setUp(() {
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            copied.add(args['text']! as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('OrderCardScreen', () {
    testWidgets('a Hebrew order at 390px in an RTL app: both dishes, their '
        'lines right to left, and the allergy note once', (tester) async {
      // Act
      await _pump(tester);

      // Assert
      expect(tester.takeException(), isNull);
      expect(find.text(_he.orderCardTitle), findsOneWidget);
      expect(find.text('סלט עם טחינה'), findsOneWidget);
      expect(find.text('סלט חצילים'), findsOneWidget);
      final avoid = tester.widget<Text>(
        find.text("התפריט מציין 'טחינה' במנה הזו."),
      );
      expect(avoid.textDirection, TextDirection.rtl);
      expect(
        find.text("בתפריט כתוב 'סלט חצילים' — האם יש בזה שומשום?"),
        findsOneWidget,
      );
      final note = tester.widget<Text>(find.byKey(orderCardAllergyKey));
      expect(note.data, startsWith('יש לי אלרגיה לשומשום.'));
      expect(note.textDirection, TextDirection.rtl);
      expect(find.byKey(orderCardAllergyKey), findsOneWidget);
      expect(find.text(_he.helperToolSentence), findsOneWidget);
    });

    testWidgets('raises the brightness while open and restores it on close', (
      tester,
    ) async {
      // Arrange
      final brightness = FakeScreenBrightness();

      // Act
      await _pump(tester, brightness: brightness);

      // Assert
      expect(brightness.raiseCount, 1);
      expect(brightness.restoreCount, 0);

      // Act
      await tester.tap(find.text(_he.waiterCardDone));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(OrderCardScreen), findsNothing);
      expect(brightness.restoreCount, 1);
    });

    testWidgets('every control has a screen-reader label', (tester) async {
      // Arrange
      final handle = tester.ensureSemantics();

      // Act
      await _pump(tester, locale: const Locale('en'), sharer: FakeMenuSharer());

      // Assert
      expect(
        find.bySemanticsLabel(_en.orderCardRemoveDish('סלט עם טחינה')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(_en.orderCardRemoveDish('סלט חצילים')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(_en.orderCardCopy), findsOneWidget);
      expect(find.bySemanticsLabel(_en.orderCardShare), findsOneWidget);
      expect(find.bySemanticsLabel(_en.orderCardClear), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Remove takes one dish out and tells the menu; the last one '
        'closes the card', (tester) async {
      // Arrange
      final calls = await _pump(tester);

      // Act
      await tester.tap(find.byKey(orderCardRemoveKey('tahini')));
      await tester.pumpAndSettle();

      // Assert
      expect(calls.removed, <String>['tahini']);
      expect(find.byKey(orderCardSectionKey('tahini')), findsNothing);
      expect(find.byKey(orderCardSectionKey('eggplant')), findsOneWidget);

      // Act
      await tester.tap(find.byKey(orderCardRemoveKey('eggplant')));
      await tester.pumpAndSettle();

      // Assert
      expect(calls.removed, <String>['tahini', 'eggplant']);
      expect(find.byType(OrderCardScreen), findsNothing);
    });

    testWidgets('Copy puts the whole order on the clipboard and says so', (
      tester,
    ) async {
      // Arrange
      await _pump(tester);

      // Act
      await tester.ensureVisible(find.byKey(orderCardCopyKey));
      await tester.tap(find.byKey(orderCardCopyKey));
      await tester.pumpAndSettle();

      // Assert
      expect(copied, <String>[
        OrderCardText.asText(
          OrderCardText.compose(_hebrewOrder, profile: _sesame, hebrew: true),
        ),
      ]);
      expect(find.text(_he.orderCardCopied), findsOneWidget);
    });

    testWidgets('Share sends the same text with the card title as subject', (
      tester,
    ) async {
      // Arrange
      final sharer = FakeMenuSharer();
      await _pump(tester, sharer: sharer);

      // Act
      await tester.ensureVisible(find.byKey(orderCardShareKey));
      await tester.tap(find.byKey(orderCardShareKey));
      await tester.pumpAndSettle();

      // Assert
      expect(sharer.shareCalls, hasLength(1));
      expect(sharer.shareCalls.single.subject, _he.orderCardTitle);
      expect(sharer.shareCalls.single.text, contains('סלט חצילים'));
    });

    testWidgets('no sharer leaves Share out', (tester) async {
      // Act
      await _pump(tester);

      // Assert
      expect(find.byKey(orderCardShareKey), findsNothing);
    });

    testWidgets('Clear order empties the order and closes the card', (
      tester,
    ) async {
      // Arrange
      final calls = await _pump(tester);

      // Act
      await tester.ensureVisible(find.byKey(orderCardClearKey));
      await tester.tap(find.byKey(orderCardClearKey));
      await tester.pumpAndSettle();

      // Assert
      expect(calls.cleared, 1);
      expect(find.byType(OrderCardScreen), findsNothing);
    });

    testWidgets('an English order in an English app reads left to right', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        dishes: <OrderDish>[_item('t', 'Tahini salad')],
        hebrew: false,
        locale: const Locale('en'),
      );

      // Assert
      final line = tester.widget<Text>(
        find.text("The menu names 'Tahini' in this dish."),
      );
      expect(line.textDirection, TextDirection.ltr);
      expect(
        tester.widget<Text>(find.byKey(orderCardAllergyKey)).data,
        startsWith('I have an allergy to sesame.'),
      );
    });
  });
}
