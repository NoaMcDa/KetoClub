// The profile-only chef card page (Banto, ALG-08a, issue #350).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/utils/allergens/chef_card_templates.dart';

import '../fakes/fake_menu_sharer.dart';
import '../fakes/fake_screen_brightness.dart';

final AppLocalizations _en = AppLocalizationsEn();

final DietaryProfile _profile = DietaryProfile.empty
    .withEntry(RestrictionId.sesame)
    .withEntry(RestrictionId.lactose, exceptions: const <String>['butter']);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: child,
    ),
  );
}

void main() {
  // Clipboard.setData needs a platform handler in the test host.
  final copied = <String>[];

  setUp(() {
    copied.clear();
    TestWidgetsFlutterBinding.ensureInitialized();
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

  group('ChefCardScreen', () {
    testWidgets('shows the lines of the profile in English under an English '
        'app', (tester) async {
      // Act
      await _pump(tester, ChefCardScreen(profile: _profile));

      // Assert
      for (final line in ChefCardText.compose(_profile, hebrew: false)) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(find.text(_en.chefCardTitle), findsOneWidget);
      expect(find.text(_en.helperToolSentence), findsOneWidget);
    });

    testWidgets('starts in Hebrew under a Hebrew app', (tester) async {
      // Act
      await _pump(
        tester,
        ChefCardScreen(profile: _profile),
        locale: const Locale('he'),
      );

      // Assert
      for (final line in ChefCardText.compose(_profile, hebrew: true)) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
    });

    testWidgets('the toggle switches the card between Hebrew and English', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, ChefCardScreen(profile: _profile));
      final englishLine = ChefCardText.compose(_profile, hebrew: false)[1];
      final hebrewLine = ChefCardText.compose(_profile, hebrew: true)[1];
      expect(find.text(englishLine), findsOneWidget);

      // Act
      await tester.tap(find.text(_en.settingsLanguageHebrew));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(hebrewLine), findsOneWidget);
      expect(find.text(englishLine), findsNothing);

      // Act
      await tester.tap(find.text(_en.settingsLanguageEnglish));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(englishLine), findsOneWidget);
      expect(find.text(hebrewLine), findsNothing);
    });

    testWidgets('Copy puts the whole card, in the chosen language, on the '
        'clipboard', (tester) async {
      // Arrange
      await _pump(tester, ChefCardScreen(profile: _profile));
      await tester.tap(find.text(_en.settingsLanguageHebrew));
      await tester.pumpAndSettle();

      // Act
      await tester.ensureVisible(find.text(_en.waiterCardCopyButton));
      await tester.tap(find.text(_en.waiterCardCopyButton));
      await tester.pumpAndSettle();

      // Assert
      expect(copied, [
        ChefCardText.asText(ChefCardText.compose(_profile, hebrew: true)),
      ]);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Share sends the same text through the sharer', (tester) async {
      // Arrange
      final sharer = FakeMenuSharer();
      await _pump(
        tester,
        ChefCardScreen(profile: _profile, menuSharer: sharer),
      );

      // Act
      await tester.ensureVisible(find.byKey(chefCardShareKey));
      await tester.tap(find.byKey(chefCardShareKey));
      await tester.pumpAndSettle();

      // Assert
      expect(sharer.shareCalls, hasLength(1));
      expect(
        sharer.shareCalls.single.text,
        ChefCardText.asText(ChefCardText.compose(_profile, hebrew: false)),
      );
      expect(sharer.shareCalls.single.subject, _en.chefCardTitle);
    });

    testWidgets('has no Share button without a sharer', (tester) async {
      // Act
      await _pump(tester, ChefCardScreen(profile: _profile));

      // Assert
      expect(find.byKey(chefCardShareKey), findsNothing);
    });

    testWidgets('raises the brightness while open and restores it after', (
      tester,
    ) async {
      // Arrange
      final brightness = FakeScreenBrightness();

      // Act
      await _pump(
        tester,
        ChefCardScreen(profile: _profile, screenBrightness: brightness),
      );

      // Assert
      expect(brightness.raiseCount, 1);
      expect(brightness.restoreCount, 0);

      // Act
      await tester.pumpWidget(const SizedBox());

      // Assert
      expect(brightness.restoreCount, 1);
    });

    testWidgets('an empty profile shows the message and no lines', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        ChefCardScreen(
          profile: DietaryProfile.empty,
          menuSharer: FakeMenuSharer(),
        ),
      );

      // Assert
      expect(find.byKey(chefCardEmptyKey), findsOneWidget);
      expect(find.text(_en.chefCardEmpty), findsOneWidget);
      expect(find.text(_en.waiterCardCopyButton), findsNothing);
      expect(find.byKey(chefCardShareKey), findsNothing);
    });

    testWidgets('Done closes the page', (tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ChefCardScreen(profile: _profile),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(_en.chefCardTitle), findsOneWidget);

      // Act
      await tester.tap(find.text(_en.waiterCardDone));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.chefCardTitle), findsNothing);
    });
  });
}
