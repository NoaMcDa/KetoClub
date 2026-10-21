import 'package:ketoclub/models/restriction.dart';
import 'package:ketoclub/services/storage/settings_store.dart';

/// The two writes behind the empty-profile notice (Banto, issue #421), as
/// plain functions over a [SettingsStore] so the menu's controller and the
/// Discovery screen share one implementation. Each reads the stored
/// settings, changes one thing and writes them back; neither throws.

/// Remembers that the notice of [surface] was dismissed. A no-op, with no
/// write, when it already was.
Future<void> dismissProfileNudge(
  SettingsStore store,
  ProfileNudgeSurface surface,
) async {
  final settings = await store.read();
  if (settings.nudgeDismissed(surface)) return;
  await store.write(switch (surface) {
    ProfileNudgeSurface.menu => settings.copyWith(menuNudgeDismissed: true),
    ProfileNudgeSurface.discovery => settings.copyWith(
      discoveryNudgeDismissed: true,
    ),
  });
}

/// Adds what the user picked from the notice to their own profile: the
/// restriction [id], or their own word [term] (ALG-17). Exactly one of the
/// two is given.
///
/// Answers whether the helper-tool sheet should be shown now: true when
/// the profile changed and the sheet had not been shown before, in which
/// case it is marked shown in the same write (ALG-11), so a swipe away
/// counts as seen.
Future<bool> addToProfile(
  SettingsStore store, {
  RestrictionId? id,
  String? term,
}) async {
  final settings = await store.read();
  final profile = settings.profile;
  final next = term != null
      ? profile.withCustomTerm(term)
      : id != null
      ? profile.withEntry(id)
      : profile;
  if (identical(next, profile) || next == profile) return false;
  final showHelper = !settings.helperToolSeen;
  await store.write(settings.copyWith(profile: next, helperToolSeen: true));
  return showHelper;
}
