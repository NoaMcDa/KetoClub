import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ketoclub/l10n/generated/app_localizations.dart';
import 'package:ketoclub/models/dietary_profile.dart';
import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/models/trip_destination.dart';
import 'package:ketoclub/screens/chef_card_screen.dart';
import 'package:ketoclub/services/platform/menu_sharer.dart';
import 'package:ketoclub/services/platform/screen_brightness.dart';
import 'package:ketoclub/state/settings_controller.dart';
import 'package:ketoclub/utils/allergens/group_evaluator.dart';
import 'package:ketoclub/utils/allergens/taxonomy.dart';
import 'package:ketoclub/utils/allergens/trip_lexicon.dart';
import 'package:ketoclub/utils/allergens/trip_regulation.dart';
import 'package:ketoclub/widgets/content_width.dart';
import 'package:ketoclub/widgets/restriction_picker_sheet.dart';
import 'package:provider/provider.dart';

/// The row of [id]'s regulation hint on the briefing.
Key tripHintRowKey(RestrictionId id) =>
    ValueKey<String>('tripHintRow_${id.name}');

/// The row of the lexicon entry whose first term is [term].
Key tripLexiconRowKey(String term) => ValueKey<String>('tripLexiconRow_$term');

/// The briefing's "Open my chef card" button.
const Key tripBriefingChefCardKey = Key('tripBriefingChefCard');

/// The briefing's "Turn off trip mode" button.
const Key tripBriefingOffKey = Key('tripBriefingOff');

/// The hints section's empty state (no strict entry).
const Key tripBriefingRulesEmptyKey = Key('tripBriefingRulesEmpty');

/// The lexicon section's empty state.
const Key tripBriefingLexiconEmptyKey = Key('tripBriefingLexiconEmpty');

/// [destination]'s name in the UI language.
String tripDestinationName(
  AppLocalizations l10n,
  TripDestination destination,
) => switch (destination) {
  TripDestination.israel => l10n.tripCountryIsrael,
  TripDestination.unitedStates => l10n.tripCountryUnitedStates,
  TripDestination.unitedKingdom => l10n.tripCountryUnitedKingdom,
  TripDestination.france => l10n.tripCountryFrance,
  TripDestination.italy => l10n.tripCountryItaly,
  TripDestination.spain => l10n.tripCountrySpain,
  TripDestination.germany => l10n.tripCountryGermany,
  TripDestination.japan => l10n.tripCountryJapan,
};

/// [hint] in the UI language. None of them says a dish is safe, and every
/// one ends on asking (file 09 §6).
String tripHintText(AppLocalizations l10n, RegulationHint hint) =>
    switch (hint) {
      RegulationHint.restaurantMustTell => l10n.tripHintRestaurantMustTell,
      RegulationHint.packagedOnly => l10n.tripHintPackagedOnly,
      RegulationHint.packagedOnlyLargeChains =>
        l10n.tripHintPackagedOnlyLargeChains,
      RegulationHint.notRegulated => l10n.tripHintNotRegulated,
    };

/// The pre-trip briefing (Banto, ALG-13, issue #355): for the active trip
/// and the profiles menus are read for (their union), what the
/// destination's allergen law obliges a restaurant to tell about each
/// strict entry ([TripRegulation.hintFor]); the local dishes and
/// ingredients that hide the profile's restrictions there
/// ([TripLexicon.briefing]); and the chef card.
///
/// Everything on it is composed on the device from the stored profile and
/// the destination: nothing is fetched, so it opens, and so does its chef
/// card, with no connection — the "pre-cached" card of file 10 §ALG-13.
/// The card stays Hebrew or English; a card in the local language is not
/// built yet.
///
/// Reads its [SettingsController] from `provider`, pushed by Settings'
/// trip rows (`settings_trip_section.dart`) with Settings' own controller.
class TripBriefingScreen extends StatelessWidget {
  /// Creates the briefing.
  const new({
    this.screenBrightness = const NoOpScreenBrightness(),
    this.menuSharer,
    super.key,
  });

  /// Raised while the chef card opened from here is on screen.
  final ScreenBrightness screenBrightness;

  /// Shares the chef card as text; null leaves its Share button out.
  final MenuSharer? menuSharer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<SettingsController>();
    final trip = controller.tripDestination;
    if (trip == null) {
      return Scaffold(appBar: AppBar(title: Text(l10n.settingsTrip)));
    }
    final people = controller.activeProfiles;
    final profile = GroupEvaluator.union(<DietaryProfile>[
      for (final named in people) named.profile,
    ]);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tripBriefingTitle(tripDestinationName(l10n, trip))),
      ),
      body: ContentWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(l10n.tripBriefingRulesSection),
              ..._hints(context, l10n, profile, trip),
              const SizedBox(height: 24),
              _Heading(l10n.tripBriefingLexiconSection),
              Text(
                l10n.tripBriefingLexiconNote,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              ..._lexicon(context, l10n, profile, trip),
              const SizedBox(height: 24),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: tripBriefingChefCardKey,
                  icon: const Icon(Icons.restaurant_menu),
                  label: Text(l10n.tripBriefingChefCard),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ChefCardScreen(
                        profile: profile,
                        people: people,
                        screenBrightness: screenBrightness,
                        menuSharer: menuSharer,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.tripBriefingChefCardNote,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: tripBriefingOffKey,
                  icon: const Icon(Icons.close),
                  label: Text(l10n.settingsTripOff),
                  onPressed: () {
                    unawaited(controller.setTripDestination(null));
                    Navigator.maybePop(context);
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(l10n.helperToolSentence, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  /// One row per strict entry of [profile], in taxonomy order: its name
  /// and its hint at [trip]; the empty state when there is none.
  List<Widget> _hints(
    BuildContext context,
    AppLocalizations l10n,
    DietaryProfile profile,
    TripDestination trip,
  ) {
    final locale = Localizations.localeOf(context);
    final rows = <Widget>[
      for (final restriction in restrictionTaxonomy)
        if (profile.contains(restriction.id))
          if (TripRegulation.hintFor(restriction.id, trip) case final hint?)
            ListTile(
              key: tripHintRowKey(restriction.id),
              contentPadding: EdgeInsets.zero,
              title: Text(restrictionDisplayName(restriction, locale)),
              subtitle: Text(tripHintText(l10n, hint)),
            ),
    ];
    if (rows.isNotEmpty) return rows;
    return <Widget>[
      Text(
        l10n.tripBriefingRulesEmpty,
        key: tripBriefingRulesEmptyKey,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ];
  }

  /// One row per lexicon entry hiding something [profile] holds: the
  /// words as a menu there prints them, what the dish is, and which of
  /// the profile's restrictions it may hide; the empty state when none.
  List<Widget> _lexicon(
    BuildContext context,
    AppLocalizations l10n,
    DietaryProfile profile,
    TripDestination trip,
  ) {
    final locale = Localizations.localeOf(context);
    final hebrew = locale.languageCode == 'he';
    final entries = TripLexicon.briefing(trip, profile);
    if (entries.isEmpty) {
      return <Widget>[
        Text(
          l10n.tripBriefingLexiconEmpty,
          key: tripBriefingLexiconEmptyKey,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ];
    }
    String hides(TripLexiconEntry entry) => l10n.tripBriefingHides(
      <String>[
        for (final id in entry.restrictions)
          if (id != RestrictionId.keto && profile.contains(id))
            restrictionDisplayName(restrictionFor(id), locale),
      ].join(', '),
    );
    return <Widget>[
      for (final entry in entries)
        ListTile(
          key: tripLexiconRowKey(entry.terms.first),
          contentPadding: EdgeInsets.zero,
          title: Text(entry.terms.join(' · ')),
          subtitle: Text(
            '${hebrew ? entry.glossHe : entry.glossEn}\n${hides(entry)}',
          ),
        ),
    ];
  }
}

/// A section heading on the briefing.
class _Heading extends StatelessWidget {
  const new(this.text);

  /// The heading.
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
