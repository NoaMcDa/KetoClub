import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/state/confirmation_controller.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/content_direction.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

/// The key of the dish block for [dishId].
Key confirmDishKey(String dishId) => ValueKey<String>('confirmDish_$dishId');

/// The key of [answer]'s chip for the concern at [index] on [dishId].
Key confirmAnswerKey(String dishId, int index, ConfirmationAnswer answer) =>
    ValueKey<String>('confirmAnswer_${dishId}_${index}_${answer.name}');

/// The key of the "changed as requested" chip for [honoured] on [dishId].
Key confirmChangeKey(String dishId, {required bool honoured}) =>
    ValueKey<String>('confirmChange_${dishId}_$honoured');

/// The key of the note field on [dishId].
Key confirmNoteKey(String dishId) => ValueKey<String>('confirmNote_$dishId');

/// The key of the Save button.
const Key confirmSaveKey = ValueKey<String>('confirmSave');

/// Opens the post-meal prompt (ALG-14) over a controller [create] makes,
/// capped at the app's sheet width ([showKetoClubSheet]). Completes with
/// true when the answers were saved and something was written.
///
/// With [bantoMode] off nothing opens and the future completes with false,
/// so a caller needs no gate of its own.
Future<bool> showConfirmationSheet(
  BuildContext context, {
  required ConfirmationController Function() create,
  bool bantoMode = BantoMode.enabled,
}) async {
  if (!bantoMode) return false;
  final saved = await showKetoClubSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (_) => ConfirmationSheet(create: create),
  );
  return saved ?? false;
}

/// The post-meal "Did you ask the staff?" prompt (Banto, ALG-14, issue
/// #356; architecture.md D27): one block per dish the profile has a
/// concern about, each with one question per concern — *confirmed present
/// · confirmed absent · didn't ask* — "they changed the dish as requested —
/// yes / no" when the dish carried a change, and a note that stays on the
/// device.
///
/// Owns the [ConfirmationController] [create] makes: loads it after the
/// first frame and disposes it with the sheet. Save pops the sheet with
/// whether anything was written.
class ConfirmationSheet extends StatefulWidget {
  /// Creates the prompt over the controller [create] makes.
  const new({required this.create, super.key});

  /// Makes the prompt's controller, once.
  final ConfirmationController Function() create;

  @override
  State<ConfirmationSheet> createState() => _ConfirmationSheetState();
}

class _ConfirmationSheetState extends State<ConfirmationSheet> {
  late final ConfirmationController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.create();
    // Deferred, so building the sheet never itself starts I/O.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.load());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final wrote = await _controller.save();
    if (!mounted) return;
    Navigator.of(context).pop(wrote);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final dishes = _controller.dishes;
        final canSave =
            !_controller.isLoading &&
            _controller.isAvailable &&
            dishes.isNotEmpty &&
            !_saving;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.confirmPromptTitle,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.confirmPromptIntro,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(child: _body(context, l10n, theme)),
                  if (canSave)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        24,
                        8,
                        24,
                        16,
                      ),
                      child: FilledButton(
                        key: confirmSaveKey,
                        onPressed: () => unawaited(_save()),
                        child: Text(l10n.confirmSave),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, ThemeData theme) {
    if (_controller.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final message = !_controller.isAvailable
        ? l10n.confirmUnavailable
        : _controller.dishes.isEmpty
        ? l10n.confirmNothing
        : null;
    if (message != null) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
        child: Text(message, style: theme.textTheme.bodyMedium),
      );
    }
    final dishes = _controller.dishes;
    // A plain Column in a scroll view, not a lazy list: the blocks are
    // collapsed tiles, and every one must exist in the tree.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in dishes)
            _DishBlock(
              key: confirmDishKey(item.dish.id),
              item: item,
              controller: _controller,
              initiallyExpanded: dishes.length == 1,
            ),
        ],
      ),
    );
  }
}

/// One dish of the prompt: its name, collapsed until tapped, then its
/// questions, the change question and the note.
class _DishBlock extends StatelessWidget {
  const new({
    required this.item,
    required this.controller,
    required this.initiallyExpanded,
    super.key,
  });

  final ConfirmationDish item;
  final ConfirmationController controller;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final dish = item.dish;
    final direction = contentDirection(dish.name, Directionality.of(context));
    final honoured = controller.changeFor(dish.id);
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      title: Text(dish.name, textDirection: direction),
      childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < item.concerns.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Text(
            l10n.confirmPromptQuestion(
              _restrictionName(context, item.concerns[i]),
              dish.name,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final answer in ConfirmationAnswer.values)
                ChoiceChip(
                  key: confirmAnswerKey(dish.id, i, answer),
                  label: Text(_answerLabel(l10n, answer)),
                  selected:
                      controller.answerFor(dish.id, item.concerns[i]) == answer,
                  onSelected: (_) =>
                      controller.setAnswer(dish.id, item.concerns[i], answer),
                ),
            ],
          ),
        ],
        if (item.hasChange) ...[
          const SizedBox(height: 16),
          Text(l10n.confirmChangeQuestion, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final value in const <bool>[true, false])
                ChoiceChip(
                  key: confirmChangeKey(dish.id, honoured: value),
                  label: Text(
                    value ? l10n.confirmChangeYes : l10n.confirmChangeNo,
                  ),
                  selected: honoured == value,
                  // A second tap on the chosen answer clears it.
                  onSelected: (_) => controller.setChange(
                    dish.id,
                    honoured: honoured == value ? null : value,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          key: confirmNoteKey(dish.id),
          initialValue: controller.noteFor(dish.id),
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(labelText: l10n.confirmNoteLabel),
          onChanged: (text) => controller.setNote(dish.id, text),
        ),
      ],
    );
  }

  /// [concern]'s restriction in the UI language; the user's own
  /// restriction (ALG-17) with the word that matched.
  static String _restrictionName(BuildContext context, Concern concern) {
    final restriction = restrictionFor(concern.restrictionId);
    final name = restrictionDisplayName(
      restriction,
      Localizations.localeOf(context),
    );
    final own = concern.matchedText?.trim();
    if (restriction.id == RestrictionId.custom &&
        own != null &&
        own.isNotEmpty) {
      return '$name: $own';
    }
    return name;
  }

  static String _answerLabel(
    AppLocalizations l10n,
    ConfirmationAnswer answer,
  ) => switch (answer) {
    ConfirmationAnswer.present => l10n.confirmAnswerPresent,
    ConfirmationAnswer.absent => l10n.confirmAnswerAbsent,
    ConfirmationAnswer.notAsked => l10n.confirmAnswerNotAsked,
  };
}
