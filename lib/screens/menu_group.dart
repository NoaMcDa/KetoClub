/// The menu screen's group-profile surfaces (Banto; the Allergens epic,
/// ALG-12, issue #354), kept out of `menu_screen.dart` so that file only
/// calls them: the combine control and its sheet, the "N dishes fit
/// everyone" header line and the per-person breakdown on each card.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide MenuController;
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/analysis.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/screens/premium_gate.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/state/menu_controller.dart';
import 'package:ketoclub/utils/premium_gates.dart';
import 'package:ketoclub/utils/profile_wording.dart';
import 'package:ketoclub/widgets/group_breakdown_line.dart';
import 'package:ketoclub/widgets/group_combine_sheet.dart';
import 'package:ketoclub/widgets/profile_summary_line.dart';

/// The menu header's "N dishes fit everyone" line, public so a test can
/// find it.
const Key menuGroupFitsKey = ValueKey<String>('menuGroupFits');

/// What the Filters row shows above its fields in a Banto build: the
/// combine control naming the people when the device holds more than one
/// profile, else the restriction summary of a non-empty profile, else
/// nothing. [onEditProfile] opens Settings; the combine control opens
/// [openGroupCombine].
Widget? menuProfileSummary(
  BuildContext context,
  MenuController controller, {
  required VoidCallback onEditProfile,
  required ScreenBrightness screenBrightness,
  required MenuSharer menuSharer,
}) {
  if (controller.allProfiles.length > 1) {
    return GroupCombineControl(
      people: controller.people,
      onTap: () => unawaited(
        openGroupCombine(
          context,
          controller,
          onManage: onEditProfile,
          screenBrightness: screenBrightness,
          menuSharer: menuSharer,
        ),
      ),
    );
  }
  if (controller.profile.isEmpty) return null;
  return ProfileSummaryLine(profile: controller.profile, onTap: onEditProfile);
}

/// Opens the combine sheet over [controller]'s profiles and applies what
/// the user checks ([MenuController.setActiveProfiles]). Its chef card
/// button opens the card with a section per checked person.
Future<void> openGroupCombine(
  BuildContext context,
  MenuController controller, {
  required VoidCallback onManage,
  required ScreenBrightness screenBrightness,
  required MenuSharer menuSharer,
}) async {
  final ids = await showGroupCombineSheet(
    context: context,
    profiles: controller.allProfiles,
    active: controller.people,
    onManage: onManage,
    onChefCard: (people) => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChefCardScreen(
          profile: people.first.profile,
          people: people,
          screenBrightness: screenBrightness,
          menuSharer: menuSharer,
        ),
      ),
    ),
  );
  if (ids == null || !context.mounted) return;
  // Checking several people is Premium (ALG-18); the choice already saved,
  // and narrowing it, never are.
  final allowed = await passPremiumGate(
    context,
    PremiumFeature.groupProfiles,
    locks: (access) => PremiumGates.locksCheckingPeople(
      access,
      current: <String>[for (final person in controller.people) person.id],
      next: ids,
    ),
  );
  if (!allowed) return;
  await controller.setActiveProfiles(ids);
}

/// The header line "N dishes fit everyone" for a group whose menu is
/// worded in states and analysed; null otherwise. A group holding a
/// strict entry reads "no trigger found for anyone" instead: the epic's
/// floor never lets an allergen read as fitting.
Widget? groupFitsEveryoneLine(
  BuildContext context,
  AppLocalizations l10n,
  MenuController controller,
) {
  if (!controller.isGroup ||
      !controller.wording.usesStates ||
      controller.analysis is! MenuAnalysed) {
    return null;
  }
  final count = controller.stateCounts.green;
  final text = controller.wording == ProfileWording.strict
      ? l10n.groupFitsEveryoneStrict(count)
      : l10n.groupFitsEveryone(count);
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      text,
      key: menuGroupFitsKey,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

/// The per-person breakdown for the dish [dishId] when the menu is read
/// for a group; null for one person.
Widget? groupBreakdownFor(MenuController controller, String dishId) {
  final people = controller.breakdownFor(dishId);
  return people == null ? null : GroupBreakdownLine(people: people);
}
