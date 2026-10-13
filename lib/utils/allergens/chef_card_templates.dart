/// The chef card's sentences (Banto; the Allergens epic, ALG-08a, issue
/// #350): what a person with a dietary profile says to a kitchen, composed
/// from sentence templates per restriction kind and language.
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
import 'package:ketoclub/utils/allergens/taxonomy.dart';

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
    final base = hebrew ? _baseHe(restriction) : _baseEn(restriction);
    if (entry.exceptions.isEmpty) return base;
    final joined = entry.exceptions.join(', ');
    return hebrew
        ? '$base אני כן יכול/ה לאכול: $joined.'
        : '$base I can still have: $joined.';
  }

  static String _baseEn(Restriction restriction) {
    final name = restriction.nameEn.toLowerCase();
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
