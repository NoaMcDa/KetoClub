import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/content_direction.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

/// The key of the concern row at [index], so a test can find one row
/// among several that name the same restriction.
Key whyConcernKey(int index) => ValueKey<String>('whyConcern_$index');

/// The key of the empty-state line.
const Key whyEmptyKey = ValueKey<String>('whyEmpty');

/// The key of the helper-tool footer.
const Key whyFooterKey = ValueKey<String>('whyFooter');

/// The key of the sheet's dish-name line (ALG-05's visual pass).
const Key whyDishNameKey = ValueKey<String>('whyDishName');

/// The short phrase saying how [tier] is known, in words and never in a
/// number: an invented percentage is what ALG-06 rules out.
String whyTierPhrase(AppLocalizations l10n, EvidenceTier tier) =>
    switch (tier) {
      EvidenceTier.declared => l10n.whyTierDeclared,
      EvidenceTier.stated => l10n.whyTierStated,
      EvidenceTier.inferred => l10n.whyTierInferred,
      EvidenceTier.suspected => l10n.whyTierSuspected,
      EvidenceTier.confirmed => l10n.whyTierConfirmed,
      EvidenceTier.denied => l10n.whyTierDenied,
    };

/// The line saying where on the dish [source] was found.
String whySourcePhrase(AppLocalizations l10n, ConcernSource source) =>
    switch (source) {
      ConcernSource.name => l10n.whySourceName,
      ConcernSource.description => l10n.whySourceDescription,
      ConcernSource.option => l10n.whySourceOption,
      ConcernSource.hidden => l10n.whySourceHidden,
      ConcernSource.model => l10n.whySourceModel,
    };

/// Opens the [WhySheet] for [dishName] as a modal bottom sheet capped at
/// the app's sheet width ([showKetoClubSheet]).
///
/// With [bantoMode] off nothing opens and the future completes at once, so
/// a caller needs no gate of its own.
Future<void> showWhySheet(
  BuildContext context, {
  required String dishName,
  required List<Concern> concerns,
  required bool strictProfile,
  bool bantoMode = BantoMode.enabled,
}) {
  if (!bantoMode) return Future<void>.value();
  return showKetoClubSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => WhySheet(
      dishName: dishName,
      concerns: concerns,
      strictProfile: strictProfile,
      bantoMode: bantoMode,
    ),
  );
}

/// A sheet explaining why a dish got its state (Banto, ALG-06, issue
/// #348): one row per [Concern] with the restriction, how it is known, where
/// it was found, the text it matched and the question that would settle it.
///
/// Confidence is words, never a number. An empty [concerns] list says that
/// nothing in the menu text points to the profile, never that the dish is
/// fine: for a [strictProfile] it adds "still ask the restaurant". The
/// footer is the helper-tool sentence.
///
/// With [bantoMode] off the widget builds nothing.
class WhySheet extends StatelessWidget {
  /// Creates the sheet for [dishName] listing [concerns].
  const new({
    required this.dishName,
    required this.concerns,
    required this.strictProfile,
    this.bantoMode = BantoMode.enabled,
    super.key,
  });

  /// The dish the sheet is about.
  final String dishName;

  /// Every concern found for the dish, in the order to show them.
  final List<Concern> concerns;

  /// Whether the profile holds a strict restriction (an allergen or celiac
  /// disease), which adds "still ask the restaurant" to an empty list.
  final bool strictProfile;

  /// Whether this build shows Banto surfaces; the sheet is empty without.
  final bool bantoMode;

  @override
  Widget build(BuildContext context) {
    if (!bantoMode) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // A plain Column, not a lazy ListView: a dish has a handful of
    // concerns, and every row must exist in the tree.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.whySheetTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            // Menu content, in its own direction (audit M8; ALG-05's
            // visual pass, B4): a Hebrew dish in the English UI reads from
            // the right, as on its card.
            Text(
              l10n.whySheetDishName(dishName),
              key: whyDishNameKey,
              textDirection: contentDirection(
                dishName,
                Directionality.of(context),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (concerns.isEmpty)
              Text(
                strictProfile ? l10n.whyEmptyStrict : l10n.whyEmptyFlexible,
                key: whyEmptyKey,
                style: theme.textTheme.bodyMedium,
              )
            else
              for (var i = 0; i < concerns.length; i++) ...[
                if (i > 0) const Divider(height: 24),
                _ConcernRow(key: whyConcernKey(i), concern: concerns[i]),
              ],
            const SizedBox(height: 20),
            Text(
              l10n.helperToolSentence,
              key: whyFooterKey,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One concern: the restriction, the tier phrase, the source, the quoted
/// text and the waiter question.
class _ConcernRow extends StatelessWidget {
  const new({required this.concern, super.key});

  final Concern concern;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final name = restrictionDisplayName(
      restrictionFor(concern.restrictionId),
      locale,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final matched = concern.matchedText;
    final question = concern.waiterQuestion;

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            whyTierPhrase(l10n, concern.tier),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 2),
          Text(whySourcePhrase(l10n, concern.source), style: muted),
          if (matched != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.whyMatchedText(matched),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (question != null) ...[
            const SizedBox(height: 8),
            Text(l10n.whyWaiterQuestionLabel, style: muted),
            SizedBox(
              width: double.infinity,
              child: Text(
                question,
                textDirection: contentDirection(
                  question,
                  Directionality.of(context),
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
