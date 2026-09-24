import 'package:flutter/widgets.dart';
import 'package:ketoclub/utils/text_normaliser.dart';

/// Matches one Latin letter: text with one, and no Hebrew, reads left to
/// right.
final RegExp _latinLetter = RegExp('[A-Za-z]');

/// The direction a piece of **menu content** reads in — a dish name, a
/// description, a waiter-script line — which follows the menu's own
/// language, not the UI's (architecture.md §12).
///
/// Hebrew text is right to left, text with Latin letters and no Hebrew is
/// left to right, and anything else (digits, punctuation, empty) keeps
/// [ambient]. Without this, an English description in the Hebrew UI was
/// laid out right to left and its closing full stop jumped to the start of
/// the line (".butter, grilled onion"), and a Hebrew one in the English UI
/// did the mirror image — found by the visual audit
/// (`docs/VISUAL_AUDIT.md`).
TextDirection contentDirection(String text, TextDirection ambient) {
  if (TextNormaliser.containsHebrew(text)) return TextDirection.rtl;
  if (_latinLetter.hasMatch(text)) return TextDirection.ltr;
  return ambient;
}
