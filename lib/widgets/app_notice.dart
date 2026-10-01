import 'package:flutter/material.dart';
import 'package:ketoclub/theme/verdict_colors.dart';

/// Which of [AppNotice]'s three shapes a notice takes (issue #260,
/// `docs/UX_REVIEW.md` §3). Each kind carries a different weight, so a
/// banner that asks for a decision never looks like one that only informs,
/// and "you are offline" never looks like "cached 2 hours ago".
enum AppNoticeKind {
  /// A surface card with a title, a body and a primary button — for a
  /// notice the user must answer (the first-launch AI disclosure).
  decision,

  /// A single muted line with an icon, and optional text actions — for a
  /// notice that only explains (the rules reason, the stale-cache lines).
  info,

  /// An amber-tinted line — for a state that changes what the app can do
  /// (offline).
  warning,
}

/// One button an [AppNotice] renders: its [label] and what tapping it
/// does. A null [onPressed] renders the button disabled, as Material's own
/// buttons do.
@immutable
final class AppNoticeAction {
  /// Creates an action labelled [label] that runs [onPressed].
  const new({required this.label, required this.onPressed});

  /// The button's text, already localised by the caller.
  final String label;

  /// What tapping the button does; null disables it.
  final VoidCallback? onPressed;
}

/// The one banner vocabulary every notice in the app is built from (issue
/// #260): [AppNotice.decision], [AppNotice.info] and [AppNotice.warning],
/// one per [AppNoticeKind].
///
/// Takes the width of its parent and adds no outer spacing of its own, so
/// a caller places it exactly as it placed the box it replaces. Every
/// string arrives already localised: this widget owns the look, never the
/// copy.
///
/// An [AppNotice.info] with actions puts them on their own row under the
/// text when its width is below [stackedActionsBreakpoint]: at a phone's
/// 390px a trailing Retry button squeezed the rules reason into a column a
/// few words wide and the banner grew to about 212px (issue #234's note).
class AppNotice extends StatelessWidget {
  /// A surface card asking the user to decide: [title], [message] as its
  /// body, a [primary] filled button and, optionally, a [secondary]
  /// outlined one.
  const new decision({
    required String this.title,
    required this.message,
    required AppNoticeAction this.primary,
    this.secondary,
    this.icon = Icons.info_outline,
    super.key,
  }) : kind = AppNoticeKind.decision,
       actions = const <AppNoticeAction>[];

  /// One muted line, [message] after [icon], with optional trailing text
  /// [actions].
  const new info({
    required this.message,
    this.icon = Icons.info_outline,
    this.actions = const <AppNoticeAction>[],
    super.key,
  }) : kind = AppNoticeKind.info,
       title = null,
       primary = null,
       secondary = null;

  /// An amber-tinted line, [message] after [icon], drawn in
  /// [VerdictColors.amber]'s ink on its tint.
  const new warning({
    required this.message,
    this.icon = Icons.warning_amber_rounded,
    super.key,
  }) : kind = AppNoticeKind.warning,
       title = null,
       primary = null,
       secondary = null,
       actions = const <AppNoticeAction>[];

  /// The width below which an [AppNoticeKind.info] notice moves its
  /// actions to their own row under the text, rather than squeezing the
  /// text beside them.
  static const double stackedActionsBreakpoint = 480;

  /// Which shape this notice takes.
  final AppNoticeKind kind;

  /// The decision card's heading; null for the other kinds.
  final String? title;

  /// The notice's text: the decision card's body, or the one line of an
  /// info or warning notice.
  final String message;

  /// The icon drawn before the title (decision) or the line (info,
  /// warning).
  final IconData icon;

  /// The decision card's filled button; null for the other kinds.
  final AppNoticeAction? primary;

  /// The decision card's optional outlined button; null for the other
  /// kinds.
  final AppNoticeAction? secondary;

  /// An info notice's text actions; empty for the other kinds.
  final List<AppNoticeAction> actions;

  @override
  Widget build(BuildContext context) => switch (kind) {
    AppNoticeKind.decision => _decision(context),
    AppNoticeKind.info => _info(context),
    AppNoticeKind.warning => _warning(context),
  };

  Widget _decision(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryAction = primary!;
    final secondaryAction = secondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title ?? '', style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: primaryAction.onPressed,
                  child: Text(primaryAction.label),
                ),
                if (secondaryAction != null)
                  OutlinedButton(
                    onPressed: secondaryAction.onPressed,
                    child: Text(secondaryAction.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final line = _line(colorScheme.onSurfaceVariant);
    if (actions.isEmpty) return line;
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttons = [
          for (final action in actions)
            TextButton(
              onPressed: action.onPressed,
              style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
              child: Text(action.label),
            ),
        ];
        if (constraints.maxWidth < stackedActionsBreakpoint) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line,
              Padding(
                // Aligns the buttons with the text, not the icon.
                padding: const EdgeInsetsDirectional.only(
                  start: _iconSize + _iconGap,
                ),
                child: Wrap(spacing: 8, children: buttons),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: line),
            for (final button in buttons)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: button,
              ),
          ],
        );
      },
    );
  }

  Widget _warning(BuildContext context) {
    final amber = VerdictColors.of(context).amber;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: amber.tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.rail),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: _line(amber.ink),
      ),
    );
  }

  /// [icon] then [message], both in [color], the icon held level with the
  /// text's first line however many lines the text wraps to.
  Widget _line(Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: _iconSize, color: color),
        ),
        const SizedBox(width: _iconGap),
        Expanded(
          child: Text(message, style: TextStyle(color: color)),
        ),
      ],
    );
  }

  static const double _iconSize = 18;
  static const double _iconGap = 8;
}
