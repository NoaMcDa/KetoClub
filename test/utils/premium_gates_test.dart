// The free plan's gates as a table (Banto, ALG-18, issue #360): each gate
// against Premium on and off, a Banto and a KetoClub build, and the web
// build (which sells nothing) against a phone (which does).

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/utils/premium_gates.dart';

/// One row of the table: who is asking.
typedef _Who = ({bool banto, bool phone, bool premium});

/// Every combination of the three.
final List<_Who> _everyone = <_Who>[
  for (final banto in <bool>[true, false])
    for (final phone in <bool>[true, false])
      for (final premium in <bool>[true, false])
        (banto: banto, phone: phone, premium: premium),
];

PremiumAccess _access(_Who who) => PremiumAccess(
  bantoMode: who.banto,
  // A phone sells Premium through its store; the web build sells nothing.
  sellsPremium: who.phone,
  premium: who.premium,
);

/// Only a Banto phone without Premium is ever limited.
bool _limited(_Who who) => who.banto && who.phone && !who.premium;

final DietaryProfile _peanuts = DietaryProfile.empty.withEntry(
  RestrictionId.peanuts,
);

void main() {
  group('PremiumFeature', () {
    test('names exactly the four gated things and nothing about what is '
        'saved', () {
      expect(PremiumFeature.values, <PremiumFeature>[
        PremiumFeature.restrictions,
        PremiumFeature.groupProfiles,
        PremiumFeature.tripMode,
        PremiumFeature.scans,
      ]);
    });
  });

  group('the free plan', () {
    test('is one restriction and five scans a month', () {
      expect(freeRestrictionCount, 1);
      expect(freeScansPerMonth, 5);
    });
  });

  group('PremiumAccess', () {
    test('is limited only for a Banto phone without Premium', () {
      for (final who in _everyone) {
        expect(_access(who).limited, _limited(who), reason: '$who');
      }
      expect(PremiumAccess.unlimited.limited, isFalse);
    });
  });

  group('gate table', () {
    for (final who in _everyone) {
      final access = _access(who);
      final locked = _limited(who);

      test('$who: a second restriction is locked: $locked', () {
        expect(
          PremiumGates.locksAddingRestriction(
            access,
            profile: _peanuts,
            adding: RestrictionId.sesame,
          ),
          locked,
        );
      });

      test('$who: adding a person is locked: $locked', () {
        expect(PremiumGates.locksAddingPerson(access), locked);
      });

      test('$who: checking a second person is locked: $locked', () {
        expect(
          PremiumGates.locksCheckingPeople(
            access,
            current: const <String>['me'],
            next: const <String>['me', 'p1'],
          ),
          locked,
        );
      });

      test('$who: picking a destination is locked: $locked', () {
        expect(PremiumGates.locksPickingDestination(access), locked);
      });

      test('$who: a sixth scan is locked: $locked', () {
        expect(
          PremiumGates.locksScan(access, scansThisMonth: freeScansPerMonth),
          locked,
        );
      });

      test('$who: the first restriction and the first five scans are never '
          'locked', () {
        expect(
          PremiumGates.locksAddingRestriction(
            access,
            profile: DietaryProfile.empty,
            adding: RestrictionId.peanuts,
          ),
          isFalse,
        );
        for (var used = 0; used < freeScansPerMonth; used++) {
          expect(
            PremiumGates.locksScan(access, scansThisMonth: used),
            isFalse,
            reason: '$used used',
          );
        }
      });
    }
  });

  group('only adding is gated', () {
    const free = PremiumAccess(
      bantoMode: true,
      sellsPremium: true,
      premium: false,
    );
    final full = DietaryProfile.empty
        .withEntry(RestrictionId.peanuts)
        .withEntry(RestrictionId.sesame)
        .withEntry(RestrictionId.gluten);

    test('keto is never counted and never gated', () {
      final keto = DietaryProfile.empty.withEntry(RestrictionId.keto);
      expect(PremiumGates.countedRestrictions(keto), 0);
      expect(
        PremiumGates.locksAddingRestriction(
          free,
          profile: keto,
          adding: RestrictionId.peanuts,
        ),
        isFalse,
      );
      expect(
        PremiumGates.locksAddingRestriction(
          free,
          profile: full,
          adding: RestrictionId.keto,
        ),
        isFalse,
      );
    });

    test('a restriction already saved is never gated, however many a lapsed '
        'profile holds', () {
      expect(PremiumGates.countedRestrictions(full), 3);
      for (final entry in full.entries) {
        expect(
          PremiumGates.locksAddingRestriction(
            free,
            profile: full,
            adding: entry.restrictionId,
          ),
          isFalse,
          reason: '${entry.restrictionId}',
        );
      }
    });

    test('another word for the own restriction already saved is not a new '
        'restriction', () {
      final own = DietaryProfile.empty.withCustomTerm('kiwi');
      expect(
        PremiumGates.locksAddingRestriction(
          free,
          profile: own,
          adding: RestrictionId.custom,
        ),
        isFalse,
      );
      expect(
        PremiumGates.locksAddingRestriction(
          free,
          profile: _peanuts,
          adding: RestrictionId.custom,
        ),
        isTrue,
      );
    });

    test('the onboarding counts its chosen chips the same way', () {
      expect(
        PremiumGates.locksChoosing(
          free,
          chosen: const <RestrictionId>[],
          adding: RestrictionId.peanuts,
        ),
        isFalse,
      );
      expect(
        PremiumGates.locksChoosing(
          free,
          chosen: const <RestrictionId>[RestrictionId.peanuts],
          adding: RestrictionId.sesame,
        ),
        isTrue,
      );
      expect(
        PremiumGates.locksChoosing(
          free,
          chosen: const <RestrictionId>[RestrictionId.keto],
          adding: RestrictionId.sesame,
        ),
        isFalse,
      );
      expect(
        PremiumGates.locksChoosing(
          free,
          chosen: const <RestrictionId>[RestrictionId.peanuts],
          adding: RestrictionId.peanuts,
        ),
        isFalse,
      );
      expect(
        PremiumGates.locksChoosing(
          PremiumAccess.unlimited,
          chosen: const <RestrictionId>[RestrictionId.peanuts],
          adding: RestrictionId.sesame,
        ),
        isFalse,
      );
    });

    test('a saved choice of people, or a narrower one, is never gated', () {
      expect(
        PremiumGates.locksCheckingPeople(
          free,
          current: const <String>['me', 'p1', 'p2'],
          next: const <String>['me', 'p1', 'p2'],
        ),
        isFalse,
      );
      expect(
        PremiumGates.locksCheckingPeople(
          free,
          current: const <String>['me', 'p1', 'p2'],
          next: const <String>['me', 'p2'],
        ),
        isFalse,
      );
      expect(
        PremiumGates.locksCheckingPeople(
          free,
          current: const <String>['me', 'p1'],
          next: const <String>['p2'],
        ),
        isFalse,
      );
    });
  });

  group('freeScansLeft', () {
    test('counts down to zero and never below', () {
      expect(PremiumGates.freeScansLeft(0), 5);
      expect(PremiumGates.freeScansLeft(4), 1);
      expect(PremiumGates.freeScansLeft(5), 0);
      expect(PremiumGates.freeScansLeft(12), 0);
    });
  });

  group('scanMonthKey', () {
    test('is the UTC year and month', () {
      expect(scanMonthKey(DateTime.utc(2026, 10, 19, 12)), '2026-10');
      expect(scanMonthKey(DateTime.utc(2026)), '2026-01');
      expect(scanMonthKey(DateTime.utc(2026, 12, 31, 23, 59)), '2026-12');
      // The same instant is the same month whatever the device's zone.
      final instant = DateTime.utc(2026, 11);
      expect(scanMonthKey(instant.toLocal()), '2026-11');
    });
  });

  group('kosher and halal (#342)', () {
    const free = PremiumAccess(
      bantoMode: true,
      sellsPremium: true,
      premium: false,
    );

    test('count as a restriction like any other', () {
      final kosher = DietaryProfile.empty.withEntry(RestrictionId.kosher);
      expect(PremiumGates.countedRestrictions(kosher), 1);
      expect(
        PremiumGates.locksAddingRestriction(
          free,
          profile: DietaryProfile.empty,
          adding: RestrictionId.kosher,
        ),
        isFalse,
      );
      expect(
        PremiumGates.locksAddingRestriction(
          free,
          profile: kosher,
          adding: RestrictionId.halal,
        ),
        isTrue,
      );
      expect(
        PremiumGates.locksChoosing(
          free,
          chosen: const <RestrictionId>[RestrictionId.halal],
          adding: RestrictionId.peanuts,
        ),
        isTrue,
      );
    });
  });
}
