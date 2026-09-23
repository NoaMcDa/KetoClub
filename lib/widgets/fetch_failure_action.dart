import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/failures.dart';

/// The action offered for a failed menu fetch, one per
/// [MenuFetchFailureReason] (issue #68).
///
/// `fetchFailureMessage` (`widgets/failure_copy.dart`) already explains
/// *why* the fetch failed; this widget is the *way out* — retrying the
/// same fetch, or going back to paste a different link:
///
/// - [MenuFetchFailureReason.offline] and
///   [MenuFetchFailureReason.backendUnreachable]: retry. Both are
///   connectivity problems that may already have cleared by the time the
///   user taps the button.
/// - [MenuFetchFailureReason.notFound],
///   [MenuFetchFailureReason.platformChanged] and
///   [MenuFetchFailureReason.unsupportedSource]: nothing about retrying
///   the identical request would help — the venue reference itself was
///   the problem — so the action goes back to paste a different one.
/// - [MenuFetchFailureReason.blockedByBrowser]: neither. No retry on this
///   platform will ever succeed, and `fetchFailureMessage`'s own copy
///   already names the way out (the phone app), so this widget renders
///   nothing rather than a dead button.
///
/// An exhaustive switch with no `default`: adding a reason without adding
/// its action here is a compile error, never a silently missing button
/// (architecture.md §10, "collapsing reasons is a bug" — the same rule
/// `failure_copy.dart` already applies to copy).
class FetchFailureAction extends StatelessWidget {
  /// Creates the action for [reason]. [onRetry] is read only for a
  /// reason whose action is "retry"; [onBackToSearch] only for one whose
  /// action is "back to search" — passing the wrong one for a given
  /// [reason] is harmless, since the button that would read it is never
  /// built.
  const new({
    required this.reason,
    this.onRetry,
    this.onBackToSearch,
    super.key,
  });

  /// Why the fetch failed.
  final MenuFetchFailureReason reason;

  /// Called when [reason]'s action is "retry".
  final VoidCallback? onRetry;

  /// Called when [reason]'s action is "back to search".
  final VoidCallback? onBackToSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (reason) {
      MenuFetchFailureReason.offline ||
      MenuFetchFailureReason.backendUnreachable => ElevatedButton(
        onPressed: onRetry,
        child: Text(l10n.actionRetry),
      ),
      MenuFetchFailureReason.notFound ||
      MenuFetchFailureReason.platformChanged ||
      MenuFetchFailureReason.unsupportedSource => ElevatedButton(
        onPressed: onBackToSearch,
        child: Text(l10n.actionBackToSearch),
      ),
      MenuFetchFailureReason.blockedByBrowser => const SizedBox.shrink(),
    };
  }
}
