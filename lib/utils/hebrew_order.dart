/// A run of Hebrew letters: one Hebrew word, niqqud and punctuation aside.
final RegExp _hebrewWord = RegExp('[א-ת]+');

/// The five final-form letters: ך ם ן ף ץ. Hebrew writes them only at the
/// end of a word.
const String _finalForms = 'ךםןףץ';

/// Whether [text] reads as character-reversed Hebrew (architecture.md D19;
/// issue #181).
///
/// A text layer extracted from a Hebrew PDF, or an old "visual Hebrew"
/// web page, can come out with every word's letters backwards, as valid
/// Unicode and with no warning: 68% of the Hebrew PDFs in one measured
/// corpus did (`docs/menu_sources_research.md` §3.2). Hebrew writes a
/// final-form letter only at the end of a word, so a word that *starts*
/// with one is proof the text is reversed, and one such word rejects the
/// whole text. Text with no Hebrew is never reversed by this test.
bool looksCharacterReversed(String text) {
  for (final match in _hebrewWord.allMatches(text)) {
    final word = match.group(0);
    if (word != null && _finalForms.contains(word[0])) return true;
  }
  return false;
}
