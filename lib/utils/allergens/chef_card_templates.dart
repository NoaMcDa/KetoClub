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

import 'package:ketoclub/models/concern.dart';
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
      if (name.isNotEmpty) dishLine(name, hebrew: hebrew),
      if (modification != null)
        for (final line in modification.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      for (final question in questions)
        if (question.trim().isNotEmpty) question.trim(),
      closingLine(crossContact: crossContact, hebrew: hebrew),
    ]);
  }

  /// "The dish I would like: {dish}" in Hebrew when [hebrew], else
  /// English, with [dishName] as the menu printed it (a dish card's one
  /// naming line; also the group dish card's, ALG-12).
  static String dishLine(String dishName, {required bool hebrew}) =>
      (hebrew ? _dishLineHe : _dishLineEn).replaceAll('{dish}', dishName);

  /// A dish card's last line: the request to confirm how cross-contact is
  /// avoided when [crossContact], plain thanks otherwise.
  static String closingLine({
    required bool crossContact,
    required bool hebrew,
  }) => switch ((hebrew, crossContact)) {
    (false, true) => _closingStrictEn,
    (false, false) => _closingEn,
    (true, true) => _closingStrictHe,
    (true, false) => _closingHe,
  };

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
    final parts = _NoteParts.of(profile, hebrew: hebrew);
    if (parts == null) return null;
    final closing = parts.strict
        ? (hebrew ? _noteClosingStrictHe : _noteClosingStrictEn)
        : (hebrew ? _noteClosingHe : _noteClosingEn);

    String join({required bool withFlexible}) => <String>[
      ...parts.sentences(withFlexible: withFlexible),
      closing,
    ].join(' ');

    final full = join(withFlexible: true);
    if (full.length <= allergyNoteMaxLength || !parts.strict) return full;
    return join(withFlexible: false);
  }

  /// The allergy note for one dish (ALG-15, issue #357): [allergyNote]'s
  /// profile sentences, then what to do about this dish, composed from
  /// its [concerns] (an `EvaluatedDish`'s, already the profile's), in
  /// Hebrew when [hebrew], else English, for a delivery app's note box or
  /// a waiter. Null when [profile] holds nothing but keto.
  ///
  /// After the profile, "For {dish}:" and, for every concern that is
  /// stated or likely, "please make it without {items}" with the menu's
  /// own words in quotes (the restriction's name when there are none to
  /// quote); for every suspected one, "please check whether it contains
  /// {restrictions}". With no such concern it asks to check every
  /// ingredient. A profile with a strict entry closes with "make sure
  /// nothing touches {its strict restrictions} in preparation"; a
  /// flexible one with thanks. A kitchen concern (ALG-07) is the closing
  /// line's business, and a heads-up restriction (ALG-17) never asks for
  /// a dish "without" something, so neither adds an item.
  ///
  /// To stay within [allergyNoteMaxLength] it drops, in order, the
  /// flexible sentence, the list in the closing line (keeping "no
  /// cross-contact in preparation") and the dish's name; it never drops
  /// an allergen, an item or a question. No severity word, no promise and
  /// no "safe".
  static String? dishAllergyNote(
    DietaryProfile profile, {
    required String dishName,
    required List<Concern> concerns,
    required bool hebrew,
  }) {
    final parts = _NoteParts.of(profile, hebrew: hebrew);
    if (parts == null) return null;

    final without = <String>[];
    final check = <String>[];
    final seen = <String>{};
    void add(List<String> into, String value) {
      if (seen.add(value.toLowerCase())) into.add(value);
    }

    for (final concern in concerns) {
      final id = concern.restrictionId;
      if (concern.source == ConcernSource.kitchen) continue;
      if (headsUpRestrictions.contains(id)) continue;
      final subject = WaiterQuestions.subject(id, hebrew: hebrew);
      if (concern.certainty == Certainty.suspected) {
        add(check, subject);
        continue;
      }
      final quoted = concern.source == ConcernSource.matrix
          ? null
          : _quotable(concern.matchedText);
      add(
        without,
        quoted == null ||
                quoted.toLowerCase() == subject.toLowerCase() ||
                quoted.toLowerCase() ==
                    WaiterQuestions.subject(id, hebrew: !hebrew).toLowerCase()
            ? subject
            : "'$quoted'",
      );
    }
    // A restriction both asked about and to leave out is left out.
    check.removeWhere(
      (subject) => without.any((item) => item.toLowerCase() == subject),
    );

    final strictSubjects = <String>[
      for (final entry in profile.entries)
        if (restrictionFor(entry.restrictionId).isStrict)
          if (entry.restrictionId == RestrictionId.custom &&
              entry.terms.isNotEmpty)
            ...entry.terms
          else
            WaiterQuestions.subject(entry.restrictionId, hebrew: hebrew),
    ];

    String dishSentence({required bool named}) {
      final name = dishName.trim();
      final lead = !named || name.isEmpty
          ? ''
          : (hebrew ? 'לגבי {dish}: ' : 'For {dish}: ').replaceAll(
              '{dish}',
              name,
            );
      final asks = <String>[
        if (without.isNotEmpty)
          (hebrew ? 'בבקשה להכין בלי {list}' : 'please make it without {list}')
              .replaceAll('{list}', _joinList(without, hebrew: hebrew)),
        if (check.isNotEmpty)
          (hebrew
                  ? 'בבקשה לבדוק אם יש בה {list}'
                  : 'please check whether it contains {list}')
              .replaceAll('{list}', _joinList(check, hebrew: hebrew)),
        if (without.isEmpty && check.isEmpty && hebrew)
          'בבקשה לבדוק כל מרכיב, כולל רטבים',
        if (without.isEmpty && check.isEmpty && !hebrew)
          'please check every ingredient, including sauces',
      ];
      final body = asks.join(hebrew ? ', ו' : ', and ');
      final sentence = '$lead$body.';
      // Capitalise an English sentence that has no dish name to lead it.
      return lead.isEmpty && !hebrew
          ? '${sentence[0].toUpperCase()}${sentence.substring(1)}'
          : sentence;
    }

    String closing({required bool listed}) {
      if (!parts.strict) return hebrew ? _closingHe : _closingEn;
      if (!listed || strictSubjects.isEmpty) {
        return hebrew ? _dishNoteClosingHe : _dishNoteClosingEn;
      }
      return (hebrew ? _dishNoteClosingListHe : _dishNoteClosingListEn)
          .replaceAll('{list}', _joinList(strictSubjects, hebrew: hebrew));
    }

    String compose({
      required bool withFlexible,
      required bool listed,
      required bool named,
    }) => <String>[
      ...parts.sentences(withFlexible: withFlexible),
      dishSentence(named: named),
      closing(listed: listed),
    ].join(' ');

    // Each step drops one more thing; the last is returned whatever its
    // length, since what is left is never cut.
    final steps = <({bool withFlexible, bool listed, bool named})>[
      (withFlexible: true, listed: true, named: true),
      (withFlexible: false, listed: true, named: true),
      (withFlexible: false, listed: false, named: true),
      (withFlexible: false, listed: false, named: false),
    ];
    var note = '';
    for (final step in steps) {
      note = compose(
        withFlexible: step.withFlexible || !parts.strict,
        listed: step.listed,
        named: step.named,
      );
      if (note.length <= allergyNoteMaxLength) return note;
    }
    return note;
  }

  /// [matched] trimmed, when it is short enough to quote as the menu's
  /// own words (at most [_maxQuotedNoteLength] characters); null
  /// otherwise.
  static String? _quotable(String? matched) {
    final item = matched?.trim();
    if (item == null || item.isEmpty || item.length > _maxQuotedNoteLength) {
      return null;
    }
    return item;
  }

  /// The most characters of menu text a dish note quotes, as a waiter
  /// question does: a longer slice is a sentence, not an ingredient.
  static const int _maxQuotedNoteLength = 40;

  static const String _dishNoteClosingListEn =
      'Please make sure nothing touches {list} in preparation. Thank you.';
  static const String _dishNoteClosingListHe =
      'בבקשה לוודא ששום דבר לא בא במגע עם {list} בהכנה. תודה.';
  static const String _dishNoteClosingEn =
      'Please make sure there is no cross-contact in preparation. Thank you.';
  static const String _dishNoteClosingHe =
      'בבקשה לוודא שאין מגע צולב בהכנה. תודה.';

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
  ///
  /// Issue #342 adds fava (G6PD deficiency, strict: "check every
  /// ingredient", and falafel, which may be made of fava), the heads-up
  /// sensitivities (each names the foods that carry it) and the diets
  /// whose names are not ingredients (each names what it leaves out).
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
        RestrictionId.fava:
            'I have G6PD deficiency and cannot eat {name} — please check '
            'every ingredient, including falafel, ful, sauces and garnishes.',
        RestrictionId.nightshades:
            'I am sensitive to {name} — please tell me which dishes contain '
            'tomato, potato, aubergine, peppers, chilli or paprika.',
        RestrictionId.msg:
            'I am sensitive to MSG — please tell me which dishes have MSG, '
            'stock powder or a seasoning mix added.',
        RestrictionId.caffeine:
            'I go easy on {name} — please tell me which dishes and drinks '
            'contain coffee, tea, cola, chocolate or energy drinks.',
        RestrictionId.salicylates:
            'I am sensitive to {name} — please tell me which dishes are '
            'heavy in spices, herbs, tomato, berries or dried fruit.',
        RestrictionId.oralAllergy:
            'I have {name}: raw fruit and vegetables bother me — please tell '
            'me which dishes contain them raw, and whether they can be '
            'served cooked.',
        RestrictionId.pescatarian:
            'I eat a pescatarian diet — please tell me which dishes contain '
            'meat or poultry.',
        RestrictionId.paleo:
            'I follow a paleo diet — please tell me which dishes contain '
            'grains, legumes, dairy or refined sugar.',
        RestrictionId.whole30:
            'I follow the Whole30 programme — please tell me which dishes '
            'contain sugar, grains, legumes, dairy or alcohol.',
        RestrictionId.aip:
            'I follow the autoimmune protocol (AIP) — please tell me which '
            'dishes contain grains, legumes, dairy, eggs, nuts, seeds or '
            'nightshades.',
        RestrictionId.jain:
            'I follow a Jain diet — please tell me which dishes contain meat, '
            'fish, eggs, honey, onion, garlic or other root vegetables.',
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
        RestrictionId.fava:
            'יש לי חסר באנזים G6PD ואני לא יכול/ה לאכול {name} — נא לבדוק '
            'כל מרכיב, כולל פלאפל, רטבים וקישוטים.',
        RestrictionId.nightshades:
            'אני רגיש/ה ל{name} — נא לומר לי אילו מנות מכילות עגבנייה, תפוח '
            "אדמה, חציל, פלפל, צ'ילי או פפריקה.",
        RestrictionId.msg:
            'אני רגיש/ה ל{name} — נא לומר לי לאילו מנות מוסיפים MSG, אבקת '
            'מרק או תערובת תיבול.',
        RestrictionId.caffeine:
            'אני ממעיט/ה ב{name} — נא לומר לי אילו מנות ומשקאות מכילים קפה, '
            'תה, קולה, שוקולד או משקאות אנרגיה.',
        RestrictionId.salicylates:
            'אני רגיש/ה ל{name} — נא לומר לי אילו מנות מתובלות מאוד או '
            'עשירות בעשבי תיבול, עגבניות, פירות יער או פירות יבשים.',
        RestrictionId.oralAllergy:
            'יש לי {name}: פירות וירקות לא מבושלים מפריעים לי — נא לומר לי '
            'באילו מנות הם לא מבושלים, והאם אפשר להגיש אותם מבושלים.',
        RestrictionId.pescatarian:
            'אני פסקטריאני/ת — נא לומר לי אילו מנות מכילות בשר או עוף.',
        RestrictionId.paleo:
            'אני בתזונת פליאו — נא לומר לי אילו מנות מכילות דגנים, קטניות, '
            'מוצרי חלב או סוכר מעובד.',
        RestrictionId.whole30:
            'אני בתוכנית Whole30 — נא לומר לי אילו מנות מכילות סוכר, דגנים, '
            'קטניות, מוצרי חלב או אלכוהול.',
        RestrictionId.aip:
            'אני בפרוטוקול האוטואימוני (AIP) — נא לומר לי אילו מנות מכילות '
            'דגנים, קטניות, מוצרי חלב, ביצים, אגוזים, זרעים או סולניים.',
        RestrictionId.jain:
            "אני שומר/ת על תזונה ג'יינית — נא לומר לי אילו מנות מכילות בשר, "
            'דגים, ביצים, דבש, בצל, שום או ירקות שורש אחרים.',
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
      case RestrictionKind.medical:
        return 'Because of a health condition I cannot eat $name — please '
            'check every ingredient, including sauces, oils and garnishes.';
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
      case RestrictionKind.medical:
        return 'בגלל מצב בריאותי אני לא יכול/ה לאכול $name — נא לבדוק כל '
            'מרכיב, כולל רטבים, שמנים וקישוטים.';
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

/// The profile half of an allergy note (ALG-15), shared by
/// [ChefCardText.allergyNote] and [ChefCardText.dishAllergyNote]: one
/// sentence for the allergens, celiac disease, the user's own words and
/// the flexible entries, each in Hebrew or English.
final class _NoteParts {
  const new({
    required this.strict,
    required this.allergen,
    required this.celiac,
    required this.medical,
    required this.own,
    required this.flexible,
  });

  /// The parts for [profile], or null when it holds nothing but keto,
  /// which a kitchen note does not carry.
  static _NoteParts? of(DietaryProfile profile, {required bool hebrew}) {
    final allergens = <RestrictionId>[];
    var celiac = false;
    final medical = <RestrictionId>[];
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
        case RestrictionKind.medical:
          medical.add(restriction.id);
        case RestrictionKind.keto:
          break;
        case RestrictionKind.intolerance:
        case RestrictionKind.lifestyle:
        case RestrictionKind.religiousComponent:
          flexible.add(restriction.id);
      }
    }
    final strictBefore = allergens.isNotEmpty || celiac || medical.isNotEmpty;
    final strict = strictBefore || ownEntry;
    if (!strict && flexible.isEmpty) return null;

    String subjects(List<RestrictionId> ids, String prefix) =>
        ChefCardText._joinList(<String>[
          for (final id in ids)
            '$prefix${WaiterQuestions.subject(id, hebrew: hebrew)}',
        ], hebrew: hebrew);

    final ownList = ownTerms.isEmpty
        ? WaiterQuestions.subject(RestrictionId.custom, hebrew: hebrew)
        : ChefCardText._joinList(ownTerms, hebrew: hebrew);
    return _NoteParts(
      strict: strict,
      allergen: allergens.isEmpty
          ? null
          : (hebrew ? 'יש לי אלרגיה {list}.' : 'I have an allergy to {list}.')
                .replaceAll('{list}', subjects(allergens, hebrew ? 'ל' : '')),
      celiac: !celiac
          ? null
          : (hebrew
                ? 'יש לי צליאק ואני לא יכול/ה לאכול גלוטן.'
                : 'I have celiac disease and cannot eat gluten.'),
      medical: medical.isEmpty
          ? null
          : (hebrew
                    ? 'בגלל מצב בריאותי אני לא יכול/ה לאכול {list}.'
                    : 'Because of a health condition I cannot eat {list}.')
                .replaceAll('{list}', subjects(medical, '')),
      own: !ownEntry
          ? null
          : (hebrew
                    ? (strictBefore
                          ? 'אני גם לא יכול/ה לאכול {list}.'
                          : 'אני לא יכול/ה לאכול {list}.')
                    : (strictBefore
                          ? 'I also cannot eat {list}.'
                          : 'I cannot eat {list}.'))
                .replaceAll('{list}', ownList),
      flexible: flexible.isEmpty
          ? null
          : (hebrew
                    ? (strict ? 'אני גם נמנע/ת {list}.' : 'אני נמנע/ת {list}.')
                    : (strict ? 'I also avoid {list}.' : 'I avoid {list}.'))
                .replaceAll('{list}', subjects(flexible, hebrew ? 'מ' : '')),
    );
  }

  /// Whether the profile holds a strict entry: an allergen, celiac
  /// disease, a medical condition or the user's own words.
  final bool strict;

  /// "I have an allergy to …", or null without an allergen.
  final String? allergen;

  /// The celiac sentence, or null without celiac disease.
  final String? celiac;

  /// "Because of a health condition I cannot eat …" (issue #342: fava for
  /// G6PD deficiency), or null without a medical entry.
  final String? medical;

  /// "I (also) cannot eat …", or null without the user's own words.
  final String? own;

  /// "I (also) avoid …", or null without a flexible entry.
  final String? flexible;

  /// The sentences in order, the flexible one only when [withFlexible].
  List<String> sentences({required bool withFlexible}) => <String>[
    ?allergen,
    ?celiac,
    ?medical,
    ?own,
    if (withFlexible) ?flexible,
  ];
}
