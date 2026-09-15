import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/app_typography.dart';
import 'package:ketoclub/theme/verdict_colors.dart';

/// Pumps a widget that captures its [BuildContext] under [theme], with
/// Hebrew and English localisation delegates so callers can switch
/// [locale].
Future<BuildContext> _pumpWithTheme(
  WidgetTester tester,
  ThemeData theme, {
  Locale locale = const Locale('en'),
}) async {
  late final BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (context) {
          captured = context;
          return const Scaffold(body: Text('theme probe'));
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('AppTheme.light', () {
    testWidgets('registers a VerdictColors extension that resolves', (
      tester,
    ) async {
      // Act
      final context = await _pumpWithTheme(tester, AppTheme.light());
      final colors = VerdictColors.of(context);

      // Assert
      expect(Theme.of(context).brightness, Brightness.light);
      expect(colors.green.rail, isNotNull);
      expect(colors.amber.rail, isNotNull);
      expect(colors.red.rail, isNotNull);
    });
  });

  group('AppTheme.dark', () {
    testWidgets('registers a VerdictColors extension that resolves', (
      tester,
    ) async {
      // Act
      final context = await _pumpWithTheme(tester, AppTheme.dark());
      final colors = VerdictColors.of(context);

      // Assert
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(colors.green.rail, isNotNull);
      expect(colors.amber.rail, isNotNull);
      expect(colors.red.rail, isNotNull);
    });
  });

  test('the light and dark palettes are not the same tones', () {
    // Arrange
    final light = AppTheme.light().extension<VerdictColors>()!;
    final dark = AppTheme.dark().extension<VerdictColors>()!;

    // Assert
    expect(light.green, isNot(dark.green));
    expect(light.amber, isNot(dark.amber));
    expect(light.red, isNot(dark.red));
  });

  group('bilingual fonts', () {
    testWidgets('renders Hebrew text in the light theme', (tester) async {
      // Act
      final context = await _pumpWithTheme(
        tester,
        AppTheme.light(),
        locale: const Locale('he'),
      );
      await tester.pumpAndSettle();

      // Assert: the theme's body style reaches a Hebrew-capable face, and
      // Hebrew text actually renders without throwing.
      final body = Theme.of(context).textTheme.bodyMedium!;
      expect(body.fontFamilyFallback, AppTypography.uiFallback);
      expect(find.text('theme probe'), findsOneWidget);
    });

    testWidgets('renders Hebrew text in the dark theme', (tester) async {
      // Act
      final context = await _pumpWithTheme(
        tester,
        AppTheme.dark(),
        locale: const Locale('he'),
      );
      await tester.pumpAndSettle();

      // Assert
      final body = Theme.of(context).textTheme.bodyMedium!;
      expect(body.fontFamilyFallback, AppTypography.uiFallback);
      expect(find.text('theme probe'), findsOneWidget);
    });

    test('the display face also declares a Hebrew fallback', () {
      // Act
      final style = AppTypography.displayStyle(
        size: 32,
        color: const Color(0xFF000000),
      );

      // Assert
      expect(style.fontFamilyFallback, AppTypography.displayFallback);
    });
  });
}
