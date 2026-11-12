import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/theme/app_theme.dart';
import 'package:ketoclub/theme/app_tokens.dart';
import 'package:ketoclub/theme/loader_colors.dart';

void main() {
  group('LoaderColors (issues #450, #451)', () {
    test('the light theme registers the light loader colours', () {
      // Act
      final colors = AppTheme.light().extension<LoaderColors>();

      // Assert
      expect(colors, const LoaderColors.light());
      expect(colors!.meat, AppTokens.lightMeat);
      expect(colors.leaf, AppTokens.lightLeaf);
    });

    test('the dark theme registers the dark loader colours', () {
      // Act
      final colors = AppTheme.dark().extension<LoaderColors>();

      // Assert
      expect(colors, const LoaderColors.dark());
      expect(colors!.meat, AppTokens.darkMeat);
      expect(colors.yolk, AppTokens.darkYolk);
    });

    test('light and dark differ in every food colour', () {
      // Arrange
      const light = LoaderColors.light();
      const dark = LoaderColors.dark();

      // Assert
      expect(light.meat, isNot(dark.meat));
      expect(light.eggWhite, isNot(dark.eggWhite));
      expect(light.yolk, isNot(dark.yolk));
      expect(light.leaf, isNot(dark.leaf));
      expect(light.sweep, isNot(dark.sweep));
      expect(light, isNot(dark));
      expect(light.hashCode, isNot(dark.hashCode));
    });

    test('copyWith replaces only the given fields', () {
      // Act
      final copy = const LoaderColors.light().copyWith(
        meat: AppTokens.darkMeat,
        ring: AppTokens.darkRing,
      );

      // Assert
      expect(copy.meat, AppTokens.darkMeat);
      expect(copy.ring, AppTokens.darkRing);
      expect(copy.leaf, AppTokens.lightLeaf);
      expect(copy.sweep, AppTokens.lightSweep);
    });

    test('copyWith with nothing given is equal to the original', () {
      // Assert
      expect(const LoaderColors.dark().copyWith(), const LoaderColors.dark());
    });

    test('lerp at the endpoints returns the matching palette', () {
      // Arrange
      const light = LoaderColors.light();
      const dark = LoaderColors.dark();

      // Assert
      expect(light.lerp(dark, 0), light);
      expect(light.lerp(dark, 1), dark);
    });

    test('lerp against a foreign extension returns this unchanged', () {
      // Arrange
      const light = LoaderColors.light();

      // Assert
      expect(light.lerp(null, 0.5), same(light));
    });

    testWidgets('of reads the theme, and falls back to light with none', (
      tester,
    ) async {
      // Arrange
      late LoaderColors themed;
      late LoaderColors bare;

      // Act
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              themed = LoaderColors.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      // A fresh tree, keyed apart, so the dark theme does not cross-fade
      // into this one.
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Builder(
            builder: (context) {
              bare = LoaderColors.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      // Assert
      expect(themed, const LoaderColors.dark());
      expect(bare, const LoaderColors.light());
    });
  });
}
