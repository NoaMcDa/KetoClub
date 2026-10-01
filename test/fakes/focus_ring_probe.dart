import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/widgets/focus_ring.dart';

/// Whether the [FocusRing] at or under [scope] is drawing its outline right now
/// (issue #264). The ring is a foreground [DecoratedBox] whose border is
/// null while nothing inside it holds keyboard focus.
bool focusRingShown(WidgetTester tester, Finder scope) {
  final boxes = find.descendant(
    of: find.descendant(
      of: scope,
      matching: find.byType(FocusRing),
      matchRoot: true,
    ),
    matching: find.byType(DecoratedBox),
  );
  return tester
      .widgetList<DecoratedBox>(boxes)
      .where((box) => box.position == DecorationPosition.foreground)
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .any((decoration) => decoration.border != null);
}
