// The two dismissal keys of the empty-profile notice (Banto, issue #421):
// absent by default, so a keto install's stored record stays
// byte-identical; written only when set; read tolerantly; and the two
// writes behind the notice.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/profile_nudge_actions.dart';

import '../../fakes/fake_settings_store.dart';

const String _menuKey = 'profileNudgeMenuDismissed';
const String _discoveryKey = 'profileNudgeDiscoveryDismissed';

void main() {
  group('AppSettings nudge dismissals', () {
    test('default to not dismissed, and the default record writes neither '
        'key', () {
      const settings = AppSettings();

      expect(settings.menuNudgeDismissed, isFalse);
      expect(settings.discoveryNudgeDismissed, isFalse);
      expect(settings.toJson().containsKey(_menuKey), isFalse);
      expect(settings.toJson().containsKey(_discoveryKey), isFalse);
    });

    test('the keto record is byte-identical to the one before the keys '
        'existed', () {
      // The exact record a keto install has always stored.
      expect(
        jsonEncode(const AppSettings().toJson()),
        '{"languageTag":null,"filter":"all","estimationConsentGiven":true,'
        '"lastVenue":null,"themeMode":"system","netCarbLimitGrams":6,'
        '"seedOilFree":false,"dairyFree":false,"carnivoreOnly":false,'
        '"lastFilter":null,"disclosureSeen":false}',
      );
    });

    test('each key is written alone, only when set, and round-trips', () {
      const menu = AppSettings(menuNudgeDismissed: true);
      const discovery = AppSettings(discoveryNudgeDismissed: true);

      expect(menu.toJson()[_menuKey], isTrue);
      expect(menu.toJson().containsKey(_discoveryKey), isFalse);
      expect(discovery.toJson()[_discoveryKey], isTrue);
      expect(discovery.toJson().containsKey(_menuKey), isFalse);
      for (final settings in <AppSettings>[menu, discovery]) {
        final decoded = jsonDecode(jsonEncode(settings.toJson()));
        expect(AppSettings.tryFrom(decoded as Map<String, Object?>), settings);
      }
    });

    test('a non-boolean value reads as not dismissed, keeping the rest', () {
      for (final raw in <Object?>['yes', 1, null, <Object?>[]]) {
        final json = const AppSettings(seedOilFree: true).toJson()
          ..[_menuKey] = raw
          ..[_discoveryKey] = raw;

        final read = AppSettings.tryFrom(json);

        expect(read, isNotNull, reason: '$raw');
        expect(read!.menuNudgeDismissed, isFalse, reason: '$raw');
        expect(read.discoveryNudgeDismissed, isFalse, reason: '$raw');
        expect(read.seedOilFree, isTrue, reason: '$raw');
      }
    });

    test('nudgeDismissed answers per surface', () {
      const settings = AppSettings(menuNudgeDismissed: true);

      expect(settings.nudgeDismissed(ProfileNudgeSurface.menu), isTrue);
      expect(settings.nudgeDismissed(ProfileNudgeSurface.discovery), isFalse);
    });

    test('copyWith, equality and the hash follow both flags', () {
      const base = AppSettings();
      final menu = base.copyWith(menuNudgeDismissed: true);
      final discovery = base.copyWith(discoveryNudgeDismissed: true);

      expect(base.copyWith(), base);
      expect(menu, isNot(base));
      expect(discovery, isNot(base));
      expect(menu, isNot(discovery));
      expect(menu.copyWith().hashCode, menu.hashCode);
      expect(menu.copyWith(menuNudgeDismissed: false), base);
    });
  });

  group('dismissProfileNudge', () {
    test('writes only the surface dismissed, and only once', () async {
      final store = FakeSettingsStore();

      await dismissProfileNudge(store, ProfileNudgeSurface.menu);
      await dismissProfileNudge(store, ProfileNudgeSurface.menu);

      final settings = await store.read();
      expect(settings.menuNudgeDismissed, isTrue);
      expect(settings.discoveryNudgeDismissed, isFalse);
      expect(store.writeCallCount, 1);
    });

    test('dismisses Discovery on its own', () async {
      final store = FakeSettingsStore();

      await dismissProfileNudge(store, ProfileNudgeSurface.discovery);

      final settings = await store.read();
      expect(settings.discoveryNudgeDismissed, isTrue);
      expect(settings.menuNudgeDismissed, isFalse);
    });
  });

  group('addToProfile', () {
    test(
      'adds the restriction and says the helper sheet is due, once',
      () async {
        final store = FakeSettingsStore();

        final first = await addToProfile(store, id: RestrictionId.sesame);
        final second = await addToProfile(store, id: RestrictionId.lactose);

        final settings = await store.read();
        expect(first, isTrue);
        expect(second, isFalse);
        expect(settings.helperToolSeen, isTrue);
        expect(
          settings.profile.entries.map((entry) => entry.restrictionId),
          <RestrictionId>[RestrictionId.sesame, RestrictionId.lactose],
        );
      },
    );

    test("adds one of the user's own words", () async {
      final store = FakeSettingsStore();

      final due = await addToProfile(store, term: 'mango');

      expect((await store.read()).profile.customTerms, <String>['mango']);
      expect(due, isTrue);
    });

    test('changes nothing, and writes nothing, for a restriction already '
        'held or no pick', () async {
      final store = FakeSettingsStore(
        initial: AppSettings(
          profile: DietaryProfile.empty.withEntry(RestrictionId.sesame),
          helperToolSeen: true,
        ),
      );

      final held = await addToProfile(store, id: RestrictionId.sesame);
      final none = await addToProfile(store);

      expect(held, isFalse);
      expect(none, isFalse);
      expect(store.writeCallCount, 0);
    });
  });
}
