import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/utils/price_format.dart';
import 'package:ketoclub/widgets/status_badge.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// One menu row: the dish, its price, and its verdict once analysed
/// (architecture.md §6.6).
///
/// A [DishVerdict.modifiable] row shows its waiter script inline and a
/// button to open the full-screen waiter card; a [DishVerdict.nonKeto]
/// row shows neither; a row whose [DishRow.analysis] is null shows no
/// verdict claim and no script, because none has been made yet.
class DishCard extends StatelessWidget {
  /// Creates a card for [row], formatting its price for [localeTag] and
  /// calling [onShowScript] with [row] when the user asks to open the
  /// full-screen waiter card.
  const new({
    required this.row,
    required this.localeTag,
    required this.onShowScript,
    super.key,
  });

  /// The dish, its category, and its verdict if any.
  final DishRow row;

  /// The locale used to format the dish price.
  final String localeTag;

  /// Called with [row] when the user asks to open the full waiter card
  /// for a [DishVerdict.modifiable] dish.
  final ValueChanged<DishRow> onShowScript;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dish = row.dish;
    final analysis = row.analysis;
    final modification = analysis?.modification;
    final showsScript =
        analysis != null &&
        analysis.verdict == DishVerdict.modifiable &&
        modification != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dish.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (dish.description.isNotEmpty)
                        Text(
                          dish.description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatPrice(dish.price, localeTag: localeTag)),
              ],
            ),
            if (analysis != null) ...[
              const SizedBox(height: 8),
              StatusBadge(verdict: analysis.verdict),
            ],
            if (showsScript) ...[
              const SizedBox(height: 8),
              WaiterScriptWidget(script: modification),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => onShowScript(row),
                  child: Text(l10n.waiterCardOpen),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
