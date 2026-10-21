import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/vocabulary.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';

/// The most suggestion chips the exceptions sheet offers.
const int maxExceptionSuggestions = 8;

/// The longest word offered as a suggestion, in UTF-16 units: a chip, not
/// a phrase.
const int _maxSuggestionLength = 24;

/// The sheet itself, for a test that looks for it.
const Key exceptionsSheetKey = ValueKey<String>('exceptionsSheet');

/// The sheet's free-text field.
const Key exceptionsFieldKey = ValueKey<String>('exceptionsField');

/// The sheet's "Add" button beside [exceptionsFieldKey].
const Key exceptionsAddKey = ValueKey<String>('exceptionsAdd');

/// The sheet's "Save" button.
const Key exceptionsSaveKey = ValueKey<String>('exceptionsSave');

/// The "up to N exceptions" message, shown once a word is refused for the
/// cap.
const Key exceptionsFullKey = ValueKey<String>('exceptionsFull');

/// The extra line a strict restriction's sheet carries.
const Key exceptionsStrictNoteKey = ValueKey<String>('exceptionsStrictNote');

/// The removable chip of the exception [word].
Key exceptionChipKey(String word) => ValueKey<String>('exceptionChip_$word');

/// The suggestion chip of [word].
Key exceptionSuggestionKey(String word) =>
    ValueKey<String>('exceptionSuggestion_$word');

/// The words the exceptions sheet suggests for [id]: its direct terms in
/// one language ([hebrew] picks Hebrew, otherwise English), in vocabulary
/// order, at most [limit].
///
/// Left out: a term already in [exclude] (ignoring case), a term that is
/// only the restriction's own name or its plural ("tree nuts" under tree
/// nuts: excepting it would switch the restriction off), and a long
/// phrase. Plural and singular forms are both offered, because an
/// exception matches as whole words, exactly as written, so "almond" does
/// not cover "almonds" (`ProfileEvaluator`). The user's own restriction
/// has no vocabulary to draw from. Pure.
List<String> exceptionSuggestions(
  RestrictionId id, {
  required bool hebrew,
  Iterable<String> exclude = const <String>[],
  int limit = maxExceptionSuggestions,
}) {
  final vocabulary = allergenVocabulary[id];
  if (vocabulary == null) return const <String>[];
  final restriction = restrictionFor(id);
  final own = _stem(hebrew ? restriction.nameHe : restriction.nameEn);
  final skip = <String>{for (final word in exclude) word.trim().toLowerCase()};
  final out = <String>[];
  for (final term in hebrew ? vocabulary.directHe : vocabulary.directEn) {
    if (out.length == limit) break;
    if (term.length > _maxSuggestionLength) continue;
    if (_stem(term) == own) continue;
    if (skip.add(term.toLowerCase())) out.add(term);
  }
  return List<String>.unmodifiable(out);
}

/// [name] lowercased, without a trailing "s" or the Hebrew plural "ים".
String _stem(String name) {
  final lower = name.trim().toLowerCase();
  if (lower.endsWith('ים')) return lower.substring(0, lower.length - 2);
  return lower.endsWith('s') ? lower.substring(0, lower.length - 1) : lower;
}

/// Opens the [ExceptionsSheet] for [restriction] holding [exceptions] and
/// answers the list the user saved, or null when the sheet is dismissed.
///
/// Capped at the app's sheet width ([showKetoClubSheet]).
Future<List<String>?> showExceptionsSheet({
  required BuildContext context,
  required RestrictionId restriction,
  required List<String> exceptions,
}) => showKetoClubSheet<List<String>>(
  context: context,
  showDragHandle: true,
  builder: (_) =>
      ExceptionsSheet(restriction: restriction, exceptions: exceptions),
);

/// A modal sheet that edits a restriction's exceptions (Banto, issue
/// #417): what an exception means in one sentence, the current ones as
/// removable chips, suggestions from the restriction's own vocabulary in
/// the UI language, and a free-text field for any word, in either script.
///
/// A strict restriction (an allergy, celiac disease or a health
/// condition) carries one extra line: an exception only stops the app
/// flagging that word, and the user should still ask the restaurant.
/// Blanks and repeats (ignoring case) are ignored; a word past
/// [ProfileEntry.maxExceptions] is refused with a message rather than
/// dropped silently. "Save" pops the sheet with the list; dismissing it
/// changes nothing.
class ExceptionsSheet extends StatefulWidget {
  /// Creates the sheet for [restriction], starting from [exceptions].
  const new({required this.restriction, required this.exceptions, super.key});

  /// The restriction whose exceptions are edited.
  final RestrictionId restriction;

  /// The exceptions it holds now.
  final List<String> exceptions;

  @override
  State<ExceptionsSheet> createState() => _ExceptionsSheetState();
}

class _ExceptionsSheetState extends State<ExceptionsSheet> {
  final TextEditingController _controller = TextEditingController();
  late List<String> _words = List<String>.of(widget.exceptions);
  bool _full = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Adds [raw] unless it is blank or already held; false when the cap
  /// refused it.
  bool _add(String raw) {
    final word = raw.trim();
    if (word.isEmpty) return true;
    if (_words.any((held) => held.toLowerCase() == word.toLowerCase())) {
      return true;
    }
    if (_words.length >= ProfileEntry.maxExceptions) {
      setState(() => _full = true);
      return false;
    }
    setState(() {
      _words = ProfileEntry.normaliseExceptions(<String>[..._words, word]);
      _full = false;
    });
    return true;
  }

  void _submitField() {
    if (_add(_controller.text)) _controller.clear();
  }

  void _remove(String word) => setState(() {
    _words = <String>[
      for (final held in _words)
        if (held != word) held,
    ];
    _full = false;
  });

  /// Saves, taking the word still typed in the field with it.
  void _save() {
    if (!_add(_controller.text)) return;
    Navigator.pop(context, List<String>.unmodifiable(_words));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final restriction = restrictionFor(widget.restriction);
    final name = restrictionDisplayName(restriction, locale);
    final suggestions = exceptionSuggestions(
      widget.restriction,
      hebrew: locale.languageCode == 'he',
      exclude: _words,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: exceptionsSheetKey,
        padding: EdgeInsetsDirectional.fromSTEB(
          24,
          0,
          24,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.exceptionsSheetTitle(name),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.exceptionsExplain, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(l10n.exceptionsWholeWord, style: muted),
            const SizedBox(height: 16),
            _heading(theme, l10n.exceptionsCurrentHeading),
            const SizedBox(height: 4),
            if (_words.isEmpty)
              Text(l10n.exceptionsNone, style: muted)
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final word in _words)
                    InputChip(
                      key: exceptionChipKey(word),
                      label: Text(word),
                      deleteButtonTooltipMessage: l10n.exceptionsRemove(word),
                      onDeleted: () => _remove(word),
                    ),
                ],
              ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              _heading(theme, l10n.exceptionsSuggestionsHeading),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final word in suggestions)
                    ActionChip(
                      key: exceptionSuggestionKey(word),
                      label: Text(word),
                      onPressed: () => _add(word),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: exceptionsFieldKey,
                    controller: _controller,
                    maxLength: ProfileEntry.maxExceptionLength,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submitField(),
                    decoration: InputDecoration(
                      labelText: l10n.exceptionsField,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton(
                    key: exceptionsAddKey,
                    onPressed: _submitField,
                    child: Text(l10n.exceptionsAdd),
                  ),
                ),
              ],
            ),
            if (_full)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.exceptionsFull(ProfileEntry.maxExceptions),
                  key: exceptionsFullKey,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (restriction.isStrict)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.exceptionsStrictNote,
                  key: exceptionsStrictNoteKey,
                  style: muted,
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: exceptionsSaveKey,
              onPressed: _save,
              child: Text(l10n.exceptionsSave),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(ThemeData theme, String text) => Semantics(
    header: true,
    child: Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        fontSize: 12,
        letterSpacing: 0.6,
      ),
    ),
  );
}

/// The subtitle of a restriction's row in Settings and the profile editor:
/// its [kindLabel], and under it, when there are [exceptions], one muted
/// line ("Except almonds, pistachio").
class RestrictionRowSubtitle extends StatelessWidget {
  /// Creates the subtitle.
  const new({required this.kindLabel, required this.exceptions, super.key});

  /// The restriction kind's label ("Allergy").
  final String kindLabel;

  /// The entry's exceptions; none shows the label alone.
  final List<String> exceptions;

  @override
  Widget build(BuildContext context) {
    if (exceptions.isEmpty) return Text(kindLabel);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kindLabel),
        Text(
          AppLocalizations.of(context)!
              .exceptionsRowLine(exceptions.join(', ')),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
