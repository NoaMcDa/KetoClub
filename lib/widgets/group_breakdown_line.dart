import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/widgets/profile_names.dart';
import 'package:ketoclub/widgets/verdict_copy.dart';

/// The breakdown line's text, public so a test can find it.
const Key groupBreakdownKey = Key('groupBreakdownLine');

/// The words for one person's state on the breakdown line: their own
/// profile's wording ([ProfileWording.of]), except that a keto-only person
/// is worded in states too, since the card already is.
ProfileWording personWording(DietaryProfile profile) {
  final wording = ProfileWording.of(profile, bantoMode: true);
  return wording.usesStates ? wording : ProfileWording.flexible;
}

/// [people]'s results as one line, "Dana: Fits · Me: Avoid", in the UI
/// language: each person's state in the words their own profile uses, so a
/// strict profile's "fits" still reads "No trigger found".
String groupBreakdownText(
  AppLocalizations l10n,
  List<PersonEvaluation> people,
) => people
    .map(
      (result) => l10n.groupBreakdownEntry(
        profileDisplayName(l10n, result.person),
        VerdictCopy.badge(
          l10n,
          result.state,
          personWording(result.person.profile),
        ),
      ),
    )
    .join(' · ');

/// The per-person breakdown on a dish card when a menu is read for several
/// profiles at once (Banto, ALG-12, issue #354). The card's own pill shows
/// the strictest state; this line says whose it is.
class GroupBreakdownLine extends StatelessWidget {
  /// Creates the line for [people], in their order.
  const new({required this.people, super.key});

  /// Each person's result for the dish.
  final List<PersonEvaluation> people;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final text = groupBreakdownText(l10n, people);
    return Semantics(
      label: l10n.groupBreakdownSemanticLabel(text),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6, top: 1),
            child: Icon(
              Icons.group_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              text,
              key: groupBreakdownKey,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
