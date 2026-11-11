import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/utils/known_places.dart';
import 'package:ketoclub/widgets/app_sheet.dart';

/// What the location picker was closed with (issue #443).
///
/// Not constructed directly; use [LocationPickDevice] or
/// [LocationPickPlace].
@immutable
sealed class LocationPick {
  /// Subclasses only.
  const new();
}

/// "Use my current location": ask the device where it is.
@immutable
final class LocationPickDevice extends LocationPick {
  /// Creates the "use the device's position" answer.
  const new();
}

/// A place from the list: look around [place].
@immutable
final class LocationPickPlace extends LocationPick {
  /// Creates the answer for [place].
  const new(this.place);

  /// The place the user picked.
  final KnownPlace place;
}

/// Opens the location picker (issue #443) and completes with what the user
/// picked, or null when they dismissed it.
///
/// [selected] is the place being looked around now, marked in the list;
/// null when the position is the device's own or there is none.
Future<LocationPick?> showLocationPickerSheet(
  BuildContext context, {
  required KnownPlace? selected,
}) => showKetoClubSheet<LocationPick>(
  context: context,
  showDragHandle: true,
  builder: (context) => LocationPickerSheet(selected: selected),
);

/// The Discovery screen's location picker (issue #443): "Use my current
/// location" above a searchable list of the places in
/// `utils/known_places.dart`, each named in the UI language.
///
/// Pure UI: it pops with a [LocationPick] and neither reads a position nor
/// searches for venues; the screen hands the answer to its controller.
/// The search matches a place's English and Hebrew names alike, whatever
/// the UI language.
class LocationPickerSheet extends StatefulWidget {
  /// Creates the sheet with [selected] marked in the list.
  const new({required this.selected, super.key});

  /// The place being looked around now, or null when there is none.
  final KnownPlace? selected;

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final places = searchKnownPlaces(_query);
    final media = MediaQuery.of(context);
    return SafeArea(
      child: Padding(
        // The sheet rides above the keyboard rather than under it.
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          // Short enough that the page behind stays in view, so the sheet
          // reads as a sheet.
          constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
                child: Text(
                  l10n.locationPickerTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.my_location),
                title: Text(l10n.locationPickerUseDevice),
                onTap: () =>
                    Navigator.of(context)
                        .pop<LocationPick>(const LocationPickDevice()),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 8),
                child: TextField(
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: l10n.locationPickerSearchLabel,
                  ),
                ),
              ),
              if (places.isEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 24),
                  child: Text(
                    l10n.locationPickerNoMatch,
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: places.length,
                    itemBuilder: (context, i) {
                      final place = places[i];
                      final isSelected = place.id == widget.selected?.id;
                      return ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(place.nameFor(language)),
                        selected: isSelected,
                        trailing: isSelected ? const Icon(Icons.check) : null,
                        onTap: () =>
                            Navigator.of(context)
                                .pop<LocationPick>(LocationPickPlace(place)),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
