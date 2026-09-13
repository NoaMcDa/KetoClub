// Shared harness for the flow tests (FLOW_TEST_CONVENTIONS.md,
// architecture.md §18.4).
//
// A flow test runs the real app — real routing, real localisation, real
// provider tree, real widgets — over faked I/O, which is the seam §18.1
// describes. It reaches the fakes by relative import from test/fakes/ rather
// than keeping a second copy: both trees sit outside lib/, so the import is
// legal, and one set of fakes means a contract change cannot leave the flow
// tests asserting against a stale double.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/app.dart';

import '../../test/fakes/fake_app_dependencies.dart';

/// Pumps the whole app over [fakes] and settles it.
///
/// Returns nothing: a flow test drives the app through its UI and asserts on
/// what the user can see, never on a controller it reached around the side.
Future<void> pumpApp(WidgetTester tester, FakeAppDependencies fakes) async {
  await tester.pumpWidget(KetoClubApp(dependencies: fakes.dependencies));
  await tester.pumpAndSettle();
}

/// Types [text] into the first text field on screen and settles.
Future<void> enterText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText).first, text);
  await tester.pumpAndSettle();
}

/// Taps the widget [finder] resolves to and settles.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
