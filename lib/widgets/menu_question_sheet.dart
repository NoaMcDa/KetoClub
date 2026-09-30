// `material.dart` exports its own `MenuController` (a menu-anchor widget),
// which collides with ours in state/. Hiding it keeps the import unprefixed
// (same pattern as `menu_screen.dart` and `app.dart`).
import 'package:flutter/material.dart' hide MenuController;
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/menu.dart';
import 'package:ketoclub/models/menu_question.dart';
import 'package:ketoclub/services/classifier/menu_question_prompt.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/widgets/failure_copy.dart';

/// A modal bottom sheet for asking one free-text question about the
/// analysed menu (architecture.md §9.5; issue #214).
///
/// Renders four states driven by [MenuController.questionState]:
/// - [QuestionState.idle]: text field + Ask button.
/// - [QuestionState.loading]: spinner.
/// - [QuestionState.answered]: answer text + referenced-dish chips +
///   Ask-another button.
/// - [QuestionState.failed]: distinct failure message + Ask-another button.
///
/// The question is never stored or logged by this widget — it is passed
/// directly to [onAsk], which is `MenuController.askQuestion`. The sheet
/// observes [questionState] and rebuilds its body accordingly; [onDismiss]
/// resets to idle when the Ask-another button is tapped.
class MenuQuestionSheet extends StatefulWidget {
  /// Creates the sheet with the current state values from `MenuController`
  /// passed in explicitly, so the widget is testable without a
  /// provider.
  const new({
    required this.questionState,
    required this.answer,
    required this.failure,
    required this.allDishes,
    required this.onAsk,
    required this.onDismiss,
    super.key,
  });

  /// The current state of the question lifecycle.
  final QuestionState questionState;

  /// The last successful answer, or null.
  final MenuQuestionAnswered? answer;

  /// The last failure reason, or null.
  final MenuQuestionFailureReason? failure;

  /// Every dish in the menu, keyed by id — used to resolve referenced ids
  /// from [answer] to their display names.
  final List<Dish> allDishes;

  /// Called with the user's trimmed question text when they tap Ask.
  final ValueChanged<String> onAsk;

  /// Called when the user taps the Ask-another or dismiss action.
  final VoidCallback onDismiss;

  @override
  State<MenuQuestionSheet> createState() => _MenuQuestionSheetState();
}

class _MenuQuestionSheetState extends State<MenuQuestionSheet> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _textController.text.trim();
    if (text.isEmpty || text.length > menuQuestionMaxLength) return;
    widget.onAsk(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 24,
          end: 24,
          top: 24,
          bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.menuQuestionSheetTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _body(context, l10n, theme),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, ThemeData theme) {
    switch (widget.questionState) {
      case QuestionState.idle:
        return _idleBody(l10n, theme);
      case QuestionState.loading:
        return _loadingBody(l10n);
      case QuestionState.answered:
        return _answeredBody(l10n, theme);
      case QuestionState.failed:
        return _failedBody(l10n, theme);
    }
  }

  Widget _idleBody(AppLocalizations l10n, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _textController,
          autofocus: true,
          maxLines: 3,
          minLines: 2,
          maxLength: menuQuestionMaxLength,
          decoration: InputDecoration(hintText: l10n.menuQuestionSheetHint),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            onPressed: _submit,
            child: Text(l10n.menuQuestionSheetAsk),
          ),
        ),
      ],
    );
  }

  Widget _loadingBody(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.menuQuestionSheetLoading),
          ],
        ),
      ),
    );
  }

  Widget _answeredBody(AppLocalizations l10n, ThemeData theme) {
    final answer = widget.answer;
    if (answer == null) return const SizedBox.shrink();
    final dishById = <String, Dish>{for (final d in widget.allDishes) d.id: d};
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(answer.answer, style: theme.textTheme.bodyMedium),
        if (answer.referencedDishIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in answer.referencedDishIds)
                if (dishById.containsKey(id))
                  Chip(label: Text(dishById[id]!.name)),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextButton(
          onPressed: widget.onDismiss,
          child: Text(l10n.menuQuestionSheetAskAnother),
        ),
      ],
    );
  }

  Widget _failedBody(AppLocalizations l10n, ThemeData theme) {
    final failure = widget.failure;
    final message = failure != null
        ? menuQuestionFailureMessage(failure, l10n)
        : l10n.menuQuestionFailedBadResponse;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextButton(
          onPressed: widget.onDismiss,
          child: Text(l10n.menuQuestionSheetAskAnother),
        ),
      ],
    );
  }
}
