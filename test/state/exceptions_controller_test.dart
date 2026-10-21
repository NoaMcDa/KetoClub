// Editing a restriction's exceptions through SettingsController (Banto,
// issue #417): the user's own profile and another person's, written to the
// store and read back, capped by the model.

import 'package:flutter_test/flutter_test.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/named_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/state/settings_controller.dart';

import '../fakes/fake_menu_repository.dart';
import '../fakes/fake_settings_store.dart';

void main() {
  late FakeSettingsStore store;
  late SettingsController controller;

  setUp(() async {
    store = FakeSettingsStore();
    controller = SettingsController(store, FakeMenuRepository());
    await controller.load();
  });

  group('setExceptionsFor', () {
    test('for the primary id is setExceptions, and round-trips through the '
        'store', () async {
      // Arrange
      await controller.addRestriction(RestrictionId.treeNuts);

      // Act
      await controller.setExceptionsFor(
        NamedProfile.primaryId,
        RestrictionId.treeNuts,
        <String>['almond', 'שקדים'],
      );

      // Assert
      expect(
        (await store.read()).profile
            .entryFor(RestrictionId.treeNuts)!
            .exceptions,
        <String>['almond', 'שקדים'],
      );
    });

    test("caps the list at the model's maximum", () async {
      // Arrange
      await controller.addRestriction(RestrictionId.treeNuts);

      // Act
      await controller.setExceptionsFor(
        NamedProfile.primaryId,
        RestrictionId.treeNuts,
        <String>['a', 'b', 'c', 'd', 'e', 'f', 'g'],
      );

      // Assert
      expect(
        controller.profile.entryFor(RestrictionId.treeNuts)!.exceptions,
        hasLength(ProfileEntry.maxExceptions),
      );
    });

    test('edits another person and leaves the primary alone', () async {
      // Arrange
      await controller.addRestriction(RestrictionId.treeNuts);
      final id = (await controller.addProfile('Dana'))!;
      await controller.addRestrictionTo(id, RestrictionId.treeNuts);

      // Act
      await controller.setExceptionsFor(id, RestrictionId.treeNuts, <String>[
        ' cashew ',
        'cashew',
      ]);

      // Assert
      final saved = await store.read();
      expect(
        saved.otherProfiles.single.profile
            .entryFor(RestrictionId.treeNuts)!
            .exceptions,
        <String>['cashew'],
      );
      expect(
        saved.profile.entryFor(RestrictionId.treeNuts)!.exceptions,
        isEmpty,
      );
    });

    test('writes nothing for an unknown person or an absent '
        'restriction', () async {
      // Arrange
      final id = (await controller.addProfile('Dana'))!;
      final before = store.writeCallCount;

      // Act
      await controller.setExceptionsFor(
        'nobody',
        RestrictionId.treeNuts,
        <String>['almond'],
      );
      await controller.setExceptionsFor(id, RestrictionId.soy, <String>['x']);

      // Assert
      expect(store.writeCallCount, before);
      expect(controller.profileById(id)!.profile, DietaryProfile.empty);
    });
  });
}
