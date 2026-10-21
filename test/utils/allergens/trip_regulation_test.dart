// Trip mode's regulation hints (Banto, ALG-13, issue #355): the rendering
// table — every taxonomy entry × every destination — and the data it reads,
// the per-jurisdiction scope that tells a restaurant duty from a
// packaged-food rule.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/trip_regulation.dart';

/// The Codex eight on Japan's mandatory list too (file 02).
const Set<RestrictionId> _everywhere = <RestrictionId>{
  RestrictionId.peanuts,
  RestrictionId.treeNuts,
  RestrictionId.milk,
  RestrictionId.eggs,
  RestrictionId.wheat,
  RestrictionId.crustaceans,
};

/// On every list but Japan's mandatory one (file 02).
const Set<RestrictionId> _allButJapan = <RestrictionId>{
  RestrictionId.soy,
  RestrictionId.fish,
  RestrictionId.sesame,
};

/// The EU 14's additions, shared by the UK and Israel, not the US.
const Set<RestrictionId> _euAdditions = <RestrictionId>{
  RestrictionId.gluten,
  RestrictionId.molluscs,
  RestrictionId.celery,
  RestrictionId.mustard,
  RestrictionId.lupin,
  RestrictionId.sulphites,
};

/// Strict, but on no list anywhere.
const Set<RestrictionId> _nowhere = <RestrictionId>{
  RestrictionId.legumes,
  RestrictionId.alphaGal,
  RestrictionId.custom,
};

/// Flexible: no hint at all.
const Set<RestrictionId> _flexible = <RestrictionId>{
  RestrictionId.lactose,
  RestrictionId.fodmap,
  RestrictionId.histamine,
  RestrictionId.vegan,
  RestrictionId.vegetarian,
  RestrictionId.glp1,
  RestrictionId.kosher,
  RestrictionId.halal,
  RestrictionId.keto,
};

/// The hint a restriction on the destination's list gets there.
RegulationHint _listed(TripDestination destination) => switch (destination) {
  TripDestination.israel ||
  TripDestination.japan => RegulationHint.packagedOnly,
  TripDestination.unitedStates => RegulationHint.packagedOnlyLargeChains,
  TripDestination.unitedKingdom ||
  TripDestination.france ||
  TripDestination.italy ||
  TripDestination.spain ||
  TripDestination.germany => RegulationHint.restaurantMustTell,
};

/// The expected hint for [id] at [destination], written from file 02's
/// lists rather than from the taxonomy the code reads.
RegulationHint? _expected(RestrictionId id, TripDestination destination) {
  if (_flexible.contains(id)) return null;
  if (_nowhere.contains(id)) return RegulationHint.notRegulated;
  final listed =
      _everywhere.contains(id) ||
      (_allButJapan.contains(id) && destination != TripDestination.japan) ||
      (_euAdditions.contains(id) &&
          destination != TripDestination.japan &&
          destination != TripDestination.unitedStates);
  return listed ? _listed(destination) : RegulationHint.notRegulated;
}

void main() {
  test('the expectation groups cover every restriction exactly once', () {
    final groups = <Set<RestrictionId>>[
      _everywhere,
      _allButJapan,
      _euAdditions,
      _nowhere,
      _flexible,
    ];
    for (final id in RestrictionId.values) {
      expect(
        groups.where((group) => group.contains(id)),
        hasLength(1),
        reason: id.name,
      );
    }
  });

  group('the rendering table: every taxonomy entry × every destination', () {
    for (final restriction in restrictionTaxonomy) {
      for (final destination in TripDestination.values) {
        test('${restriction.id.name} in ${destination.name}', () {
          expect(
            TripRegulation.hintFor(restriction.id, destination),
            _expected(restriction.id, destination),
          );
        });
      }
    }
  });

  group('the home markets', () {
    test('Israel: every strict entry is "ask every time" — the 2028 rule '
        'covers packaged food only', () {
      for (final restriction in restrictionTaxonomy.where((r) => r.isStrict)) {
        expect(
          TripRegulation.hintFor(restriction.id, TripDestination.israel),
          isNot(RegulationHint.restaurantMustTell),
          reason: restriction.id.name,
        );
      }
    });

    test('the US: no strict entry is a restaurant duty', () {
      for (final restriction in restrictionTaxonomy.where((r) => r.isStrict)) {
        expect(
          TripRegulation.hintFor(restriction.id, TripDestination.unitedStates),
          isNot(RegulationHint.restaurantMustTell),
          reason: restriction.id.name,
        );
      }
    });

    test('the EU and the UK are where a restaurant must answer', () {
      for (final destination in <TripDestination>[
        TripDestination.unitedKingdom,
        TripDestination.france,
        TripDestination.germany,
      ]) {
        expect(
          TripRegulation.hintFor(RestrictionId.sesame, destination),
          RegulationHint.restaurantMustTell,
        );
      }
    });

    test('mustard is not regulated in the US; buckwheat-free Japan does '
        'not list sesame', () {
      expect(
        TripRegulation.hintFor(
          RestrictionId.mustard,
          TripDestination.unitedStates,
        ),
        RegulationHint.notRegulated,
      );
      expect(
        TripRegulation.hintFor(RestrictionId.sesame, TripDestination.japan),
        RegulationHint.notRegulated,
      );
    });
  });

  group('the scope data', () {
    test('every jurisdiction has a scope; only the EU and the UK bind '
        'restaurants', () {
      expect(jurisdictionListScope.keys.toSet(), Jurisdiction.values.toSet());
      expect(
        <Jurisdiction>{
          for (final MapEntry(:key, :value) in jurisdictionListScope.entries)
            if (value == ListScope.restaurants) key,
        },
        <Jurisdiction>{Jurisdiction.eu, Jurisdiction.uk},
      );
      expect(jurisdictionListScope[Jurisdiction.il], ListScope.packagedFood);
      expect(
        jurisdictionListScope[Jurisdiction.us],
        ListScope.packagedFoodAndLargeChains,
      );
    });

    test('each destination names its jurisdiction', () {
      expect(
        <TripDestination, Jurisdiction>{
          for (final destination in TripDestination.values)
            destination: destination.jurisdiction,
        },
        <TripDestination, Jurisdiction>{
          TripDestination.israel: Jurisdiction.il,
          TripDestination.unitedStates: Jurisdiction.us,
          TripDestination.unitedKingdom: Jurisdiction.uk,
          TripDestination.france: Jurisdiction.eu,
          TripDestination.italy: Jurisdiction.eu,
          TripDestination.spain: Jurisdiction.eu,
          TripDestination.germany: Jurisdiction.eu,
          TripDestination.japan: Jurisdiction.jp,
        },
      );
    });

    test('destinations parse by name, never by ordinal', () {
      for (final destination in TripDestination.values) {
        expect(TripDestination.tryParse(destination.name), destination);
      }
      expect(TripDestination.tryParse('narnia'), isNull);
      expect(TripDestination.tryParse('0'), isNull);
    });
  });
}
