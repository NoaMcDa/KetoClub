import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/utils/visit_profile.dart';

/// The key of the "Worked for me" tag.
const Key workedForTagKey = ValueKey<String>('workedForTag');

/// The words of the tag for the marked people [names] (Banto, #412): "Worked
/// for me" for the device owner alone, otherwise "Worked for Dana, Noa". The
/// owner's unnamed profile reads in the UI's language ([workedForSelf]
/// becomes the profile's default name). Never "safe".
String workedForLabel(AppLocalizations l10n, List<String> names) {
  if (names.length == 1 && names.single == workedForSelf) {
    return l10n.workedChip;
  }
  return l10n.workedTagNames(
    names
        .map((name) => name == workedForSelf ? l10n.profileDefaultName : name)
        .join(', '),
  );
}

/// A small tag saying a venue worked for the people in [names] (Banto,
/// #412): on a marked Recent row and in the menu header. A label only: it
/// carries no number and orders nothing (D27).
class WorkedForTag extends StatelessWidget {
  /// Creates the tag for [names], which must not be empty.
  const new({required this.names, super.key});

  /// The marked people, as `VisitEntry.workedFor` names them.
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final label = workedForLabel(l10n, names);
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        key: workedForTagKey,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 14, color: scheme.onSecondaryContainer),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
