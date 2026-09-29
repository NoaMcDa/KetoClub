// Flow test (FLOW_TEST_CONVENTIONS.md, architecture.md §6.2, §11, §18.4;
// issue #84, D15): with AI analysis refused in Settings, analysing scanned
// pages shows the consent copy that names Settings, sends nothing — the pages
// never leave the device — and the Scan tab's Settings link lands on
// Settings, where the consent box is unticked.
//
// The real `RoutingScannedMenuClassifier` runs over a faked chat client and a
// connectivity fake that counts how often it is asked; consent is checked
// before either, so both must stay at zero.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/models/scanned_menu.dart';
import 'package:ketoclub/services/platform/connectivity.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/widgets/dish_card.dart';

import 'flow_support.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the app itself does.
final AppLocalizations _en = AppLocalizationsEn();

/// The Analyse-pages button on the Scan tab.
Finder get _analysePages =>
    find.widgetWithText(ElevatedButton, _en.scanScreenAnalysePages);

/// The Scan tab's link to Settings, scoped to the button so it does not
/// match the bottom-navigation label or the Settings title.
Finder get _settingsLink =>
    find.widgetWithText(TextButton, _en.scanScreenSettingsLink);

/// A [Connectivity] that reports online and counts how often it is asked.
final class _CountingConnectivity implements Connectivity {
  /// How many times [isOnline] was asked.
  int callCount = 0;

  @override
  Future<bool> isOnline() async {
    callCount++;
    return true;
  }
}

/// Gives the surface a phone-tall viewport, so a lazy `ListView` builds
/// everything below the fold (CLAUDE.md's traps); reset when the test ends.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Scan consent withheld flow', () {
    testWidgets(
      'with AI analysis refused, Analyse pages sends nothing, says so and '
      'points to Settings',
      (tester) async {
        // Setup: an install that has refused consent (D16: seeded
        // explicitly, not relying on the default), with two chosen pages.
        _useTallSurface(tester);
        final fakes = FakeAppDependencies();
        final client = FlowFakeLlmChatClient()
          ..enqueueReply(validScannedReply(2));
        final connectivity = _CountingConnectivity();
        fakes.scannedClassifierOverride = realScannedClassifier(
          fakes,
          client,
          connectivity: connectivity,
        );
        await fakes.settingsStore.write(
          const AppSettings(
            estimationConsentGiven: false,
            disclosureSeen: true,
          ),
        );
        fakes.pagePicker.images = [
          ScannedPage(mimeType: ScannedPage.png, bytes: whitePngBytes),
          ScannedPage(mimeType: ScannedPage.png, bytes: blackPngBytes),
        ];
        await pumpApp(tester, fakes);
        await tapAndSettle(tester, navDestination(_en.navScan));
        await tapAndSettle(tester, find.text(_en.scanScreenActionChoosePhotos));

        // Act: analyse the pages.
        await tapAndSettle(tester, _analysePages);

        // Assert: the consent copy, which names Settings, and nothing
        // else happened: no request, no connectivity probe, no menu.
        expect(find.text(_en.scanScreenFailureConsentWithheld), findsOneWidget);
        expect(_en.scanScreenFailureConsentWithheld, contains('Settings'));
        expect(client.calls, isEmpty);
        expect(connectivity.callCount, 0);
        expect(find.byType(DishCard), findsNothing);
        // The pages are kept, so allowing consent and retrying loses nothing.
        expect(find.text(_en.scanScreenPageCount(2, 6)), findsOneWidget);

        // Act: follow the Settings link on the Scan tab.
        await tester.ensureVisible(_settingsLink);
        await tapAndSettle(tester, _settingsLink);

        // Assert: Settings is showing, with the consent box unticked.
        final consent = find.text(_en.settingsConsentAccept);
        await tester.ensureVisible(consent);
        expect(consent, findsOneWidget);
        final checkbox = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(checkbox.value, isFalse);
        expect(client.calls, isEmpty);
      },
    );
  });
}
