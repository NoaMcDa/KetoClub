import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
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
  bool bantoMode = false,
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
          bantoMode: bantoMode,
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
      expect(find.text(_en.settingsConsentBody), findsOneWidget);
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
        expect(find.text(_en.settingsConsentBodyDirect), findsOneWidget);
        expect(find.text(_en.settingsConsentBody), findsNothing);
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
          find.text(_en.settingsConsentBodyDirectViaBackend),
          findsOneWidget,
        );
        expect(find.text(_en.settingsConsentBodyDirect), findsNothing);

        // Act: web with a backend.
        await _pump(tester, backendConfigured: true);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(_en.settingsConsentBody), findsOneWidget);
        expect(
          find.text(_en.settingsConsentBodyDirectViaBackend),
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

  group('ConsentDisclosureBanner in Banto (ALG-11, issue #353)', () {
    testWidgets('adds what of the profile leaves the device to the text', (
      tester,
    ) async {
      // Act
      await _pump(tester, bantoMode: true);
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.text('${_en.settingsConsentBody}\n\n${_en.whatLeavesDeviceBanto}'),
        findsOneWidget,
      );
    });

    testWidgets('shows once more to a user who saw only the keto text, '
        'then records the copy version', (tester) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: const AppSettings(disclosureSeen: true),
      );

      // Act
      await _pump(tester, store: store, bantoMode: true);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.consentDisclosureOk), findsOneWidget);

      // Act
      await tester.tap(find.text(_en.consentDisclosureOk));
      await tester.pumpAndSettle();

      // Assert
      final saved = await store.read();
      expect(saved.disclosureCopyVersion, bantoDisclosureCopyVersion);
      expect(saved.estimationConsentGiven, isTrue);
      expect(find.text(_en.consentDisclosureOk), findsNothing);
    });

    testWidgets('stays hidden once the Banto copy was acknowledged', (
      tester,
    ) async {
      // Arrange
      final store = FakeSettingsStore(
        initial: const AppSettings(
          disclosureSeen: true,
          disclosureCopyVersion: bantoDisclosureCopyVersion,
        ),
      );

      // Act
      await _pump(tester, store: store, bantoMode: true);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.consentDisclosureOk), findsNothing);
    });

    testWidgets('"Turn off" records the version too', (tester) async {
      // Arrange
      final store = await _pump(tester, bantoMode: true);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(_en.consentDisclosureTurnOff));
      await tester.pumpAndSettle();

      // Assert
      final saved = await store.read();
      expect(saved.estimationConsentGiven, isFalse);
      expect(saved.disclosureSeen, isTrue);
      expect(saved.disclosureCopyVersion, bantoDisclosureCopyVersion);
    });

    testWidgets('a keto build ignores the version and never writes it', (
      tester,
    ) async {
      // Arrange
      final store = await _pump(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(_en.consentDisclosureOk));
      await tester.pumpAndSettle();

      // Assert
      final saved = await store.read();
      expect(saved.disclosureCopyVersion, 0);
      expect(saved.toJson().containsKey('disclosureCopyVersion'), isFalse);
    });
  });

  group('ConsentDisclosureBanner and shared confirmations (issue #409)', () {
    testWidgets('names them while sharing is on', (tester) async {
      // Arrange: a tall surface, since the banner is bare in this test and
      // in the app it sits in Explore's scrolling column.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Act
      await _pump(
        tester,
        store: FakeSettingsStore(
          initial: const AppSettings(shareConfirmations: true),
        ),
        bantoMode: true,
      );
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.text(
          '${_en.settingsConsentBody}\n\n${_en.whatLeavesDeviceBanto}'
          '\n\n${_en.whatLeavesDeviceSharedConfirmations}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('says nothing of them while sharing is off', (tester) async {
      // Act
      await _pump(tester, bantoMode: true);
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.textContaining(_en.whatLeavesDeviceSharedConfirmations),
        findsNothing,
      );
    });
  });
}
