import 'package:flutter/material.dart';
import 'package:ketoclub/utils/allergens/group_chef_card.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// The key of the section headed [heading], so a test can find it.
Key groupChefCardSectionKey(String heading) =>
    ValueKey<String>('groupChefCardSection_$heading');

/// The line naming the dish on a group dish card.
const Key groupChefCardDishKey = Key('groupChefCardDish');

/// The chef card for several people (Banto, ALG-12, issue #354): the
/// greeting, then one bordered section per person — their name over their
/// lines, drawn and copied like the single card's ([WaiterScriptWidget]) —
/// then, on a dish card, the dish's name once, then the closing line.
/// [trailingAction] (the Share button) sits under
/// the last section.
class GroupChefCardView extends StatelessWidget {
  /// Creates the view of [card].
  const new({required this.card, this.trailingAction, super.key});

  /// The composed card ([GroupChefCardText.compose]).
  final GroupChefCard card;

  /// Drawn after the sections; null draws nothing.
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(card.intro, style: theme.textTheme.titleMedium),
        for (final section in card.sections) ...[
          const SizedBox(height: 14),
          DecoratedBox(
            key: groupChefCardSectionKey(section.heading),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      section.heading,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (section.lines.isNotEmpty)
                    WaiterScriptWidget(
                      script: section.lines.join('\n'),
                      prominent: true,
                    ),
                ],
              ),
            ),
          ),
        ],
        if (card.dishLine.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            card.dishLine,
            key: groupChefCardDishKey,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (card.closing.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(card.closing, style: theme.textTheme.titleMedium),
        ],
        if (trailingAction case final action?) ...[
          const SizedBox(height: 14),
          Align(alignment: AlignmentDirectional.centerStart, child: action),
        ],
      ],
    );
  }
}
