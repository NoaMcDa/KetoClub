import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/concern.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/confirmations.dart';
import 'package:ketoclub/utils/allergens/declarations.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/banto_mode.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/content_direction.dart';
import 'package:ketoclub/widgets/kitchen_notice.dart';
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

/// The key of the dated "you confirmed with the staff" line under the
/// concern row at [index] (ALG-14).
Key whyConfirmationKey(int index) => ValueKey<String>('whyConfirmation_$index');

/// The dated line for [concern] when the person's own answer moved it to
/// [EvidenceTier.confirmed] or [EvidenceTier.denied] (ALG-14): "You
/// confirmed with the staff on 12 May", or that the staff said no on that
/// day and it holds for that visit only. Null for any other concern, and
/// for one only a shared count decided (no such count exists yet).
String? whyConfirmationLine(
  AppLocalizations l10n,
  Concern concern,
  List<ConfirmationEvidence> confirmations,
) {
  if (concern.tier != EvidenceTier.confirmed &&
      concern.tier != EvidenceTier.denied) {
    return null;
  }
  final piece = Confirmations.deciding(concern, confirmations);
  if (piece == null || piece.shared) return null;
  return concern.tier == EvidenceTier.confirmed
      ? l10n.whyConfirmedOn(piece.day)
      : l10n.whyDeniedOn(piece.day);
}

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

/// The tier phrase for a concern at [EvidenceTier.declared] that
/// [declaration] lowered (ALG-09): "declared by the platform" for a
/// platform tag, "declared by the restaurant" for the dish's own text or
/// its heading, "declared in the restaurant's allergen information" for a
/// matrix's `free` cell (ALG-16). Without a declaration it is
/// [whyTierPhrase]'s.
String whyDeclaredTierPhrase(AppLocalizations l10n, Declaration? declaration) =>
    switch (declaration?.source) {
      DeclarationSource.dishText ||
      DeclarationSource.heading => l10n.whyTierDeclaredRestaurant,
      DeclarationSource.allergenMatrix => l10n.whyTierDeclaredMatrix,
      DeclarationSource.platformTag || null => l10n.whyTierDeclared,
    };

/// The line saying where on the dish [source] was found.
String whySourcePhrase(AppLocalizations l10n, ConcernSource source) =>
    switch (source) {
      ConcernSource.name => l10n.whySourceName,
      ConcernSource.description => l10n.whySourceDescription,
      ConcernSource.option => l10n.whySourceOption,
      ConcernSource.hidden => l10n.whySourceHidden,
      ConcernSource.model => l10n.whySourceModel,
      ConcernSource.kitchen => l10n.whySourceKitchenGeneric,
      ConcernSource.matrix => l10n.whySourceMatrix,
    };

/// The line saying where [concern] was found: [whySourcePhrase], except
/// that a kitchen concern (ALG-07) names its kitchen, "This kitchen has a
/// fryer — ask about cross-contact".
String whyConcernSourcePhrase(AppLocalizations l10n, Concern concern) {
  if (kitchenKindOf(concern) case final kind?) {
    return l10n.whySourceKitchen(kitchenKindNoun(l10n, kind));
  }
  return whySourcePhrase(l10n, concern.source);
}

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
  List<Declaration> declarations = const <Declaration>[],
  List<ConfirmationEvidence> confirmations = const <ConfirmationEvidence>[],
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
      declarations: declarations,
      confirmations: confirmations,
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
/// A concern a declaration lowered ([EvidenceTier.declared], ALG-09) says
/// who declared it, the platform or the restaurant, and quotes the
/// declaration with the reminder that it never rules the finding out.
///
/// A concern the person's own staff answer moved (ALG-14) says when:
/// "You confirmed with the staff on 12 May", or that the staff said no
/// that day, which holds for that visit only.
///
/// With [bantoMode] off the widget builds nothing.
class WhySheet extends StatelessWidget {
  /// Creates the sheet for [dishName] listing [concerns].
  const new({
    required this.dishName,
    required this.concerns,
    required this.strictProfile,
    this.declarations = const <Declaration>[],
    this.confirmations = const <ConfirmationEvidence>[],
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

  /// The declarations that lowered a concern (`EvaluatedDish.declarations`),
  /// quoted under each concern at [EvidenceTier.declared].
  final List<Declaration> declarations;

  /// The staff answers that moved a concern (`EvaluatedDish.confirmations`,
  /// ALG-14), dated under each concern they answer.
  final List<ConfirmationEvidence> confirmations;

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
                _ConcernRow(
                  key: whyConcernKey(i),
                  concern: concerns[i],
                  declaration: _declarationFor(concerns[i]),
                  confirmationLine: whyConfirmationLine(
                    l10n,
                    concerns[i],
                    confirmations,
                  ),
                  confirmationKey: whyConfirmationKey(i),
                ),
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

  /// The first of [declarations] that names [concern]'s restriction, when
  /// the concern is at [EvidenceTier.declared].
  Declaration? _declarationFor(Concern concern) {
    if (concern.tier != EvidenceTier.declared) return null;
    for (final declaration in declarations) {
      if (declaration.restrictionIds.contains(concern.restrictionId)) {
        return declaration;
      }
    }
    return null;
  }
}

/// One concern: the restriction, the tier phrase, the source, the quoted
/// text and the waiter question.
class _ConcernRow extends StatelessWidget {
  const new({
    required this.concern,
    this.declaration,
    this.confirmationLine,
    this.confirmationKey,
    super.key,
  });

  final Concern concern;

  /// The declaration that lowered [concern], when one did.
  final Declaration? declaration;

  /// The dated staff-answer line (ALG-14), when one moved [concern].
  final String? confirmationLine;

  /// The key of [confirmationLine]'s text.
  final Key? confirmationKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final restriction = restrictionFor(concern.restrictionId);
    final matchedOwn = concern.matchedText?.trim();
    // The user's own restriction (ALG-17) names the word that matched.
    final name =
        restriction.id == RestrictionId.custom &&
            matchedOwn != null &&
            matchedOwn.isNotEmpty
        ? '${restrictionDisplayName(restriction, locale)}: $matchedOwn'
        : restrictionDisplayName(restriction, locale);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // A kitchen concern's matched text is its kind's name, which
    // [whyConcernSourcePhrase] already puts into words (ALG-07).
    final matched = concern.source == ConcernSource.kitchen
        ? null
        : concern.matchedText;
    final question = concern.waiterQuestion;

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            // The restaurant's allergen matrix declares its own concerns
            // (ALG-16), with no declaration to name.
            concern.tier == EvidenceTier.declared &&
                    declaration == null &&
                    concern.source == ConcernSource.matrix
                ? l10n.whyTierDeclaredMatrix
                : concern.tier == EvidenceTier.declared
                ? whyDeclaredTierPhrase(l10n, declaration)
                : whyTierPhrase(l10n, concern.tier),
            style: theme.textTheme.labelLarge,
          ),
          if (confirmationLine case final line?) ...[
            const SizedBox(height: 2),
            Text(line, key: confirmationKey, style: theme.textTheme.bodyMedium),
          ],
          if (declaration case final declared?) ...[
            const SizedBox(height: 2),
            Text(
              declared.source == DeclarationSource.allergenMatrix
                  ? l10n.whyMatrixAbsent(declared.matchedText)
                  : l10n.whyDeclaredAbsent(declared.matchedText),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 2),
          Text(whyConcernSourcePhrase(l10n, concern), style: muted),
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
