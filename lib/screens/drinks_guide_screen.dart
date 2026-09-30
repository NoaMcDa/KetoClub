import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/utils/drinks_guide_data.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/waiter_script_widget.dart';

/// The route path for the offline drinks guide (issue #216).
const String drinksRoutePath = '/drinks';

/// An offline, bilingual reference of keto-friendly bar and coffee
/// orders with typical net-carb estimates (issue #216, Part B).
///
/// Three sections: order as-is (green), ask for a swap (yellow, with a
/// [WaiterScriptWidget] copy affordance), and skip (red). All content
/// lives in `drinks_guide_data.dart` as Dart literals (architecture.md
/// §6.3 exception: waiter-readable text follows the menu's language, not
/// ARB). The disclaimer that all numbers are estimates is shown once at
/// the top of each section.
///
/// No dependency on any service, controller, or network request — the
/// screen works entirely offline.
class DrinksGuideScreen extends StatelessWidget {
  /// Creates the drinks guide screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    final isHebrew = locale.languageCode == 'he';

    final orderAsIs = isHebrew ? drinkGuideOrderAsIsHe : drinkGuideOrderAsIsEn;
    final askForSwap = isHebrew
        ? drinkGuideAskForSwapHe
        : drinkGuideAskForSwapEn;
    final skip = isHebrew ? drinkGuideSkipHe : drinkGuideSkipEn;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.drinksGuideTitle)),
      body: ContentWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Disclaimer(l10n.drinksGuideDisclaimer),
              const SizedBox(height: 20),
              _SectionHeader(l10n.drinksGuideSectionOrderAsIs),
              const SizedBox(height: 8),
              _DrinkGroup(entries: orderAsIs, showScript: false),
              const SizedBox(height: 20),
              _SectionHeader(l10n.drinksGuideSectionSwap),
              const SizedBox(height: 8),
              _DrinkGroup(entries: askForSwap, showScript: true),
              const SizedBox(height: 20),
              _SectionHeader(l10n.drinksGuideSectionSkip),
              const SizedBox(height: 8),
              _DrinkGroup(entries: skip, showScript: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// The disclaimer line shown at the top of the screen.
class _Disclaimer extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 2, top: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(fontSize: 12, height: 1.4),
      ),
    );
  }
}

/// A section heading for one of the three groups.
class _SectionHeader extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 2, bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontSize: 12, letterSpacing: 0.6),
      ),
    );
  }
}

/// A card holding one section's drink entries.
class _DrinkGroup extends StatelessWidget {
  const new({required this.entries, required this.showScript});

  final List<DrinkEntry> entries;

  /// When true, yellow entries render their [DrinkEntry.swapScript] via
  /// [WaiterScriptWidget] for the copy affordance.
  final bool showScript;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              _DrinkRow(entry: entries[i], showScript: showScript),
              if (i < entries.length - 1)
                const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// One drink entry row: name, net-carb range chip, and optional
/// [WaiterScriptWidget] if [showScript] is true and a script exists.
class _DrinkRow extends StatelessWidget {
  const new({required this.entry, required this.showScript});

  final DrinkEntry entry;
  final bool showScript;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final script = showScript ? entry.swapScript : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(entry.netCarbsRangeLabel),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                labelStyle: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (script != null) ...[
            const SizedBox(height: 10),
            WaiterScriptWidget(script: script),
          ],
        ],
      ),
    );
  }
}
