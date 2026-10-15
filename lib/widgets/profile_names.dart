import 'package:flutter/widgets.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

/// What the UI calls [person] (Banto, ALG-12, issue #354): their name, or
/// "Me" in the UI language for the user's own profile until it is renamed.
String profileDisplayName(AppLocalizations l10n, NamedProfile person) =>
    person.name.isEmpty ? l10n.profileDefaultName : person.name;

/// [people]'s display names joined with commas, in their order.
String profileDisplayNames(
  AppLocalizations l10n,
  Iterable<NamedProfile> people,
) => people.map((person) => profileDisplayName(l10n, person)).join(', ');

/// One line naming [profile]'s restrictions in [locale]'s language, in the
/// order they were added, or "Keto only" for an empty profile, which is
/// read as keto everywhere.
String profileRestrictionsLine(
  AppLocalizations l10n,
  Locale locale,
  DietaryProfile profile,
) {
  if (profile.isEmpty) return l10n.profileKetoOnly;
  return profile.entries
      .map((entry) => profileEntryDisplayName(entry, locale))
      .join(', ');
}
