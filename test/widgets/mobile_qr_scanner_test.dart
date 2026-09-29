import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/l10n/generated/app_localizations_en.dart';
import 'package:ketoclub/l10n/generated/app_localizations_he.dart';
import 'package:ketoclub/widgets/mobile_qr_scanner.dart';

import '../services/platform/qr_scanner_contract.dart';

final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _he = AppLocalizationsHe();

/// A camera stand-in: a button per code it can "decode", so a test drives
/// `MobileQrScanner` with no platform channel.
Widget _fakeCamera(BuildContext context, ValueChanged<String> onCode) => Column(
  children: [
    TextButton(
      onPressed: () => onCode('https://cafe.co.il/menu'),
      child: const Text('decode'),
    ),
    TextButton(
      onPressed: () {
        onCode('first');
        onCode('second');
      },
      child: const Text('decode twice'),
    ),
    TextButton(onPressed: () => onCode(''), child: const Text('decode empty')),
  ],
);

Future<GlobalKey<NavigatorState>> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: key,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: const Scaffold(body: Text('home')),
    ),
  );
  return key;
}

void main() {
  // No navigator is behind this key, so there is nothing to show: the
  // contract's "null, never throws" case.
  runQrScannerContract(
    'MobileQrScanner with no navigator',
    () => MobileQrScanner(navigatorKey: GlobalKey<NavigatorState>()),
  );

  group('MobileQrScanner', () {
    testWidgets('is available', (tester) async {
      final key = await _pump(tester);
      expect(MobileQrScanner(navigatorKey: key).isAvailable, isTrue);
    });

    testWidgets('shows the camera page and answers the first code', (
      tester,
    ) async {
      // Arrange
      final key = await _pump(tester);
      final scanner = MobileQrScanner(
        navigatorKey: key,
        cameraBuilder: _fakeCamera,
      );

      // Act
      final result = scanner.scan();
      await tester.pumpAndSettle();
      expect(find.text(_en.scanQrTitle), findsOneWidget);
      expect(find.text(_en.scanQrInstruction), findsOneWidget);
      await tester.tap(find.text('decode'));
      await tester.pumpAndSettle();

      // Assert
      expect(await result, 'https://cafe.co.il/menu');
      expect(find.text('decode'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('answers only the first of several codes', (tester) async {
      // Arrange
      final key = await _pump(tester);
      final scanner = MobileQrScanner(
        navigatorKey: key,
        cameraBuilder: _fakeCamera,
      );

      // Act
      final result = scanner.scan();
      await tester.pumpAndSettle();
      await tester.tap(find.text('decode twice'));
      await tester.pumpAndSettle();

      // Assert
      expect(await result, 'first');
    });

    testWidgets('ignores an empty code and stays open', (tester) async {
      // Arrange
      final key = await _pump(tester);
      final scanner = MobileQrScanner(
        navigatorKey: key,
        cameraBuilder: _fakeCamera,
      );
      var done = false;

      // Act
      final result = scanner.scan().whenComplete(() => done = true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('decode empty'));
      await tester.pumpAndSettle();

      // Assert
      expect(done, isFalse);
      expect(find.text('decode'), findsOneWidget);

      await tester.tap(find.text('decode'));
      await tester.pumpAndSettle();
      expect(await result, 'https://cafe.co.il/menu');
    });

    testWidgets('closing the page answers null', (tester) async {
      // Arrange
      final key = await _pump(tester);
      final scanner = MobileQrScanner(
        navigatorKey: key,
        cameraBuilder: _fakeCamera,
      );

      // Act
      final result = scanner.scan();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      // Assert
      expect(await result, isNull);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a second scan while the page is open answers null', (
      tester,
    ) async {
      // Arrange
      final key = await _pump(tester);
      final scanner = MobileQrScanner(
        navigatorKey: key,
        cameraBuilder: _fakeCamera,
      );
      final first = scanner.scan();
      await tester.pumpAndSettle();

      // Act
      final second = await scanner.scan();
      await tester.pumpAndSettle();

      // Assert: one camera on the stack, and the first still answers.
      expect(second, isNull);
      expect(find.text('decode'), findsOneWidget);
      await tester.tap(find.text('decode'));
      await tester.pumpAndSettle();
      expect(await first, 'https://cafe.co.il/menu');
    });

    testWidgets('can scan again after a scan finished', (tester) async {
      // Arrange
      final key = await _pump(tester);
      final scanner = MobileQrScanner(
        navigatorKey: key,
        cameraBuilder: _fakeCamera,
      );
      final first = scanner.scan();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(await first, isNull);

      // Act
      final second = scanner.scan();
      await tester.pumpAndSettle();
      await tester.tap(find.text('decode'));
      await tester.pumpAndSettle();

      // Assert
      expect(await second, 'https://cafe.co.il/menu');
    });

    testWidgets('the page is in Hebrew, right to left, under Locale(he)', (
      tester,
    ) async {
      // Arrange
      final key = await _pump(tester, locale: const Locale('he'));
      final scanner = MobileQrScanner(
        navigatorKey: key,
        cameraBuilder: _fakeCamera,
      );

      // Act
      final result = scanner.scan();
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_he.scanQrTitle), findsOneWidget);
      expect(find.text(_he.scanQrInstruction), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(_he.scanQrInstruction))),
        TextDirection.rtl,
      );

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });
}
