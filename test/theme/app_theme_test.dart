import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/app_tokens.dart';
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

  group('NeutralSurfaces', () {
    test('the light theme resolves the artboard --surface2 and --line2 '
        'exactly', () {
      // Act
      final neutral = AppTheme.light().extension<NeutralSurfaces>()!;

      // Assert: `.design/theme-snippet.txt`'s `.app` block —
      // `--surface2: #f4efe4` and `--line2: rgba(31,28,23,0.07)`.
      expect(neutral.surface2, AppTokens.lightSurface2);
      expect(
        neutral.line2,
        AppTokens.lightInk.withValues(alpha: AppTokens.line2Alpha),
      );
    });

    test(
      'the dark theme resolves the artboard --surface2 and --line2 exactly',
      () {
        // Act
        final neutral = AppTheme.dark().extension<NeutralSurfaces>()!;

        // Assert: `.design/theme-snippet.txt`'s `.app.dark` block —
        // `--surface2: #272218` and `--line2: rgba(245,240,228,0.07)`.
        expect(neutral.surface2, AppTokens.darkSurface2);
        expect(
          neutral.line2,
          AppTokens.darkInk.withValues(alpha: AppTokens.line2Alpha),
        );
      },
    );

    test('light and dark resolve to different values', () {
      // Arrange
      final light = AppTheme.light().extension<NeutralSurfaces>()!;
      final dark = AppTheme.dark().extension<NeutralSurfaces>()!;

      // Assert
      expect(light.surface2, isNot(dark.surface2));
      expect(light.line2, isNot(dark.line2));
    });

    test('copyWith replaces only the given fields', () {
      // Arrange
      final base = AppTheme.light().extension<NeutralSurfaces>()!;

      // Act
      final copy = base.copyWith(surface2: AppTokens.darkSurface2);

      // Assert
      expect(copy.surface2, AppTokens.darkSurface2);
      expect(copy.line2, base.line2);
    });

    test('lerp at the endpoints returns the matching palette', () {
      // Arrange
      final light = AppTheme.light().extension<NeutralSurfaces>()!;
      final dark = AppTheme.dark().extension<NeutralSurfaces>()!;

      // Act & Assert
      expect(light.lerp(dark, 0).surface2, light.surface2);
      expect(light.lerp(dark, 1).surface2, dark.surface2);
    });

    test('lerp against a foreign extension type returns this unchanged', () {
      // Arrange
      final light = AppTheme.light().extension<NeutralSurfaces>()!;

      // Act & Assert
      expect(light.lerp(null, 0.5), same(light));
    });

    testWidgets('of falls back to the light values when unregistered', (
      tester,
    ) async {
      // Arrange: a bare MaterialApp with no theme.
      late final BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Act
      final resolved = NeutralSurfaces.of(capturedContext);

      // Assert
      expect(resolved, AppTheme.light().extension<NeutralSurfaces>());
    });

    testWidgets('of resolves the registered extension when one exists', (
      tester,
    ) async {
      // Arrange
      late final BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Act
      final resolved = NeutralSurfaces.of(capturedContext);

      // Assert
      expect(resolved, AppTheme.dark().extension<NeutralSurfaces>());
    });
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
