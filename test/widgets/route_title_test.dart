import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/utils/constants.dart';
import 'package:ketoclub/widgets/route_title.dart';

/// The labels the platform channel was told about, oldest first.
final List<String> _labels = <String>[];

/// Routes the switcher-description call into [_labels].
void _recordTitles() {
  _labels.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
          final args = call.arguments as Map<Object?, Object?>;
          _labels.add(args['label']! as String);
        }
        return null;
      });
}

void main() {
  setUp(_recordTitles);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('documentTitle', () {
    test('puts the page before the app name', () {
      expect(documentTitle('Hamosad'), 'Hamosad · $appName');
    });

    test('is the bare app name without a page', () {
      expect(documentTitle(null), appName);
      expect(documentTitle(''), appName);
      expect(documentTitle('   '), appName);
    });

    test('trims the page', () {
      expect(documentTitle('  Saved '), 'Saved · $appName');
    });
  });

  group('RouteTitle', () {
    testWidgets('sets the title of the route that is showing', (tester) async {
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: RouteTitle(page: 'Saved', child: Text('body')),
        ),
      );
      await tester.pump();

      // Assert
      expect(find.text('body'), findsOneWidget);
      expect(_labels.last, 'Saved · $appName');
    });

    testWidgets('restores the title of the route beneath after a pop', (
      tester,
    ) async {
      // Arrange
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const RouteTitle(page: 'Explore', child: Text('home')),
        ),
      );
      await tester.pump();

      // Act: push a second titled route, then pop it.
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const RouteTitle(page: 'Hamosad', child: Text('venue')),
        ),
      );
      await tester.pumpAndSettle();
      final whilePushed = _labels.last;
      navigator.currentState!.pop();
      await tester.pumpAndSettle();

      // Assert
      expect(whilePushed, 'Hamosad · $appName');
      expect(_labels.last, 'Explore · $appName');
    });
  });
}
