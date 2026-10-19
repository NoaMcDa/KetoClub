// Architecture test (Banto, ALG-18, issue #360): Premium is reached only
// where something is *added*, never on a surface that reads what is saved.
//
// Gating safety is the research's complaint 4 and the fastest way to lose
// trust. So the gate's API is pinned to the screens that add a
// restriction, a person, a checked person, a destination or a scan, and
// the surfaces that carry what a person already saved — the chef cards,
// the helper copy, confirmations, waiter questions, the Why sheet, the
// evaluators and the menu screen's state — may not mention Premium at all.
// A new caller is a deliberate change to the allowlist below, made beside
// a "never gated" test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The only lib/ files that may call the gate, each adding something.
const _gateCallers = <String>{
  // "Add restriction" in Settings (a second restriction).
  'screens/settings_screen.dart',
  // "Add restriction" for a person (a second restriction).
  'screens/profile_editor_screen.dart',
  // "Add person" and "Import a profile" (group profiles).
  'screens/settings_profiles_section.dart',
  // "Choose a destination" and "Change destination" (trip mode).
  'screens/settings_trip_section.dart',
  // The first-run chips (a second restriction).
  'screens/restriction_onboarding_screen.dart',
  // "Checking for" on the menu (several people).
  'screens/menu_group.dart',
  // Analyse on the Scan tab (scans past the monthly count).
  'screens/scan_screen.dart',
};

/// lib/ files that carry what a person already saved, or the copy that
/// goes with it. None may name Premium, a paywall or an entitlement.
const _neverGated = <String>[
  // The chef card for the profile, for a dish and for a group.
  'screens/chef_card_screen.dart',
  'utils/allergens/chef_card_templates.dart',
  'utils/allergens/group_chef_card.dart',
  'widgets/group_chef_card_view.dart',
  // The liability and helper copy.
  'widgets/helper_tool_sheet.dart',
  'widgets/consent_disclosure_banner.dart',
  // Confirmations (ALG-14).
  'widgets/confirmation_sheet.dart',
  'state/confirmation_controller.dart',
  'utils/allergens/confirmations.dart',
  // Waiter questions and the Waiter Card.
  'utils/allergens/waiter_questions.dart',
  'screens/waiter_card_sheet.dart',
  'widgets/waiter_script_widget.dart',
  // The Why sheet and the dish card.
  'widgets/why_sheet.dart',
  'widgets/dish_card.dart',
  // Every saved entry is evaluated on every menu.
  'state/menu_controller.dart',
  'utils/allergens/profile_evaluator.dart',
  'utils/allergens/group_evaluator.dart',
  'utils/allergens/allergen_matcher.dart',
  'utils/allergens/kitchen_signals.dart',
  // A trip already on keeps its briefing.
  'screens/trip_briefing_screen.dart',
  // Recent, where the post-meal check is offered.
  'screens/saved_screen.dart',
];

final RegExp _premium = RegExp(
  'premium|paywall|entitlement',
  caseSensitive: false,
);

String _read(String relative) => File('lib/$relative').readAsStringSync();

void main() {
  test('only the screens that add something call the gate', () {
    final callers = <String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final relative = file.path.replaceAll(r'\', '/').split('lib/').last;
      if (relative == 'screens/premium_gate.dart') continue;
      if (file.readAsStringSync().contains('passPremiumGate(')) {
        callers.add(relative);
      }
    }
    expect(callers, _gateCallers);
  });

  test('no surface that carries what is saved names Premium', () {
    final violations = <String>[
      for (final relative in _neverGated)
        if (_premium.hasMatch(_read(relative))) relative,
    ];
    expect(violations, isEmpty);
  });

  test('every never-gated file exists, so the list cannot rot', () {
    for (final relative in _neverGated) {
      expect(File('lib/$relative').existsSync(), isTrue, reason: relative);
    }
  });
}
