// The first-run "What do you avoid?" onboarding (Banto, ALG-02b, issue #344)
// and the gate that decides whether to show it. Every test passes
// `bantoMode` explicitly: plain `flutter test` compiles the flag off.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/screens/restriction_onboarding_screen.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/settings_controller.dart';

import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

const Key _childKey = ValueKey<String>('gateChild');

/// Pumps the gate over [store] with [bantoMode] set, and settles the load.
/// [created] counts the controllers the gate asked for.
Future<void> _pump(
  WidgetTester tester,
  FakeSettingsStore store, {
  required bool bantoMode,
  Locale locale = const Locale('en'),
  List<int>? created,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: RestrictionOnboardingGate(
        bantoMode: bantoMode,
        createController: () {
          created?.add(1);
          return SettingsController(store, FakeMenuRepository());
        },
        child: const Scaffold(key: _childKey, body: Text('Explore')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, RestrictionId id) async {
  final chip = find.byKey(restrictionOnboardingChipKey(id));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final button = find.byKey(key);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('RestrictionOnboardingGate', () {
    testWidgets('shows the onboarding, not the child, on a first Banto run', (
      tester,
    ) async {
      await _pump(tester, FakeSettingsStore(), bantoMode: true);

      expect(find.text(_en.restrictionOnboardingTitle), findsOneWidget);
      expect(find.text(_en.helperToolSentence), findsOneWidget);
      expect(find.byKey(_childKey), findsNothing);
    });

    testWidgets('never shows it, and never builds a controller, when the '
        'flag is off', (tester) async {
      final created = <int>[];

      await _pump(
        tester,
        FakeSettingsStore(),
        bantoMode: false,
        created: created,
      );

      expect(find.byKey(_childKey), findsOneWidget);
      expect(find.text(_en.restrictionOnboardingTitle), findsNothing);
      expect(created, isEmpty);
    });

    testWidgets('shows the child once the onboarding was seen', (tester) async {
      final store = FakeSettingsStore(
        initial: const AppSettings(onboardingSeen: true),
      );

      await _pump(tester, store, bantoMode: true);

      expect(find.byKey(_childKey), findsOneWidget);
      expect(find.text(_en.restrictionOnboardingTitle), findsNothing);
    });

    testWidgets('treats a profile added in Settings first as seen', (
      tester,
    ) async {
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
        ),
      );

      await _pump(tester, store, bantoMode: true);

      expect(find.byKey(_childKey), findsOneWidget);
    });

    testWidgets('Continue saves the picks in order, marks it seen and shows '
        'the child', (tester) async {
      final store = FakeSettingsStore();
      await _pump(tester, store, bantoMode: true);

      await _choose(tester, RestrictionId.sesame);
      await _choose(tester, RestrictionId.lactose);
      await _tap(tester, restrictionOnboardingContinueKey);

      final saved = await store.read();
      expect(saved.onboardingSeen, isTrue);
      // The page carried the helper-tool sentence (ALG-11).
      expect(saved.helperToolSeen, isTrue);
      expect(saved.profile.entries.map((e) => e.restrictionId), <RestrictionId>[
        RestrictionId.sesame,
        RestrictionId.lactose,
      ]);
      expect(find.byKey(_childKey), findsOneWidget);
    });

    testWidgets('a chip tapped twice is not chosen', (tester) async {
      final store = FakeSettingsStore();
      await _pump(tester, store, bantoMode: true);

      await _choose(tester, RestrictionId.sesame);
      await _choose(tester, RestrictionId.sesame);
      await _tap(tester, restrictionOnboardingContinueKey);

      final saved = await store.read();
      expect(saved.profile, DietaryProfile.empty);
      expect(saved.onboardingSeen, isTrue);
    });

    testWidgets('Skip marks it seen and keeps the profile empty, even after '
        'a pick', (tester) async {
      final store = FakeSettingsStore();
      await _pump(tester, store, bantoMode: true);

      await _choose(tester, RestrictionId.sesame);
      await _tap(tester, restrictionOnboardingSkipKey);

      final saved = await store.read();
      expect(saved.onboardingSeen, isTrue);
      expect(saved.profile, DietaryProfile.empty);
      expect(saved.helperToolSeen, isFalse);
      expect(find.byKey(_childKey), findsOneWidget);
    });

    testWidgets('is not shown again on the next launch', (tester) async {
      final store = FakeSettingsStore();
      await _pump(tester, store, bantoMode: true);
      await _tap(tester, restrictionOnboardingSkipKey);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, store, bantoMode: true);

      expect(find.byKey(_childKey), findsOneWidget);
    });

    testWidgets('reads in Hebrew, right to left, and never says safe', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeSettingsStore(),
        bantoMode: true,
        locale: const Locale('he'),
      );

      expect(find.text(_he.restrictionOnboardingTitle), findsOneWidget);
      expect(find.text(_he.restrictionOnboardingContinue), findsOneWidget);
      expect(find.text(_he.helperToolSentence), findsOneWidget);
      final direction = Directionality.of(
        tester.element(find.text(_he.restrictionOnboardingTitle)),
      );
      expect(direction, TextDirection.rtl);
      expect(find.textContaining('בטוח'), findsNothing);
      expect(
        find.textContaining(RegExp('safe', caseSensitive: false)),
        findsNothing,
      );
    });
  });
}
