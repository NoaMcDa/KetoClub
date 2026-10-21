// SavedController under a Banto profile (issues #411 and #412): which kind
// of row each visit gets (keto, per-profile counts, re-check), the "Worked
// for me" mark per person and the filter that is only a filter.
import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/venue.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/services/storage/visit_history_store.dart';
import 'package:ketoclub/state/saved_controller.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/utils/visit_profile.dart';

import '../fakes/fake_clock.dart';
import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';
import '../fakes/fake_visit_history_store.dart';

const VenueRef _a = VenueRef(source: MenuSource.wolt, platformId: 'a');
const VenueRef _b = VenueRef(source: MenuSource.wolt, platformId: 'b');

final DietaryProfile _sesame = DietaryProfile.empty.withEntry(
  RestrictionId.sesame,
);
final DietaryProfile _lactose = DietaryProfile.empty.withEntry(
  RestrictionId.lactose,
);

/// A visit to [ref] at [at] counted for [profile] (or not counted at all).
VisitEntry _visit(
  VenueRef ref,
  DateTime at, {
  DietaryProfile? profile,
  List<String> workedFor = const <String>[],
}) => VisitEntry(
  ref: ref,
  firstOpenedAt: at,
  lastOpenedAt: at,
  openCount: 1,
  score: 7,
  greenCount: 5,
  yellowCount: 2,
  fits: profile == null ? null : 4,
  withChange: profile == null ? null : 2,
  ask: profile == null ? null : 3,
  avoid: profile == null ? null : 1,
  profileFingerprint: profile == null ? null : profileFingerprintOf(profile),
  workedFor: workedFor,
);

void main() {
  late FakeMenuRepository repository;
  late FakeVisitHistoryStore history;

  SavedController build(AppSettings settings) => SavedController(
    repository,
    history,
    FakeSettingsStore(initial: settings),
  );

  setUp(() {
    repository = FakeMenuRepository();
    history = FakeVisitHistoryStore(FakeClock(DateTime.utc(2026)));
  });

  group('the kind of row', () {
    test("a keto-only profile keeps today's row, even for an entry with "
        'counts', () async {
      // Arrange
      history.seed(_visit(_a, DateTime.utc(2026), profile: _sesame));
      final controller = build(const AppSettings());

      // Act
      await controller.load(bantoMode: true);

      // Assert
      expect(controller.readsProfile, isFalse);
      expect(controller.wording, ProfileWording.ketoOnly);
      expect(
        controller.rowKindFor(controller.entries.single),
        RecentRowKind.keto,
      );
    });

    test(
      'without Banto every row is a keto row, whatever the profile',
      () async {
        // Arrange
        history.seed(_visit(_a, DateTime.utc(2026), profile: _sesame));
        final controller = build(AppSettings(profile: _sesame));

        // Act
        await controller.load();

        // Assert
        expect(
          controller.rowKindFor(controller.entries.single),
          RecentRowKind.keto,
        );
      },
    );

    test('a strict profile shows the counts of the profile they were made '
        'for', () async {
      // Arrange
      history.seed(_visit(_a, DateTime.utc(2026), profile: _sesame));
      final controller = build(AppSettings(profile: _sesame));

      // Act
      await controller.load(bantoMode: true);

      // Assert
      expect(controller.wording, ProfileWording.strict);
      expect(
        controller.rowKindFor(controller.entries.single),
        RecentRowKind.states,
      );
    });

    test('a flexible profile words them flexibly', () async {
      // Arrange
      history.seed(_visit(_a, DateTime.utc(2026), profile: _lactose));
      final controller = build(AppSettings(profile: _lactose));

      // Act
      await controller.load(bantoMode: true);

      // Assert
      expect(controller.wording, ProfileWording.flexible);
      expect(
        controller.rowKindFor(controller.entries.single),
        RecentRowKind.states,
      );
    });

    test(
      'a changed profile asks for a re-check instead of stale numbers',
      () async {
        // Arrange: counted for sesame, now the profile is sesame and lactose.
        history.seed(_visit(_a, DateTime.utc(2026), profile: _sesame));
        final controller = build(
          AppSettings(profile: _sesame.withEntry(RestrictionId.lactose)),
        );

        // Act
        await controller.load(bantoMode: true);

        // Assert
        expect(
          controller.rowKindFor(controller.entries.single),
          RecentRowKind.recheck,
        );
      },
    );

    test('an entry never counted for a profile asks for a re-check', () async {
      // Arrange: opened as a keto user.
      history.seed(_visit(_a, DateTime.utc(2026)));
      final controller = build(AppSettings(profile: _sesame));

      // Act
      await controller.load(bantoMode: true);

      // Assert
      expect(
        controller.rowKindFor(controller.entries.single),
        RecentRowKind.recheck,
      );
    });

    test('a group is counted for the union of its people', () async {
      // Arrange
      final dana = NamedProfile(id: 'dana', name: 'Dana', profile: _lactose);
      final union = _sesame.withEntry(RestrictionId.lactose);
      history.seed(_visit(_a, DateTime.utc(2026), profile: union));
      final controller = build(
        AppSettings(
          profile: _sesame,
          otherProfiles: <NamedProfile>[dana],
          activeProfileIds: const <String>[NamedProfile.primaryId, 'dana'],
        ),
      );

      // Act
      await controller.load(bantoMode: true);

      // Assert
      expect(
        controller.rowKindFor(controller.entries.single),
        RecentRowKind.states,
      );
    });
  });

  group('canAskStaff', () {
    test('is true for a kept dish list even when nothing is cached', () async {
      // Arrange
      history
        ..seed(
          VisitEntry(
            ref: _a,
            firstOpenedAt: DateTime.utc(2026),
            lastOpenedAt: DateTime.utc(2026),
            openCount: 1,
            openedStrict: true,
            strictDishes: const [],
          ),
        )
        ..seed(_visit(_b, DateTime.utc(2025)));
      final controller = build(AppSettings(profile: _sesame));

      // Act
      await controller.load(bantoMode: true);

      // Assert
      final byRef = {for (final e in controller.entries) e.ref: e};
      expect(byRef[_a]!.canAskStaff, isTrue);
      expect(byRef[_b]!.canAskStaff, isFalse);
    });
  });

  group('Worked for me', () {
    test("marks the active person, leaves other people's marks, and "
        'unmarks', () async {
      // Arrange: the owner unnamed, Dana earlier.
      history.seed(
        _visit(_a, DateTime.utc(2026), profile: _sesame, workedFor: ['Dana']),
      );
      final controller = build(AppSettings(profile: _sesame));
      await controller.load(bantoMode: true);

      // Act & Assert: Dana is not the active person.
      expect(controller.isWorkedFor(controller.entries.single), isFalse);
      await controller.setWorked(_a, worked: true);
      expect(controller.workedForOf(controller.entries.single), <String>[
        workedForSelf,
      ]);
      expect((await history.read(_a))!.workedFor, <String>[
        'Dana',
        workedForSelf,
      ]);
      await controller.setWorked(_a, worked: false);
      expect(controller.isWorkedFor(controller.entries.single), isFalse);
      expect((await history.read(_a))!.workedFor, <String>['Dana']);
    });

    test(
      'in a group the mark is per person: worked for Dana and Noa',
      () async {
        // Arrange
        final dana = NamedProfile(id: 'dana', name: 'Dana', profile: _lactose);
        history.seed(_visit(_a, DateTime.utc(2026), profile: _sesame));
        final controller = build(
          AppSettings(
            profile: _sesame,
            primaryProfileName: 'Noa',
            otherProfiles: <NamedProfile>[dana],
            activeProfileIds: const <String>[NamedProfile.primaryId, 'dana'],
          ),
        );
        await controller.load(bantoMode: true);

        // Act
        await controller.setWorked(_a, worked: true);

        // Assert
        expect(controller.workedForOf(controller.entries.single), <String>[
          'Noa',
          'Dana',
        ]);
      },
    );

    test('does nothing for a keto-only profile or an unknown venue', () async {
      // Arrange
      history.seed(_visit(_a, DateTime.utc(2026)));
      final keto = build(const AppSettings());
      await keto.load(bantoMode: true);

      // Act
      await keto.setWorked(_a, worked: true);
      final strict = build(AppSettings(profile: _sesame));
      await strict.load(bantoMode: true);
      await strict.setWorked(_b, worked: true);

      // Assert
      expect(history.workedCalls, isEmpty);
      expect(await history.read(_b), isNull);
    });

    test('the filter narrows the list and orders and counts nothing', () async {
      // Arrange: b is newer and unmarked, a is older and marked.
      history
        ..seed(
          _visit(
            _a,
            DateTime.utc(2025),
            profile: _sesame,
            workedFor: <String>[workedForSelf],
          ),
        )
        ..seed(_visit(_b, DateTime.utc(2026), profile: _sesame));
      final controller = build(AppSettings(profile: _sesame));
      await controller.load(bantoMode: true);
      expect(controller.entries.map((e) => e.ref), <VenueRef>[_b, _a]);
      expect(controller.hasWorkedMarks, isTrue);

      // Act
      controller.setWorkedOnly(value: true);

      // Assert
      expect(controller.entries.map((e) => e.ref), <VenueRef>[_a]);

      // Act: the last mark goes.
      await controller.setWorked(_a, worked: false);

      // Assert: the filter lets go with it.
      expect(controller.workedOnly, isFalse);
      expect(controller.entries, hasLength(2));
    });

    test('a hidden row keeps its place for an undo', () async {
      // Arrange
      history.seed(
        _visit(
          _a,
          DateTime.utc(2026),
          profile: _sesame,
          workedFor: <String>[workedForSelf],
        ),
      );
      final controller = build(AppSettings(profile: _sesame));
      await controller.load(bantoMode: true);
      controller.setWorkedOnly(value: true);

      // Act
      final removed = controller.hide(_a)!;
      controller.restore(removed);

      // Assert
      expect(controller.entries.single.ref, _a);
    });

    test('a keto build carries no marks', () async {
      // Arrange
      history.seed(
        _visit(_a, DateTime.utc(2026), workedFor: <String>[workedForSelf]),
      );
      final controller = build(AppSettings(profile: _sesame));

      // Act
      await controller.load();

      // Assert
      expect(controller.hasWorkedMarks, isFalse);
      expect(controller.workedForOf(controller.entries.single), isEmpty);
    });
  });
}
