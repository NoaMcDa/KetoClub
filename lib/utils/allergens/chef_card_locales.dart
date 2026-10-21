/// The chef card in a trip destination's language (Banto; the Allergens
/// epic, ALG-13's local-language card, issue #419): French, Italian,
/// Spanish, German and Japanese, beside the Hebrew and English of
/// `chef_card_templates.dart`.
///
/// Like the Hebrew and English sentences, this text is shown and read to
/// restaurant staff, so it follows the language picked for the card, never
/// the UI's, and lives in Dart rather than in ARB (architecture.md §6.3 and
/// §12, the documented exception).
///
/// **Every block below is UNREVIEWED BY A NATIVE SPEAKER.** The sentences
/// are the app's own translation of the English card. The restriction names
/// listed in a block's [ChefCardLocale.officialNames] are copied from the
/// law: for French, Italian, Spanish and German, the wording of Annex II of
/// Regulation (EU) No 1169/2011 in that language (the 14 allergens, and
/// wheat from point 1); for Japanese, the Consumer Affairs Agency's
/// allergen list (特定原材料 and 特定原材料に準ずるもの). Every other name
/// is a translation too. The sources are file 12 §15. The card says so
/// under itself in the UI's language, and the screen never hides it.
///
/// The wording obeys the epic's floor in every language: a strict entry is
/// only stated and asked about, nothing promises anything, and no sentence
/// holds a word meaning "safe" (`test/l10n/banned_words_test.dart` checks
/// every line in every language). Names sit after a colon wherever a
/// language would otherwise need an article or a case for them, so a
/// sentence never has to agree with the name it carries. Pure: no widget,
/// no clock, no I/O.
library;

import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';

/// A language the chef card can be shown in.
enum ChefCardLanguage {
  /// Hebrew.
  he,

  /// English.
  en,

  /// French (France).
  fr,

  /// Italian (Italy).
  it,

  /// Spanish (Spain).
  es,

  /// German (Germany).
  de,

  /// Japanese (Japan).
  ja;

  /// The language for the Hebrew/English flag the older call sites pass.
  static ChefCardLanguage of({required bool hebrew}) => hebrew ? he : en;

  /// The local language of [trip]'s destination when the card has a
  /// translation for it; null for no trip, and for Israel, the United
  /// States and the United Kingdom, whose cards stay Hebrew or English.
  static ChefCardLanguage? forTrip(TripDestination? trip) => switch (trip) {
    TripDestination.france => fr,
    TripDestination.italy => it,
    TripDestination.spain => es,
    TripDestination.germany => de,
    TripDestination.japan => ja,
    TripDestination.israel ||
    TripDestination.unitedStates ||
    TripDestination.unitedKingdom ||
    null => null,
  };

  /// Whether the card's text runs right to left.
  bool get isRtl => this == he;

  /// The translated sentences and names, or null for Hebrew and English,
  /// whose sentences are `ChefCardText`'s own.
  ChefCardLocale? get locale => switch (this) {
    he || en => null,
    fr => frenchChefCard,
    it => italianChefCard,
    es => spanishChefCard,
    de => germanChefCard,
    ja => japaneseChefCard,
  };

  /// Whether the card in this language is the app's own translation,
  /// which the screen marks as not checked by a native speaker.
  bool get isTranslated => locale != null;
}

/// One language's chef card: the sentences, each with `{name}`, `{list}`
/// or `{dish}` where the restriction's name, a list or the dish goes, and
/// the restriction names.
final class ChefCardLocale {
  /// Creates a language block.
  const new({
    required this.intro,
    required this.groupIntro,
    required this.me,
    required this.allergenLine,
    required this.celiacLine,
    required this.medicalLine,
    required this.avoidLine,
    required this.dietLine,
    required this.ketoLine,
    required this.veganLine,
    required this.vegetarianLine,
    required this.kosherLine,
    required this.halalLine,
    required this.glp1Line,
    required this.kosherQuestion,
    required this.halalQuestion,
    required this.ownLine,
    required this.exceptionsLine,
    required this.dishLine,
    required this.groupDishLine,
    required this.closingStrict,
    required this.closing,
    required this.footer,
    required this.names,
    required this.officialNames,
    this.listSeparator = ', ',
    this.sentenceJoiner = ' ',
    this.nativeSpeakerReviewed = false,
  });

  /// The greeting of a card for one person.
  final String intro;

  /// The greeting of a card for several people (ALG-12).
  final String groupIntro;

  /// The primary profile's default name, heading its section.
  final String me;

  /// An allergen's line: stated, and every ingredient to be checked.
  final String allergenLine;

  /// Celiac disease's line, with gluten's cereals and cross-contact.
  final String celiacLine;

  /// A medical condition's line (fava for G6PD deficiency).
  final String medicalLine;

  /// An intolerance's line: "tell me which dishes contain it".
  final String avoidLine;

  /// A diet's line (lifestyle, Jain): "tell me which dishes do not fit".
  final String dietLine;

  /// Keto's line.
  final String ketoLine;

  /// The vegan line, naming what it leaves out.
  final String veganLine;

  /// The vegetarian line, naming what it leaves out.
  final String vegetarianLine;

  /// Kosher's line, naming its components (never a certification).
  final String kosherLine;

  /// Halal's line, naming its components (never a certification).
  final String halalLine;

  /// The small-portions line (no medicine named).
  final String glp1Line;

  /// The question after the kosher line: is the meat certified?
  final String kosherQuestion;

  /// The question after the halal line: is the meat certified?
  final String halalQuestion;

  /// The user's own words' line (ALG-17), with `{list}`.
  final String ownLine;

  /// An entry's exceptions, appended to its line, with `{list}`.
  final String exceptionsLine;

  /// A dish card's naming line, with `{dish}`.
  final String dishLine;

  /// A group dish card's naming line, with `{dish}`.
  final String groupDishLine;

  /// The closing that asks how cross-contact is avoided.
  final String closingStrict;

  /// The closing of a card with no strict entry: thanks.
  final String closing;

  /// The shared image's footer: a helper, not a guarantee; ask.
  final String footer;

  /// Each restriction's name in this language. A restriction missing here
  /// is named in English on the card, never dropped.
  final Map<RestrictionId, String> names;

  /// The restrictions whose [names] are the law's own wording (Annex II,
  /// or Japan's Consumer Affairs Agency list). Every other name is the
  /// app's translation, unreviewed.
  final Set<RestrictionId> officialNames;

  /// What joins the items of a list: a comma, or Japanese's 、.
  final String listSeparator;

  /// What joins an entry's line and its exceptions: a space, or nothing
  /// after Japanese's 。.
  final String sentenceJoiner;

  /// Whether a native speaker has checked this block. False for all five;
  /// the screen shows its "translated by the app" line while it is.
  final bool nativeSpeakerReviewed;
}

/// Composes the lines of a translated chef card.
abstract final class ChefCardLocales {
  /// [id]'s name in [locale], or its English name when [locale] has none:
  /// a restriction is never dropped from a card for want of a word.
  static String nameOf(RestrictionId id, ChefCardLocale locale) =>
      locale.names[id] ?? restrictionFor(id).nameEn;

  /// Whether [locale] has its own name for [id] (otherwise [nameOf] gives
  /// the English one).
  static bool hasLocalName(RestrictionId id, ChefCardLocale locale) =>
      locale.names.containsKey(id);

  /// [entry]'s line in [locale]: its kind's sentence (or its own, for
  /// keto, vegan, vegetarian, kosher, halal and small portions) with the
  /// restriction's name, then its exceptions; for the user's own
  /// restriction, their words as they wrote them.
  static String entryLine(ProfileEntry entry, ChefCardLocale locale) {
    final restriction = restrictionFor(entry.restrictionId);
    final base = restriction.id == RestrictionId.custom
        ? locale.ownLine.replaceAll(
            '{list}',
            entry.terms.isEmpty
                ? nameOf(RestrictionId.custom, locale)
                : entry.terms.join(locale.listSeparator),
          )
        : _base(restriction, locale);
    if (entry.exceptions.isEmpty) return base;
    final exceptions = locale.exceptionsLine.replaceAll(
      '{list}',
      entry.exceptions.join(locale.listSeparator),
    );
    return '$base${locale.sentenceJoiner}$exceptions';
  }

  /// The certification question a kosher or halal entry adds under its
  /// line, in [locale]; null for every other restriction.
  static String? certificationQuestion(
    RestrictionId id,
    ChefCardLocale locale,
  ) => switch (id) {
    RestrictionId.kosher => locale.kosherQuestion,
    RestrictionId.halal => locale.halalQuestion,
    _ => null,
  };

  static String _base(Restriction restriction, ChefCardLocale locale) {
    final template = switch (restriction.id) {
      RestrictionId.keto => locale.ketoLine,
      RestrictionId.vegan => locale.veganLine,
      RestrictionId.vegetarian => locale.vegetarianLine,
      RestrictionId.kosher => locale.kosherLine,
      RestrictionId.halal => locale.halalLine,
      RestrictionId.glp1 => locale.glp1Line,
      _ => switch (restriction.kind) {
        RestrictionKind.allergen => locale.allergenLine,
        RestrictionKind.autoimmune => locale.celiacLine,
        RestrictionKind.medical => locale.medicalLine,
        RestrictionKind.intolerance => locale.avoidLine,
        RestrictionKind.lifestyle ||
        RestrictionKind.religiousComponent => locale.dietLine,
        RestrictionKind.keto => locale.ketoLine,
      },
    };
    return template.replaceAll('{name}', nameOf(restriction.id, locale));
  }
}

/// The EU 14 and wheat (Annex II point 1 names it): the names the four EU
/// blocks copy from Annex II of Regulation (EU) No 1169/2011.
const Set<RestrictionId> _annexII = <RestrictionId>{
  RestrictionId.gluten,
  RestrictionId.wheat,
  RestrictionId.crustaceans,
  RestrictionId.eggs,
  RestrictionId.fish,
  RestrictionId.peanuts,
  RestrictionId.soy,
  RestrictionId.milk,
  RestrictionId.treeNuts,
  RestrictionId.celery,
  RestrictionId.mustard,
  RestrictionId.sesame,
  RestrictionId.sulphites,
  RestrictionId.lupin,
  RestrictionId.molluscs,
};

// ---------------------------------------------------------------------
// French. UNREVIEWED BY A NATIVE SPEAKER (file 12 §15). Annex II names
// from the French text of Regulation (EU) No 1169/2011, lower-cased after
// the colon; everything else is the app's translation.
// ---------------------------------------------------------------------

/// The French card. Unreviewed by a native speaker.
const ChefCardLocale frenchChefCard = ChefCardLocale(
  intro:
      "Bonjour, j'ai des restrictions alimentaires et j'aimerais votre aide "
      'pour ma commande.',
  groupIntro:
      "Bonjour, certains d'entre nous ont des restrictions alimentaires et "
      'nous aimerions votre aide pour notre commande.',
  me: 'Moi',
  allergenLine:
      'Allergie alimentaire : {name} — merci de vérifier chaque ingrédient, '
      'y compris les sauces, les huiles et les garnitures.',
  celiacLine:
      "J'ai la maladie cœliaque. À éviter : {name} (blé, seigle, orge et "
      'leurs dérivés) — merci de vérifier chaque ingrédient, y compris les '
      'sauces, les soupes et les marinades, et de me dire si les friteuses, '
      'les grills ou les ustensiles sont partagés.',
  medicalLine:
      'Pour raison de santé, je ne peux pas manger : {name} — merci de '
      'vérifier chaque ingrédient, y compris les sauces, les huiles et les '
      'garnitures.',
  avoidLine: "J'évite : {name} — merci de me dire quels plats en contiennent.",
  dietLine:
      'Je suis un régime particulier : {name} — merci de me dire quels '
      "plats n'y conviennent pas.",
  ketoLine:
      'Je suis un régime cétogène (très pauvre en glucides) — merci de me '
      'dire quels plats contiennent du sucre, de la farine, du riz, des '
      'pommes de terre ou des sauces sucrées.',
  veganLine:
      'Je suis végane — merci de me dire quels plats contiennent de la '
      'viande, du poisson, des produits laitiers, des œufs ou du miel.',
  vegetarianLine:
      'Je suis végétarien(ne) — merci de me dire quels plats contiennent de '
      'la viande, de la volaille ou du poisson.',
  kosherLine:
      'Je mange casher — merci de me dire si un plat contient du porc, des '
      'fruits de mer, du poisson sans nageoires ni écailles, ou mélange '
      'viande et produits laitiers.',
  halalLine:
      'Je mange halal — merci de me dire si un plat contient du porc, de '
      "l'alcool (même cuit dans une sauce), de la gélatine ou du sang.",
  glp1Line:
      'Je mange de petites portions — merci de me dire quels plats existent '
      'en plus petite taille, et lesquels sont frits, crémeux ou très '
      'sucrés.',
  kosherQuestion: 'Votre viande est-elle certifiée casher ?',
  halalQuestion: 'Votre viande est-elle certifiée halal ?',
  ownLine:
      'Je ne peux pas manger : {list} — merci de vérifier chaque ingrédient, '
      'y compris les sauces, les huiles et les garnitures.',
  exceptionsLine: 'Je peux quand même manger : {list}.',
  dishLine: 'Le plat que je souhaite : {dish}',
  groupDishLine: 'Le plat que nous souhaitons : {dish}',
  closingStrict:
      'Pourriez-vous demander à la cuisine comment elle évite la '
      'contamination croisée (surfaces, huile et ustensiles partagés) ? '
      'Merci.',
  closing: 'Merci.',
  footer:
      'Banto · une aide, pas une garantie — demandez toujours au restaurant',
  officialNames: _annexII,
  names: <RestrictionId, String>{
    // Annex II (FR).
    RestrictionId.gluten: 'céréales contenant du gluten',
    RestrictionId.wheat: 'blé',
    RestrictionId.crustaceans: 'crustacés',
    RestrictionId.eggs: 'œufs',
    RestrictionId.fish: 'poissons',
    RestrictionId.peanuts: 'arachides',
    RestrictionId.soy: 'soja',
    RestrictionId.milk: 'lait',
    RestrictionId.treeNuts: 'fruits à coque',
    RestrictionId.celery: 'céleri',
    RestrictionId.mustard: 'moutarde',
    RestrictionId.sesame: 'graines de sésame',
    RestrictionId.sulphites: 'anhydride sulfureux et sulfites',
    RestrictionId.lupin: 'lupin',
    RestrictionId.molluscs: 'mollusques',
    // The app's translation, unreviewed.
    RestrictionId.lactose: 'lactose',
    RestrictionId.legumes:
        'légumineuses (pois chiches, lentilles, pois, fèves)',
    RestrictionId.alphaGal:
        'viande de mammifères (alpha-gal : bœuf, agneau, porc, gélatine, '
        'saindoux, bouillon de viande)',
    RestrictionId.fodmap:
        'FODMAP (oignon, ail, blé, haricots, lentilles, miel, pomme)',
    RestrictionId.histamine:
        'aliments riches en histamine (fromages affinés, charcuterie, '
        'aliments fermentés, vinaigre, vin, thon)',
    RestrictionId.vegan: 'végane',
    RestrictionId.vegetarian: 'végétarien',
    RestrictionId.glp1: 'petites portions',
    RestrictionId.kosher: 'casher',
    RestrictionId.halal: 'halal',
    RestrictionId.buckwheat: 'sarrasin',
    RestrictionId.kiwi: 'kiwi',
    RestrictionId.peach: 'pêche',
    RestrictionId.apple: 'pomme',
    RestrictionId.banana: 'banane',
    RestrictionId.orange: 'orange',
    RestrictionId.beef: 'bœuf',
    RestrictionId.pork: 'porc',
    RestrictionId.chicken: 'poulet',
    RestrictionId.gelatin: 'gélatine',
    RestrictionId.yam: 'igname japonaise (yamaimo)',
    RestrictionId.corn: 'maïs',
    RestrictionId.sunflower: 'graines de tournesol',
    RestrictionId.flax: 'graines de lin',
    RestrictionId.chickpea: 'pois chiches',
    RestrictionId.lentil: 'lentilles',
    RestrictionId.pea: 'pois',
    RestrictionId.fenugreek: 'fenugrec',
    RestrictionId.fava: 'fèves (favisme, déficit en G6PD)',
    RestrictionId.nightshades:
        'solanacées (tomate, pomme de terre, aubergine, poivron, piment, '
        'paprika)',
    RestrictionId.msg:
        'glutamate monosodique (MSG, bouillon en poudre, mélanges '
        "d'assaisonnement)",
    RestrictionId.caffeine:
        'caféine (café, thé, cola, chocolat, boissons énergisantes)',
    RestrictionId.salicylates:
        'salicylates (épices, herbes, tomate, baies, fruits secs)',
    RestrictionId.oralAllergy:
        "fruits et légumes crus (syndrome d'allergie orale)",
    RestrictionId.pescatarian:
        'pescétarien (du poisson, mais ni viande ni volaille)',
    RestrictionId.paleo:
        'paléo (sans céréales, légumineuses, produits laitiers ni sucre '
        'raffiné)',
    RestrictionId.whole30:
        'Whole30 (sans sucre, céréales, légumineuses, produits laitiers ni '
        'alcool)',
    RestrictionId.aip:
        'protocole auto-immun (AIP : sans céréales, légumineuses, produits '
        'laitiers, œufs, fruits à coque, graines ni solanacées)',
    RestrictionId.jain:
        'jaïn (sans viande, poisson, œufs, miel, oignon, ail ni '
        'légumes-racines)',
    RestrictionId.keto: 'cétogène',
    RestrictionId.custom: 'certains aliments',
  },
);

// ---------------------------------------------------------------------
// Italian. UNREVIEWED BY A NATIVE SPEAKER (file 12 §15). Annex II names
// from the Italian text of Regulation (EU) No 1169/2011, lower-cased after
// the colon; everything else is the app's translation.
// ---------------------------------------------------------------------

/// The Italian card. Unreviewed by a native speaker.
const ChefCardLocale italianChefCard = ChefCardLocale(
  intro:
      'Buongiorno, ho delle restrizioni alimentari e vorrei il vostro aiuto '
      'per la mia ordinazione.',
  groupIntro:
      'Buongiorno, alcuni di noi hanno delle restrizioni alimentari e '
      'vorremmo il vostro aiuto per la nostra ordinazione.',
  me: 'Io',
  allergenLine:
      'Allergia alimentare: {name} — per favore controllate ogni '
      'ingrediente, compresi salse, oli e guarnizioni.',
  celiacLine:
      'Sono celiaco/a. Da evitare: {name} (frumento, segale, orzo e '
      'derivati) — per favore controllate ogni ingrediente, compresi salse, '
      'zuppe e marinate, e ditemi se friggitrici, griglie o utensili sono '
      'condivisi.',
  medicalLine:
      'Per motivi di salute non posso mangiare: {name} — per favore '
      'controllate ogni ingrediente, compresi salse, oli e guarnizioni.',
  avoidLine: 'Evito: {name} — per favore ditemi quali piatti ne contengono.',
  dietLine:
      'Seguo una dieta particolare: {name} — per favore ditemi quali piatti '
      'non sono adatti.',
  ketoLine:
      'Seguo una dieta chetogenica (pochissimi carboidrati) — per favore '
      'ditemi quali piatti contengono zucchero, farina, riso, patate o salse '
      'dolci.',
  veganLine:
      'Sono vegano/a — per favore ditemi quali piatti contengono carne, '
      'pesce, latticini, uova o miele.',
  vegetarianLine:
      'Sono vegetariano/a — per favore ditemi quali piatti contengono carne, '
      'pollame o pesce.',
  kosherLine:
      'Mangio kosher — per favore ditemi se un piatto contiene maiale, '
      'frutti di mare, pesce senza pinne e squame, oppure unisce carne e '
      'latticini.',
  halalLine:
      'Mangio halal — per favore ditemi se un piatto contiene maiale, alcol '
      '(anche cotto in una salsa), gelatina o sangue.',
  glp1Line:
      'Mangio porzioni piccole — per favore ditemi quali piatti si possono '
      'avere in porzione ridotta, e quali sono fritti, cremosi o molto '
      'dolci.',
  kosherQuestion: 'La vostra carne ha la certificazione kosher?',
  halalQuestion: 'La vostra carne ha la certificazione halal?',
  ownLine:
      'Non posso mangiare: {list} — per favore controllate ogni ingrediente, '
      'compresi salse, oli e guarnizioni.',
  exceptionsLine: 'Posso comunque mangiare: {list}.',
  dishLine: 'Il piatto che vorrei: {dish}',
  groupDishLine: 'Il piatto che vorremmo: {dish}',
  closingStrict:
      'Potreste chiedere in cucina come evitano la contaminazione crociata '
      '(superfici, olio e utensili condivisi)? Grazie.',
  closing: 'Grazie.',
  footer: 'Banto · un aiuto, non una garanzia — chiedete sempre al ristorante',
  officialNames: _annexII,
  names: <RestrictionId, String>{
    // Annex II (IT).
    RestrictionId.gluten: 'cereali contenenti glutine',
    RestrictionId.wheat: 'grano',
    RestrictionId.crustaceans: 'crostacei',
    RestrictionId.eggs: 'uova',
    RestrictionId.fish: 'pesce',
    RestrictionId.peanuts: 'arachidi',
    RestrictionId.soy: 'soia',
    RestrictionId.milk: 'latte',
    RestrictionId.treeNuts: 'frutta a guscio',
    RestrictionId.celery: 'sedano',
    RestrictionId.mustard: 'senape',
    RestrictionId.sesame: 'semi di sesamo',
    RestrictionId.sulphites: 'anidride solforosa e solfiti',
    RestrictionId.lupin: 'lupini',
    RestrictionId.molluscs: 'molluschi',
    // The app's translation, unreviewed.
    RestrictionId.lactose: 'lattosio',
    RestrictionId.legumes: 'legumi (ceci, lenticchie, piselli, fave)',
    RestrictionId.alphaGal:
        'carne di mammiferi (alfa-gal: manzo, agnello, maiale, gelatina, '
        'strutto, brodo di carne)',
    RestrictionId.fodmap:
        'FODMAP (cipolla, aglio, frumento, fagioli, lenticchie, miele, mela)',
    RestrictionId.histamine:
        'cibi ricchi di istamina (formaggi stagionati, salumi, cibi '
        'fermentati, aceto, vino, tonno)',
    RestrictionId.vegan: 'vegana',
    RestrictionId.vegetarian: 'vegetariana',
    RestrictionId.glp1: 'porzioni piccole',
    RestrictionId.kosher: 'kosher',
    RestrictionId.halal: 'halal',
    RestrictionId.buckwheat: 'grano saraceno',
    RestrictionId.kiwi: 'kiwi',
    RestrictionId.peach: 'pesca',
    RestrictionId.apple: 'mela',
    RestrictionId.banana: 'banana',
    RestrictionId.orange: 'arancia',
    RestrictionId.beef: 'manzo',
    RestrictionId.pork: 'maiale',
    RestrictionId.chicken: 'pollo',
    RestrictionId.gelatin: 'gelatina',
    RestrictionId.yam: 'igname giapponese (yamaimo)',
    RestrictionId.corn: 'mais',
    RestrictionId.sunflower: 'semi di girasole',
    RestrictionId.flax: 'semi di lino',
    RestrictionId.chickpea: 'ceci',
    RestrictionId.lentil: 'lenticchie',
    RestrictionId.pea: 'piselli',
    RestrictionId.fenugreek: 'fieno greco',
    RestrictionId.fava: 'fave (favismo, carenza di G6PD)',
    RestrictionId.nightshades:
        'solanacee (pomodoro, patata, melanzana, peperone, peperoncino, '
        'paprica)',
    RestrictionId.msg:
        'glutammato monosodico (MSG, dado da brodo, miscele di spezie)',
    RestrictionId.caffeine:
        'caffeina (caffè, tè, cola, cioccolato, bevande energetiche)',
    RestrictionId.salicylates:
        'salicilati (spezie, erbe, pomodoro, frutti di bosco, frutta '
        'essiccata)',
    RestrictionId.oralAllergy:
        'frutta e verdura crude (sindrome orale allergica)',
    RestrictionId.pescatarian:
        'pescetariana (pesce, ma niente carne né pollame)',
    RestrictionId.paleo:
        'paleo (senza cereali, legumi, latticini né zucchero raffinato)',
    RestrictionId.whole30:
        'Whole30 (senza zucchero, cereali, legumi, latticini né alcol)',
    RestrictionId.aip:
        'protocollo autoimmune (AIP: senza cereali, legumi, latticini, uova, '
        'frutta a guscio, semi né solanacee)',
    RestrictionId.jain:
        'giainista (senza carne, pesce, uova, miele, cipolla, aglio né '
        'ortaggi a radice)',
    RestrictionId.keto: 'chetogenica',
    RestrictionId.custom: 'alcuni alimenti',
  },
);

// ---------------------------------------------------------------------
// Spanish. UNREVIEWED BY A NATIVE SPEAKER (file 12 §15). Annex II names
// from the Spanish text of Regulation (EU) No 1169/2011, lower-cased after
// the colon; everything else is the app's translation.
// ---------------------------------------------------------------------

/// The Spanish card. Unreviewed by a native speaker.
const ChefCardLocale spanishChefCard = ChefCardLocale(
  intro:
      'Hola, tengo restricciones alimentarias y me gustaría que me ayudaran '
      'con mi pedido.',
  groupIntro:
      'Hola, algunos de nosotros tenemos restricciones alimentarias y nos '
      'gustaría que nos ayudaran con nuestro pedido.',
  me: 'Yo',
  allergenLine:
      'Alergia alimentaria: {name} — por favor, revisen cada ingrediente, '
      'incluidas salsas, aceites y guarniciones.',
  celiacLine:
      'Soy celíaco/a. Debo evitar: {name} (trigo, centeno, cebada y sus '
      'derivados) — por favor, revisen cada ingrediente, incluidas salsas, '
      'sopas y adobos, y díganme si comparten freidoras, planchas o '
      'utensilios.',
  medicalLine:
      'Por un problema de salud no puedo comer: {name} — por favor, revisen '
      'cada ingrediente, incluidas salsas, aceites y guarniciones.',
  avoidLine: 'Evito: {name} — por favor, díganme qué platos lo contienen.',
  dietLine:
      'Sigo una dieta especial: {name} — por favor, díganme qué platos no '
      'son adecuados.',
  ketoLine:
      'Sigo una dieta cetogénica (muy baja en carbohidratos) — por favor, '
      'díganme qué platos contienen azúcar, harina, arroz, patata o salsas '
      'dulces.',
  veganLine:
      'Soy vegano/a — por favor, díganme qué platos contienen carne, '
      'pescado, lácteos, huevo o miel.',
  vegetarianLine:
      'Soy vegetariano/a — por favor, díganme qué platos contienen carne, '
      'aves o pescado.',
  kosherLine:
      'Como kosher — por favor, díganme si un plato tiene cerdo, marisco, '
      'pescado sin aletas ni escamas, o mezcla carne y lácteos.',
  halalLine:
      'Como halal — por favor, díganme si un plato tiene cerdo, alcohol '
      '(aunque esté cocinado en una salsa), gelatina o sangre.',
  glp1Line:
      'Como raciones pequeñas — por favor, díganme qué platos hay en tamaño '
      'más pequeño, y cuáles son fritos, cremosos o muy dulces.',
  kosherQuestion: '¿Su carne tiene certificación kosher?',
  halalQuestion: '¿Su carne tiene certificación halal?',
  ownLine:
      'No puedo comer: {list} — por favor, revisen cada ingrediente, '
      'incluidas salsas, aceites y guarniciones.',
  exceptionsLine: 'Sí puedo comer: {list}.',
  dishLine: 'El plato que quiero: {dish}',
  groupDishLine: 'El plato que queremos: {dish}',
  closingStrict:
      '¿Podrían preguntar en cocina cómo evitan la contaminación cruzada '
      '(superficies, aceite y utensilios compartidos)? Gracias.',
  closing: 'Gracias.',
  footer:
      'Banto · una ayuda, no una garantía — pregunte siempre al restaurante',
  officialNames: _annexII,
  names: <RestrictionId, String>{
    // Annex II (ES).
    RestrictionId.gluten: 'cereales que contengan gluten',
    RestrictionId.wheat: 'trigo',
    RestrictionId.crustaceans: 'crustáceos',
    RestrictionId.eggs: 'huevos',
    RestrictionId.fish: 'pescado',
    RestrictionId.peanuts: 'cacahuetes',
    RestrictionId.soy: 'soja',
    RestrictionId.milk: 'leche',
    RestrictionId.treeNuts: 'frutos de cáscara',
    RestrictionId.celery: 'apio',
    RestrictionId.mustard: 'mostaza',
    RestrictionId.sesame: 'granos de sésamo',
    RestrictionId.sulphites: 'dióxido de azufre y sulfitos',
    RestrictionId.lupin: 'altramuces',
    RestrictionId.molluscs: 'moluscos',
    // The app's translation, unreviewed.
    RestrictionId.lactose: 'lactosa',
    RestrictionId.legumes: 'legumbres (garbanzos, lentejas, guisantes, habas)',
    RestrictionId.alphaGal:
        'carne de mamíferos (alfa-gal: vacuno, cordero, cerdo, gelatina, '
        'manteca, caldo de carne)',
    RestrictionId.fodmap:
        'FODMAP (cebolla, ajo, trigo, alubias, lentejas, miel, manzana)',
    RestrictionId.histamine:
        'alimentos ricos en histamina (quesos curados, embutidos, '
        'fermentados, vinagre, vino, atún)',
    RestrictionId.vegan: 'vegana',
    RestrictionId.vegetarian: 'vegetariana',
    RestrictionId.glp1: 'raciones pequeñas',
    RestrictionId.kosher: 'kosher',
    RestrictionId.halal: 'halal',
    RestrictionId.buckwheat: 'trigo sarraceno',
    RestrictionId.kiwi: 'kiwi',
    RestrictionId.peach: 'melocotón',
    RestrictionId.apple: 'manzana',
    RestrictionId.banana: 'plátano',
    RestrictionId.orange: 'naranja',
    RestrictionId.beef: 'carne de vacuno',
    RestrictionId.pork: 'cerdo',
    RestrictionId.chicken: 'pollo',
    RestrictionId.gelatin: 'gelatina',
    RestrictionId.yam: 'ñame japonés (yamaimo)',
    RestrictionId.corn: 'maíz',
    RestrictionId.sunflower: 'pipas de girasol',
    RestrictionId.flax: 'semillas de lino',
    RestrictionId.chickpea: 'garbanzos',
    RestrictionId.lentil: 'lentejas',
    RestrictionId.pea: 'guisantes',
    RestrictionId.fenugreek: 'fenogreco',
    RestrictionId.fava: 'habas (favismo, déficit de G6PD)',
    RestrictionId.nightshades:
        'solanáceas (tomate, patata, berenjena, pimiento, guindilla, '
        'pimentón)',
    RestrictionId.msg:
        'glutamato monosódico (MSG, caldo en polvo, mezclas de condimentos)',
    RestrictionId.caffeine:
        'cafeína (café, té, cola, chocolate, bebidas energéticas)',
    RestrictionId.salicylates:
        'salicilatos (especias, hierbas, tomate, frutos rojos, fruta '
        'deshidratada)',
    RestrictionId.oralAllergy:
        'frutas y verduras crudas (síndrome de alergia oral)',
    RestrictionId.pescatarian: 'pescetariana (pescado, pero sin carne ni aves)',
    RestrictionId.paleo:
        'paleo (sin cereales, legumbres, lácteos ni azúcar refinado)',
    RestrictionId.whole30:
        'Whole30 (sin azúcar, cereales, legumbres, lácteos ni alcohol)',
    RestrictionId.aip:
        'protocolo autoinmune (AIP: sin cereales, legumbres, lácteos, '
        'huevos, frutos de cáscara, semillas ni solanáceas)',
    RestrictionId.jain:
        'jainista (sin carne, pescado, huevos, miel, cebolla, ajo ni '
        'tubérculos)',
    RestrictionId.keto: 'cetogénica',
    RestrictionId.custom: 'algunos alimentos',
  },
);

// ---------------------------------------------------------------------
// German. UNREVIEWED BY A NATIVE SPEAKER (file 12 §15). Annex II names
// from the German text of Regulation (EU) No 1169/2011; everything else
// is the app's translation.
// ---------------------------------------------------------------------

/// The German card. Unreviewed by a native speaker.
const ChefCardLocale germanChefCard = ChefCardLocale(
  intro:
      'Guten Tag, ich habe Ernährungseinschränkungen und würde mich über '
      'Ihre Hilfe bei meiner Bestellung freuen.',
  groupIntro:
      'Guten Tag, einige von uns haben Ernährungseinschränkungen und wir '
      'würden uns über Ihre Hilfe bei unserer Bestellung freuen.',
  me: 'Ich',
  allergenLine:
      'Lebensmittelallergie: {name} — bitte prüfen Sie jede Zutat, auch '
      'Saucen, Öle und Garnituren.',
  celiacLine:
      'Ich habe Zöliakie. Ich muss meiden: {name} (Weizen, Roggen, Gerste '
      'und daraus gewonnene Erzeugnisse) — bitte prüfen Sie jede Zutat, auch '
      'Saucen, Suppen und Marinaden, und sagen Sie mir, ob Fritteusen, '
      'Grills oder Utensilien gemeinsam genutzt werden.',
  medicalLine:
      'Aus gesundheitlichen Gründen kann ich nicht essen: {name} — bitte '
      'prüfen Sie jede Zutat, auch Saucen, Öle und Garnituren.',
  avoidLine:
      'Ich meide: {name} — bitte sagen Sie mir, welche Gerichte das '
      'enthalten.',
  dietLine:
      'Ich ernähre mich nach einer besonderen Diät: {name} — bitte sagen Sie '
      'mir, welche Gerichte nicht passen.',
  ketoLine:
      'Ich ernähre mich ketogen (sehr kohlenhydratarm) — bitte sagen Sie '
      'mir, welche Gerichte Zucker, Mehl, Reis, Kartoffeln oder süße Saucen '
      'enthalten.',
  veganLine:
      'Ich ernähre mich vegan — bitte sagen Sie mir, welche Gerichte '
      'Fleisch, Fisch, Milchprodukte, Eier oder Honig enthalten.',
  vegetarianLine:
      'Ich ernähre mich vegetarisch — bitte sagen Sie mir, welche Gerichte '
      'Fleisch, Geflügel oder Fisch enthalten.',
  kosherLine:
      'Ich esse koscher — bitte sagen Sie mir, ob ein Gericht '
      'Schweinefleisch, Meeresfrüchte oder Fisch ohne Flossen und Schuppen '
      'enthält oder Fleisch mit Milchprodukten kombiniert.',
  halalLine:
      'Ich esse halal — bitte sagen Sie mir, ob ein Gericht Schweinefleisch, '
      'Alkohol (auch in einer Sauce gekocht), Gelatine oder Blut enthält.',
  glp1Line:
      'Ich esse kleine Portionen — bitte sagen Sie mir, welche Gerichte es '
      'in einer kleineren Größe gibt und welche frittiert, sahnig oder sehr '
      'süß sind.',
  kosherQuestion: 'Ist Ihr Fleisch koscher zertifiziert?',
  halalQuestion: 'Ist Ihr Fleisch halal zertifiziert?',
  ownLine:
      'Ich kann nicht essen: {list} — bitte prüfen Sie jede Zutat, auch '
      'Saucen, Öle und Garnituren.',
  exceptionsLine: 'Essen kann ich trotzdem: {list}.',
  dishLine: 'Das Gericht, das ich möchte: {dish}',
  groupDishLine: 'Das Gericht, das wir möchten: {dish}',
  closingStrict:
      'Könnten Sie bitte in der Küche fragen, wie Kreuzkontakt vermieden '
      'wird (gemeinsame Flächen, Öl und Utensilien)? Danke.',
  closing: 'Danke.',
  footer:
      'Banto · eine Hilfe, keine Garantie — fragen Sie immer im Restaurant '
      'nach',
  officialNames: _annexII,
  names: <RestrictionId, String>{
    // Annex II (DE).
    RestrictionId.gluten: 'glutenhaltiges Getreide',
    RestrictionId.wheat: 'Weizen',
    RestrictionId.crustaceans: 'Krebstiere',
    RestrictionId.eggs: 'Eier',
    RestrictionId.fish: 'Fische',
    RestrictionId.peanuts: 'Erdnüsse',
    RestrictionId.soy: 'Sojabohnen',
    RestrictionId.milk: 'Milch',
    RestrictionId.treeNuts: 'Schalenfrüchte',
    RestrictionId.celery: 'Sellerie',
    RestrictionId.mustard: 'Senf',
    RestrictionId.sesame: 'Sesamsamen',
    RestrictionId.sulphites: 'Schwefeldioxid und Sulphite',
    RestrictionId.lupin: 'Lupinen',
    RestrictionId.molluscs: 'Weichtiere',
    // The app's translation, unreviewed.
    RestrictionId.lactose: 'Laktose',
    RestrictionId.legumes:
        'Hülsenfrüchte (Kichererbsen, Linsen, Erbsen, Ackerbohnen)',
    RestrictionId.alphaGal:
        'Fleisch von Säugetieren (Alpha-Gal: Rind, Lamm, Schwein, Gelatine, '
        'Schmalz, Fleischbrühe)',
    RestrictionId.fodmap:
        'FODMAP (Zwiebel, Knoblauch, Weizen, Bohnen, Linsen, Honig, Apfel)',
    RestrictionId.histamine:
        'histaminreiche Lebensmittel (gereifter Käse, Wurst, Fermentiertes, '
        'Essig, Wein, Thunfisch)',
    RestrictionId.vegan: 'vegan',
    RestrictionId.vegetarian: 'vegetarisch',
    RestrictionId.glp1: 'kleine Portionen',
    RestrictionId.kosher: 'koscher',
    RestrictionId.halal: 'halal',
    RestrictionId.buckwheat: 'Buchweizen',
    RestrictionId.kiwi: 'Kiwi',
    RestrictionId.peach: 'Pfirsich',
    RestrictionId.apple: 'Apfel',
    RestrictionId.banana: 'Banane',
    RestrictionId.orange: 'Orange',
    RestrictionId.beef: 'Rindfleisch',
    RestrictionId.pork: 'Schweinefleisch',
    RestrictionId.chicken: 'Hähnchen',
    RestrictionId.gelatin: 'Gelatine',
    RestrictionId.yam: 'japanische Yamswurzel (Yamaimo)',
    RestrictionId.corn: 'Mais',
    RestrictionId.sunflower: 'Sonnenblumenkerne',
    RestrictionId.flax: 'Leinsamen',
    RestrictionId.chickpea: 'Kichererbsen',
    RestrictionId.lentil: 'Linsen',
    RestrictionId.pea: 'Erbsen',
    RestrictionId.fenugreek: 'Bockshornklee',
    RestrictionId.fava: 'Ackerbohnen (Favismus, G6PD-Mangel)',
    RestrictionId.nightshades:
        'Nachtschattengewächse (Tomate, Kartoffel, Aubergine, Paprika, '
        'Chili)',
    RestrictionId.msg: 'Mononatriumglutamat (MSG, Brühpulver, Würzmischungen)',
    RestrictionId.caffeine:
        'Koffein (Kaffee, Tee, Cola, Schokolade, Energydrinks)',
    RestrictionId.salicylates:
        'Salicylate (Gewürze, Kräuter, Tomate, Beeren, Trockenobst)',
    RestrictionId.oralAllergy: 'rohes Obst und Gemüse (orales Allergiesyndrom)',
    RestrictionId.pescatarian:
        'pescetarisch (Fisch, aber kein Fleisch und kein Geflügel)',
    RestrictionId.paleo:
        'Paleo (ohne Getreide, Hülsenfrüchte, Milchprodukte und raffinierten '
        'Zucker)',
    RestrictionId.whole30:
        'Whole30 (ohne Zucker, Getreide, Hülsenfrüchte, Milchprodukte und '
        'Alkohol)',
    RestrictionId.aip:
        'Autoimmunprotokoll (AIP: ohne Getreide, Hülsenfrüchte, '
        'Milchprodukte, Eier, Nüsse, Samen und Nachtschattengewächse)',
    RestrictionId.jain:
        'jainistisch (ohne Fleisch, Fisch, Eier, Honig, Zwiebel, Knoblauch '
        'und Wurzelgemüse)',
    RestrictionId.keto: 'ketogen',
    RestrictionId.custom: 'bestimmte Lebensmittel',
  },
);

// ---------------------------------------------------------------------
// Japanese. UNREVIEWED BY A NATIVE SPEAKER (file 12 §15). The names in
// [_caaNames] are the Consumer Affairs Agency's allergen list as it
// writes them (特定原材料 and 特定原材料に準ずるもの, 2026); every other
// name and every sentence is the app's translation.
// ---------------------------------------------------------------------

/// The restrictions whose Japanese name is the Consumer Affairs Agency's
/// own (one item of its list, written as the list writes it).
const Set<RestrictionId> _caaNames = <RestrictionId>{
  RestrictionId.peanuts,
  RestrictionId.wheat,
  RestrictionId.buckwheat,
  RestrictionId.eggs,
  RestrictionId.milk,
  RestrictionId.soy,
  RestrictionId.sesame,
  RestrictionId.kiwi,
  RestrictionId.peach,
  RestrictionId.apple,
  RestrictionId.banana,
  RestrictionId.orange,
  RestrictionId.beef,
  RestrictionId.pork,
  RestrictionId.chicken,
  RestrictionId.gelatin,
  RestrictionId.yam,
};

/// The Japanese card. Unreviewed by a native speaker.
const ChefCardLocale japaneseChefCard = ChefCardLocale(
  intro: 'こんにちは。食事制限があるため、注文の際にご協力をお願いします。',
  groupIntro:
      'こんにちは。私たちのうち何人かに食事制限があるため、注文の際にご協力を'
      'お願いします。',
  me: '私',
  allergenLine:
      '食物アレルギー：{name}。ソース、油、付け合わせを含め、すべての材料を'
      'ご確認ください。',
  celiacLine:
      'セリアック病のため、{name}（小麦、大麦、ライ麦とその加工品）を避ける'
      '必要があります。ソース、スープ、マリネ液を含め、すべての材料をご確認'
      'のうえ、揚げ油・グリル・調理器具を共用しているか教えてください。',
  medicalLine:
      '健康上の理由で食べられないもの：{name}。ソース、油、付け合わせを含め、'
      'すべての材料をご確認ください。',
  avoidLine: '控えているもの：{name}。どの料理に含まれているか教えてください。',
  dietLine: '特別な食事法を守っています：{name}。合わない料理を教えてください。',
  ketoLine:
      'ケトジェニック（糖質をごく少なくする）食事をしています。砂糖、小麦粉、'
      '米、じゃがいも、甘いソースを含む料理を教えてください。',
  veganLine: 'ヴィーガンです。肉、魚、乳製品、卵、はちみつを含む料理を教えてください。',
  vegetarianLine: 'ベジタリアンです。肉、鶏肉、魚を含む料理を教えてください。',
  kosherLine:
      'コーシャの食事をしています。豚肉、甲殻類や貝類、ひれとうろこのない魚を'
      '含む料理、または肉と乳製品を組み合わせた料理を教えてください。',
  halalLine:
      'ハラールの食事をしています。豚肉、アルコール（ソースで加熱したものも'
      '含む）、ゼラチン、血を含む料理を教えてください。',
  glp1Line:
      '少量しか食べられません。小さいサイズにできる料理と、揚げ物、クリーム系、'
      'とても甘い料理を教えてください。',
  kosherQuestion: 'お店のお肉はコーシャ認証を受けていますか？',
  halalQuestion: 'お店のお肉はハラール認証を受けていますか？',
  ownLine:
      '食べられないもの：{list}。ソース、油、付け合わせを含め、すべての材料を'
      'ご確認ください。',
  exceptionsLine: 'ただし、次のものは食べられます：{list}。',
  dishLine: '注文したい料理：{dish}',
  groupDishLine: '私たちが注文したい料理：{dish}',
  closingStrict:
      '交差接触（調理台、油、調理器具の共用）をどのように防いでいるか、厨房に'
      'ご確認いただけますか？よろしくお願いします。',
  closing: 'よろしくお願いします。',
  footer: 'Banto · 補助ツールであり、保証ではありません — 必ずお店にご確認ください',
  officialNames: _caaNames,
  listSeparator: '、',
  sentenceJoiner: '',
  names: <RestrictionId, String>{
    // The Consumer Affairs Agency's list.
    RestrictionId.peanuts: '落花生（ピーナッツ）',
    RestrictionId.wheat: '小麦',
    RestrictionId.buckwheat: 'そば',
    RestrictionId.eggs: '卵',
    RestrictionId.milk: '乳',
    RestrictionId.soy: '大豆',
    RestrictionId.sesame: 'ごま',
    RestrictionId.kiwi: 'キウイフルーツ',
    RestrictionId.peach: 'もも',
    RestrictionId.apple: 'りんご',
    RestrictionId.banana: 'バナナ',
    RestrictionId.orange: 'オレンジ',
    RestrictionId.beef: '牛肉',
    RestrictionId.pork: '豚肉',
    RestrictionId.chicken: '鶏肉',
    RestrictionId.gelatin: 'ゼラチン',
    RestrictionId.yam: 'やまいも',
    // Built from the list's names, with a grouping word of the app's.
    RestrictionId.crustaceans: 'えび・かに（甲殻類）',
    RestrictionId.treeNuts:
        'ナッツ類（くるみ、カシューナッツ、アーモンド、ピスタチオ、'
        'マカダミアナッツなど）',
    RestrictionId.fish: '魚（さけ、さばなど）',
    RestrictionId.molluscs: 'いか・たこ・貝類（あわびなど）',
    // The app's translation, unreviewed.
    RestrictionId.gluten: 'グルテン',
    RestrictionId.lactose: '乳糖',
    RestrictionId.celery: 'セロリ',
    RestrictionId.mustard: 'マスタード（からし）',
    RestrictionId.lupin: 'ルピナス',
    RestrictionId.sulphites: '亜硫酸塩（二酸化硫黄）',
    RestrictionId.legumes: '豆類（ひよこ豆、レンズ豆、えんどう豆、そら豆）',
    RestrictionId.alphaGal: '哺乳類の肉（アルファガル：牛肉、羊肉、豚肉、ゼラチン、ラード、肉のだし）',
    RestrictionId.fodmap: 'FODMAP（玉ねぎ、にんにく、小麦、豆類、はちみつ、りんご）',
    RestrictionId.histamine: 'ヒスタミンの多い食品（熟成チーズ、加工肉、発酵食品、酢、ワイン、まぐろ）',
    RestrictionId.vegan: 'ヴィーガン',
    RestrictionId.vegetarian: 'ベジタリアン',
    RestrictionId.glp1: '少量の食事',
    RestrictionId.kosher: 'コーシャ',
    RestrictionId.halal: 'ハラール',
    RestrictionId.corn: 'とうもろこし',
    RestrictionId.sunflower: 'ひまわりの種',
    RestrictionId.flax: '亜麻仁',
    RestrictionId.chickpea: 'ひよこ豆',
    RestrictionId.lentil: 'レンズ豆',
    RestrictionId.pea: 'えんどう豆',
    RestrictionId.fenugreek: 'フェヌグリーク',
    RestrictionId.fava: 'そら豆（G6PD欠乏症）',
    RestrictionId.nightshades: 'ナス科の野菜（トマト、じゃがいも、なす、ピーマン、唐辛子、パプリカ）',
    RestrictionId.msg: 'グルタミン酸ナトリウム（うま味調味料、顆粒だし、調味料ミックス）',
    RestrictionId.caffeine: 'カフェイン（コーヒー、お茶、コーラ、チョコレート、エナジードリンク）',
    RestrictionId.salicylates: 'サリチル酸（香辛料、ハーブ、トマト、ベリー類、ドライフルーツ）',
    RestrictionId.oralAllergy: '生の果物と野菜（口腔アレルギー症候群）',
    RestrictionId.pescatarian: 'ペスカタリアン（魚は食べますが、肉と鶏肉は食べません）',
    RestrictionId.paleo: 'パレオ（穀物、豆類、乳製品、精製糖なし）',
    RestrictionId.whole30: 'Whole30（砂糖、穀物、豆類、乳製品、アルコールなし）',
    RestrictionId.aip: '自己免疫プロトコル（AIP：穀物、豆類、乳製品、卵、ナッツ、種子、ナス科なし）',
    RestrictionId.jain: 'ジャイナ教の食事（肉、魚、卵、はちみつ、玉ねぎ、にんにく、根菜なし）',
    RestrictionId.keto: 'ケトジェニック',
    RestrictionId.custom: '一部の食品',
  },
);
