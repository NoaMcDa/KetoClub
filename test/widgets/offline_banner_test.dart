import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/widgets/offline_banner.dart';

import '../fakes/fake_connectivity.dart';

/// The English strings this test reads expected copy from, computed the
/// same way the widget under test does.
final AppLocalizations _en = AppLocalizationsEn();

/// Pumps [child] inside a localised [MaterialApp].
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('OfflineBanner', () {
    testWidgets('shows the offline message when Connectivity reports '
        'offline', (tester) async {
      // Act
      await _pump(
        tester,
        OfflineBanner(connectivity: FakeConnectivity(online: false)),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.offlineBannerMessage), findsOneWidget);
    });

    testWidgets('renders nothing when Connectivity reports online', (
      tester,
    ) async {
      // Act
      await _pump(tester, OfflineBanner(connectivity: FakeConnectivity()));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.offlineBannerMessage), findsNothing);
    });

    testWidgets('hides once recheckToken changes and Connectivity now reports '
        'online', (tester) async {
      // Arrange: offline on the first build.
      final connectivity = FakeConnectivity(online: false);
      await _pump(tester, OfflineBanner(connectivity: connectivity));
      await tester.pumpAndSettle();
      expect(find.text(_en.offlineBannerMessage), findsOneWidget);

      // Act: flip the fake, then bump the token to trigger a recheck.
      connectivity.online = true;
      await _pump(
        tester,
        OfflineBanner(connectivity: connectivity, recheckToken: 1),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.offlineBannerMessage), findsNothing);
    });

    testWidgets('shows again once recheckToken changes and Connectivity now '
        'reports offline', (tester) async {
      // Arrange: online on the first build.
      final connectivity = FakeConnectivity();
      await _pump(tester, OfflineBanner(connectivity: connectivity));
      await tester.pumpAndSettle();
      expect(find.text(_en.offlineBannerMessage), findsNothing);

      // Act
      connectivity.online = false;
      await _pump(
        tester,
        OfflineBanner(connectivity: connectivity, recheckToken: 1),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.offlineBannerMessage), findsOneWidget);
    });

    testWidgets('does not re-check when rebuilt with the same recheckToken', (
      tester,
    ) async {
      // Arrange: offline on the first build.
      final connectivity = FakeConnectivity(online: false);
      await _pump(tester, OfflineBanner(connectivity: connectivity));
      await tester.pumpAndSettle();
      expect(find.text(_en.offlineBannerMessage), findsOneWidget);

      // Act: the fake now answers online, but the token stays at its
      // default (0), the same value the first pump above already used.
      connectivity.online = true;
      await _pump(tester, OfflineBanner(connectivity: connectivity));
      await tester.pumpAndSettle();

      // Assert: still shows the stale (offline) answer.
      expect(find.text(_en.offlineBannerMessage), findsOneWidget);
    });
  });
}
