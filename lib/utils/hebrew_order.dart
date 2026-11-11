/// A Hebrew letter, or a niqqud or cantillation mark written on one.
const String _letter =
    r'[א-ת\u0591-\u05BD\u05BF\u05C1\u05C2\u05C4\u05C5\u05C7]';

/// A geresh or gershayim as menus type them: the Hebrew marks ׳ and ״, and
/// the ASCII and curly quotes that stand in for them.
const String _geresh = r"""['"\u05F3\u05F4\u2018\u2019\u201C\u201D]""";

/// One Hebrew word: a run of Hebrew letters and their marks. A geresh or
/// gershayim between two letters is part of the word (issue #442): it marks
/// a foreign sound in a loanword (פרמז'ן, קרפצ'יו) or an acronym (תנ"ך),
/// and splitting there would leave a final-form letter looking like the
/// start of a word. A quote with no Hebrew letter on both sides still ends
/// the word.
final RegExp _hebrewWord = RegExp('$_letter+(?:$_geresh$_letter+)*');

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
/// whole text. Text with no Hebrew is never reversed by this test, and
/// neither is a loanword whose geresh comes before a final letter, nor
/// pointed text, where a mark sits between the letters.
bool looksCharacterReversed(String text) {
  for (final match in _hebrewWord.allMatches(text)) {
    final word = match.group(0);
    if (word != null && _finalForms.contains(word[0])) return true;
  }
  return false;
}
