import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/theme/app_typography.dart';
import 'package:ketoclub/utils/allergens/order_card_text.dart';
import 'package:ketoclub/widgets/content_direction.dart';
import 'package:ketoclub/widgets/content_width.dart';

/// The key of the section for the dish [dishId] on the order card.
Key orderCardSectionKey(String dishId) =>
    ValueKey<String>('orderCardSection:$dishId');

/// The key of the remove button of the dish [dishId]'s section.
Key orderCardRemoveKey(String dishId) =>
    ValueKey<String>('orderCardRemove:$dishId');

/// The allergy note shown once after the dishes.
const Key orderCardAllergyKey = ValueKey<String>('orderCardAllergy');

/// The order card's Copy button.
const Key orderCardCopyKey = ValueKey<String>('orderCardCopy');

/// The order card's Share button.
const Key orderCardShareKey = ValueKey<String>('orderCardShare');

/// The order card's "Clear order" button.
const Key orderCardClearKey = ValueKey<String>('orderCardClear');

/// The full-screen order card (Banto, issue #418): every dish the person
/// added to "My order" on one menu, one section each — the dish's name as
/// printed, its change and its questions ([OrderCardText.sectionLines]) —
/// and the profile's allergy note once after them, so the phone is handed
/// across the table once instead of once per dish.
///
/// It keeps the Waiter Card's shell (`WaiterCardSheet`): the screen
/// brightness is raised while the card is open and restored when it
/// closes, the type is large, menu text is laid out in its own direction
/// ([contentDirection]) and a pinned Done button closes it. Every dish's
/// lines are in that dish's language and the allergy note in the menu's
/// ([hebrew]), never the UI's (architecture.md §12); the chrome is ARB.
///
/// Remove takes one dish out (and closes the card with the last one),
/// Copy and Share hand over [OrderCardText.asText], and "Clear order"
/// empties the order and closes the card. [onRemove] and [onClear] tell
/// the menu, which owns the order; this screen keeps its own copy of the
/// dishes so a removal shows at once.
///
/// It never says a dish is safe: an avoided dish says what the menu names
/// in it and keeps its question, and the helper-tool sentence closes the
/// card.
class OrderCardScreen extends StatefulWidget {
  /// Creates the card for [dishes], in the order they were added.
  const new({
    required this.dishes,
    required this.profile,
    required this.hebrew,
    required this.onRemove,
    required this.onClear,
    this.menuSharer,
    this.screenBrightness = const NoOpScreenBrightness(),
    super.key,
  });

  /// The dishes of the order, each with its evaluation and questions.
  final List<OrderDish> dishes;

  /// The profile the menu is read for (a group's union), whose allergy
  /// note closes the card.
  final DietaryProfile profile;

  /// Whether the menu is Hebrew: the allergy note's language.
  final bool hebrew;

  /// Called with a dish's id when its section is removed.
  final ValueChanged<String> onRemove;

  /// Called when the order is cleared.
  final VoidCallback onClear;

  /// Shares the card as text; null leaves the Share button out.
  final MenuSharer? menuSharer;

  /// Raised while the card is open, restored when it closes.
  final ScreenBrightness screenBrightness;

  @override
  State<OrderCardScreen> createState() => _OrderCardScreenState();
}

class _OrderCardScreenState extends State<OrderCardScreen> {
  late List<OrderDish> _dishes = List<OrderDish>.of(widget.dishes);

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: ScreenBrightness's contract never throws.
    unawaited(widget.screenBrightness.raise());
  }

  @override
  void dispose() {
    unawaited(widget.screenBrightness.restore());
    super.dispose();
  }

  void _remove(String dishId) {
    widget.onRemove(dishId);
    setState(
      () => _dishes = <OrderDish>[
        for (final item in _dishes)
          if (item.dish.id != dishId) item,
      ],
    );
    if (_dishes.isEmpty) Navigator.maybePop(context);
  }

  void _clear() {
    widget.onClear();
    Navigator.maybePop(context);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.orderCardCopied), showCloseIcon: true),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final card = OrderCardText.compose(
      _dishes,
      profile: widget.profile,
      hebrew: widget.hebrew,
    );
    final text = OrderCardText.asText(card);
    final sharer = widget.menuSharer;
    final note = card.allergyNote;
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.orderCardTitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 12,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      color: theme.textTheme.bodySmall?.color,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final section in card.sections) ...[
                        _OrderSectionView(
                          key: orderCardSectionKey(section.dishId),
                          section: section,
                          onRemove: () => _remove(section.dishId),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (note != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          l10n.orderCardAllergyTitle,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          note,
                          key: orderCardAllergyKey,
                          textDirection: widget.hebrew
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 19,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            key: orderCardCopyKey,
                            onPressed: () => unawaited(_copy(text)),
                            icon: const Icon(Icons.copy),
                            label: Text(l10n.orderCardCopy),
                          ),
                          if (sharer != null)
                            OutlinedButton.icon(
                              key: orderCardShareKey,
                              onPressed: () => unawaited(
                                sharer.shareText(
                                  text,
                                  subject: l10n.orderCardTitle,
                                ),
                              ),
                              icon: const Icon(Icons.ios_share),
                              label: Text(l10n.orderCardShare),
                            ),
                          OutlinedButton.icon(
                            key: orderCardClearKey,
                            onPressed: _clear,
                            icon: const Icon(Icons.remove_shopping_cart),
                            label: Text(l10n.orderCardClear),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        l10n.helperToolSentence,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () => Navigator.maybePop(context),
                  child: Text(l10n.waiterCardDone),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One dish's section: its name as printed, large, with a remove button,
/// and its lines below, in the dish's own direction.
class _OrderSectionView extends StatelessWidget {
  const new({required this.section, required this.onRemove, super.key});

  /// The section to show.
  final OrderSection section;

  /// Takes the dish out of the order.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final direction = section.hebrew ? TextDirection.rtl : TextDirection.ltr;
    final removeLabel = l10n.orderCardRemoveDish(section.name);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 6, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    section.name,
                    textDirection: contentDirection(
                      section.name,
                      Directionality.of(context),
                    ),
                    style: AppTypography.displayStyle(
                      size: 28,
                      color: theme.colorScheme.onSurface,
                    ).copyWith(height: 1.15),
                  ),
                ),
                // The tooltip is visual only; the icon's label is the one
                // screen-reader announcement, as on the dish card's icons.
                Tooltip(
                  message: removeLabel,
                  excludeFromSemantics: true,
                  child: IconButton(
                    key: orderCardRemoveKey(section.dishId),
                    color: theme.colorScheme.onSurfaceVariant,
                    icon: Icon(
                      Icons.remove_circle_outline,
                      semanticLabel: removeLabel,
                    ),
                    onPressed: onRemove,
                  ),
                ),
              ],
            ),
            for (final line in section.lines)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 10, end: 10),
                child: Text(
                  line,
                  textDirection: direction,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 19,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
