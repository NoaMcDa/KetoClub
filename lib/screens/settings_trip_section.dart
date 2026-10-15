import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/screens/trip_briefing_screen.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:provider/provider.dart';

/// The trip row's "Choose a destination" tile, shown while no trip is on.
const Key settingsTripPickKey = Key('settingsTripPick');

/// The active trip's row, which opens the briefing.
const Key settingsTripActiveKey = Key('settingsTripActive');

/// The active trip's "Change destination" button.
const Key settingsTripChangeKey = Key('settingsTripChange');

/// The active trip's one-tap "Turn off trip mode" button.
const Key settingsTripOffKey = Key('settingsTripOff');

/// The destination picker's row for [destination].
Key tripDestinationOptionKey(TripDestination destination) =>
    ValueKey<String>('tripDestinationOption_${destination.name}');

/// Opens the destination picker (ALG-13): one row per [TripDestination],
/// [current] marked. Answers the pick, or null when dismissed.
Future<TripDestination?> showTripDestinationPicker(
  BuildContext context, {
  TripDestination? current,
}) => showKetoClubSheet<TripDestination>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) {
    final l10n = AppLocalizations.of(sheetContext)!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
              child: Text(
                l10n.tripPickerTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final destination in TripDestination.values)
              ListTile(
                key: tripDestinationOptionKey(destination),
                title: Text(tripDestinationName(l10n, destination)),
                trailing: destination == current
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(destination),
              ),
          ],
        ),
      ),
    );
  },
);

/// The rows of Settings' "Trip mode" group (Banto, ALG-13, issue #355).
/// With no trip, one row that opens [showTripDestinationPicker]. With a
/// trip, its row — which opens the [TripBriefingScreen] — then "Change
/// destination" and the one-tap "Turn off trip mode". Settings draws the
/// group, its heading and its note around these rows.
class SettingsTripRows extends StatelessWidget {
  /// Creates the rows.
  const new({
    this.screenBrightness = const NoOpScreenBrightness(),
    this.menuSharer,
    super.key,
  });

  /// Passed to the briefing, for its chef card.
  final ScreenBrightness screenBrightness;

  /// Passed to the briefing, for sharing its chef card.
  final MenuSharer? menuSharer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<SettingsController>();
    final busy = controller.isBusy;
    final trip = controller.tripDestination;
    if (trip == null) {
      return ListTile(
        key: settingsTripPickKey,
        leading: const Icon(Icons.flight_takeoff),
        title: Text(l10n.settingsTripPick),
        trailing: const Icon(Icons.chevron_right),
        onTap: busy ? null : () => unawaited(_pick(context, controller)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: settingsTripActiveKey,
          leading: const Icon(Icons.flight),
          title: Text(l10n.settingsTripActive(tripDestinationName(l10n, trip))),
          subtitle: Text(l10n.settingsTripBriefing),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => unawaited(_openBriefing(context, controller)),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 8),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: settingsTripChangeKey,
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: Text(l10n.settingsTripChange),
                onPressed: busy
                    ? null
                    : () => unawaited(_pick(context, controller)),
              ),
              TextButton.icon(
                key: settingsTripOffKey,
                icon: const Icon(Icons.close),
                label: Text(l10n.settingsTripOff),
                onPressed: busy
                    ? null
                    : () => unawaited(controller.setTripDestination(null)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pick(
    BuildContext context,
    SettingsController controller,
  ) async {
    final picked = await showTripDestinationPicker(
      context,
      current: controller.tripDestination,
    );
    if (picked == null) return;
    await controller.setTripDestination(picked);
  }

  /// Pushes the briefing with [controller] provided to it: Settings' own
  /// provider sits on its route, which a pushed route does not inherit.
  Future<void> _openBriefing(
    BuildContext context,
    SettingsController controller,
  ) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: TripBriefingScreen(
          screenBrightness: screenBrightness,
          menuSharer: menuSharer,
        ),
      ),
    ),
  );
}
