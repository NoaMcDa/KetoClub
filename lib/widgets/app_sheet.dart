import 'package:flutter/material.dart';

/// The widest a modal sheet grows, in logical pixels.
///
/// On a phone the screen is narrower than this, so the cap changes
/// nothing; on a computer it makes a sheet read as a centred card rather
/// than a panel spanning the whole window (issue #224).
const double kSheetMaxWidth = 560;

/// Opens [builder]'s content as a modal bottom sheet capped at
/// [kSheetMaxWidth] wide, so every sheet in the app shares one width.
///
/// The sheet is scroll-controlled, so it may grow to the full height.
/// [showDragHandle] adds Material's drag handle above the content.
Future<T?> showKetoClubSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: showDragHandle,
    constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
    builder: builder,
  );
}
