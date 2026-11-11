/// The places the Discovery screen's location picker offers (issue #443):
/// Israeli cities, each with the approximate centre a nearby search is made
/// at.
///
/// A bundled list rather than a typed address: turning an address into
/// coordinates needs a geocoder, which would be a new outside host and
/// would send what the user types to it (`phase2_discovery_research.md`
/// §6 defers reverse geocoding for the same reason). A list works offline,
/// on every platform, with no permission.
///
/// Pure data and pure functions only.
library;

import 'package:ketoclub/models/place.dart';

/// Every place the picker offers, larger cities first so the common picks
/// sit at the top of the list.
///
/// Coordinates are approximate city centres, good to a few hundred metres:
/// enough for "restaurants around here", not a street address. An id is
/// stored on the device (`AppSettings.discoveryPlaceId`), so one already
/// shipped must never change or be reused; a removed place simply stops
/// being restored.
const List<KnownPlace> knownPlaces = <KnownPlace>[
  KnownPlace(
    id: 'tel-aviv',
    nameEn: 'Tel Aviv-Yafo',
    nameHe: 'תל אביב-יפו',
    latitude: 32.0853,
    longitude: 34.7818,
  ),
  KnownPlace(
    id: 'jerusalem',
    nameEn: 'Jerusalem',
    nameHe: 'ירושלים',
    latitude: 31.7683,
    longitude: 35.2137,
  ),
  KnownPlace(
    id: 'haifa',
    nameEn: 'Haifa',
    nameHe: 'חיפה',
    latitude: 32.7940,
    longitude: 34.9896,
  ),
  KnownPlace(
    id: 'rishon-lezion',
    nameEn: 'Rishon LeZion',
    nameHe: 'ראשון לציון',
    latitude: 31.9730,
    longitude: 34.7925,
  ),
  KnownPlace(
    id: 'petah-tikva',
    nameEn: 'Petah Tikva',
    nameHe: 'פתח תקווה',
    latitude: 32.0871,
    longitude: 34.8875,
  ),
  KnownPlace(
    id: 'ashdod',
    nameEn: 'Ashdod',
    nameHe: 'אשדוד',
    latitude: 31.8044,
    longitude: 34.6553,
  ),
  KnownPlace(
    id: 'netanya',
    nameEn: 'Netanya',
    nameHe: 'נתניה',
    latitude: 32.3215,
    longitude: 34.8532,
  ),
  KnownPlace(
    id: 'beersheba',
    nameEn: 'Beersheba',
    nameHe: 'באר שבע',
    latitude: 31.2518,
    longitude: 34.7913,
  ),
  KnownPlace(
    id: 'bnei-brak',
    nameEn: 'Bnei Brak',
    nameHe: 'בני ברק',
    latitude: 32.0849,
    longitude: 34.8352,
  ),
  KnownPlace(
    id: 'holon',
    nameEn: 'Holon',
    nameHe: 'חולון',
    latitude: 32.0158,
    longitude: 34.7874,
  ),
  KnownPlace(
    id: 'ramat-gan',
    nameEn: 'Ramat Gan',
    nameHe: 'רמת גן',
    latitude: 32.0684,
    longitude: 34.8248,
  ),
  KnownPlace(
    id: 'ashkelon',
    nameEn: 'Ashkelon',
    nameHe: 'אשקלון',
    latitude: 31.6688,
    longitude: 34.5743,
  ),
  KnownPlace(
    id: 'rehovot',
    nameEn: 'Rehovot',
    nameHe: 'רחובות',
    latitude: 31.8928,
    longitude: 34.8113,
  ),
  KnownPlace(
    id: 'bat-yam',
    nameEn: 'Bat Yam',
    nameHe: 'בת ים',
    latitude: 32.0231,
    longitude: 34.7503,
  ),
  KnownPlace(
    id: 'beit-shemesh',
    nameEn: 'Beit Shemesh',
    nameHe: 'בית שמש',
    latitude: 31.7470,
    longitude: 34.9881,
  ),
  KnownPlace(
    id: 'kfar-saba',
    nameEn: 'Kfar Saba',
    nameHe: 'כפר סבא',
    latitude: 32.1750,
    longitude: 34.9070,
  ),
  KnownPlace(
    id: 'herzliya',
    nameEn: 'Herzliya',
    nameHe: 'הרצליה',
    latitude: 32.1663,
    longitude: 34.8436,
  ),
  KnownPlace(
    id: 'hadera',
    nameEn: 'Hadera',
    nameHe: 'חדרה',
    latitude: 32.4340,
    longitude: 34.9197,
  ),
  KnownPlace(
    id: 'modiin',
    nameEn: "Modi'in",
    nameHe: 'מודיעין',
    latitude: 31.8980,
    longitude: 35.0105,
  ),
  KnownPlace(
    id: 'nazareth',
    nameEn: 'Nazareth',
    nameHe: 'נצרת',
    latitude: 32.6996,
    longitude: 35.3035,
  ),
  KnownPlace(
    id: 'lod',
    nameEn: 'Lod',
    nameHe: 'לוד',
    latitude: 31.9516,
    longitude: 34.8953,
  ),
  KnownPlace(
    id: 'ramla',
    nameEn: 'Ramla',
    nameHe: 'רמלה',
    latitude: 31.9296,
    longitude: 34.8667,
  ),
  KnownPlace(
    id: 'raanana',
    nameEn: "Ra'anana",
    nameHe: 'רעננה',
    latitude: 32.1848,
    longitude: 34.8713,
  ),
  KnownPlace(
    id: 'givatayim',
    nameEn: 'Givatayim',
    nameHe: 'גבעתיים',
    latitude: 32.0722,
    longitude: 34.8125,
  ),
  KnownPlace(
    id: 'hod-hasharon',
    nameEn: 'Hod HaSharon',
    nameHe: 'הוד השרון',
    latitude: 32.1522,
    longitude: 34.8932,
  ),
  KnownPlace(
    id: 'rosh-haayin',
    nameEn: 'Rosh HaAyin',
    nameHe: 'ראש העין',
    latitude: 32.0956,
    longitude: 34.9566,
  ),
  KnownPlace(
    id: 'kiryat-gat',
    nameEn: 'Kiryat Gat',
    nameHe: 'קריית גת',
    latitude: 31.6100,
    longitude: 34.7642,
  ),
  KnownPlace(
    id: 'nahariya',
    nameEn: 'Nahariya',
    nameHe: 'נהריה',
    latitude: 33.0059,
    longitude: 35.0941,
  ),
  KnownPlace(
    id: 'afula',
    nameEn: 'Afula',
    nameHe: 'עפולה',
    latitude: 32.6078,
    longitude: 35.2897,
  ),
  KnownPlace(
    id: 'eilat',
    nameEn: 'Eilat',
    nameHe: 'אילת',
    latitude: 29.5577,
    longitude: 34.9519,
  ),
  KnownPlace(
    id: 'acre',
    nameEn: 'Acre (Akko)',
    nameHe: 'עכו',
    latitude: 32.9281,
    longitude: 35.0765,
  ),
  KnownPlace(
    id: 'karmiel',
    nameEn: 'Karmiel',
    nameHe: 'כרמיאל',
    latitude: 32.9136,
    longitude: 35.2961,
  ),
  KnownPlace(
    id: 'tiberias',
    nameEn: 'Tiberias',
    nameHe: 'טבריה',
    latitude: 32.7922,
    longitude: 35.5312,
  ),
  KnownPlace(
    id: 'ness-ziona',
    nameEn: 'Ness Ziona',
    nameHe: 'נס ציונה',
    latitude: 31.9293,
    longitude: 34.7987,
  ),
  KnownPlace(
    id: 'ramat-hasharon',
    nameEn: 'Ramat HaSharon',
    nameHe: 'רמת השרון',
    latitude: 32.1461,
    longitude: 34.8394,
  ),
  KnownPlace(
    id: 'yavne',
    nameEn: 'Yavne',
    nameHe: 'יבנה',
    latitude: 31.8781,
    longitude: 34.7394,
  ),
  KnownPlace(
    id: 'kiryat-ono',
    nameEn: 'Kiryat Ono',
    nameHe: 'קריית אונו',
    latitude: 32.0636,
    longitude: 34.8553,
  ),
  KnownPlace(
    id: 'or-yehuda',
    nameEn: 'Or Yehuda',
    nameHe: 'אור יהודה',
    latitude: 32.0306,
    longitude: 34.8533,
  ),
  KnownPlace(
    id: 'kiryat-shmona',
    nameEn: 'Kiryat Shmona',
    nameHe: 'קריית שמונה',
    latitude: 33.2073,
    longitude: 35.5695,
  ),
  KnownPlace(
    id: 'safed',
    nameEn: 'Safed (Tzfat)',
    nameHe: 'צפת',
    latitude: 32.9646,
    longitude: 35.4960,
  ),
  KnownPlace(
    id: 'zichron-yaakov',
    nameEn: "Zichron Ya'akov",
    nameHe: 'זכרון יעקב',
    latitude: 32.5707,
    longitude: 34.9518,
  ),
  KnownPlace(
    id: 'caesarea',
    nameEn: 'Caesarea',
    nameHe: 'קיסריה',
    latitude: 32.5190,
    longitude: 34.9045,
  ),
];

/// The place whose [KnownPlace.id] is [id], or null when there is none:
/// an id saved by a version that offered a place this one does not.
KnownPlace? knownPlaceById(String id) {
  for (final place in knownPlaces) {
    if (place.id == id) return place;
  }
  return null;
}

/// The [knownPlaces] whose English or Hebrew name contains [query], in
/// list order; every place for a blank [query].
///
/// Both sides are folded first (see [_fold]), so `tel aviv` finds
/// "Tel Aviv-Yafo", `raanana` finds "Ra'anana" and `קרית גת` finds
/// "קריית גת". Either language matches whatever the UI language is: a
/// Hebrew speaker with an English UI still types Hebrew.
List<KnownPlace> searchKnownPlaces(String query) {
  final needle = _fold(query);
  if (needle.isEmpty) return knownPlaces;
  return <KnownPlace>[
    for (final place in knownPlaces)
      if (_fold(place.nameEn).contains(needle) ||
          _fold(place.nameHe).contains(needle))
        place,
  ];
}

/// Everything a typed name and a listed one may differ by without being a
/// different place: spaces, hyphens (and the Hebrew maqaf), apostrophes
/// (and the Hebrew geresh), brackets and full stops.
final RegExp _separators = RegExp('[\\s\\-־\'’`׳"״().]');

/// A doubled yod, which Hebrew spells either way ("קריית" and "קרית").
final RegExp _doubleYod = RegExp('י+');

/// [text] lower-cased, without [_separators] and with a doubled yod
/// written once, so two spellings of one name compare equal.
String _fold(String text) =>
    text.toLowerCase().replaceAll(_separators, '').replaceAll(_doubleYod, 'י');
