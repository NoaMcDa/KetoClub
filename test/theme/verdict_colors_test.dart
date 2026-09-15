import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/verdict_colors.dart';

void main() {
  group('VerdictTone', () {
    const a = VerdictTone(
      rail: Color(0xFF000000),
      pill: Color(0xFF111111),
      tint: Color(0xFF222222),
      ink: Color(0xFF333333),
      on: Color(0xFF444444),
    );
    const b = VerdictTone(
      rail: Color(0xFFFFFFFF),
      pill: Color(0xFFEEEEEE),
      tint: Color(0xFFDDDDDD),
      ink: Color(0xFFCCCCCC),
      on: Color(0xFFBBBBBB),
    );

    test('copyWith replaces only the given fields', () {
      // Act
      final copy = a.copyWith(rail: const Color(0xFFAAAAAA));

      // Assert
      expect(copy.rail, const Color(0xFFAAAAAA));
      expect(copy.pill, a.pill);
      expect(copy.tint, a.tint);
      expect(copy.ink, a.ink);
      expect(copy.on, a.on);
    });

    test('copyWith with no arguments returns an equal tone', () {
      // Act & Assert
      expect(a.copyWith(), a);
    });

    test('lerp at t=0 returns a, at t=1 returns b', () {
      // Act & Assert
      expect(VerdictTone.lerp(a, b, 0), a);
      expect(VerdictTone.lerp(a, b, 1), b);
    });

    test('lerp at t=0.5 interpolates every field with Color.lerp', () {
      // Act
      final mid = VerdictTone.lerp(a, b, 0.5);

      // Assert
      expect(mid.rail, Color.lerp(a.rail, b.rail, 0.5));
      expect(mid.pill, Color.lerp(a.pill, b.pill, 0.5));
      expect(mid.tint, Color.lerp(a.tint, b.tint, 0.5));
      expect(mid.ink, Color.lerp(a.ink, b.ink, 0.5));
      expect(mid.on, Color.lerp(a.on, b.on, 0.5));
    });

    test('equal tones compare equal and share a hashCode', () {
      // Arrange
      const copy = VerdictTone(
        rail: Color(0xFF000000),
        pill: Color(0xFF111111),
        tint: Color(0xFF222222),
        ink: Color(0xFF333333),
        on: Color(0xFF444444),
      );

      // Assert
      expect(a, copy);
      expect(a.hashCode, copy.hashCode);
      expect(a == b, isFalse);
    });
  });

  group('VerdictColors', () {
    final light = AppTheme.light().extension<VerdictColors>()!;
    final dark = AppTheme.dark().extension<VerdictColors>()!;

    test('forVerdict maps every DishVerdict without a default clause', () {
      // Assert: exercising all three values is the regression test for the
      // exhaustive switch — a missing case is a compile error, not a
      // runtime one, but this still pins the mapping.
      expect(light.forVerdict(DishVerdict.orderAsIs), light.green);
      expect(light.forVerdict(DishVerdict.modifiable), light.amber);
      expect(light.forVerdict(DishVerdict.nonKeto), light.red);
    });

    test('the three tones are visually distinct', () {
      for (final colors in [light, dark]) {
        final rails = {colors.green.rail, colors.amber.rail, colors.red.rail};
        expect(rails, hasLength(3));
      }
    });

    test('copyWith replaces only the given palette', () {
      // Act
      final copy = light.copyWith(green: dark.green);

      // Assert
      expect(copy.green, dark.green);
      expect(copy.amber, light.amber);
      expect(copy.red, light.red);
    });

    test('lerp at the endpoints returns the matching palette', () {
      // Act & Assert
      expect(light.lerp(dark, 0), light);
      expect(light.lerp(dark, 1), dark);
    });

    test('lerp against null returns this unchanged', () {
      // The reachable half of lerp's `other is! VerdictColors` guard.
      // A foreign extension cannot reach it: the parameter is typed
      // ThemeExtension<VerdictColors>?, so Dart rejects a differently-typed
      // argument at the call boundary before the body ever runs, even
      // through a dynamic call. Null is what ThemeData actually passes when
      // the theme being interpolated towards has no VerdictColors
      // registered, which is the case the guard exists to survive.
      expect(light.lerp(null, 0.5), same(light));
      expect(dark.lerp(null, 0.5), same(dark));
    });

    test('equal palettes compare equal and share a hashCode', () {
      // Arrange
      final copy = VerdictColors(
        green: light.green,
        amber: light.amber,
        red: light.red,
      );

      // Assert
      expect(light, copy);
      expect(light.hashCode, copy.hashCode);
      expect(light == dark, isFalse);
    });

    testWidgets('of falls back to AppTheme.light when unregistered', (
      tester,
    ) async {
      // Arrange: a bare MaterialApp with no theme, the shape ~3500 lines of
      // existing widget tests already pump.
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
      final resolved = VerdictColors.of(capturedContext);

      // Assert
      expect(resolved, AppTheme.light().extension<VerdictColors>());
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
      final resolved = VerdictColors.of(capturedContext);

      // Assert
      expect(resolved, dark);
    });
  });
}
