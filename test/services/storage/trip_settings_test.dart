// Trip mode's destination in the settings (Banto, ALG-13, issue #355):
// written only while a trip is on, so a keto install's stored record stays
// byte-identical; read tolerantly; switched on and off through the
// controller with one call.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/services/storage/settings_store.dart';
import 'package:ketoclub/state/settings_controller.dart';

import '../../fakes/fake_menu_repository.dart';
import '../../fakes/fake_settings_store.dart';

void main() {
  group('AppSettings.tripDestination', () {
    test('defaults to no trip, and the default record writes no trip key', () {
      expect(const AppSettings().tripDestination, isNull);
      expect(const AppSettings().tripJurisdiction, isNull);
      expect(
        const AppSettings().toJson().containsKey('tripDestination'),
        isFalse,
      );
    });

    test('is written by name while a trip is on, and read back', () {
      for (final destination in TripDestination.values) {
        final settings = AppSettings(tripDestination: destination);
        final json = settings.toJson();
        expect(json['tripDestination'], destination.name);
        final decoded = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
        expect(AppSettings.tryFrom(decoded), settings);
      }
    });

    test('the jurisdiction follows the destination', () {
      expect(
        const AppSettings(tripDestination: TripDestination.france)
            .tripJurisdiction,
        Jurisdiction.eu,
      );
    });

    test('an unknown or non-string value reads as no trip, keeping the rest '
        'of the record', () {
      for (final raw in <Object?>[
        'narnia',
        3,
        true,
        <String>['japan'],
      ]) {
        final json = const AppSettings(seedOilFree: true).toJson()
          ..['tripDestination'] = raw;
        final read = AppSettings.tryFrom(json);
        expect(read, isNotNull, reason: '$raw');
        expect(read!.tripDestination, isNull, reason: '$raw');
        expect(read.seedOilFree, isTrue);
      }
    });

    test('copyWith keeps, sets and clears it', () {
      const on = AppSettings(tripDestination: TripDestination.japan);
      expect(
        on.copyWith(seedOilFree: true).tripDestination,
        TripDestination.japan,
      );
      expect(on.copyWith(tripDestination: null).tripDestination, isNull);
      expect(
        const AppSettings()
            .copyWith(tripDestination: TripDestination.spain)
            .tripDestination,
        TripDestination.spain,
      );
    });

    test('takes part in equality, and toString never names the place', () {
      const on = AppSettings(tripDestination: TripDestination.japan);
      expect(on, isNot(const AppSettings()));
      expect(on.hashCode, isNot(const AppSettings().hashCode));
      expect(on.toString(), contains('trip: true'));
      expect(on.toString().toLowerCase(), isNot(contains('japan')));
    });
  });

  group('SettingsController.setTripDestination', () {
    test('starts a trip and switches it off with one call each', () async {
      final store = FakeSettingsStore();
      final controller = SettingsController(store, FakeMenuRepository());
      await controller.load();

      await controller.setTripDestination(TripDestination.germany);
      expect(controller.tripDestination, TripDestination.germany);
      expect((await store.read()).tripDestination, TripDestination.germany);

      await controller.setTripDestination(null);
      expect(controller.tripDestination, isNull);
      expect((await store.read()).tripDestination, isNull);
    });

    test('is a no-op, with no write, when nothing changes', () async {
      final store = FakeSettingsStore(
        initial: const AppSettings(tripDestination: TripDestination.italy),
      );
      final controller = SettingsController(store, FakeMenuRepository());
      await controller.load();
      final writes = store.writeCallCount;

      await controller.setTripDestination(TripDestination.italy);

      expect(store.writeCallCount, writes);
    });

    test('touches nothing else in the settings', () async {
      final store = FakeSettingsStore(
        initial: const AppSettings(dairyFree: true, netCarbLimitGrams: 12),
      );
      final controller = SettingsController(store, FakeMenuRepository());
      await controller.load();

      await controller.setTripDestination(TripDestination.japan);

      final saved = await store.read();
      expect(
        saved,
        const AppSettings(
          dairyFree: true,
          netCarbLimitGrams: 12,
          tripDestination: TripDestination.japan,
        ),
      );
    });
  });
}
