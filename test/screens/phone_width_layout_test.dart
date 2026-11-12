import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/failures.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/screens/settings_screen.dart';
import 'package:ketoclub/state/locale_controller.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/state/theme_mode_controller.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/widgets/category_chips.dart';
import 'package:ketoclub/widgets/engine_chip.dart';
import 'package:ketoclub/widgets/restaurant_notices_row.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_app_info.dart';
import '../fakes/fake_external_link_opener.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

/// The bundled font files by family. flutter_test paints every family in
/// its Ahem stand-in unless the real file is loaded, which hides real
/// overflows (issue #462), so these tests load what the app bundles.
const Map<String, List<String>> _fonts = {
  'Public Sans': [
    'PublicSans-400.ttf',
    'PublicSans-500.ttf',
    'PublicSans-600.ttf',
    'PublicSans-700.ttf',
    'PublicSans-800.ttf',
  ],
  'Rubik': ['Rubik-400.ttf', 'Rubik-500.ttf', 'Rubik-600.ttf', 'Rubik-700.ttf'],
  'Noto Sans Hebrew': ['NotoSansHebrew-400.ttf', 'NotoSansHebrew-700.ttf'],
  'Instrument Serif': ['InstrumentSerif-400.ttf'],
};

/// Loads every bundled font once for this file.
Future<void> _loadFonts() async {
  for (final entry in _fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }
}

/// Sets the view to [width] logical pixels at [scale] text size.
void _setView(WidgetTester tester, double width, {double scale = 1}) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _pumpApp(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: Scaffold(body: home),
  ),
);

Dish _dish(String name, {String id = 'd1', String description = ''}) => Dish(
  id: id,
  name: name,
  description: description,
  price: 0,
  options: const <DishOption>[],
);

void main() {
  setUpAll(_loadFonts);

  group('Settings segmented controls (issue #482)', () {
    for (final locale in ['en', 'he']) {
      for (final width in [320.0, 360.0, 390.0]) {
        testWidgets('every segment is fully on screen at $width px in '
            '$locale', (tester) async {
          // Arrange
          _setView(tester, width);
          final controller = SettingsController(
            FakeSettingsStore(),
            FakeMenuRepository(),
            null,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale(locale),
              home: MultiProvider(
                providers: [
                  ChangeNotifierProvider<SettingsController>.value(
                    value: controller,
                  ),
                  ChangeNotifierProvider<LocaleController>.value(
                    value: LocaleController(FakeSettingsStore()),
                  ),
                  ChangeNotifierProvider<ThemeModeController>.value(
                    value: ThemeModeController(FakeSettingsStore()),
                  ),
                ],
                child: SettingsScreen(
                  appInfo: FakeAppInfo(),
                  externalLinkOpener: FakeExternalLinkOpener(),
                  backendConfigured: false,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Act
          final buttons = find.byWidgetPredicate((w) => w is SegmentedButton);
          expect(buttons, findsNWidgets(3));
          for (var i = 0; i < 3; i++) {
            final button = buttons.at(i);
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            final box = tester.getRect(button);

            // Assert: the control sits inside the screen, and every label
            // sits inside the control.
            expect(box.left, greaterThanOrEqualTo(0));
            expect(box.right, lessThanOrEqualTo(width + 0.01));
            final labels = find.descendant(
              of: button,
              matching: find.byType(Text),
            );
            expect(labels, findsAtLeastNWidgets(3));
            for (final label in labels.evaluate()) {
              final rect = tester.getRect(find.byWidget(label.widget));
              expect(rect.left, greaterThanOrEqualTo(box.left - 0.01));
              expect(rect.right, lessThanOrEqualTo(box.right + 0.01));
            }
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('EngineChip (issue #462)', () {
    for (final locale in ['en', 'he']) {
      for (final width in [320.0, 360.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('does not overflow at $width px, ${scale}x text, '
              '$locale', (tester) async {
            // Arrange
            _setView(tester, width, scale: scale);

            // Act: a chip in a row the width of a Recent tile's body.
            await _pumpApp(
              tester,
              const Padding(
                padding: EdgeInsets.all(20),
                child: Wrap(
                  children: [
                    EngineChip(engine: LlmEngine(model: 'gemini-3.5-flash')),
                  ],
                ),
              ),
              locale: Locale(locale),
            );

            // Assert
            expect(tester.takeException(), isNull);
            expect(
              tester.getRect(find.byType(EngineChip)).right,
              lessThanOrEqualTo(width),
            );
          });
        }
      }
    }
  });

  group('CategoryChips (issues #484, #463)', () {
    testWidgets('shows a Wolt name that opens with an unclosed RLE in full, '
        'in its own direction', (tester) async {
      // Arrange
      _setView(tester, 390);
      const raw = '‫בחירה ירוקה 🌿';
      String? selected;

      // Act
      await _pumpApp(
        tester,
        CategoryChips(categories: const [raw], onSelected: (c) => selected = c),
      );

      // Assert: the label has no bidi control, reads right to left and
      // fits its chip, and the tap still reports the stored name.
      final label = tester.widget<Text>(
        find.descendant(
          of: find.byType(ActionChip),
          matching: find.byType(Text),
        ),
      );
      expect(label.data, 'בחירה ירוקה 🌿');
      expect(label.textDirection, TextDirection.rtl);
      final chip = tester.getRect(find.byType(ActionChip));
      final text = tester.getRect(find.text('בחירה ירוקה 🌿'));
      expect(text.left, greaterThanOrEqualTo(chip.left));
      expect(text.right, lessThanOrEqualTo(chip.right));
      await tester.tap(find.byType(ActionChip));
      expect(selected, raw);
    });
  });

  group('RestaurantNoticesRow (issue #463)', () {
    testWidgets('lays a Hebrew notice out right to left in the English UI', (
      tester,
    ) async {
      // Arrange
      _setView(tester, 390);

      // Act
      await _pumpApp(
        tester,
        RestaurantNoticesRow(
          notices: [
            _dish('מידע לאלרגנים!', description: 'יש ליצור קשר עם המסעדה!!'),
          ],
          expanded: true,
          onToggle: () {},
        ),
      );

      // Assert
      for (final text in ['מידע לאלרגנים!', 'יש ליצור קשר עם המסעדה!!']) {
        expect(
          tester.widget<Text>(find.text(text)).textDirection,
          TextDirection.rtl,
        );
      }
    });
  });

  group('Settings cache row (issue #462)', () {
    testWidgets('does not overflow at 320 px and 2x text', (tester) async {
      // Arrange
      _setView(tester, 320, scale: 2);
      final controller = SettingsController(
        FakeSettingsStore(),
        FakeMenuRepository(),
        null,
      );

      // Act
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsController>.value(
                value: controller,
              ),
              ChangeNotifierProvider<LocaleController>.value(
                value: LocaleController(FakeSettingsStore()),
              ),
              ChangeNotifierProvider<ThemeModeController>.value(
                value: ThemeModeController(FakeSettingsStore()),
              ),
            ],
            child: SettingsScreen(
              appInfo: FakeAppInfo(),
              externalLinkOpener: FakeExternalLinkOpener(),
              backendConfigured: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;
      await tester.fling(scrollable, const Offset(0, -3000), 3000);
      await tester.pumpAndSettle();

      // Assert
      expect(tester.takeException(), isNull);
    });
  });

  // Keeps the failure import honest: the engine chip is also built for a
  // rules result.
  testWidgets('a rules engine chip fits at 320 px', (tester) async {
    _setView(tester, 320, scale: 2);
    await _pumpApp(
      tester,
      const Padding(
        padding: EdgeInsets.all(20),
        child: Wrap(
          children: [
            EngineChip(
              engine: RulesEngine(reason: MenuAnalysisFailureReason.offline),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
