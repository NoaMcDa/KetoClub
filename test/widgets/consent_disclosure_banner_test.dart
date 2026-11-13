import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/consent_disclosure_banner.dart';

import '../fakes/fake_settings_store.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the widget under test does.
final AppLocalizations _en = AppLocalizationsEn();

/// Pumps the [ConsentDisclosureBanner] over [store] (defaulting to a
/// fresh, virgin fake) inside a localised [MaterialApp], and returns
/// the store so the test can inspect what was persisted.
Future<FakeSettingsStore> _pump(
  WidgetTester tester, {
  FakeSettingsStore? store,
  bool directToGoogle = false,
  bool backendConfigured = false,
}) async {
  final backing = store ?? FakeSettingsStore();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ConsentDisclosureBanner(
          settingsStore: backing,
          directToGoogle: directToGoogle,
          backendConfigured: backendConfigured,
        ),
      ),
    ),
  );
  return backing;
}

void main() {
  group('ConsentDisclosureBanner (D16, issue #167)', () {
    testWidgets('shows title, body, OK and Turn off on a fresh install', (
      tester,
    ) async {
      // Act
      await _pump(tester);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.settingsConsentTitle), findsOneWidget);
      expect(find.text(_en.consentDisclosureBody), findsOneWidget);
      expect(find.text(_en.consentDisclosureOk), findsOneWidget);
      expect(find.text(_en.consentDisclosureTurnOff), findsOneWidget);
    });

    testWidgets(
      'says dish text goes straight to Google when directToGoogle is set '
      "(iOS and Android, D17), not through KetoClub's server",
      (tester) async {
        // Act
        await _pump(tester, directToGoogle: true);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.consentDisclosureBodyDirect), findsOneWidget);
        expect(find.text(_en.consentDisclosureBody), findsNothing);
      },
    );

    testWidgets(
      'says the server comes first on a phone with a backend (issue #330), '
      'and leaves the web text alone',
      (tester) async {
        // Act
        await _pump(tester, directToGoogle: true, backendConfigured: true);
        await tester.pumpAndSettle();

        // Assert
        expect(
          find.text(_en.consentDisclosureBodyDirectViaBackend),
          findsOneWidget,
        );
        expect(find.text(_en.consentDisclosureBodyDirect), findsNothing);

        // Act: web with a backend.
        await _pump(tester, backendConfigured: true);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.consentDisclosureBody), findsOneWidget);
        expect(
          find.text(_en.consentDisclosureBodyDirectViaBackend),
          findsNothing,
        );
      },
    );

    testWidgets(
      'renders nothing once disclosureSeen is true — never shown twice on '
      'the same install',
      (tester) async {
        // Arrange
        final store = FakeSettingsStore(
          initial: const AppSettings(disclosureSeen: true),
        );

        // Act
        await _pump(tester, store: store);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.settingsConsentTitle), findsNothing);
        expect(find.text(_en.consentDisclosureOk), findsNothing);
        expect(find.text(_en.consentDisclosureTurnOff), findsNothing);
      },
    );

    testWidgets(
      'tapping OK acknowledges without changing consent, and hides the '
      'banner',
      (tester) async {
        // Arrange
        final store = await _pump(tester);
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.text(_en.consentDisclosureOk));
        await tester.pumpAndSettle();

        // Assert: consent stays on (the D16 default), disclosureSeen
        // persists, banner vanishes.
        final stored = await store.read();
        expect(stored.disclosureSeen, isTrue);
        expect(stored.estimationConsentGiven, isTrue);
        expect(find.text(_en.settingsConsentTitle), findsNothing);
      },
    );

    testWidgets('tapping OK after consent was turned off elsewhere keeps it '
        'off, with the venue and filter written since (issue #287)', (
      tester,
    ) async {
      // Arrange: the banner shows on Explore; the user opens a venue, turns
      // AI off in Settings, and comes back.
      final store = await _pump(tester);
      await tester.pumpAndSettle();
      const venue = VenueRef(source: MenuSource.wolt, platformId: 'v1');
      await store.write(
        (await store.read()).copyWith(
          lastVenue: venue,
          lastFilter: MenuFilter.greenOnly,
          estimationConsentGiven: false,
        ),
      );

      // Act
      await tester.tap(find.text(_en.consentDisclosureOk));
      await tester.pumpAndSettle();

      // Assert: only disclosureSeen changed.
      final stored = await store.read();
      expect(stored.estimationConsentGiven, isFalse);
      expect(stored.lastVenue, venue);
      expect(stored.lastFilter, MenuFilter.greenOnly);
      expect(stored.disclosureSeen, isTrue);
      expect(find.text(_en.settingsConsentTitle), findsNothing);
    });

    testWidgets('tapping Turn off sets consent to false, marks the disclosure '
        'seen, and hides the banner', (tester) async {
      // Arrange
      final store = await _pump(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(_en.consentDisclosureTurnOff));
      await tester.pumpAndSettle();

      // Assert
      final stored = await store.read();
      expect(stored.disclosureSeen, isTrue);
      expect(stored.estimationConsentGiven, isFalse);
      expect(find.text(_en.settingsConsentTitle), findsNothing);
    });
  });
}
