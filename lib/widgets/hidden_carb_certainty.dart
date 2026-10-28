import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';

/// The short label for how sure the model was of a hidden-carb flag, in
/// the UI language (issue #213).
///
/// The flag's source and waiter question stay in the menu's own language
/// (architecture.md §12); only this label follows the interface, so a
/// Hebrew UI over an English menu reads "house dressing  חשד".
String hiddenCarbCertaintyLabel(
  AppLocalizations l10n,
  HiddenCarbCertainty certainty,
) => switch (certainty) {
  HiddenCarbCertainty.suspected => l10n.hiddenCarbsCertaintySuspected,
  HiddenCarbCertainty.likely => l10n.hiddenCarbsCertaintyLikely,
};

/// What a screen reader says for one [flag]: the source, how sure the
/// model was, then the question to ask — one phrase, so the certainty is
/// never separated from the ingredient it qualifies.
String hiddenCarbSemanticLabel(AppLocalizations l10n, HiddenCarb flag) =>
    '${flag.source}, ${hiddenCarbCertaintyLabel(l10n, flag.certainty)}. '
    '${flag.waiterQuestion}';
