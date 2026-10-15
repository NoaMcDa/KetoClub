/// The chef card's sentences (Banto; the Allergens epic, ALG-08a and
/// ALG-08b, issue #350, and ALG-15, issue #357): what a person with a
/// dietary profile says to a kitchen, composed from sentence templates per
/// restriction kind and language — for the profile alone
/// ([ChefCardText.compose]), for one dish ([ChefCardText.composeForDish])
/// and as the short note a delivery app's free-text box takes
/// ([ChefCardText.allergyNote]).
///
/// This text is read aloud and shown to restaurant staff, so like the
/// waiter templates in `constants.dart` it follows the language the person
/// picks for the card, not the UI locale, and lives here rather than in the
/// ARB files (architecture.md §6.3 and §12, the documented exception).
///
/// The wording obeys the epic's floor: a strict entry (an allergen or
/// celiac disease, `RestrictionKind.isStrict`) is only ever *stated* and
/// *asked about*; nothing here says a dish is safe, and nothing promises
/// anything. There are no severity levels, so the same strict sentence is
/// used for every allergen. Pure: no widget, no clock, no I/O.
library;

import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/allergens/kitchen_signals.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/waiter_questions.dart';

/// The longest [ChefCardText.allergyNote] aims to be, in characters: what
/// a delivery app's note box takes without scrolling. The allergen list is
/// never cut to fit; the flexible sentence is dropped first.
const int allergyNoteMaxLength = 280;

/// Composes the lines of the chef card.
abstract final class ChefCardText {
  /// The card's lines for [profile] in Hebrew when [hebrew], else English:
  /// an introduction, one line per entry in profile order, and a closing
  /// line. An empty [profile] has no card, so the result is empty.
  ///
  /// Per entry, by the restriction's kind: an allergen gets the strict
  /// "please check every ingredient" sentence, celiac disease (autoimmune)
  /// its own sentence about gluten and cross-contact, an intolerance, a
  /// lifestyle diet or keto the flexible "tell me which dishes contain it"
  /// sentence. An entry with exceptions gets them appended to its own line.
  ///
  /// The closing line asks the kitchen to confirm its cross-contact
  /// precautions when the profile holds a strict entry; a profile of
  /// flexible entries only closes with thanks, since there is nothing to
  /// cross-contaminate.
  static List<String> compose(DietaryProfile profile, {required bool hebrew}) {
    if (profile.isEmpty) return const <String>[];
    final strict = profile.entries.any(
      (entry) => restrictionFor(entry.restrictionId).isStrict,
    );
    final closing = switch ((hebrew, strict)) {
      (false, true) => _closingStrictEn,
      (false, false) => _closingEn,
      (true, true) => _closingStrictHe,
      (true, false) => _closingHe,
    };
    return List<String>.unmodifiable(<String>[
      if (hebrew) _introHe else _introEn,
      for (final entry in profile.entries) _entryLine(entry, hebrew: hebrew),
      closing,
    ]);
  }

  /// [lines] as the plain text that is copied and shared: one line each.
  static String asText(List<String> lines) => lines.join('\n');

  /// The chef card for one dish (ALG-08b), in Hebrew when [hebrew], else
  /// English: the introduction, the profile's heading lines (its strict
  /// entries — an allergen or celiac disease — or, for a profile with no
  /// strict entry, every entry), the dish's name as the menu printed it,
  /// the dish's [modification] one line each (the evaluator's, with the
  /// menu's words quoted, ALG-05), every one of [questions], and a closing
  /// line. An empty [profile] has no card, so the result is empty.
  ///
  /// The closing line asks the kitchen to confirm its cross-contact
  /// precautions when [crossContact] — a kitchen signal of the menu
  /// threatens a strict entry ([kitchenThreatensStrict]) — and is plain
  /// thanks otherwise. [dishName], [modification] and [questions] are used
  /// as given: they are already in the menu's language.
  static List<String> composeForDish(
    DietaryProfile profile, {
    required String dishName,
    required String? modification,
    required List<String> questions,
    required bool crossContact,
    required bool hebrew,
  }) {
    if (profile.isEmpty) return const <String>[];
    final strictEntries = <ProfileEntry>[
      for (final entry in profile.entries)
        if (restrictionFor(entry.restrictionId).isStrict) entry,
    ];
    final headed = strictEntries.isEmpty ? profile.entries : strictEntries;
    final name = dishName.trim();
    return List<String>.unmodifiable(<String>[
      if (hebrew) _introHe else _introEn,
      for (final entry in headed) _entryLine(entry, hebrew: hebrew),
      if (name.isNotEmpty)
        (hebrew ? _dishLineHe : _dishLineEn).replaceAll('{dish}', name),
      if (modification != null)
        for (final line in modification.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      for (final question in questions)
        if (question.trim().isNotEmpty) question.trim(),
      switch ((hebrew, crossContact)) {
        (false, true) => _closingStrictEn,
        (false, false) => _closingEn,
        (true, true) => _closingStrictHe,
        (true, false) => _closingHe,
      },
    ]);
  }

  /// Whether any of [signals] threatens a strict entry of [profile] (an
  /// allergen or celiac disease): the condition for [composeForDish]'s
  /// cross-contact closing line (ALG-07's signals, ALG-08b).
  static bool kitchenThreatensStrict(
    List<KitchenSignal> signals,
    DietaryProfile profile,
  ) => signals.any(
    (signal) => signal.threatens.any(
      (id) => profile.contains(id) && restrictionFor(id).isStrict,
    ),
  );

  /// The chef card's compact form for a whole order (ALG-15): one short
  /// paragraph for a delivery app's note box, in Hebrew when [hebrew],
  /// else English. Null when [profile] holds nothing but keto, which a
  /// kitchen note does not carry.
  ///
  /// The allergens, then celiac disease, then the user's own words
  /// (ALG-17's free-text restriction, strict: "I cannot eat kiwi"), then
  /// the flexible entries (an intolerance or a diet, named as what is left
  /// out), and a closing
  /// sentence: for a profile with a strict entry, "check every
  /// ingredient … confirm there is no cross-contact"; otherwise "please
  /// leave them out". When the note is longer than
  /// [allergyNoteMaxLength] the flexible sentence is dropped; the allergen
  /// list is never cut. No severity word, no promise and no "safe".
  static String? allergyNote(DietaryProfile profile, {required bool hebrew}) {
    final allergens = <RestrictionId>[];
    var celiac = false;
    final flexible = <RestrictionId>[];
    final ownTerms = <String>[];
    var ownEntry = false;
    for (final entry in profile.entries) {
      final restriction = restrictionFor(entry.restrictionId);
      if (restriction.id == RestrictionId.custom) {
        ownEntry = true;
        ownTerms.addAll(entry.terms);
        continue;
      }
      switch (restriction.kind) {
        case RestrictionKind.allergen:
          allergens.add(restriction.id);
        case RestrictionKind.autoimmune:
          celiac = true;
        case RestrictionKind.keto:
          break;
        case RestrictionKind.intolerance:
        case RestrictionKind.lifestyle:
        case RestrictionKind.religiousComponent:
          flexible.add(restriction.id);
      }
    }
    final strict = allergens.isNotEmpty || celiac || ownEntry;
    if (!strict && flexible.isEmpty) return null;

    String subjects(List<RestrictionId> ids, String prefix) =>
        _joinList(<String>[
          for (final id in ids)
            '$prefix${WaiterQuestions.subject(id, hebrew: hebrew)}',
        ], hebrew: hebrew);

    final allergenSentence = allergens.isEmpty
        ? null
        : (hebrew ? 'יש לי אלרגיה {list}.' : 'I have an allergy to {list}.')
              .replaceAll('{list}', subjects(allergens, hebrew ? 'ל' : ''));
    final celiacSentence = !celiac
        ? null
        : (hebrew
              ? 'יש לי צליאק ואני לא יכול/ה לאכול גלוטן.'
              : 'I have celiac disease and cannot eat gluten.');
    final ownList = ownTerms.isEmpty
        ? WaiterQuestions.subject(RestrictionId.custom, hebrew: hebrew)
        : _joinList(ownTerms, hebrew: hebrew);
    final ownSentence = !ownEntry
        ? null
        : (hebrew
                  ? (allergens.isNotEmpty || celiac
                        ? 'אני גם לא יכול/ה לאכול {list}.'
                        : 'אני לא יכול/ה לאכול {list}.')
                  : (allergens.isNotEmpty || celiac
                        ? 'I also cannot eat {list}.'
                        : 'I cannot eat {list}.'))
              .replaceAll('{list}', ownList);
    final flexibleSentence = flexible.isEmpty
        ? null
        : (hebrew
                  ? (strict ? 'אני גם נמנע/ת {list}.' : 'אני נמנע/ת {list}.')
                  : (strict ? 'I also avoid {list}.' : 'I avoid {list}.'))
              .replaceAll('{list}', subjects(flexible, hebrew ? 'מ' : ''));
    final closing = strict
        ? (hebrew ? _noteClosingStrictHe : _noteClosingStrictEn)
        : (hebrew ? _noteClosingHe : _noteClosingEn);

    String join({required bool withFlexible}) => <String>[
      ?allergenSentence,
      ?celiacSentence,
      ?ownSentence,
      if (withFlexible) ?flexibleSentence,
      closing,
    ].join(' ');

    final full = join(withFlexible: true);
    if (full.length <= allergyNoteMaxLength || !strict) return full;
    return join(withFlexible: false);
  }

  /// [items] as one list in running text: "a", "a and b", "a, b and c";
  /// in Hebrew the last joins with the conjunction ו, attached to it.
  static String _joinList(List<String> items, {required bool hebrew}) {
    if (items.length == 1) return items.single;
    final head = items.sublist(0, items.length - 1).join(', ');
    return hebrew ? '$head ו${items.last}' : '$head and ${items.last}';
  }

  static const String _dishLineEn = 'The dish I would like: {dish}';
  static const String _dishLineHe = 'המנה שאני רוצה להזמין: {dish}';

  static const String _noteClosingStrictEn =
      'Please check every ingredient, including sauces, and make sure '
      'there is no cross-contact in preparation. Thank you.';
  static const String _noteClosingStrictHe =
      'בבקשה לבדוק כל מרכיב, כולל רטבים, ולוודא שאין מגע צולב בהכנה. תודה.';
  static const String _noteClosingEn =
      'Please leave them out of my order. Thank you.';
  static const String _noteClosingHe = 'בבקשה לא לכלול אותם בהזמנה. תודה.';

  static const String _introEn =
      'Hello, I have dietary restrictions and I would like your help '
      'with my order.';
  static const String _introHe =
      'שלום, יש לי הגבלות תזונה ואשמח לעזרתכם בהזמנה.';

  static const String _closingStrictEn =
      'Please ask the kitchen to confirm how cross-contact is avoided '
      '(shared surfaces, oil, utensils). Thank you.';
  static const String _closingStrictHe =
      'אשמח שתבררו עם המטבח איך נמנע מגע צולב '
      '(משטחים, שמן וכלים משותפים). תודה.';

  static const String _closingEn = 'Thank you.';
  static const String _closingHe = 'תודה.';

  static String _entryLine(ProfileEntry entry, {required bool hebrew}) {
    final restriction = restrictionFor(entry.restrictionId);
    final base = restriction.id == RestrictionId.custom
        ? _ownLine(entry.terms, hebrew: hebrew)
        : (hebrew ? _baseHe(restriction) : _baseEn(restriction));
    if (entry.exceptions.isEmpty) return base;
    final joined = entry.exceptions.join(', ');
    return hebrew
        ? '$base אני כן יכול/ה לאכול: $joined.'
        : '$base I can still have: $joined.';
  }

  /// The strict line of the user's own restriction (ALG-17): their words,
  /// as they wrote them, and the allergen sentence's "check every
  /// ingredient". It names no condition: the words may be an allergy or
  /// something the person cannot eat for another reason, and the card
  /// says only what to keep out.
  static String _ownLine(List<String> terms, {required bool hebrew}) {
    final list = terms.isEmpty
        ? WaiterQuestions.subject(RestrictionId.custom, hebrew: hebrew)
        : terms.join(', ');
    return hebrew
        ? 'אני לא יכול/ה לאכול: $list — נא לבדוק כל מרכיב, כולל רטבים, '
              'שמנים וקישוטים.'
        : 'I cannot eat: $list — please check every ingredient, including '
              'sauces, oils and garnishes.';
  }

  /// The ALG-17 restrictions whose line is their own rather than their
  /// kind's, in English; `{name}` is the restriction's name, lower-cased.
  /// Alpha-gal names its foods, since nobody orders "alpha-gal"; FODMAP,
  /// histamine and small portions ask to be told, as every flexible line
  /// does, and name what they go easy on. Small portions names no medicine:
  /// the kitchen needs the portion, not the reason.
  static const Map<RestrictionId, String> _extendedLineEn =
      <RestrictionId, String>{
        RestrictionId.alphaGal:
            'I have an allergy to {name} — beef, lamb, pork, gelatin, lard '
            'and meat stock — please check every ingredient, including '
            'sauces, stocks, oils and garnishes.',
        RestrictionId.fodmap:
            'I follow a low-FODMAP diet — please tell me which dishes '
            'contain onion, garlic, wheat, beans or lentils, honey or apple, '
            'even in a sauce or a stock.',
        RestrictionId.histamine:
            'I am sensitive to {name} — please tell me which dishes contain '
            'aged cheese, smoked or processed meat, fermented foods, '
            'vinegar, wine or tuna.',
        RestrictionId.glp1:
            'I eat small portions — please tell me which dishes come in a '
            'smaller size, and which are fried, creamy or very sweet.',
      };

  /// [_extendedLineEn] in Hebrew; `{name}` is the Hebrew name.
  static const Map<RestrictionId, String> _extendedLineHe =
      <RestrictionId, String>{
        RestrictionId.alphaGal:
            "יש לי אלרגיה ל{name} — בקר, כבש, חזיר, ג'לטין, שומן מן החי וציר "
            'בשר — נא לבדוק כל מרכיב, כולל רטבים, צירים, שמנים וקישוטים.',
        RestrictionId.fodmap:
            'אני בתזונה דלת {name} (FODMAP) — נא לומר לי אילו מנות מכילות '
            'בצל, שום, חיטה, שעועית או עדשים, דבש או תפוח, גם ברוטב או '
            'בציר.',
        RestrictionId.histamine:
            'אני רגיש/ה ל{name} — נא לומר לי אילו מנות מכילות גבינה '
            'מיושנת, בשר מעושן או מעובד, מזון מותסס, חומץ, יין או טונה.',
        RestrictionId.glp1:
            'אני אוכל/ת מנות קטנות — נא לומר לי אילו מנות אפשר לקבל בגודל '
            'קטן יותר, ואילו מטוגנות, שמנתיות או מתוקות מאוד.',
      };

  static String _baseEn(Restriction restriction) {
    final name = restriction.nameEn.toLowerCase();
    final special = _extendedLineEn[restriction.id];
    if (special != null) return special.replaceAll('{name}', name);
    switch (restriction.kind) {
      case RestrictionKind.allergen:
        return 'I have an allergy to $name — please check every ingredient, '
            'including sauces, oils and garnishes.';
      case RestrictionKind.autoimmune:
        return 'I have celiac disease and cannot eat $name (wheat, barley, '
            'rye and their derivatives) — please check every ingredient, '
            'including sauces, soups and marinades, and tell me about '
            'shared fryers, grills and utensils.';
      case RestrictionKind.lifestyle:
        return _lifestyleEn(restriction.id, name);
      case RestrictionKind.keto:
        return 'I follow a keto diet (very low carbohydrate) — please tell '
            'me which dishes contain sugar, flour, rice, potato or sweet '
            'sauces.';
      case RestrictionKind.intolerance:
      case RestrictionKind.religiousComponent:
        return 'I avoid $name — please tell me which dishes contain it.';
    }
  }

  static String _lifestyleEn(RestrictionId id, String name) {
    if (id == RestrictionId.vegan) {
      return 'I eat a vegan diet — please tell me which dishes contain '
          'meat, fish, dairy, eggs or honey.';
    }
    if (id == RestrictionId.vegetarian) {
      return 'I eat a vegetarian diet — please tell me which dishes '
          'contain meat, poultry or fish.';
    }
    return 'I follow a $name diet — please tell me which dishes do not '
        'fit it.';
  }

  static String _baseHe(Restriction restriction) {
    final name = restriction.nameHe;
    final special = _extendedLineHe[restriction.id];
    if (special != null) return special.replaceAll('{name}', name);
    switch (restriction.kind) {
      case RestrictionKind.allergen:
        return 'יש לי אלרגיה ל$name — נא לבדוק כל מרכיב, '
            'כולל רטבים, שמנים וקישוטים.';
      case RestrictionKind.autoimmune:
        return 'יש לי צליאק ואני לא יכול/ה לאכול $name (חיטה, שעורה, שיפון '
            'ונגזרותיהם) — נא לבדוק כל מרכיב, כולל רטבים, מרקים ומרינדות, '
            'ולברר אם יש מגע צולב עם מטגנות, גרילים וכלים משותפים.';
      case RestrictionKind.lifestyle:
        return _lifestyleHe(restriction.id, name);
      case RestrictionKind.keto:
        return 'אני בתזונת קטו (דלת פחמימות) — נא לומר לי אילו מנות מכילות '
            'סוכר, קמח, אורז, תפוחי אדמה או רטבים מתוקים.';
      case RestrictionKind.intolerance:
      case RestrictionKind.religiousComponent:
        return 'אני נמנע/ת מ$name — נא לומר לי אילו מנות מכילות אותו.';
    }
  }

  static String _lifestyleHe(RestrictionId id, String name) {
    if (id == RestrictionId.vegan) {
      return 'אני טבעוני/ת — נא לומר לי אילו מנות מכילות בשר, דגים, '
          'מוצרי חלב, ביצים או דבש.';
    }
    if (id == RestrictionId.vegetarian) {
      return 'אני צמחוני/ת — נא לומר לי אילו מנות מכילות בשר, עוף או דגים.';
    }
    return 'אני בתזונה $name — נא לומר לי אילו מנות אינן מתאימות לה.';
  }
}
