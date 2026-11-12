import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/place.dart';
import 'package:ketoclub/services/place/place_search_service.dart';
import 'package:ketoclub/utils/known_places.dart';
import 'package:ketoclub/widgets/app_sheet.dart';
import 'package:ketoclub/widgets/failure_copy.dart';

/// What the location picker was closed with (issue #443).
///
/// Not constructed directly; use [LocationPickDevice], [LocationPickPlace]
/// or [LocationPickStreet].
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

/// A street a street search found (issue #449): look around [street].
@immutable
final class LocationPickStreet extends LocationPick {
  /// Creates the answer for [street].
  const new(this.street);

  /// The street the user picked.
  final StreetPlace street;
}

/// Runs one street search for what the user typed (issue #449); the
/// screen passes `VenueSearchController.searchStreets` in the UI
/// language.
typedef StreetSearch = Future<PlaceSearchResult> Function(String query);

/// The shortest typed text, trimmed, for which the picker offers a street
/// search (issue #449): fewer letters name too many streets to be worth
/// sending anywhere.
const int streetSearchMinLength = 3;

/// Opens the location picker (issue #443) and completes with what the user
/// picked, or null when they dismissed it.
///
/// [selected] is the place being looked around now, marked in the list;
/// null when the position is the device's own, a street, or there is none.
/// [searchStreets] enables the street search (issue #449), and
/// [streetSearchThroughBackend] says whether it goes to KetoClub's server
/// first, which the action's caption names.
Future<LocationPick?> showLocationPickerSheet(
  BuildContext context, {
  required KnownPlace? selected,
  StreetSearch? searchStreets,
  bool streetSearchThroughBackend = false,
}) => showKetoClubSheet<LocationPick>(
  context: context,
  showDragHandle: true,
  builder: (context) => LocationPickerSheet(
    selected: selected,
    searchStreets: searchStreets,
    streetSearchThroughBackend: streetSearchThroughBackend,
  ),
);

/// The Discovery screen's location picker (issue #443): "Use my current
/// location" above a searchable list of the places in
/// `utils/known_places.dart`, each named in the UI language, and — once
/// the text is at least [streetSearchMinLength] characters — one explicit
/// "Search streets" action (issue #449, architecture.md D28).
///
/// **Typing sends nothing.** The city list is filtered on the device as
/// the user types; the text leaves the device only when the user taps the
/// street action, which runs exactly one [searchStreets] call and says
/// beneath it where the text goes. Editing the text afterwards drops the
/// answer, and a late answer to older text is ignored.
///
/// Pops with a [LocationPick] and neither reads a position nor searches
/// for venues; the screen hands the answer to its controller. The city
/// search matches a place's English and Hebrew names alike, whatever the
/// UI language.
class LocationPickerSheet extends StatefulWidget {
  /// Creates the sheet with [selected] marked in the list; a null
  /// [searchStreets] offers cities only.
  const new({
    required this.selected,
    this.searchStreets,
    this.streetSearchThroughBackend = false,
    super.key,
  });

  /// The place being looked around now, or null when there is none.
  final KnownPlace? selected;

  /// Runs one street search, or null when this build offers none.
  final StreetSearch? searchStreets;

  /// Whether a street search goes to KetoClub's server before Photon.
  final bool streetSearchThroughBackend;

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  String _query = '';

  // The street search for the current text: the text it was run for,
  // whether it is still in flight, and its answer once it lands. Reset on
  // every edit, and [_streetRun] drops an answer to older text.
  String? _streetQuery;
  bool _streetSearching = false;
  PlaceSearchResult? _streetResult;
  int _streetRun = 0;

  void _onChanged(String value) {
    setState(() {
      _query = value;
      _streetRun++;
      _streetQuery = null;
      _streetSearching = false;
      _streetResult = null;
    });
  }

  Future<void> _searchStreets() async {
    final search = widget.searchStreets;
    if (search == null) return;
    final query = _query.trim();
    final run = ++_streetRun;
    setState(() {
      _streetQuery = query;
      _streetSearching = true;
      _streetResult = null;
    });
    final result = await search(query);
    if (!mounted || run != _streetRun) return;
    setState(() {
      _streetSearching = false;
      _streetResult = result;
    });
  }

  bool get _offersStreets =>
      widget.searchStreets != null &&
      _query.trim().runes.length >= streetSearchMinLength;

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
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: l10n.locationPickerSearchLabel,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (places.isEmpty)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          20,
                          8,
                          20,
                          16,
                        ),
                        child: Text(
                          l10n.locationPickerNoMatch,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    for (final place in places)
                      _placeTile(context, place, language),
                    if (_offersStreets) ..._streetSection(context, l10n),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeTile(BuildContext context, KnownPlace place, String language) {
    final isSelected = place.id == widget.selected?.id;
    return ListTile(
      leading: const Icon(Icons.place_outlined),
      title: Text(place.nameFor(language)),
      selected: isSelected,
      trailing: isSelected ? const Icon(Icons.check) : null,
      onTap: () =>
          Navigator.of(context).pop<LocationPick>(LocationPickPlace(place)),
    );
  }

  /// The street action, or what it is doing or found: the action with its
  /// caption before a search, progress while one runs, then the matches,
  /// "no street found", or the failure with a retry.
  List<Widget> _streetSection(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final query = _streetQuery;
    final result = _streetResult;
    const padding = EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16);
    if (query == null) {
      return [
        const Divider(),
        ListTile(
          leading: const Icon(Icons.travel_explore),
          title: Text(l10n.locationPickerStreetSearch(_query.trim())),
          subtitle: Text(
            widget.streetSearchThroughBackend
                ? l10n.locationPickerStreetCaptionBackend
                : l10n.locationPickerStreetCaptionDirect,
          ),
          onTap: _searchStreets,
        ),
      ];
    }
    if (_streetSearching || result == null) {
      return [
        const Divider(),
        Padding(
          padding: padding,
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(l10n.locationPickerStreetSearching)),
            ],
          ),
        ),
      ];
    }
    return switch (result) {
      PlacesFound(:final places) when places.isEmpty => [
        const Divider(),
        Padding(
          padding: padding,
          child: Text(
            l10n.locationPickerStreetNoMatch(query),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
      PlacesFound(:final places) => [
        const Divider(),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 0),
          child: Text(
            l10n.locationPickerStreetsHeading,
            style: theme.textTheme.titleSmall,
          ),
        ),
        for (final street in places)
          ListTile(
            leading: const Icon(Icons.signpost_outlined),
            title: Text(street.label),
            onTap: () =>
                Navigator.of(context)
                    .pop<LocationPick>(LocationPickStreet(street)),
          ),
      ],
      PlaceSearchFailed(:final reason) => [
        const Divider(),
        Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                placeSearchFailureMessage(reason, l10n),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _searchStreets,
                child: Text(l10n.actionRetry),
              ),
            ],
          ),
        ),
      ],
    };
  }
}
