/// Trip mode's destination (Banto; the Allergens epic, ALG-13, issue #355).
///
/// A [TripDestination] is the country the user is travelling to. It sits
/// beside the dietary profile (`AppSettings.tripDestination`), never inside
/// it, and like the profile it stays on the device (contract decision C1):
/// nothing here is put in a request, a log line or the menu cache.
///
/// The first set is the epic's: the two home markets (Israel, the United
/// States), the United Kingdom, the European Union's largest tourist
/// countries (France, Italy, Spain, Germany) and Japan.
library;

import 'package:ketoclub/models/restriction.dart';

/// A country trip mode knows: its allergen [jurisdiction] and, in
/// `lib/utils/allergens/trip_lexicon.dart`, its local hidden-ingredient
/// lexicon.
///
/// The wire and storage form is [name], matched by string and never by
/// ordinal ([tryParse]), so adding or reordering a value cannot re-map a
/// stored trip.
enum TripDestination {
  /// Israel.
  israel(Jurisdiction.il),

  /// The United States.
  unitedStates(Jurisdiction.us),

  /// The United Kingdom.
  unitedKingdom(Jurisdiction.uk),

  /// France.
  france(Jurisdiction.eu),

  /// Italy.
  italy(Jurisdiction.eu),

  /// Spain.
  spain(Jurisdiction.eu),

  /// Germany.
  germany(Jurisdiction.eu),

  /// Japan.
  japan(Jurisdiction.jp);

  new(this.jurisdiction);

  /// The jurisdiction whose allergen law applies in this country: the
  /// `tripJurisdiction` the regulation hints read.
  final Jurisdiction jurisdiction;

  /// The destination whose [name] equals [wire], or null when none does.
  static TripDestination? tryParse(String wire) {
    for (final destination in TripDestination.values) {
      if (destination.name == wire) return destination;
    }
    return null;
  }
}
